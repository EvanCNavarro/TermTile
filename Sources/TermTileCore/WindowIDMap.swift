import CoreGraphics

/// The pure element-hash → `CGWindowID` map the AX event bridge (#19b) owns (ADR-0001: Core is
/// pure — this imports only CoreGraphics for `CGWindowID`, so `core-purity.sh` stays green and the
/// AX `AXUIElement` type never leaks in; the Kit adapter computes `CFHash(element)` and passes the
/// bare `UInt`).
///
/// Why it exists: at window destroy `_AXUIElementGetWindow` fails with -25201 and the CGWindowID is
/// 0 (spike-05), so a `.destroyed` WindowEvent's real id can ONLY be recovered from a map SEEDED at
/// create time (when the element is alive and its id resolves). Keyed on the element's stable
/// `CFHash`, which is identical dead-or-alive (spike-05: the destroyed element still arrives in the
/// callback with the same hash it had at create).
///
/// `consumeDestroy` is a one-shot resolve+remove: the belt-and-braces DOUBLE registration
/// (app-level + per-window, spike-05 (b)) can deliver the same-hash destroy twice on some OS build,
/// so the second call must yield nil (dedupe). A destroy for a never-recorded hash (the ~5s
/// undo-close anomaly, spike-05) also yields nil — the reducer no-ops on an unknown id, so no
/// phantom removal.
///
/// SCOPE (stoke-plan-19b F3): seeded ONLY on `.created` this beat. A window that pre-exists the
/// observer (or is adopted via `activate()`→`tileableWindows()`) is not in the map, so its later
/// destroy resolves nil and lingers in state — the enumerate-seed is deferred to #12 (it would make
/// the map cross-thread, breaking the callback-thread single-writer confinement the bridge relies on).
public struct WindowIDMap {
    private var hashToID: [UInt: CGWindowID] = [:]

    public init() {}

    /// Seed (or upsert) the id for an element hash at create/enumerate time. Upsert, not append:
    /// a reused hash adopts the newest id.
    public mutating func record(hash: UInt, id: CGWindowID) {
        hashToID[hash] = id
    }

    /// The id currently mapped for `hash`, or nil if unknown / already consumed.
    public func resolve(hash: UInt) -> CGWindowID? {
        hashToID[hash]
    }

    /// One-shot destroy resolution: return the recorded id AND remove it, so a duplicate
    /// same-hash destroy (double registration) yields nil. An unknown hash yields nil.
    public mutating func consumeDestroy(hash: UInt) -> CGWindowID? {
        hashToID.removeValue(forKey: hash)
    }
}
