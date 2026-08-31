import Foundation
import TermTileCore

/// Runs `TintingCoordinator.pass()` on an interval while tinting is enabled.
///
/// Replaces the launchd job the out-of-tree tool needed (`StartInterval 5`). A menu-bar app
/// already has a run loop, so the schedule belongs in the app rather than in a plist the user
/// cannot see and would have to uninstall separately.
public actor TintingDriver {
    private let coordinator: TintingCoordinator
    private let interval: Duration
    private var loop: Task<Void, Never>?
    /// Passes completed since the driver last started.
    private(set) public var completedPasses = 0
    /// How many loops have actually been CREATED. Exposed so idempotence can be asserted
    /// deterministically: counting passes over a wall-clock window measures machine speed as much
    /// as it measures the guard, and a flaky gate is worse than none.
    private(set) public var loopsStarted = 0

    public func setReadyIntensity(_ intensity: ReadyIntensity) async {
        await coordinator.setReadyIntensity(intensity)
    }

    public init(coordinator: TintingCoordinator, interval: Duration = .seconds(5)) {
        self.coordinator = coordinator
        self.interval = interval
    }

    public var isRunning: Bool { loop != nil }

    /// Idempotent: starting an already-running driver is a no-op, not a second loop. Two loops
    /// would double the poll rate and race each other's baselines.
    public func start() {
        guard loop == nil else { return }
        loopsStarted += 1
        loop = Task { [coordinator, interval] in
            while !Task.isCancelled {
                await coordinator.pass()
                await self.countPass()
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    private func countPass() { completedPasses += 1 }

    /// Stop polling AND put every touched session back to normal.
    ///
    /// The reset is not optional. A tinted window that outlives the feature is orphaned state:
    /// the user cannot explain the colour and TermTile is no longer maintaining it.
    public func stop() async {
        loop?.cancel()
        loop = nil
        await coordinator.resetAll()
    }
}
