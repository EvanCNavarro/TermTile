import Foundation
@testable import TermTileKit

/// Deterministic in-memory `SettingsStore` fake (test double, ADR-0001 imperative-shell seam).
/// A `final class` + `NSLock` — NOT an `actor`: `SettingsStore.load/save` are SYNCHRONOUS, so an
/// actor's isolated methods cannot satisfy the nonisolated protocol requirement (stoke-plan-12a
/// audit F2, compiler-verified). `@unchecked Sendable` is honest because the lock serializes the
/// single mutable field — the same single-writer discipline as `AXWindowSystem`'s
/// `nonisolated(unsafe)` bridge globals. Unblocks #12c's shell tests (inject settings without
/// touching real UserDefaults).
final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var current: AppSettings?

    func load() -> AppSettings { lock.withLock { current ?? .defaults } }
    func save(_ settings: AppSettings) { lock.withLock { current = settings } }
}
