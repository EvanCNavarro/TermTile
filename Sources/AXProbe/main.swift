// Spike 02 probe — prints whether THIS process is trusted for Accessibility.
// Run contexts compared: shell-exec (TCC attributes to the terminal) vs a micro
// .app bundle launched via `open` (attributes to itself). Findings note:
// docs/research/spikes/02-accessibility-tcc.md
// Throwaway-quality by design (backlog Phase A contract).
@preconcurrency import ApplicationServices
import Foundation

let key: CFString = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
// --prompt exercises the grant-dialog path; guarded because even prompting:false
// registers a denied TCC row when run from a bundle (spike finding — see note).
let prompting = CommandLine.arguments.contains("--prompt")
let trusted = AXIsProcessTrustedWithOptions([key: prompting] as CFDictionary)

let report = "trusted=\(trusted) prompting=\(prompting) pid=\(ProcessInfo.processInfo.processIdentifier) "
    + "path=\(CommandLine.arguments[0]) bundleID=\(Bundle.main.bundleIdentifier ?? "none")"

// `open` drops the caller's env, so the launcher passes AXPROBE_OUT via `open --env`.
if let outPath = ProcessInfo.processInfo.environment["AXPROBE_OUT"] {
    try? (report + "\n").write(toFile: outPath, atomically: true, encoding: .utf8)
}
print(report)

