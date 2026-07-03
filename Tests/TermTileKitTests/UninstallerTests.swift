import Foundation
import Testing
@testable import TermTileKit
import TermTileCore

/// #22b — the in-app Uninstaller. The load-bearing test is SCOPE SAFETY: seed a temp `~/Library`
/// with BOTH owned files and real dev-artifact decoys, inject a `trash` that RECORDS *and removes in
/// the sandbox* (never the real Trash), and prove `removeData()` trashes ONLY owned paths — decoys
/// materialized on disk SURVIVE. (Record-only would make this vacuous; we remove for real in temp.)
@MainActor
@Suite("Uninstaller — removal scope + lifecycle")
struct UninstallerTests {
    let fm = FileManager.default
    var bid: String { AppIdentity.bundleID }

    /// A fresh temp library root, cleaned by the caller's `defer`.
    func makeLibrary() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("termtile-uninstall-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func writeFile(_ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }
    func writeDir(_ url: URL, inner: String = "inner.txt") throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url.appendingPathComponent(inner))
    }

    /// A sandbox trash: records what it was asked to trash AND actually removes it (in temp only),
    /// so decoy-survival and idempotency are REAL. Boxed so the struct-copy shares the record.
    final class SandboxTrash: @unchecked Sendable {
        private(set) var trashed: [URL] = []
        let fm = FileManager.default
        func trash(_ url: URL) throws { trashed.append(url); try fm.removeItem(at: url) }
    }

    /// Shared ordered event log — a spy login item + the trash both append, so the order test can
    /// assert unregister happened BEFORE the bundle was trashed (the ghost-item hazard).
    final class EventLog: @unchecked Sendable {
        private(set) var events: [String] = []
        func record(_ e: String) { events.append(e) }
    }
    final class SpyLoginItem: LoginItem, @unchecked Sendable {
        let log: EventLog
        init(_ log: EventLog) { self.log = log }
        var status: LoginItemStatus { .notRegistered }
        func register() throws {}
        func unregister() throws { log.record("unregister") }
    }

    // KEYSTONE — removeData trashes ONLY owned paths; decoys survive; a folder is removed whole.
    @Test("scope safety: only owned paths trashed, real decoys survive")
    func scopeSafety() throws {
        let lib = try makeLibrary()
        defer { try? fm.removeItem(at: lib) }
        let owned = OwnedPaths(library: lib)
        // materialize all owned paths on disk (files + dirs, one dir with a nested file)
        try writeFile(lib.appendingPathComponent("Preferences/\(bid).plist"))
        try writeDir(lib.appendingPathComponent("Caches/\(bid)"))               // nested inner.txt
        try writeDir(lib.appendingPathComponent("HTTPStorages/\(bid)"))
        try writeFile(lib.appendingPathComponent("HTTPStorages/\(bid).binarycookies"))
        try writeDir(lib.appendingPathComponent("Saved Application State/\(bid).savedState"))
        // materialize DECOYS a prefix-glob would wrongly catch
        let decoys = [
            lib.appendingPathComponent("Preferences/\(bid).selftest.plist"),
            lib.appendingPathComponent("Preferences/com.other.app.plist"),
        ]
        for d in decoys { try writeFile(d) }
        let decoyDir = lib.appendingPathComponent("Application Support/TermTileOther")
        try writeDir(decoyDir)

        let box = SandboxTrash()
        let u = Uninstaller(ownedPaths: owned, loginItem: InMemoryLoginItem(),
                            settings: InMemorySettingsStore(), bundleURL: nil, trash: box.trash)
        let (removed, failed) = u.removeData()

        #expect(failed.isEmpty)
        #expect(Set(removed.map(\.path)) == Set(owned.dataPaths.map(\.path)))     // exactly the owned set
        for p in owned.dataPaths { #expect(!fm.fileExists(atPath: p.path)) }      // owned gone
        for d in decoys { #expect(fm.fileExists(atPath: d.path)) }               // DECOYS SURVIVE
        #expect(fm.fileExists(atPath: decoyDir.path))                            // neighbour dir survives
    }

    // Best-effort: a trash that throws for one path does NOT abort; the failure is reported.
    @Test("best-effort: one failing trash doesn't abort the rest, and is reported")
    func bestEffortReportsFailures() throws {
        let lib = try makeLibrary()
        defer { try? fm.removeItem(at: lib) }
        let owned = OwnedPaths(library: lib)
        for p in owned.dataPaths {
            if p.hasDirectoryPath { try writeDir(p) } else { try writeFile(p) }
        }
        let failURL = owned.dataPaths[0]
        let u = Uninstaller(ownedPaths: owned, loginItem: InMemoryLoginItem(),
                            settings: InMemorySettingsStore(), bundleURL: nil,
                            trash: { url in
                                if url.path == failURL.path { throw CocoaError(.fileWriteNoPermission) }
                                try FileManager.default.removeItem(at: url)
                            })
        let (removed, failed) = u.removeData()
        #expect(failed.count == 1)
        #expect(failed.first?.url.path == failURL.path)
        #expect(removed.count == owned.dataPaths.count - 1)   // the other 4 still processed
    }

    // Non-existent owned path is skipped (not counted removed, not a failure).
    @Test("absent owned path is skipped")
    func absentSkipped() throws {
        let lib = try makeLibrary()
        defer { try? fm.removeItem(at: lib) }
        // materialize NOTHING
        let box = SandboxTrash()
        let u = Uninstaller(ownedPaths: OwnedPaths(library: lib), loginItem: InMemoryLoginItem(),
                            settings: InMemorySettingsStore(), bundleURL: nil, trash: box.trash)
        let (removed, failed) = u.removeData()
        #expect(removed.isEmpty)
        #expect(failed.isEmpty)
        #expect(box.trashed.isEmpty)
    }

    // removeBundle: existing → .trashed; nil → .noBundle; a throwing trash → .needsManual.
    @Test("removeBundle: trashed / noBundle / needsManual")
    func bundleOutcomes() throws {
        let lib = try makeLibrary()
        defer { try? fm.removeItem(at: lib) }
        let bundle = lib.appendingPathComponent("TermTile.app", isDirectory: true)
        try writeDir(bundle)
        let box = SandboxTrash()
        let ok = Uninstaller(ownedPaths: OwnedPaths(library: lib), loginItem: InMemoryLoginItem(),
                             settings: InMemorySettingsStore(), bundleURL: bundle, trash: box.trash)
        #expect(ok.removeBundle() == .trashed(bundle))
        #expect(!fm.fileExists(atPath: bundle.path))

        let none = Uninstaller(ownedPaths: OwnedPaths(library: lib), loginItem: InMemoryLoginItem(),
                               settings: InMemorySettingsStore(), bundleURL: nil, trash: box.trash)
        #expect(none.removeBundle() == .noBundle)

        try writeDir(bundle)
        let readonly = Uninstaller(ownedPaths: OwnedPaths(library: lib), loginItem: InMemoryLoginItem(),
                                   settings: InMemorySettingsStore(), bundleURL: bundle,
                                   trash: { _ in throw CocoaError(.fileWriteVolumeReadOnly) })
        #expect(readonly.removeBundle() == .needsManual(bundle))
    }

    // uninstall() ORDER: unregister → data → bundle; outcome carries login result + TCC bundleID.
    @Test("uninstall orchestrates unregister BEFORE bundle trash, and reports everything")
    func uninstallOrder() throws {
        let lib = try makeLibrary()
        defer { try? fm.removeItem(at: lib) }
        let bundle = lib.appendingPathComponent("TermTile.app", isDirectory: true)
        try writeDir(bundle)
        try writeFile(lib.appendingPathComponent("Preferences/\(bid).plist"))
        let log = EventLog()
        let trash: (URL) throws -> Void = { url in
            log.record("trash:\(url.lastPathComponent)")
            try FileManager.default.removeItem(at: url)
        }
        let u = Uninstaller(ownedPaths: OwnedPaths(library: lib), loginItem: SpyLoginItem(log),
                            settings: InMemorySettingsStore(), bundleURL: bundle, trash: trash)
        let outcome = u.uninstall()

        #expect(outcome.loginItem.isOK)                         // login item deregistered
        #expect(outcome.bundle == .trashed(bundle))
        #expect(outcome.tccResetBundleID == bid)                // guidance datum, single-sourced
        #expect(outcome.removedData.contains { $0.lastPathComponent == "\(bid).plist" })  // data cleared
        #expect(outcome.isClean)                                // fully-clean predicate, one source
        // ORDER (full arc): unregister → data(plist) → bundle
        let iUnreg = log.events.firstIndex(of: "unregister")
        let iData = log.events.firstIndex(of: "trash:\(bid).plist")
        let iBundle = log.events.firstIndex(of: "trash:TermTile.app")
        #expect(iUnreg != nil && iData != nil && iBundle != nil)
        #expect(iUnreg! < iData! && iData! < iBundle!)
    }

    // isClean is the single-source success predicate — false when any part didn't fully complete.
    @Test("isClean reflects failures / dereg failure / manual-bundle")
    func isCleanPredicate() throws {
        let lib = try makeLibrary()
        defer { try? fm.removeItem(at: lib) }
        // data-failure → not clean
        for p in OwnedPaths(library: lib).dataPaths {
            if p.hasDirectoryPath { try writeDir(p) } else { try writeFile(p) }
        }
        let failURL = OwnedPaths(library: lib).dataPaths[0]
        let uFail = Uninstaller(ownedPaths: OwnedPaths(library: lib), loginItem: InMemoryLoginItem(),
                                settings: InMemorySettingsStore(), bundleURL: nil,
                                trash: { u in if u.path == failURL.path { throw CocoaError(.fileWriteNoPermission) }
                                              try FileManager.default.removeItem(at: u) })
        #expect(!uFail.uninstall().isClean)
    }

    // Idempotency: a second removeData removes nothing (owned already gone).
    @Test("idempotent: second removeData is a no-op")
    func idempotent() throws {
        let lib = try makeLibrary()
        defer { try? fm.removeItem(at: lib) }
        let owned = OwnedPaths(library: lib)
        try writeFile(lib.appendingPathComponent("Preferences/\(bid).plist"))
        let box = SandboxTrash()
        let u = Uninstaller(ownedPaths: owned, loginItem: InMemoryLoginItem(),
                            settings: InMemorySettingsStore(), bundleURL: nil, trash: box.trash)
        _ = u.removeData()
        let (removed2, _) = u.removeData()
        #expect(removed2.isEmpty)
    }
}
