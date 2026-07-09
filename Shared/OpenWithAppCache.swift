import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Open With App URL Cache

/// Caches resolved Open With app URLs in the shared App Group container.
/// The main app (non-sandboxed) resolves bundle IDs to file URLs and writes
/// this cache. The sandboxed FinderSync extension reads it, since
/// NSWorkspace.shared.urlForApplication may fail in the extension sandbox.
enum OpenWithAppCache {

    private static let fileName = "openwith_apps.json"

    /// Mapping: OpenWithSpec.id → absolute path of the .app bundle (e.g. /Applications/Visual Studio Code.app)
    private struct Cache: Codable {
        var apps: [String: String] = [:]
    }

    private static var fileURL: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RCBAppGroup.id)
        else { return nil }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }

    // MARK: - Write (main app only)

    /// Resolve all OpenWithSpec bundle IDs and persist the mapping.
    /// Call from the main app after launch or when settings change.
    /// Requires AppKit (NSWorkspace). Compiles as a no-op in targets without AppKit.
    static func refresh() {
        #if canImport(AppKit)
        _refreshWithAppKit()
        #else
        AppLogger.app.error("OpenWithAppCache: refresh requires AppKit")
        #endif
    }

    // MARK: - Read (extension)

    /// Returns the cached app path for a given spec ID, or nil if not cached.
    static func cachedAppPath(for specId: String) -> String? {
        guard let url = fileURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return nil }
        return cache.apps[specId]
    }

    /// Returns true if the spec ID has a cached app path.
    static func isAppCached(_ specId: String) -> Bool {
        cachedAppPath(for: specId) != nil
    }

    /// Returns the cached app URL for a given spec ID, or nil.
    static func cachedAppURL(for specId: String) -> URL? {
        guard let path = cachedAppPath(for: specId) else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Private (AppKit only)

    #if canImport(AppKit)
    private static func _refreshWithAppKit() {
        guard let url = fileURL else {
            AppLogger.app.error("OpenWithAppCache: no container URL")
            return
        }

        var cache = Cache()

        for spec in RCBSettings.openWithSpecs {
            if let appURL = resolveFirstBundle(spec.bundleIdCandidates) {
                cache.apps[spec.id] = appURL.path
            }
        }

        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: url, options: .atomic)
            AppLogger.app.info("OpenWithAppCache: refreshed \(cache.apps.count) apps")
        } catch {
            AppLogger.app.error("OpenWithAppCache: write failed \(error.localizedDescription)")
        }
    }

    private static func resolveFirstBundle(_ candidates: [String]) -> URL? {
        for bundleId in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return url
            }
        }
        return nil
    }
    #endif
}
