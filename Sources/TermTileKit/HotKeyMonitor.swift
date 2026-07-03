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
    /// ⌃⌥⌘R — mnemonic (Rearrange), a 3-modifier combo with very low collision risk.
    public static let rearrange = HotKeyConfig(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey | cmdKey))
}

public final class HotKeyMonitor: @unchecked Sendable {
    /// A stable id for our one hotkey, so the shared dispatcher handler fires ONLY for our press
    /// (not some other app-level hotkey). `signature` is an arbitrary 4-char OSType. NB: these are
    /// static, so all instances share one id — fine for the single hotkey today; a second hotkey
    /// (#24 configurable shortcuts) must make the id per-instance.
    static let signature: OSType = 0x544D_544C   // 'TMTL'
    static let id: UInt32 = 1

    private let config: HotKeyConfig
    private let onFire: @Sendable () -> Void
    private let lock = NSLock()
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
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        var newHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(GetEventDispatcherTarget(), hotKeyHandler,
                                                1, &eventType, selfPtr, &newHandler)
        guard installStatus == noErr, let newHandler else { return false }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.id)
        var newHotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(config.keyCode, config.modifiers, hotKeyID,
                                                 GetEventDispatcherTarget(), 0, &newHotKey)
        guard registerStatus == noErr, let newHotKey else {
            RemoveEventHandler(newHandler)   // don't leak the handler if the hotkey is taken
            return false
        }
        lock.withLock { handlerRef = newHandler; hotKeyRef = newHotKey }
        return true
    }

    /// Unregister the hotkey + remove the handler (leak-clean). Safe if never started.
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
