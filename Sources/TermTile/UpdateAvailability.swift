enum UpdateAvailability: Equatable {
    case unknown
    case checking
    case available(version: String?)
    case unavailable
    case failed

    var hasAvailableUpdate: Bool {
        if case .available = self { return true }
        return false
    }
}
