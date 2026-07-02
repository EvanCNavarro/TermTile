import CoreGraphics
import Testing
@testable import TermTileCore

/// #19b keystone — the pure element-hash→CGWindowID map the AX event bridge exists for. At
/// destroy the AX id is UNRESOLVABLE (spike-05: `_AXUIElementGetWindow` → err=-25201, id=0), so a
/// `.destroyed` WindowEvent's id can ONLY come from a map seeded at CREATE time (when the element
/// is alive and its id resolves). The map keys on the Kit-computed `CFHash(element)` (a plain
/// `UInt`) so `AXUIElement` stays out of Core (core-purity). Two guards, both pinned here:
/// - DEDUPE: the belt-and-braces double registration (app-level + per-window, spike-05 (b)) can
///   fire the SAME hash's destroy twice on some OS build — `consumeDestroy` must yield the id
///   exactly ONCE, then nil.
/// - UNKNOWN: the ~5s undo-close anomaly (spike-05: a destroy for an element never seen as a
///   window) resolves to nil — the reducer no-ops on an unknown id, so no phantom removal.
@Suite("WindowIDMap — element-hash → CGWindowID (create-seed / destroy-resolve / dedupe)")
struct WindowIDMapTests {
    // record then resolve returns the seeded id while the window is alive (create-seed path).
    @Test("record then resolve returns the id")
    func recordThenResolve() {
        var map = WindowIDMap()
        map.record(hash: 1685037960, id: 78247)
        #expect(map.resolve(hash: 1685037960) == 78247)
    }

    // KEYSTONE — consumeDestroy yields the recorded id the FIRST time and nil the SECOND
    // (dedupe: double-registration can deliver the same-hash destroy twice — spike-05 belt).
    @Test("keystone: consumeDestroy yields the id once, then nil (dedupe)")
    func consumeDestroyDedupe() {
        var map = WindowIDMap()
        map.record(hash: 1685037960, id: 78247)
        #expect(map.consumeDestroy(hash: 1685037960) == 78247)   // first destroy → resolved id
        #expect(map.consumeDestroy(hash: 1685037960) == nil)     // duplicate destroy → deduped
    }

    // After a consumed destroy the hash is gone from the live map too (no stale resolve).
    @Test("consumed destroy also clears resolve")
    func consumedClearsResolve() {
        var map = WindowIDMap()
        map.record(hash: 1685037960, id: 78247)
        _ = map.consumeDestroy(hash: 1685037960)
        #expect(map.resolve(hash: 1685037960) == nil)
    }

    // UNKNOWN — resolve/consumeDestroy of a never-recorded hash is nil (the ~5s undo-close
    // anomaly: a destroy for an element never seen as a window → no phantom removal).
    @Test("unknown hash: resolve and consumeDestroy are nil")
    func unknownHashIsNil() {
        var map = WindowIDMap()
        #expect(map.resolve(hash: 999) == nil)
        #expect(map.consumeDestroy(hash: 999) == nil)
    }

    // Re-recording a hash (id reuse after a window closed and a new one hashed the same) adopts
    // the new id — record is an upsert, not an append.
    @Test("re-record upserts the id for a hash")
    func reRecordUpserts() {
        var map = WindowIDMap()
        map.record(hash: 42, id: 100)
        map.record(hash: 42, id: 200)
        #expect(map.resolve(hash: 42) == 200)
    }
}
