import Testing
@testable import TermTileKit

@MainActor
@Suite("PermissionRepairer — stale TCC grant reset")
struct PermissionRepairerTests {
    @Test("maps repair scopes to tccutil reset services for TermTile only")
    func mapsScopesToTCCUtil() {
        final class Calls {
            var values: [(String, [String])] = []
        }
        let calls = Calls()
        let repairer = TCCPermissionRepairer(bundleID: "dev.ecn.apps.termtile") { executable, arguments in
            calls.values.append((executable, arguments))
            return 0
        }

        let reports = repairer.reset([.accessibility, .inputMonitoring])

        #expect(reports == [
            PermissionRepairReport(scope: .accessibility, exitCode: 0),
            PermissionRepairReport(scope: .inputMonitoring, exitCode: 0)
        ])
        #expect(calls.values.map(\.0) == ["/usr/bin/tccutil", "/usr/bin/tccutil"])
        #expect(calls.values.map(\.1) == [
            ["reset", "Accessibility", "dev.ecn.apps.termtile"],
            ["reset", "ListenEvent", "dev.ecn.apps.termtile"]
        ])
    }

    @Test("reports per-scope failures without hiding later resets")
    func reportsFailures() {
        var exitCodes: [Int32] = [1, 0]
        let repairer = TCCPermissionRepairer(bundleID: "dev.ecn.apps.termtile") { _, _ in
            exitCodes.removeFirst()
        }

        let reports = repairer.reset([.accessibility, .inputMonitoring])

        #expect(reports.map(\.succeeded) == [false, true])
    }
}
