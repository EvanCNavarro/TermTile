import Foundation
@testable import TermTileKit

/// Deterministic in-memory `LoginItem` fake (test double, ADR-0001 imperative-shell seam) —
/// the injectable seam #12c's shell tests use instead of touching the real login-item domain.
/// A `final class` + `NSLock`, NOT an `actor`: `LoginItem`'s requirements are SYNCHRONOUS, so an
/// actor's isolated methods cannot satisfy the nonisolated protocol requirement (same inverse as
/// `InMemorySettingsStore`). `@unchecked Sendable` is honest — the lock serializes the single
/// mutable field. Seedable initial status so #12c can exercise every state (e.g.
/// `.requiresApproval` for the approval fix-it UX); `register()`/`unregister()` toggle
/// `.enabled`/`.notRegistered` and never throw (the throw path is #12c's to inject when it lands).
final class InMemoryLoginItem: LoginItem, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LoginItemStatus

    init(initial: LoginItemStatus = .notRegistered) {
        self.current = initial
    }

    var status: LoginItemStatus { lock.withLock { current } }
    func register() throws { lock.withLock { current = .enabled } }
    func unregister() throws { lock.withLock { current = .notRegistered } }
}
