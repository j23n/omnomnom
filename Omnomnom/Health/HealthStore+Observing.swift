import Foundation
import HealthKit
import os

/// The read side of `HealthStore`: observer registration, anchored change feeds and day
/// reads.
extension HealthStore: HealthObserving {
    func startObserving(onChange: @escaping @Sendable () async -> Void) async throws {
        guard isAvailable, observerQueries.isEmpty else { return }
        for nutrient in Nutrient.allCases {
            let type = HealthObjects.quantityType(for: nutrient)
            let identifier = type.identifier
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if let error {
                    AppLog.health.error("observer for \(identifier, privacy: .public) reported: \(error.localizedDescription, privacy: .public)")
                }
                // HealthKit's completion block is not Sendable. It must be called exactly once,
                // from any thread, after the change was handled; that is all the task does with it.
                nonisolated(unsafe) let done = completion
                Task {
                    await onChange()
                    done()
                }
            }
            store.execute(query)
            observerQueries.append(query)
        }
        AppLog.health.info("observing \(self.observerQueries.count) types")
        var firstFailure: (any Error)?
        for nutrient in Nutrient.allCases {
            do {
                try await store.enableBackgroundDelivery(for: HealthObjects.quantityType(for: nutrient), frequency: .immediate)
            } catch {
                AppLog.health.error("background delivery for \(nutrient.rawValue, privacy: .public) refused: \(error.localizedDescription, privacy: .public)")
                firstFailure = firstFailure ?? error
            }
        }
        if let firstFailure { throw firstFailure }
    }

    /// A type counts as fully read only when this app may still write it (a revoked type
    /// is undocumented territory) and the user's readable window is known, so the
    /// reconciler can limit pruning to entries the read actually covered.
    func changes(since anchors: HealthAnchors) async throws -> HealthChanges {
        guard isAvailable else { return .unchanged(anchors: anchors) }
        let runStart = Date.now
        let readableSince = await readableSinceDates()
        var added: [String] = []
        var deleted: [String] = []
        var next = anchors
        var fullyRead = Set<Nutrient>()
        for nutrient in Nutrient.allCases {
            let type = HealthObjects.quantityType(for: nutrient)
            let read = try await drain(startingAt: anchors[type.identifier]) { anchor in
                HealthQueries.anchoredDescriptor(for: nutrient, anchor: anchor)
            }
            added += read.added
            deleted += read.deleted
            next[type.identifier] = read.anchor
            if read.isComplete, readableSince != nil, store.authorizationStatus(for: type) == .sharingAuthorized {
                fullyRead.insert(nutrient)
            }
        }
        let foodIdentifier = HKCorrelationType(.food).identifier
        let read = try await drain(startingAt: anchors[foodIdentifier]) { anchor in
            HealthQueries.anchoredCorrelationDescriptor(anchor: anchor)
        }
        added += read.added
        deleted += read.deleted
        next[foodIdentifier] = read.anchor
        AppLog.health.info("changes: \(added.count) added, \(deleted.count) deleted, \(fullyRead.count) types fully read")
        return HealthChanges(
            added: added, deleted: deleted, anchors: next,
            fullyRead: fullyRead, readableSince: readableSince ?? [:], runStart: runStart
        )
    }

    /// The earliest date the user let this app read, per nutrient; a type the result omits
    /// is left out (read as `.distantPast`). `nil` when HealthKit could not say, in which
    /// case no type is treated as fully read. Time-limited authorization and the API that
    /// reports it are iOS 27 features, so iOS 26 always has full history.
    /// An Xcode 26 build has no iOS 27 SDK (`OnDeviceSDK.swift`), so it reads every type as
    /// fully readable, as on iOS 26.
    private func readableSinceDates() async -> [Nutrient: Date]? {
        #if compiler(>=6.4)
        guard #available(iOS 27, *) else { return [:] }
        let types = Set<HKObjectType>(Nutrient.allCases.map { HealthObjects.quantityType(for: $0) })
        do {
            let earliest = try await store.earliestAuthorizedSampleDate(for: types)
            var result: [Nutrient: Date] = [:]
            for nutrient in Nutrient.allCases {
                if let date = earliest[HealthObjects.quantityType(for: nutrient)] {
                    result[nutrient] = date
                }
            }
            return result
        } catch {
            AppLog.health.notice("readable window unknown, no full-read pruning: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        return [:]
        #endif
    }

    func samples(in interval: DateInterval) async throws -> [HealthNutritionSample] {
        guard isAvailable else { return [] }
        do {
            let results = try await HealthQueries.daySamplesDescriptor(in: interval).result(for: store)
            let own = Bundle.main.bundleIdentifier
            return results.compactMap { HealthQueries.nutritionSample(from: $0, ownBundleIdentifier: own) }
        } catch {
            AppLog.health.error("day read failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func dailyTotals(
        for nutrients: [Nutrient], from start: Date, to end: Date
    ) async throws -> [Nutrient: [Date: Double]] {
        guard isAvailable else { return [:] }
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { return [:] }

        var totals: [Nutrient: [Date: Double]] = [:]
        for nutrient in nutrients {
            // One nutrient failing is not a reason to have no chart at all, and read
            // authorization is never knowable, so a failure here reads as "nothing" for
            // that nutrient rather than as an error for the screen.
            do {
                let collection = try await HealthQueries
                    .dailyTotalsDescriptor(for: nutrient, from: first, to: last, calendar: calendar)
                    .result(for: store)
                let unit = HealthObjects.unit(for: nutrient.unit)
                var days: [Date: Double] = [:]
                collection.enumerateStatistics(from: first, to: last) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    days[calendar.startOfDay(for: statistics.startDate)] = sum.doubleValue(for: unit)
                }
                if !days.isEmpty { totals[nutrient] = days }
            } catch {
                AppLog.health.notice(
                    "daily totals for \(nutrient.rawValue, privacy: .public) unavailable: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return totals
    }

    /// Reads every page of one type's changes since the archived anchor `data`. An anchor
    /// HealthKit rejects (after a restore onto another device it belongs to a different
    /// store) is dropped once and the type re-read from the beginning.
    private func drain<Sample: HKSample>(
        startingAt data: Data?,
        descriptor: (HKQueryAnchor?) -> HKAnchoredObjectQueryDescriptor<Sample>
    ) async throws -> TypeRead {
        var anchor = HealthAnchorCodec.decode(data)
        var fromStart = anchor == nil
        var hitCap = true
        var added: [String] = []
        var deleted: [String] = []
        for page in 0..<HealthQueries.maximumPages {
            let result: HKAnchoredObjectQueryDescriptor<Sample>.Result
            do {
                result = try await descriptor(anchor).result(for: store)
            } catch let error as HKError where error.code == .errorInvalidArgument && page == 0 && anchor != nil {
                AppLog.health.notice("stored anchor rejected, reading full history: \(error.localizedDescription, privacy: .public)")
                anchor = nil
                fromStart = true
                result = try await descriptor(nil).result(for: store)
            }
            added += result.addedSamples.compactMap { HealthQueries.syncIdentifier(in: $0.metadata) }
            deleted += result.deletedObjects.compactMap { HealthQueries.syncIdentifier(in: $0.metadata) }
            anchor = result.newAnchor
            if result.addedSamples.count + result.deletedObjects.count < HealthQueries.pageSize {
                hitCap = false
                break
            }
        }
        let encoded = try anchor.map { try HealthAnchorCodec.encode($0) }
        return TypeRead(added: added, deleted: deleted, anchor: encoded ?? data, isComplete: fromStart && !hitCap)
    }
}

/// Outcome of draining one type: identifiers seen, the anchor to keep, and whether the
/// read started from nothing and reached the end, which makes `added` exhaustive.
private nonisolated struct TypeRead {
    let added: [String]
    let deleted: [String]
    let anchor: Data?
    let isComplete: Bool
}
