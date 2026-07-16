import Foundation
import TermTileCore

/// In-app uninstall: deregisters the login item, clears TermTile's own TCC rows, and moves
/// TermTile's owned data + `.app` bundle to the Trash (never `rm`). It touches ONLY the exact
/// literals in `OwnedPaths` — no glob, no directory scan — so a neighbour is structurally
/// unreachable. `@MainActor` because the About panel's button drives it; `trash` is injectable so
/// tests prove scope without the real Trash.
///
/// The prefs domain is cleared via `SettingsStore.purge()` (not a loose plist trash): `cfprefsd`
/// caches the domain and would rewrite a separately-trashed plist on the next flush, leaving
/// residue that can poison a future reinstall. The CALLER must then `exit(0)` (a graceful
/// `NSApp.terminate` re-flushes UserDefaults).
///
/// Ordering (unregister → privacy reset → data → bundle) is NOT because trashing the running bundle
/// stops us — it doesn't (a same-volume APFS move; macOS holds the executable by inode, the process
/// keeps running). It's so `unregister()` runs while the bundle is still resolvable (else a ghost
/// background-item), and so privacy/data cleanup happens before quit.
@MainActor
public struct Uninstaller {
    /// Where a trashed bundle ended up, or why it couldn't be trashed (→ Finder-reveal fallback).
    public enum BundleOutcome: Equatable, Sendable {
        case trashed(URL)       // NB: carries the pre-trash location, not the resulting Trash URL
        case needsManual(URL)   // couldn't trash (read-only volume) — ask the user to drag it
        case noBundle           // no bundle URL supplied, OR it wasn't there (nothing to remove)
    }
    /// Login-item deregistration result — a thrown `unregister()` (e.g. unsigned build) must be
    /// visible so the UI can warn rather than silently leave a ghost item.
    public enum DeregResult: Sendable {
        case ok
        case failed(Error)
        public var isOK: Bool { if case .ok = self { return true }; return false }
    }
    /// The complete result — a PARTIAL uninstall must be distinguishable from a clean one.
    public struct UninstallOutcome: Sendable {
        public let removedData: [URL]
        public let failedData: [(url: URL, error: Error)]
        public let bundle: BundleOutcome
        public let loginItem: DeregResult
        public let permissionRepairAttempted: Bool
        /// Scoped TCC cleanup reports. Empty means no repairer was injected (tests/unbundled), not
        /// that a shell command was invented somewhere else.
        public let permissionRepairReports: [PermissionRepairReport]

        public var failedPermissionRepairReports: [PermissionRepairReport] {
            permissionRepairReports.filter { !$0.succeeded }
        }
        public var permissionRepairSucceeded: Bool {
            permissionRepairAttempted && failedPermissionRepairReports.isEmpty
        }

        /// One source of truth for "was this a fully clean uninstall?" — so #21's UI doesn't
        /// re-derive the predicate. Clean = no data failures, login item deregistered, bundle not
        /// left for manual removal, and privacy reset completed successfully.
        public var isClean: Bool {
            guard failedData.isEmpty, loginItem.isOK else { return false }
            guard permissionRepairSucceeded else { return false }
            if case .needsManual = bundle { return false }
            return true
        }
        /// The bundle URL only when it needs manual removal (nil otherwise) — for the UI's
        /// Finder-reveal affordance.
        public var bundleURLIfManual: URL? {
            if case let .needsManual(url) = bundle { return url }
            return nil
        }
    }

    private let ownedPaths: OwnedPaths
    private let loginItem: any LoginItem
    private let settings: any SettingsStore
    private let bundleURL: URL?
    private let permissionRepairer: (any PermissionRepairing)?
    private let trash: (URL) throws -> Void

    public init(
        ownedPaths: OwnedPaths,
        loginItem: any LoginItem,
        settings: any SettingsStore,
        bundleURL: URL?,
        permissionRepairer: (any PermissionRepairing)? = nil,
        trash: ((URL) throws -> Void)? = nil
    ) {
        self.ownedPaths = ownedPaths
        self.loginItem = loginItem
        self.settings = settings
        self.bundleURL = bundleURL
        self.permissionRepairer = permissionRepairer
        // FileManager.default resolved inline (not stored) — matches the codebase's Sendable pattern.
        self.trash = trash ?? { url in
            var out: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &out)
        }
    }

    /// Clear the prefs domain, then trash every owned data path that still exists. `purge()` clears
    /// cfprefsd's IN-MEMORY registration (so it can't rewrite the plist on a later flush); its
    /// on-disk plist deletion is ASYNC, so the loop below STILL trashes the plist if it's present —
    /// intentional belt-and-suspenders, not a skip. Best-effort: a path that fails to trash is
    /// REPORTED (not silently dropped) and does not abort the rest.
    public func removeData() -> (removed: [URL], failed: [(url: URL, error: Error)]) {
        settings.purge()
        var removed: [URL] = []
        var failed: [(url: URL, error: Error)] = []
        for url in ownedPaths.dataPaths where FileManager.default.fileExists(atPath: url.path) {
            do { try trash(url); removed.append(url) } catch { failed.append((url, error)) }
        }
        return (removed, failed)
    }

    /// Trash the `.app` bundle. A same-volume move — the running process survives. Throws internally
    /// are mapped to `.needsManual` so the UI can offer a Finder reveal.
    public func removeBundle() -> BundleOutcome {
        guard let bundleURL, FileManager.default.fileExists(atPath: bundleURL.path) else { return .noBundle }
        do { try trash(bundleURL); return .trashed(bundleURL) } catch { return .needsManual(bundleURL) }
    }

    /// Deregister the login item, surfacing any throw (unsigned build) rather than swallowing it.
    public func deregisterLoginItem() -> DeregResult {
        do { try loginItem.unregister(); return .ok } catch { return .failed(error) }
    }

    /// Clear TermTile's own privacy rows; this never grants permission and is intentionally routed
    /// through `PermissionRepairing` so TCC service names stay single-sourced.
    public func resetPrivacyPermissions() -> [PermissionRepairReport] {
        permissionRepairer?.reset([.accessibility, .inputMonitoring]) ?? []
    }

    /// The full flow in the safe order: unregister (while the bundle resolves) → reset privacy rows
    /// → purge+trash data (while alive) → trash the bundle. The caller renders the outcome and then
    /// `exit(0)`.
    public func uninstall() -> UninstallOutcome {
        let login = deregisterLoginItem()
        let privacyAttempted = permissionRepairer != nil
        let privacy = resetPrivacyPermissions()
        let (removed, failed) = removeData()
        let bundle = removeBundle()
        return UninstallOutcome(removedData: removed, failedData: failed, bundle: bundle,
                                loginItem: login, permissionRepairAttempted: privacyAttempted,
                                permissionRepairReports: privacy)
    }
}
