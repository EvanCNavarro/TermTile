import Foundation

/// Resolves the selected running app consistently across Kit adapters. The picker stores a bundle
/// id, but multiple processes can share that id; every command path should prefer the same regular
/// app before falling back to any matching process.
enum TargetRunningApplicationResolver {
    static func preferred<App>(
        bundleID: String,
        in apps: [App],
        bundleIdentifier: (App) -> String?,
        isRegular: (App) -> Bool
    ) -> App? {
        let matching = apps.filter { bundleIdentifier($0) == bundleID }
        return matching.first(where: isRegular) ?? matching.first
    }
}
