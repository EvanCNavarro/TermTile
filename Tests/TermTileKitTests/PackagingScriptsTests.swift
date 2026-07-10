import Foundation
import Testing

/// #13a — the packaging scripts unit-tested AS TEXT (RememBar's "scripts unit-tested as text"
/// pattern; audit §4/§8). Each assertion pins one hard-won packaging lesson as a POSITIVE,
/// line-scoped invariant so it can't be satisfied vacuously by an empty/stub file (skeptic F1/F2).
/// The LIVE proof that the script actually produces a launchable, correctly-signed bundle is #13a's
/// PROVE (build the .app + AX/bundle-id discriminator + screencapture), not here.
@Suite("Packaging scripts — text invariants (#13a)")
struct PackagingScriptsTests {
    // Resolve the repo root via #filePath walk-up (robust vs CWD): climb until a dir has Package.swift.
    private static func repoRoot() -> URL {
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appending(path: "Package.swift").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("could not locate Package.swift above \(#filePath)")
    }

    private static func script(_ name: String) -> String {
        let url = repoRoot().appending(path: "scripts/\(name)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func lines(_ text: String) -> [String] { text.split(separator: "\n").map(String.init) }

    // 1. Inside-out codesign via the #13c identity parameter: sign lines use
    //    `--sign "$SIGN_IDENTITY"`, which resolves explicit env → local dev cert → ad-hoc FALLBACK
    //    (so CI needs no keychain), and must NOT carry `--deep` (per Sparkle/audit — `--deep` corrupts
    //    nested signatures); the VERIFY line must carry BOTH `--deep` and `--strict`. Line-scoped +
    //    positive so it can't false-fail on the verify line's legitimate `--deep`, nor pass vacuously.
    @Test("build-app.sh: sign lines use $SIGN_IDENTITY (ad-hoc fallback), no --deep; verify has --deep AND --strict")
    func codesignFlagsAreCorrect() {
        let ls = Self.lines(Self.script("build-app.sh"))
        // Inspect EVERY sign line (inside-out signs the inner Mach-O AND the bundle) — checking only
        // the first would miss a --deep smuggled onto a later sign line (caught by the invert-check).
        let signLines = ls.filter { l in
            l.contains("codesign") && l.contains("--sign \"$SIGN_IDENTITY\"")
        }
        #expect(!signLines.isEmpty, "no codesign --sign \"$SIGN_IDENTITY\" line found")
        #expect(signLines.allSatisfy { !$0.contains("--deep") }, "no sign line may contain --deep")
        // Resolution: explicit TERMTILE_SIGN_IDENTITY wins; else auto-use the local dev cert IF present;
        // else fall back to ad-hoc so CI (no env, no keychain cert) needs no signing setup (#13c).
        let script = Self.script("build-app.sh")
        #expect(script.contains("TERMTILE_SIGN_IDENTITY"), "explicit sign-identity override must exist")
        #expect(script.contains("SIGN_IDENTITY=\"-\""),
                "SIGN_IDENTITY must fall back to ad-hoc (\"-\") so CI needs no keychain")

        let verifyLine = ls.first { $0.contains("codesign") && $0.contains("--verify") }
        #expect(verifyLine != nil, "no codesign --verify line found")
        #expect(verifyLine?.contains("--deep") == true, "verify line must contain --deep")
        #expect(verifyLine?.contains("--strict") == true, "verify line must contain --strict")
    }

    // 2. Monotonic CFBundleVersion from commit count; never dots-stripped (audit §8.5 collision bug:
    //    `0.10.1 → 0101`). Positive presence of the real source + absence of every dots-strip idiom.
    @Test("build-app.sh: CFBundleVersion uses git rev-list --count, never dots-stripped")
    func buildNumberIsMonotonic() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("git rev-list --count"), "build number must come from git rev-list --count")
        #expect(!s.contains("tr -d '.'"), "must not dots-strip the version (tr -d '.')")
        #expect(!s.contains("//./"), "must not dots-strip the version (bash //./ substitution)")
        #expect(!s.contains("s/\\.//g"), "must not dots-strip the version (sed s/./g)")
    }

    // 3. Menu-bar-only bundle + a lint gate on the generated plist.
    @Test("build-app.sh: sets LSUIElement and lints the Info.plist")
    func plistIsMenuBarAndLinted() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("LSUIElement"), "Info.plist must set LSUIElement (menu-bar only)")
        #expect(s.contains("plutil -lint"), "the generated Info.plist must be plutil -lint'ed")
    }

    // 4. Locate the built binary via --show-bin-path (RememBar crown-jewel), never a hardcoded
    //    .build/{debug,release} path (which rots across configs/toolchains).
    @Test("build-app.sh: locates binary via --show-bin-path, no hardcoded .build path")
    func binaryLocatedRobustly() {
        let s = Self.script("build-app.sh")
        #expect(s.contains("--show-bin-path"), "must locate the binary via swift build --show-bin-path")
        #expect(!s.contains(".build/debug"), "must not hardcode .build/debug")
        #expect(!s.contains(".build/release"), "must not hardcode .build/release")
    }

    // 5. The launch smoke really launches + verifies (positive kill -0 + codesign --verify) and never
    //    globally kills a process (RememBar safety invariant — no pkill/killall).
    @Test("test-packaged-app.sh: launches (kill -0) + verifies signature, never pkill/killall")
    func smokeLaunchesAndIsSafe() {
        let s = Self.script("test-packaged-app.sh")
        #expect(s.contains("kill -0"), "smoke must poll liveness with kill -0")
        #expect(s.contains("codesign") && s.contains("--verify"), "smoke must codesign --verify the bundle")
        // Line-scoped to CODE (skip comment lines): a "never pkill" comment is fine; INVOKING it isn't.
        let codeLines = Self.lines(s).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        #expect(!codeLines.contains { $0.contains("pkill") }, "smoke must never invoke pkill")
        #expect(!codeLines.contains { $0.contains("killall") }, "smoke must never invoke killall")
    }

    // 6. Both scripts exist and are executable (a text-present stub that isn't chmod +x never runs).
    @Test("both packaging scripts exist and are executable")
    func scriptsAreExecutable() {
        let fm = FileManager.default
        for name in ["build-app.sh", "test-packaged-app.sh"] {
            let path = Self.repoRoot().appending(path: "scripts/\(name)").path
            #expect(fm.fileExists(atPath: path), "\(name) must exist")
            #expect(fm.isExecutableFile(atPath: path), "\(name) must be executable (chmod +x)")
        }
    }
}
