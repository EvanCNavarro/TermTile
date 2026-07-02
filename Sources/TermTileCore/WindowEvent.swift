import CoreGraphics

// Window-event vocabulary observed via per-app AXObserver (spike 05); seed of the
// #9 WindowEvent state-model. Mapping source of truth: the AX notification-name
// strings (kAXWindowCreatedNotification etc. import as these exact Swift Strings).
public enum WindowEventKind: Equatable, Sendable {
    case created
    case moved
    case resized
    case destroyed

    public init?(axNotification: String) {
        switch axNotification {
        case "AXWindowCreated": self = .created
        case "AXWindowMoved": self = .moved
        case "AXWindowResized": self = .resized
        case "AXUIElementDestroyed": self = .destroyed
        default: return nil
        }
    }
}

/// One observed window-system event fed to `WindowStateReducer` (ADR-0001 rule 3). The
/// imperative shell's AX adapter (#10) constructs these from AXObserver callbacks. `frame`
/// is present for `.created`/`.moved`/`.resized` and `nil` for `.destroyed` — at destroy the
/// CGWindowID is unresolvable (spike-05: err=-25201) so the adapter supplies the id it
/// recorded at create time via its element(hash)→CGWindowID map; a nil frame on a
/// frame-bearing kind is treated as a defensive no-op by the reducer.
public struct WindowEvent: Equatable, Sendable {
    public let windowID: CGWindowID
    public let kind: WindowEventKind
    public let frame: CGRect?

    public init(windowID: CGWindowID, kind: WindowEventKind, frame: CGRect?) {
        self.windowID = windowID
        self.kind = kind
        self.frame = frame
    }
}
