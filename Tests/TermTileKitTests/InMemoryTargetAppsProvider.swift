@testable import TermTileKit

/// Deterministic in-memory `TargetAppsProviding` fake (test double, ADR-0001 imperative-shell
/// seam) — the injectable seam #12c's view-model tests use instead of enumerating real
/// `NSWorkspace` apps. A `struct` is enough: the seed is immutable, so it is trivially `Sendable`
/// with no lock (unlike the mutable `InMemorySettingsStore`/`InMemoryLoginItem`).
struct InMemoryTargetAppsProvider: TargetAppsProviding {
    let seed: [TargetApp]
    func runningTargetApps() -> [TargetApp] { seed }
}
