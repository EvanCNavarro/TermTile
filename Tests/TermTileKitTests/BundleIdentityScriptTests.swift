import Foundation
import Testing

/// TRAP-23 (2026-09-28): a local build launched under the production bundle ID pinned the user's Accessibility row
/// to that build's code identity, so the signed release stayed untrusted with the toggle ON. Only a Developer ID
/// build may default to the production bundle ID; every other local build defaults to `.local`. Runs the real
/// shell function in `scripts/lib/identity.sh`, which build-app.sh and test-packaged-app.sh both source.
@Suite("Bundle identity — only Developer ID builds get the production ID")
struct BundleIdentityScriptTests {
    private static func repoRoot() -> URL {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: "Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("could not locate Package.swift above \(#filePath)")
    }

    /// `termtile_default_bundle_id "<identity>"` with an optional explicit BUNDLE_ID in the environment.
    private static func bundleID(identity: String, explicit: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-c", "source scripts/lib/identity.sh && termtile_default_bundle_id \"$1\"", "-", identity]
        process.currentDirectoryURL = repoRoot()
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "BUNDLE_ID")
        if let explicit { env["BUNDLE_ID"] = explicit }
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("Developer ID → production bundle ID")
    func developerID() throws {
        #expect(try Self.bundleID(identity: "Developer ID Application: Evan Navarro (XG9SBNWNXT)")
                == "dev.ecn.apps.termtile")
    }

    @Test("ad-hoc and the local dev certificate → .local", arguments: ["-", "TermTile Dev Signing"])
    func localBuilds(_ identity: String) throws {
        #expect(try Self.bundleID(identity: identity) == "dev.ecn.apps.termtile.local")
    }

    @Test("an explicit BUNDLE_ID always wins")
    func explicitWins() throws {
        #expect(try Self.bundleID(identity: "-", explicit: "dev.ecn.apps.termtile") == "dev.ecn.apps.termtile")
    }
}
