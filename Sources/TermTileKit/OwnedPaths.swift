import Foundation
import TermTileCore

/// The exact `~/Library`-rooted paths a shipped TermTile owns — the canonical list an in-app
/// Uninstall (#22b) trashes. EXACT literals derived from `AppIdentity.bundleID`, never a glob or
/// prefix (so a neighbour like `dev.ecn.apps.termtile.selftest.plist` is never caught), with the
/// `library` root INJECTED so it is deterministic in tests and never reads the real `~/Library`.
///
/// Lives in Kit (not Core) for cohesion: its only consumer (the Uninstaller) and the caller that
/// supplies the real library URL from `FileManager` both live in the imperative shell — the type
/// itself is pure and would satisfy Core's purity guard. Identity is by `.path` (string); `URL.==`
/// depends on the `isDirectory` hint. Single bundleID: TermTile has only ever shipped as
/// `dev.ecn.apps.termtile` (the inverse of RememBar's prior-id rename-residue list) — add prior ids
/// here if the bundleID ever changes.
public struct OwnedPaths: Sendable {
    private let library: URL

    public init(library: URL) { self.library = library }

    /// The owned data paths, folder-granular. The `.app` bundle is deliberately NOT here — it can't
    /// self-delete while running; the Uninstaller takes it separately. Entries that don't exist yet
    /// (e.g. `Saved Application State` until a window has been opened) are harmless: #22b
    /// existence-checks each before trashing, and an owned-but-absent entry is skipped, whereas an
    /// omitted-but-later-present path would be a silent orphan.
    public var dataPaths: [URL] {
        let bid = AppIdentity.bundleID
        return [
            library.appendingPathComponent("Preferences/\(bid).plist", isDirectory: false),
            library.appendingPathComponent("Caches/\(bid)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bid)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bid).binarycookies", isDirectory: false),
            library.appendingPathComponent("Saved Application State/\(bid).savedState", isDirectory: true),
        ]
    }
}
