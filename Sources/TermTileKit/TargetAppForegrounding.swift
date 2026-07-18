import Foundation

/// Result of asking macOS to bring the selected target app forward (#36). App activation is a
/// request, not a guarantee, so production reports whether the request reached frontmost state.
public enum TargetForegroundResult: Equatable, Sendable {
    case frontmost
    case requestAcceptedButUnverified
    case notRunning
    case activationRejected
}

/// App-foregrounding port for the manual Rearrange command (#36). This lives in Kit because it is
/// an imperative AppKit/macOS shell concern, not pure layout policy.
@MainActor
public protocol TargetAppForegrounding {
    func bringToFront(bundleID: String) async -> TargetForegroundResult
}
