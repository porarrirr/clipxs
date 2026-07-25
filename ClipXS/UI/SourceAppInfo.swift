import AppKit

/// Resolves and caches icon/name for an entry's source app. Lookups hit the
/// filesystem (NSWorkspace), so rows share one cache keyed by bundle ID.
enum SourceAppInfo {
    private struct Info {
        let icon: NSImage?
        let name: String?
    }

    private static var cache: [String: Info] = [:]

    static func icon(for bundleId: String) -> NSImage? {
        info(for: bundleId).icon
    }

    static func name(for bundleId: String) -> String? {
        info(for: bundleId).name
    }

    private static func info(for bundleId: String) -> Info {
        if let cached = cache[bundleId] {
            return cached
        }
        let info: Info
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            info = Info(icon: icon, name: FileManager.default.displayName(atPath: url.path))
        } else {
            info = Info(icon: nil, name: nil)
        }
        cache[bundleId] = info
        return info
    }
}
