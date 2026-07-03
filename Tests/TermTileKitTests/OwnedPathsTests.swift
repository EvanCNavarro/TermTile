import Foundation
import Testing
@testable import TermTileKit
import TermTileCore

/// #22a — the exact on-disk footprint a shipped TermTile owns (the scope-safety foundation the
/// Uninstaller, #22b, consumes). A fixed injected `library` root keeps it deterministic and off the
/// real `~/Library`. Identity is by `.path` (audit: URL.== depends on isDirectory flags).
@Suite("OwnedPaths — exact owned footprint")
struct OwnedPathsTests {
    let lib = URL(fileURLWithPath: "/tmp/fake-library", isDirectory: true)
    var bid: String { AppIdentity.bundleID }   // dev.ecn.apps.termtile

    /// GOLDEN LOCK — dataPaths is EXACTLY the five owned paths, in a stable order, with production's
    /// isDirectory flags. Reddens if a future edit adds, drops, or broadens an entry.
    @Test("dataPaths is exactly the five owned paths")
    func exactList() {
        let expected = [
            lib.appendingPathComponent("Preferences/\(bid).plist", isDirectory: false),
            lib.appendingPathComponent("Caches/\(bid)", isDirectory: true),
            lib.appendingPathComponent("HTTPStorages/\(bid)", isDirectory: true),
            lib.appendingPathComponent("HTTPStorages/\(bid).binarycookies", isDirectory: false),
            lib.appendingPathComponent("Saved Application State/\(bid).savedState", isDirectory: true),
        ]
        #expect(OwnedPaths(library: lib).dataPaths.map(\.path) == expected.map(\.path))
    }

    /// Documented intent (conceded tautological for a literal list): the real dev-artifact neighbors
    /// on disk are never owned.
    @Test("real dev-artifact neighbors are not owned")
    func neighborsExcluded() {
        let owned = Set(OwnedPaths(library: lib).dataPaths.map(\.path))
        for neighbor in ["\(bid).selftest.plist", "\(bid).tests.roundtrip.plist", "\(bid).audit.probe.plist"] {
            let n = lib.appendingPathComponent("Preferences/\(neighbor)", isDirectory: false).path
            #expect(!owned.contains(n))
        }
    }

    /// STRENGTHENED (audit #4) — the load-bearing structural invariant: every owned path's last
    /// component is EXACTLY `bundleID + <known suffix>`, no extra dotted segment. A prefix-broadened
    /// entry (e.g. `bundleID + ".selftest.plist"`) is NOT in the allowed set → fails this.
    @Test("each owned path's last component is exactly bundleID + a known suffix")
    func exactComponent() {
        let allowed: Set<String> = ["\(bid).plist", bid, "\(bid).binarycookies", "\(bid).savedState"]
        for url in OwnedPaths(library: lib).dataPaths {
            #expect(allowed.contains(url.lastPathComponent),
                    "‘\(url.lastPathComponent)’ is not an exact bundleID+suffix owned component")
        }
        // the invariant provably excludes the broadened neighbor
        #expect(!allowed.contains("\(bid).selftest.plist"))
    }
}
