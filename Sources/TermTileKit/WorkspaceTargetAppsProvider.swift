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
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> TargetApp? in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return TargetApp(bundleID: bundleID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
