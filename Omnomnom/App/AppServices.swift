import Foundation
import os
import SwiftData

/// Long-lived services created once at launch. Reconciliation must start from the app's
/// initializer, not from a view: on a background launch for Health delivery no scene
/// task runs, and an app that repeatedly fails to register its observer queries stops
/// being woken. `startReconciliationIfNeeded` is idempotent and gated on onboarding, so
/// the primer calls it again the moment onboarding completes in-session.
final class AppServices {
    /// `nil` when no store could be opened; reconciliation then has nothing to write.
    let reconcile: ReconcileService?
    private let observing: any HealthObserving
    private let defaults: UserDefaults
    private var started = false

    nonisolated static let onboardingKey = "onboardingComplete"

    init(container: ModelContainer?, observing: any HealthObserving, defaults: UserDefaults = .standard) {
        self.reconcile = container.map { ReconcileService(context: $0.mainContext, health: observing, defaults: defaults) }
        self.observing = observing
        self.defaults = defaults
    }

    /// Registers the observer queries, then reconciles once, in a task so the caller (the
    /// app initializer or the onboarding primer) returns at once and first paint never
    /// waits. Observers go first so a background wake is registered before the possibly
    /// long first read, and the initial fire of each query coalesces into that run.
    func startReconciliationIfNeeded() {
        guard !started, defaults.bool(forKey: Self.onboardingKey), let reconcile else { return }
        started = true
        let observing = observing
        Task {
            do {
                try await observing.startObserving { await reconcile.reconcileAll() }
            } catch {
                AppLog.health.error("observers registered, but background delivery was refused: \(error.localizedDescription, privacy: .public)")
            }
            await reconcile.reconcileAll()
        }
    }

    /// The scene came to the foreground: the user may have been in the Health app.
    func sceneBecameActive() {
        startReconciliationIfNeeded()
        guard started, let reconcile else { return }
        Task { await reconcile.reconcileAll() }
    }
}
