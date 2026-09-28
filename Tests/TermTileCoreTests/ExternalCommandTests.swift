import Foundation
import Testing
@testable import TermTileCore

/// External trigger (zio): another local program asks TermTile to act with
/// `open -g termtile://rearrange`. Any app or web page can open a custom URL, so the parser is a
/// strict allowlist: one exact command with no path, query, fragment or credentials. Everything
/// else is nil, and the shell ignores nil.
@Suite("ExternalCommand — termtile:// URL allowlist")
struct ExternalCommandTests {
    @Test("termtile://rearrange → .rearrange")
    func rearrange() {
        #expect(ExternalCommand(url: URL(string: "termtile://rearrange")!) == .rearrange)
    }

    // RFC 3986: scheme and host are case-insensitive; LaunchServices may hand either form over.
    @Test("scheme and host are case-insensitive")
    func caseInsensitive() {
        #expect(ExternalCommand(url: URL(string: "TermTile://REARRANGE")!) == .rearrange)
    }

    @Test("a trailing slash alone is still the bare command")
    func trailingSlash() {
        #expect(ExternalCommand(url: URL(string: "termtile://rearrange/")!) == .rearrange)
    }

    @Test("rejected", arguments: [
        "termtile://uninstall",              // not on the allowlist
        "termtile://",                       // no command
        "termtile:rearrange",                // no authority
        "https://rearrange",                 // wrong scheme
        "termtile://rearrange?gap=0",        // parameters are not accepted
        "termtile://rearrange#x",            // fragment
        "termtile://rearrange/extra",        // path
        "termtile://user@rearrange",         // credentials
        "termtile://rearrange:80",           // port
    ])
    func rejected(_ raw: String) {
        #expect(ExternalCommand(url: URL(string: raw)!) == nil)
    }
}
