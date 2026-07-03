import AppKit
import Carbon.HIToolbox
import Foundation

/// A global hotkey (#25) — user-requested: trigger "Rearrange now" from any app. Carbon
/// `RegisterEventHotKey` is the system-wide hotkey API every shortcut library wraps; it needs NO
/// Accessibility grant (independent of TCC) and consumes the keypress. Mirrors `DragMonitor`: a live
/// `@unchecked Sendable` class, `self` reaches the no-capture `@convention(c)` handler via `userInfo`,
/// and `fire()` is the unit-testable seam the callback invokes.
///
/// The registration + callback routing is a live-only surface (can't run without a real event
/// stream), proven by pressing the key. `HotKeyConfig` + `fire()` are the testable seams.

/// The key + Carbon modifier mask for the hotkey. Carbon masks (`cmdKey` etc.), NOT
/// `NSEvent.ModifierFlags` — a frequent mix-up that silently registers the wrong combo.
public struct HotKeyConfig: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    /// ⌘⌥T — the default (user-chosen #25b). Includes ⌥, so it passes `isValid`.
    public static let rearrange = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: UInt32(cmdKey | optionKey))

    /// Carbon modifier mask from Cocoa flags — maps ONLY the 4 device-independent modifier bits, so
    /// capsLock/fn/numericPad can never leak into the mask (Cocoa flags ≠ Carbon masks — a classic
    /// mix-up). The recorder feeds `event.modifierFlags` here.
    public static func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        let m = cocoa.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if m.contains(.command) { carbon |= UInt32(cmdKey) }
        if m.contains(.option) { carbon |= UInt32(optionKey) }
        if m.contains(.control) { carbon |= UInt32(controlKey) }
        if m.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    /// Safe to bind as a GLOBAL hotkey: must include ⌥ or ⌃. This blocks the ⌘-menu-equivalent
    /// footgun class (⌘Q/⌘W/⌘C…) — a global hotkey CONSUMES its combo app-wide, so binding ⌘Q would
    /// break Quit everywhere. ⌘⌥/⌃⌥/⌃ combos are the safe (and conventional tiling) space.
    public var isValid: Bool {
        (modifiers & UInt32(optionKey)) != 0 || (modifiers & UInt32(controlKey)) != 0
    }

    /// Human-readable "⌃⌥⇧⌘T" — conventional macOS modifier order + the key glyph.
    public var displayString: String {
        var s = ""
        if (modifiers & UInt32(controlKey)) != 0 { s += "⌃" }
        if (modifiers & UInt32(optionKey)) != 0 { s += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { s += "⇧" }
        if (modifiers & UInt32(cmdKey)) != 0 { s += "⌘" }
        return s + Self.keyGlyph(keyCode)
    }

    /// keyCode → display glyph. A small map for the common bind keys; unmapped codes fall back to a
    /// safe non-crashing label (exotic keys are rare bind targets).
    static func keyGlyph(_ code: UInt32) -> String {
        if let named = specialGlyphs[Int(code)] { return named }
        if let ansi = ansiGlyphs[Int(code)] { return ansi }
        return "key\(code)"
    }
    private static let specialGlyphs: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]
    private static let ansiGlyphs: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9",
    ]
}

public final class HotKeyMonitor: @unchecked Sendable {
    /// A stable id for our one hotkey, so the shared dispatcher handler fires ONLY for our press
    /// (not some other app-level hotkey). `signature` is an arbitrary 4-char OSType. NB: these are
    /// static, so all instances share one id — fine for the single hotkey today; a second hotkey
    /// (#24 configurable shortcuts) must make the id per-instance.
    static let signature: OSType = 0x544D_544C   // 'TMTL'
    static let id: UInt32 = 1

    private let onFire: @Sendable () -> Void
    private let lock = NSLock()
    private var config: HotKeyConfig             // lock-guarded — reconfigure() mutates it
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    public init(config: HotKeyConfig = .rearrange, onFire: @escaping @Sendable () -> Void) {
        self.config = config
        self.onFire = onFire
    }

    /// Install the hotkey handler on the dispatcher, then register the hotkey. Returns `false` if
    /// either step fails (e.g. the combo is already taken by another app) — the app keeps working;
    /// the hotkey is simply inactive. Idempotent-safe: `stop()`s any prior registration first.
    @discardableResult
    public func start() -> Bool {
        stop()
        // Snapshot config under a BRIEF lock, released before the Carbon calls — never hold the
        // (non-recursive) lock across start()/RegisterEventHotKey (#25b S4: deadlock/race guard).
        let snapshot = lock.withLock { config }
        // Central footgun guard (#25b B2): never register a ⌘-only / modifier-less combo, even from a
        // tampered or downgraded plist that bypassed setHotKey — it would hijack that key system-wide.
        guard snapshot.isValid else { return false }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var newHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler,
                                                1, &eventType, selfPtr, &newHandler)
        guard installStatus == noErr, let newHandler else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.id)
        var newHotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(snapshot.keyCode, snapshot.modifiers, hotKeyID,
                                                 GetEventDispatcherTarget(), 0, &newHotKey)
        guard registerStatus == noErr, let newHotKey else {
            RemoveEventHandler(newHandler)   // don't leak the handler if the hotkey is taken
            return false
        }
        lock.withLock { handlerRef = newHandler; hotKeyRef = newHotKey }
        return true
    }

    /// Swap to a new combo, rolling back on failure (#25b B1): snapshot the old, try the new, and if
    /// registration fails RESTORE the old + re-arm it — so the user never loses their working hotkey.
    /// Returns whether the NEW combo registered. Runs on the main actor (from `setHotKey`).
    @discardableResult
    public func reconfigure(_ newConfig: HotKeyConfig) -> Bool {
        let old = lock.withLock { config }
        lock.withLock { config = newConfig }
        if start() { return true }
        lock.withLock { config = old }         // roll back
        start()                                // re-arm the previously-working combo
        return false
    }

    /// Unregister the hotkey + remove the handler (leak-clean). Safe if never started. Does NOT
    /// touch `config` (reconfigure/start own that), so the snapshot on the next start() is intact.
    public func stop() {
        lock.withLock {
            if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
            if let handlerRef { RemoveEventHandler(handlerRef) }
            hotKeyRef = nil
            handlerRef = nil
        }
    }

    /// The seam the `@convention(c)` callback invokes when OUR hotkey fires. Split out so the
    /// dispatch is unit-testable without a real keypress.
    func fire() { onFire() }

    /// Defensive cleanup — if a monitor is ever dropped (tests, or a future create/replace path),
    /// unregister so no hotkey/handler leaks. In production the composition root retains it for the
    /// process lifetime, so this rarely runs. `stop()` is safe-if-never-started.
    deinit { stop() }
}

/// No-capture `@convention(c)` handler: `self` arrives via `userInfo`. It matches the pressed
/// hotkey's `EventHotKeyID` against ours before firing, so a different app-level hotkey routed to
/// the shared dispatcher never triggers a rearrange.
private let hotKeyHandler: EventHandlerUPP = { _, eventRef, userInfo in
    guard let userInfo, let eventRef else { return OSStatus(eventNotHandledErr) }
    var pressedID = EventHotKeyID()
    let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
    guard status == noErr else { return OSStatus(eventNotHandledErr) }
    guard pressedID.signature == HotKeyMonitor.signature, pressedID.id == HotKeyMonitor.id else {
        return OSStatus(eventNotHandledErr)
    }
    Unmanaged<HotKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue().fire()
    return noErr
}
