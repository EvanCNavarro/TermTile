import AppKit

/// The production `TargetAppsProviding` — enumerates the currently-running regular apps via
/// `NSWorkspace` (spec-draft:18 "any running app selectable"). Only `.regular` apps with a bundle
/// id and a name are offered: menu-bar-only agents (`.accessory`, e.g. TermTile itself) and
/// background daemons (`.prohibited`) aren't windowed targets. Sorted by localized name for a
/// stable, scannable picker. Live behavior is exercised in #12c's launch selftest; the unit tests
/// inject `InMemoryTargetAppsProvider` instead of touching the real workspace.
public struct WorkspaceTargetAppsProvider: TargetAppsProviding {
    public init() {}

    public func runningTargetApps() -> [TargetApp] {
        Self.deduped(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> TargetApp? in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return TargetApp(bundleID: bundleID, name: name)
            })
    }

    /// Dedupe by bundleID, keeping the first occurrence, then sort by localized name. One app can
    /// have several running `.regular` instances that share a bundle id (e.g. multiple Chrome
    /// profiles = four `com.google.Chrome` processes) — the picker must show it ONCE. Also required
    /// for correctness, not just tidiness: `TargetApp` is `Identifiable` by `bundleID`, and a
    /// SwiftUI `Picker`/`ForEach` over duplicate ids is undefined behavior (glitched selection).
    /// Pure + static so it is unit-tested without touching `NSWorkspace`.
    static func deduped(_ apps: [TargetApp]) -> [TargetApp] {
        var seen = Set<String>()
        return apps
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
