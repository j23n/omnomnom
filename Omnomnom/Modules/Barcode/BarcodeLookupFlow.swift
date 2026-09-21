import Foundation
import Observation
import os
import SwiftData

/// The Settings key shared by the toggle, the Add sheet and the flow.
nonisolated enum BarcodeModule {
    static let enabledKey = "barcodeScanningEnabled"
}

/// Where a resolved barcode sends the user next.
nonisolated enum BarcodeLookupOutcome: Hashable, Sendable {
    /// A cached or freshly fetched product, ready for the Quantity sheet.
    case found(FoodChoice)
    /// Nothing usable: the food editor opens with the barcode, the name when known, and
    /// one sentence saying why.
    case manual(barcode: String, prefillName: String?, reason: String)
}

/// Resolves a barcode: the local cache first, then Open Food Facts once, with a usable
/// answer cached for good so the same code never hits the network again. Main-actor
/// because it drives the shared `ModelContext`; the decision itself is a pure `step`.
@Observable
final class BarcodeLookupFlow {
    /// What the network said; `nil` when it was not asked.
    typealias Lookup = Result<ProductRecord?, OpenFoodFactsError>

    /// The step `resolve` takes, decided from the cache and the lookup alone.
    nonisolated enum Step: Hashable, Sendable {
        case found(FoodChoice)
        /// A usable record to insert as a product row, then present.
        case cache(ProductRecord)
        case manual(barcode: String, prefillName: String?, reason: String)
    }

    private let context: ModelContext
    private let client: OpenFoodFactsClient
    private let defaults: UserDefaults

    init(context: ModelContext, client: OpenFoodFactsClient, defaults: UserDefaults = .standard) {
        self.context = context
        self.client = client
        self.defaults = defaults
    }

    func resolve(code: String) async -> BarcodeLookupOutcome {
        let cached = cachedChoice(for: code)
        var lookup: Lookup?
        if cached == nil, defaults.bool(forKey: BarcodeModule.enabledKey) {
            lookup = await lookUp(code)
        }
        switch Self.step(code: code, cached: cached, lookup: lookup) {
        case .found(let choice):
            return .found(choice)
        case .manual(let barcode, let prefillName, let reason):
            return .manual(barcode: barcode, prefillName: prefillName, reason: reason)
        case .cache(let record):
            return cache(record, code: code)
        }
    }

    /// A cache hit wins; a usable record is cached; everything else goes manual with a
    /// reason: a miss, a record without energy (name kept), no connection, or a failure.
    nonisolated static func step(code: String, cached: FoodChoice?, lookup: Lookup?) -> Step {
        if let cached { return .found(cached) }
        guard let lookup else { return .manual(barcode: code, prefillName: nil, reason: "Barcode lookup is off") }
        switch lookup {
        case .success(let record?) where record.isUsable:
            return .cache(record)
        case .success(let record?):
            return .manual(barcode: code, prefillName: record.name, reason: "No nutrition values on Open Food Facts")
        case .success(nil):
            return .manual(barcode: code, prefillName: nil, reason: "Not on Open Food Facts")
        case .failure(.network):
            return .manual(barcode: code, prefillName: nil, reason: "No connection")
        case .failure:
            return .manual(barcode: code, prefillName: nil, reason: "Lookup failed")
        }
    }

    private func lookUp(_ code: String) async -> Lookup {
        do {
            let record = try await client.product(for: code)
            return .success(record)
        } catch let error as OpenFoodFactsError {
            return .failure(error)
        } catch {
            return .failure(.network(error))
        }
    }

    private func cachedChoice(for code: String) -> FoodChoice? {
        do {
            return try Food.product(barcode: code, in: context)?.choice
        } catch {
            AppLog.store.error("product cache lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Inserts the record as a product row and saves; a failed save rolls back and
    /// sends the user to manual entry with the name kept.
    private func cache(_ record: ProductRecord, code: String) -> BarcodeLookupOutcome {
        let name = record.name ?? record.brand ?? "Product \(code)"
        let food = Food(name: name, kind: .product, bundledID: nil, per100g: record.per100g)
        food.barcode = code
        food.brand = record.brand
        food.source = .openFoodFacts
        food.fetchedAt = Date.now
        context.insert(food)
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLog.store.error("product cache save failed: \(error.localizedDescription, privacy: .public)")
            return .manual(barcode: code, prefillName: record.name, reason: "Could not save the product")
        }
        AppLog.barcode.info("cached product \(code, privacy: .private)")
        guard let choice = food.choice else {
            return .manual(barcode: code, prefillName: record.name, reason: "Lookup failed")
        }
        return .found(choice)
    }
}
