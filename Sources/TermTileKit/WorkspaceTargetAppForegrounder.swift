import AppKit
import CoreGraphics
import Foundation

@MainActor
protocol RunningAppActivating {
    var bundleIdentifier: String? { get }
    var isRegular: Bool { get }
    var isHidden: Bool { get }
    var isActive: Bool { get }
    var hasFrontmostVisibleWindow: Bool { get }

    @discardableResult func unhide() -> Bool
    @discardableResult func activateAllWindows() -> Bool
}

@MainActor
struct TargetAppForegroundCoordinator<App: RunningAppActivating> {
    let runningApplications: (String) -> [App]
    let frontmostBundleID: () -> String?
    let sleep: (Duration) async -> Void
    let pollAttempts: Int

    func bringToFront(bundleID: String) async -> TargetForegroundResult {
        guard let app = TargetRunningApplicationResolver.preferred(
            bundleID: bundleID,
            in: runningApplications(bundleID),
            bundleIdentifier: \.bundleIdentifier,
            isRegular: \.isRegular
        ) else {
            return .notRunning
        }
        if app.isHidden { _ = app.unhide() }
        guard app.activateAllWindows() else { return .activationRejected }

        let attempts = max(1, pollAttempts)
        for attempt in 0..<attempts {
            if app.isActive || frontmostBundleID() == bundleID || app.hasFrontmostVisibleWindow {
                return .frontmost
            }
            if attempt < attempts - 1 {
                await sleep(.milliseconds(20))
            }
        }
        return .requestAcceptedButUnverified
    }
}

private struct WorkspaceRunningApplication: RunningAppActivating {
    let app: NSRunningApplication

    var bundleIdentifier: String? { app.bundleIdentifier }
    var isRegular: Bool { app.activationPolicy == .regular }
    var isHidden: Bool { app.isHidden }
    var isActive: Bool { app.isActive }
    var hasFrontmostVisibleWindow: Bool {
        Self.hasFrontmostVisibleWindow(forPID: app.processIdentifier)
    }

    @discardableResult
    func unhide() -> Bool {
        app.unhide()
    }

    @discardableResult
    func activateAllWindows() -> Bool {
        app.activate(options: [.activateAllWindows])
    }

    private static func hasFrontmostVisibleWindow(forPID pid: pid_t) -> Bool {
        guard pid > 0,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            return false
        }
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerName as String] as? String) != "Window Server",
                  let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber,
                  let height = bounds["Height"] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0 else {
                continue
            }
            return pid_t(ownerPID) == pid
        }
        return false
    }
}

/// Production target-app foregrounder (#36). It asks AppKit to activate the selected app and bring
/// all of its windows forward, then briefly verifies the user-visible result via public app and
/// window-order signals.
public struct WorkspaceTargetAppForegrounder: TargetAppForegrounding {
    private let coordinator: TargetAppForegroundCoordinator<WorkspaceRunningApplication>

    public init() {
        self.coordinator = TargetAppForegroundCoordinator(
            runningApplications: { bundleID in
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                    .map(WorkspaceRunningApplication.init(app:))
            },
            frontmostBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
            sleep: { duration in try? await Task.sleep(for: duration) },
            pollAttempts: 10)
    }

    public func bringToFront(bundleID: String) async -> TargetForegroundResult {
        await coordinator.bringToFront(bundleID: bundleID)
    }
}
