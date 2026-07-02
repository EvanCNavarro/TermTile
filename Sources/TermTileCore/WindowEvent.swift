// Window-event vocabulary observed via per-app AXObserver (spike 05); seed of the
// #9 WindowEvent state-model. Mapping source of truth: the AX notification-name
// strings (kAXWindowCreatedNotification etc. import as these exact Swift Strings).
enum WindowEventKind: Equatable {
    case created
    case moved
    case resized
    case destroyed

    init?(axNotification: String) {
        switch axNotification {
        case "AXWindowCreated": self = .created
        case "AXWindowMoved": self = .moved
        case "AXWindowResized": self = .resized
        case "AXUIElementDestroyed": self = .destroyed
        default: return nil
        }
    }
}
