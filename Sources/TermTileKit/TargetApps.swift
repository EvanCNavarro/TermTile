import Foundation

/// A candidate target application for the picker (spec-draft:18 "default iTerm2; any running app
/// selectable"). A pure value type: `bundleID` is the AX adapter's target key, `name` is the
/// user-facing label. `Identifiable` by `bundleID` so a SwiftUI `Picker`/`ForEach` can tag rows
/// without a synthesized index.
public struct TargetApp: Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    public var id: String { bundleID }
}

/// The running-apps port (ADR-0001 imperative-shell seam). The picker asks "what can I target
/// right now?" The production adapter is `WorkspaceTargetAppsProvider` (NSWorkspace); tests inject
/// a deterministic fake. Synchronous by design — like `SettingsStore`/`LoginItem`, a cheap
/// non-blocking snapshot read, so no `async`/actor requirement.
public protocol TargetAppsProviding: Sendable {
    /// The currently selectable target apps, in a stable display order (adapter sorts by name).
    func runningTargetApps() -> [TargetApp]
}
