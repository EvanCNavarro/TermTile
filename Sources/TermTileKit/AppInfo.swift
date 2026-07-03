import Foundation
import TermTileCore

/// The display-metadata authority the About panel (#21) and onboarding (#23) read — one home for
/// "what do we show about this app." `version`/`build` come from `Bundle.main` at runtime; the
/// canonical URLs are constants; `name`/`bundleID` are DERIVED from `AppIdentity` (the pure identity
/// root) so nothing is re-hardcoded. The Accessibility deep-link is deliberately NOT here — it has
/// its own authority (`AccessibilityTrust.settingsDeepLink`); this type never duplicates it.
public struct AppInfo: Sendable {
    /// Marketing version (`CFBundleShortVersionString`), or `"dev"` when unbundled (`swift run`/tests).
    public let version: String
    /// Build number (`CFBundleVersion`), or `"0"` when unbundled.
    public let build: String

    public var name: String { AppIdentity.appName }
    public var bundleID: String { AppIdentity.bundleID }

    public let repoURL: URL
    public let releasesURL: URL
    public let licenseURL: URL

    public init(version: String, build: String) {
        self.version = version
        self.build = build
        // Canonical links — the single Swift-side source (build scripts hold their own copies).
        self.repoURL = URL(string: "https://github.com/EvanCNavarro/TermTile")!
        self.releasesURL = URL(string: "https://github.com/EvanCNavarro/TermTile/releases/latest")!
        // `HEAD` (not a branch name) — GitHub resolves it to the default branch, so a branch rename
        // never 404s this link.
        self.licenseURL = URL(string: "https://github.com/EvanCNavarro/TermTile/blob/HEAD/LICENSE")!
    }

    /// Pure derivation from an Info-plist dictionary — the testable seam (no disk, no real `Bundle`).
    /// A key that is absent OR present-but-empty falls back, so an unbundled process never crashes
    /// and never shows a blank version.
    public static func from(infoDictionary: [String: Any]?) -> AppInfo {
        func value(_ key: String, fallback: String) -> String {
            guard let s = infoDictionary?[key] as? String, !s.isEmpty else { return fallback }
            return s
        }
        return AppInfo(version: value("CFBundleShortVersionString", fallback: "dev"),
                       build: value("CFBundleVersion", fallback: "0"))
    }

    /// The production accessor — reads the running bundle (default `.main`).
    public static func fromBundle(_ bundle: Bundle = .main) -> AppInfo {
        from(infoDictionary: bundle.infoDictionary)
    }
}
