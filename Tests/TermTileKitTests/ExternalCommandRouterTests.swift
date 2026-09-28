import Foundation
import Testing
@testable import TermTileKit

/// The shell side of `termtile://rearrange`: URLs go through the Core allowlist, and a burst of requests (zio
/// opening three windows in a row) collapses to one running rearrange plus at most one trailing rearrange, so
/// the last window opened is always included and the windows are never walked N times.
@Suite("ExternalCommandRouter — allowlist + burst coalescing")
struct ExternalCommandRouterTests {
    /// Counts runs; each run waits on a gate so the test controls when it finishes.
    actor Work {
        private(set) var runs = 0
        private var gates: [CheckedContinuation<Void, Never>] = []
        func run() async {
            runs += 1
            await withCheckedContinuation { gates.append($0) }
        }
        func releaseOne() -> Bool {
            guard !gates.isEmpty else { return false }
            gates.removeFirst().resume()
            return true
        }
        var waiting: Int { gates.count }
    }

    private func settle(_ work: Work, runs: Int) async {
        for _ in 0..<500 where await work.runs < runs { await Task.yield() }
        for _ in 0..<500 where await work.waiting == 0 { await Task.yield() }
    }

    @Test("an allowlisted URL runs the rearrange once")
    func single() async {
        let work = Work()
        let router = ExternalCommandRouter(rearrange: { await work.run() })
        #expect(await router.receive(URL(string: "termtile://rearrange")!) == true)
        await settle(work, runs: 1)
        #expect(await work.runs == 1)
        _ = await work.releaseOne()
    }

    @Test("a rejected URL runs nothing and reports false")
    func rejected() async {
        let work = Work()
        let router = ExternalCommandRouter(rearrange: { await work.run() })
        #expect(await router.receive(URL(string: "termtile://uninstall")!) == false)
        for _ in 0..<50 { await Task.yield() }
        #expect(await work.runs == 0)
    }

    @Test("five requests during a run → one running + one trailing, never five")
    func burst() async {
        let work = Work()
        let router = ExternalCommandRouter(rearrange: { await work.run() })
        let url = URL(string: "termtile://rearrange")!
        _ = await router.receive(url)
        await settle(work, runs: 1)
        for _ in 0..<5 { _ = await router.receive(url) }
        #expect(await work.runs == 1)          // still inside the first run
        _ = await work.releaseOne()            // first run ends → exactly one trailing run starts
        await settle(work, runs: 2)
        #expect(await work.runs == 2)
        _ = await work.releaseOne()            // trailing run ends → nothing pending
        for _ in 0..<50 { await Task.yield() }
        #expect(await work.runs == 2)
    }

    @Test("a request after the router goes idle starts a fresh run")
    func idleThenAgain() async {
        let work = Work()
        let router = ExternalCommandRouter(rearrange: { await work.run() })
        let url = URL(string: "termtile://rearrange")!
        _ = await router.receive(url)
        await settle(work, runs: 1)
        _ = await work.releaseOne()
        for _ in 0..<50 { await Task.yield() }
        _ = await router.receive(url)
        await settle(work, runs: 2)
        #expect(await work.runs == 2)
        _ = await work.releaseOne()
    }
}
