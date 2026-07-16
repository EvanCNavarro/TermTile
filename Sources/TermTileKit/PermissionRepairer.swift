import Foundation
import Dispatch
import TermTileCore

/// The macOS TCC grants TermTile depends on. The service names are the `tccutil reset` arguments for
/// resetting this app's stale rows; callers still reopen System Settings because macOS
/// requires the user to grant consent again.
public enum PermissionRepairScope: Equatable, Sendable {
    case accessibility
    case inputMonitoring

    public var label: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var tccutilService: String {
        switch self {
        case .accessibility: "Accessibility"
        case .inputMonitoring: "ListenEvent"
        }
    }
}

public struct PermissionRepairReport: Equatable, Sendable {
    public let scope: PermissionRepairScope
    public let exitCode: Int32

    public init(scope: PermissionRepairScope, exitCode: Int32) {
        self.scope = scope
        self.exitCode = exitCode
    }

    public var succeeded: Bool { exitCode == 0 }
}

@MainActor
public protocol PermissionRepairing: AnyObject {
    @discardableResult
    func reset(_ scopes: [PermissionRepairScope]) -> [PermissionRepairReport]
}

/// Production repair adapter for stale TCC grants. This does not grant permission; it only clears
/// TermTile's own old rows so the current signed app can be granted normally in System Settings.
@MainActor
public final class TCCPermissionRepairer: PermissionRepairing {
    public typealias Runner = (_ executable: String, _ arguments: [String]) -> Int32

    private static let processTimeout: DispatchTimeInterval = .seconds(2)
    private static let timedOutExitCode: Int32 = 124

    private let bundleID: String
    private let runner: Runner

    public convenience init(bundleID: String = AppIdentity.bundleID) {
        self.init(bundleID: bundleID, runner: TCCPermissionRepairer.runProcess)
    }

    public init(bundleID: String, runner: @escaping Runner) {
        self.bundleID = bundleID
        self.runner = runner
    }

    @discardableResult
    public func reset(_ scopes: [PermissionRepairScope]) -> [PermissionRepairReport] {
        scopes.map { scope in
            let exitCode = runner("/usr/bin/tccutil", ["reset", scope.tccutilService, bundleID])
            return PermissionRepairReport(scope: scope, exitCode: exitCode)
        }
    }

    private static func runProcess(_ executable: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        let finished = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            guard finished.wait(timeout: .now() + processTimeout) == .success else {
                if process.isRunning { process.terminate() }
                return timedOutExitCode
            }
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}
