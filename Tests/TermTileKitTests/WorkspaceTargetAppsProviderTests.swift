import Testing
@testable import TermTileKit

/// The production provider's pure dedup/sort logic (the NSWorkspace read itself is live-only). One
/// app with several running instances sharing a bundle id (e.g. 4 Chrome profiles) must collapse to
/// ONE picker row — both to avoid the visible duplicates and because TargetApp is Identifiable by
/// bundleID (a SwiftUI ForEach over duplicate ids is undefined behavior).
@Suite("WorkspaceTargetAppsProvider — dedup by bundleID")
struct WorkspaceTargetAppsProviderTests {
    @Test("four Chrome instances collapse to one row")
    func dedupesSameBundleID() {
        let raw = [
            TargetApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
            TargetApp(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
            TargetApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
            TargetApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
            TargetApp(bundleID: "com.google.Chrome", name: "Google Chrome"),
        ]
        let out = WorkspaceTargetAppsProvider.deduped(raw)
        #expect(out.count == 2)
        #expect(out.map(\.bundleID) == ["com.google.Chrome", "com.googlecode.iterm2"])  // sorted by name
        #expect(Set(out.map(\.id)).count == out.count)  // all ids unique → safe for ForEach
    }

    @Test("sorts case-insensitively by name")
    func sortsByName() {
        let raw = [
            TargetApp(bundleID: "z", name: "zed"),
            TargetApp(bundleID: "a", name: "Alpha"),
            TargetApp(bundleID: "m", name: "mid"),
        ]
        #expect(WorkspaceTargetAppsProvider.deduped(raw).map(\.name) == ["Alpha", "mid", "zed"])
    }

    @Test("empty in, empty out")
    func emptyStable() {
        #expect(WorkspaceTargetAppsProvider.deduped([]).isEmpty)
    }
}
