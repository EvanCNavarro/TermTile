@testable import TermTileCore
import Testing

@Suite("Environment scan — extracts one variable and cannot carry any other")
struct EnvironmentScanTests {
    /// Shape taken from a real `ps -p <pid> -Eww` line. The secrets here are FAKE, but they sit
    /// exactly where the real ones sat when they leaked.
    static let realisticBlock = """
        claude TERM_SESSION_ID=w5t0p0:7F8B92B6-4D93-4EAA-8852-654362F93948 \
        PWD=/Users/evancnavarro/Developer/termtile SECURITYSESSIONID=186a3 \
        ITERM_SESSION_ID=w5t0p0:7F8B92B6-4D93-4EAA-8852-654362F93948 \
        ANTHROPIC_API_KEY=sk-ant-api03-FAKEKEYFORTESTINGONLY-not-a-real-credential \
        SESSION_SECRET=deadbeefcafe0000deadbeefcafe0000deadbeefcafe0000 \
        SUNO_CLERK_ACTIVE_CONTEXT=session_abc123 __MISE_SESSION=eAHqWpOTn5iSmhJfkp+fUzxhHZSXnJ
        """

    @Test("the observed form parses to window, tab and pane")
    func observedForm() {
        let id = EnvironmentScan.sessionID(fromEnvironmentBlock: Self.realisticBlock)
        #expect(id == ITermSessionID(windowIndex: 5, tabIndex: 0, paneIndex: 0))
    }

    /// THE LEAK TEST. It lands before the parser exists, per #37c. If the return value can be
    /// rendered into a string containing anything from the block but the indices, the structural
    /// guarantee has been broken — most likely by someone adding a convenient `rawValue`.
    @Test("nothing but the indices can escape the scanner")
    func nothingButIndicesEscapes() {
        guard let id = EnvironmentScan.sessionID(fromEnvironmentBlock: Self.realisticBlock) else {
            Issue.record("expected a session id from a block that contains one")
            return
        }
        let rendered = String(describing: id) + String(reflecting: id)
        for forbidden in [
            "sk-ant", "FAKEKEYFORTESTINGONLY", "ANTHROPIC", "deadbeef", "SESSION_SECRET",
            "7F8B92B6", "4D93-4EAA", "SUNO", "__MISE_SESSION", "eAHqWpOTn5", "PWD",
            "/Users/evancnavarro", "SECURITYSESSIONID", "186a3"
        ] {
            #expect(!rendered.contains(forbidden),
                    "the scanner's return value leaked \(forbidden)")
        }
    }

    /// The UUID half of ITERM_SESSION_ID is genuinely unnecessary — the indices are the join key
    /// — so it must not be retained either. It is not a credential, but it is the habit that
    /// makes the type start carrying things.
    @Test("the session UUID is discarded, not stored")
    func uuidDiscarded() {
        let id = EnvironmentScan.sessionID(fromEnvironmentBlock: Self.realisticBlock)
        #expect(!String(reflecting: id).contains("7F8B92B6"))
    }

    /// A substring match on "ITERM_SESSION_ID=" also matches "MY_ITERM_SESSION_ID=" and would
    /// read another program's variable as iTerm's.
    @Test("a variable merely ENDING in the permitted name is not a match")
    func prefixTrap() {
        let block = "MY_ITERM_SESSION_ID=w9t9p9:AAAA OTHER=1"
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: block) == nil)
    }

    @Test("a block without the variable yields nil")
    func absent() {
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: "TERM=xterm PWD=/tmp") == nil)
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: "") == nil)
    }

    @Test("malformed values yield nil rather than a partial guess")
    func malformed() {
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: "ITERM_SESSION_ID=garbage") == nil)
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: "ITERM_SESSION_ID=w5t0") == nil)
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: "ITERM_SESSION_ID=") == nil)
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: "ITERM_SESSION_ID=wXtYpZ:U") == nil)
    }

    @Test("multi-digit indices parse — a tenth window is w9, an eleventh is w10")
    func multiDigit() {
        let block = "ITERM_SESSION_ID=w12t3p4:ABC"
        #expect(EnvironmentScan.sessionID(fromEnvironmentBlock: block)
            == ITermSessionID(windowIndex: 12, tabIndex: 3, paneIndex: 4))
    }
}
