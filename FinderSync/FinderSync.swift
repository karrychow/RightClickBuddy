import AppKit
import FinderSync
import os

final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "com.karry.RightClickBuddy", category: "FinderSync")
    /// Synchronous file logger — survives extension crashes.
    private let fileLog = ExtensionLogger(category: "FinderSync")

    private var lastAppliedScopeDirectories: Set<URL>?
    private var cachedRealUserHomeDirectoryURL: URL?

    private var activeSecurityScopedRoots: [String: URL] = [:]
    private var lastResolvedScopeRootURLs: [URL] = []

    private func resolvedRealUserHomeDirectoryURL() -> URL {
        if let cachedRealUserHomeDirectoryURL { return cachedRealUserHomeDirectoryURL }

        let fm = FileManager.default

        // Heuristic 1: /Users/<shortname>
        // In FinderSync sandbox, APIs like NSHomeDirectory() may return the container home.
        // We still want the real home to scope Desktop/Downloads/etc.
        let shortName = NSUserName()
        let usersCandidate = URL(fileURLWithPath: "/Users/\(shortName)", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        if usersCandidate.path.hasPrefix("/Users/") {
            // In sandbox, checking file existence may be denied and return false.
            // Still prefer this as the real home for scoping common folders.
            cachedRealUserHomeDirectoryURL = usersCandidate
            return usersCandidate
        }

        // Heuristic 2: parent of Downloads if it looks like /Users/<name>/Downloads
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let home = downloads.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
            if home.path.hasPrefix("/Users/") {
                cachedRealUserHomeDirectoryURL = home
                return home
            }
        }

        // Fallback (may be sandbox container home).
        let home = fm.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .standardizedFileURL
        cachedRealUserHomeDirectoryURL = home
        return home
    }

    private func expandTildePath(_ raw: String, home: URL) -> String {
        if raw == "~" { return home.path }
        if raw.hasPrefix("~/") {
            return home.appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true).path
        }
        return raw
    }

    // Finder sometimes does not provide targeted/selected URLs for background (container)
    // context menus. Keep track of the most recently observed directory as a fallback.
    private var lastObservedDirectoryURL: URL?

    // Capture the directory we decided on when building the last contextual menu.
    // This is the most reliable source for actions, because targeted/selected and even
    // menu item representedObject can drift in multi-window Finder scenarios.
    private var lastMenuCreationDirectoryURL: URL?
    private var lastMenuKindRawValue: UInt?

    // Snapshot of selection at menu creation time, used by "Open Selection" actions.
    private var lastMenuSelectedURLs: [URL] = []

    private lazy var pagesTemplateURL: URL? = locateIWorkTemplate(appName: "Pages")
    private lazy var numbersTemplateURL: URL? = locateIWorkTemplate(appName: "Numbers")
    private lazy var keynoteTemplateURL: URL? = locateIWorkTemplate(appName: "Keynote")

    private var canCreatePagesDocument: Bool { pagesTemplateURL != nil }
    private var canCreateNumbersDocument: Bool { numbersTemplateURL != nil }
    private var canCreateKeynoteDocument: Bool { keynoteTemplateURL != nil }

    override init() {
        super.init()

        // Best-effort: refresh the settings cache from the main app so scope is correct at launch.
        RCBSettings.refreshExtensionCacheFromMainApp()
        applyScopeIfNeeded(settings: RCBSettings.loadCached())

        let realHome = resolvedRealUserHomeDirectoryURL().path
        logger.info("init realHome=\(realHome, privacy: .public)")
    }

    private func applyScopeIfNeeded(settings: RCBSettings) {
        // Ensure we have active security-scoped access for non-home roots.
        refreshSecurityScopedRoots(settings: settings)

        let directories = computeScopeDirectories(settings: settings)
        if lastAppliedScopeDirectories == directories {
            return
        }

        lastAppliedScopeDirectories = directories
        let controller = FIFinderSyncController.default()
        controller.directoryURLs = directories

        let applied = controller.directoryURLs
        let appliedCount = applied?.count ?? 0
        logger.info("applyScope requestedCount=\(directories.count) appliedCount=\(appliedCount)")

        #if DEBUG
        if let applied {
            let paths = applied.map { $0.path }.sorted().joined(separator: " | ")
            logger.info("applyScope appliedPaths=\(paths, privacy: .public)")
        }
        #endif
    }

    private func computeScopeDirectories(settings: RCBSettings) -> Set<URL> {
        // IMPORTANT:
        // - FinderSync's directoryURLs controls where the extension is active/observing.
        // - For reliability, we ALWAYS include the default scope (common user folders).
        // - When users configure scopeRoots, we UNION them into directoryURLs so FinderSync
        //   can become active there too.
        // - Menu visibility is still controlled separately via scopeRoots filtering.
        let fileManager = FileManager.default

        func normalizedDirectoryURL(from url: URL) -> URL {
            let u = url.resolvingSymlinksInPath().standardizedFileURL
            // Ensure this represents a directory URL for FinderSync scope.
            return u.hasDirectoryPath ? u : u.appendingPathComponent("", isDirectory: true)
        }

        func canonicalPath(for url: URL) -> String {
            let p = url.resolvingSymlinksInPath().standardizedFileURL.path
            if p.hasPrefix("/System/Volumes/Data/") {
                return String(p.dropFirst("/System/Volumes/Data".count))
            }
            if p.hasPrefix("/private/") {
                return String(p.dropFirst("/private".count))
            }
            return p
        }

        func directoryVariants(for url: URL) -> [URL] {
            let normalized = normalizedDirectoryURL(from: url)
            let p = normalized.path

            var out: [URL] = [normalized]

            // Some APIs / Finder may surface paths under /System/Volumes/Data/Users/... instead of /Users/...
            if p.hasPrefix("/Users/") {
                let alt = URL(fileURLWithPath: "/System/Volumes/Data" + p, isDirectory: true)
                out.append(normalizedDirectoryURL(from: alt))
            } else if p.hasPrefix("/System/Volumes/Data/Users/") {
                let alt = URL(fileURLWithPath: String(p.dropFirst("/System/Volumes/Data".count)), isDirectory: true)
                out.append(normalizedDirectoryURL(from: alt))
            }

            // De-dupe by canonical path.
            var seen = Set<String>()
            return out.filter { seen.insert(canonicalPath(for: $0)).inserted }
        }

        func insertDirectory(_ url: URL, into set: inout Set<URL>) {
            for v in directoryVariants(for: url) {
                set.insert(v)
            }
        }

        // NOTE:
        // FinderSync runs in its own sandbox container; NSHomeDirectory() and homeDirectoryForCurrentUser
        // may point to ~/Library/Containers/<bundle>/Data. We need the *real* user home to build
        // correct scope URLs (e.g. /Users/<name>/Desktop).
        let home = resolvedRealUserHomeDirectoryURL()

        var directories = Set<URL>()

        // Avoid scoping the home directory itself — doing so causes macOS to proactively
        // prompt the "Keeping app data separate" privacy dialog whenever any process (e.g.
        // a Safari file picker) traverses ~/Library/ subdirectories containing File Provider
        // content. Instead, scope only the specific common user folders listed below.

        // Common folders (explicit paths under real home, plus SearchPathDirectory fallback).
        // Note: On newer macOS versions, including only the Home directory is not always sufficient
        // for FinderSync to become active in subdirectories.
        let explicitCommon: [URL] = [
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Movies", isDirectory: true),
            home.appendingPathComponent("Music", isDirectory: true),
            home.appendingPathComponent("Pictures", isDirectory: true),
        ]
        for url in explicitCommon {
            insertDirectory(url, into: &directories)
        }

        // NOTE: Do NOT scope File Provider-backed directories (iCloud Drive, CloudStorage,
        // ~/Library/Mobile Documents, etc.) in the default scope, because registering a
        // sandboxed FinderSync extension to observe these directories triggers the macOS
        // "Keeping app data separate" privacy dialog. Users who need the right-click menu
        // in iCloud Drive / File Provider locations can add custom scope roots in Settings.

        let commonSearchPaths: [FileManager.SearchPathDirectory] = [
            .desktopDirectory,
            .downloadsDirectory,
            .moviesDirectory,
            .musicDirectory,
            .picturesDirectory
        ]
        for dir in commonSearchPaths {
            if let url = fileManager.urls(for: dir, in: .userDomainMask).first {
                insertDirectory(url, into: &directories)
            }
        }

        // If user configured custom roots, also include them in the observed scope.
        // - home roots: work without bookmarks for backward compatibility
        // - non-home roots: require security-scoped bookmarks (resolved via refreshSecurityScopedRoots)
        if !settings.scopeRoots.isEmpty {
            for raw in settings.scopeRoots {
                if let resolved = resolveScopeRootURL(scopeRoot: raw, realHome: home) {
                    insertDirectory(resolved, into: &directories)
                }
            }
        }

        return directories
    }

    private func isMenuAllowed(in directoryURL: URL?, settings: RCBSettings) -> Bool {
        // Empty = default behavior (allow everywhere FinderSync is active).
        if settings.scopeRoots.isEmpty {
            return true
        }
        guard let directoryURL else {
            return false
        }

        func canonicalizePath(_ p: String) -> String {
            if p.hasPrefix("/System/Volumes/Data/") {
                return String(p.dropFirst("/System/Volumes/Data".count))
            }
            if p.hasPrefix("/private/") {
                return String(p.dropFirst("/private".count))
            }
            return p
        }

        let fm = FileManager.default

        let dir = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        let dirPath = canonicalizePath(dir.path)

        // Use resolved root URLs (bookmark-backed + home roots) rather than raw strings.
        // Prefer filesystem relationship check to handle symlinks / different path representations.
        for rootURL in lastResolvedScopeRootURLs {
            let root = rootURL.resolvingSymlinksInPath().standardizedFileURL

            // Fast-path: simple string prefix match.
            let rootPath = canonicalizePath(root.path)
            if dirPath == rootPath {
                return true
            }
            let prefix = rootPath.hasSuffix("/") ? rootPath : (rootPath + "/")
            if dirPath.hasPrefix(prefix) {
                return true
            }

            // Robust path-agnostic check.
            var rel: FileManager.URLRelationship = .other
            do {
                try fm.getRelationship(&rel, ofDirectoryAt: root, toItemAt: dir)
                if rel == .contains || rel == .same {
                    return true
                }
            } catch {
                // Ignore: if relationship cannot be determined, fall back to other roots.
                continue
            }
        }

        return false
    }

    private func resolveScopeRootURL(scopeRoot: String, realHome: URL) -> URL? {
        if let active = activeSecurityScopedRoots[scopeRoot] {
            return active
        }

        let expanded = expandTildePath(scopeRoot, home: realHome)
        let rootURL = URL(fileURLWithPath: expanded, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        // Backward compatibility: allow home-only scope roots without bookmarks.
        if rootURL.path.hasPrefix(realHome.path) {
            return rootURL
        }

        return nil
    }

    private func refreshSecurityScopedRoots(settings: RCBSettings) {
        let home = resolvedRealUserHomeDirectoryURL()

        // Stop accessing removed roots.
        let desired = Set(settings.scopeRoots)
        for (key, url) in activeSecurityScopedRoots where !desired.contains(key) {
            url.stopAccessingSecurityScopedResource()
            logger.info("securityScope stop key=\(key, privacy: .public) url=\(url.path, privacy: .public)")
            activeSecurityScopedRoots.removeValue(forKey: key)
        }

        // Load bookmarks dictionary from App Group UserDefaults.
        let bookmarks = RCBScopeRootBookmarkStore.loadAll()

        var resolvedRoots: [URL] = []

        for key in settings.scopeRoots {
            if let existing = resolveScopeRootURL(scopeRoot: key, realHome: home) {
                resolvedRoots.append(existing)
                continue
            }

            // Non-home roots must come from a security-scoped bookmark.
            guard let data = bookmarks[key] else {
                // If this root lives under real home, it may still be valid without bookmarks.
                let expanded = expandTildePath(key, home: home)
                let candidate = URL(fileURLWithPath: expanded, isDirectory: true)
                    .resolvingSymlinksInPath()
                    .standardizedFileURL
                if candidate.path.hasPrefix(home.path) {
                    resolvedRoots.append(candidate)
                } else {
                    logger.info("securityScope missing bookmark key=\(key, privacy: .public) (needs re-Add in Settings)")
                }
                continue
            }

            do {
                var stale = false
                let resolved = try URL(
                    resolvingBookmarkData: data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                let standardized = resolved.resolvingSymlinksInPath().standardizedFileURL

                if standardized.startAccessingSecurityScopedResource() {
                    activeSecurityScopedRoots[key] = standardized
                    resolvedRoots.append(standardized)
                    logger.info("securityScope start key=\(key, privacy: .public) url=\(standardized.path, privacy: .public) stale=\(stale)")
                } else {
                    logger.info("securityScope start FAILED key=\(key, privacy: .public) url=\(standardized.path, privacy: .public)")
                    continue
                }

                if stale {
                    // Silent refresh.
                    let refreshed = try standardized.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    var updated = bookmarks
                    updated[key] = refreshed
                    RCBScopeRootBookmarkStore.saveAll(updated)
                    logger.info("securityScope refreshed stale bookmark key=\(key, privacy: .public)")
                }
            } catch {
                logger.info("securityScope resolve FAILED key=\(key, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
            }
        }

        // Cache resolved roots for menu filtering.
        lastResolvedScopeRootURLs = resolvedRoots
    }

    override func beginObservingDirectory(at url: URL) {
        lastObservedDirectoryURL = url

        // Attempt to learn the real user home from observed paths.
        // In practice, Finder passes real filesystem URLs (e.g. /Users/<name>/Downloads/...).
        // Once we learn it, we can scope Desktop/Music/Pictures reliably.
        if cachedRealUserHomeDirectoryURL == nil {
            let standardized = url.resolvingSymlinksInPath().standardizedFileURL
            let comps = standardized.pathComponents
            // Expect: /Users/<name>/Downloads[/...]
            if comps.count >= 4, comps[1] == "Users" {
                if let downloadsIdx = comps.firstIndex(of: "Downloads"), downloadsIdx >= 3 {
                    let userHomePath = "/" + comps[1...2].joined(separator: "/")
                    cachedRealUserHomeDirectoryURL = URL(fileURLWithPath: userHomePath, isDirectory: true)
                        .resolvingSymlinksInPath()
                        .standardizedFileURL
                    logger.info("learned realHome=\(userHomePath, privacy: .public) from observing=\(standardized.path, privacy: .public)")

                    // Re-apply scope so FinderSync activates under other common folders.
                    applyScopeIfNeeded(settings: RCBSettings.loadCached())
                }
            }
        }

        logger.info("beginObservingDirectory \(url.path, privacy: .public)")
    }

    override func endObservingDirectory(at url: URL) {
        logger.info("endObservingDirectory \(url.path, privacy: .public)")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        fileLog.info("▶ menu(for:) kind=\(menuKind.rawValue)")

        // Pull the latest settings from the main app over IPC before building the menu, so scope
        // roots / toggles the user just changed take effect. Falls back to the local cache if the
        // app isn't reachable.
        RCBSettings.refreshExtensionCacheFromMainApp()

        let targeted = FIFinderSyncController.default().targetedURL()
        let selected = FIFinderSyncController.default().selectedItemURLs()

        logger.info("menu(for:) kind=\(menuKind.rawValue) targeted=\(targeted?.path ?? "nil", privacy: .public) selectedCount=\(selected?.count ?? 0)")

        let menu = NSMenu(title: RCLocalizedString("RightClickBuddy"))

        #if DEBUG
        defer {
            let titles = menu.items.map { $0.title }.joined(separator: " | ")
            logger.info("menu return kind=\(menuKind.rawValue) itemCount=\(menu.items.count) titles=\(titles, privacy: .public)")
        }
        #endif

        // Capture context at menu creation time.
        // IMPORTANT: For container menus (background / empty area), Finder may still report
        // a selection from another window, so we only trust targetedURL there.
        let creationDirectory: URL? = {
            if menuKind.rawValue == FIMenuKind.contextualMenuForContainer.rawValue {
                if let targeted {
                    return targeted.hasDirectoryPath ? targeted : targeted.deletingLastPathComponent()
                }

                // On some File Provider locations (e.g. iCloud Drive root), Finder may not provide targetedURL
                // for container (blank area) contextual menus. In that case, selectedItemURLs may still point
                // to an item in the current window; prefer it over lastObservedDirectoryURL.
                if let first = selected?.first {
                    return first.hasDirectoryPath ? first : first.deletingLastPathComponent()
                }

                return lastObservedDirectoryURL
            }

            if let targeted {
                return targeted.hasDirectoryPath ? targeted : targeted.deletingLastPathComponent()
            }
            if let first = selected?.first {
                return first.hasDirectoryPath ? first : first.deletingLastPathComponent()
            }
            return lastObservedDirectoryURL
        }()

        // Persist captured context for action handlers.
        lastMenuCreationDirectoryURL = creationDirectory
        lastMenuKindRawValue = menuKind.rawValue

        // Snapshot selection at menu creation time.
        // IMPORTANT: For container menus (background / empty area), Finder may report a
        // selection from another window; treat it as "no selection" to avoid surprises.
        if menuKind.rawValue == FIMenuKind.contextualMenuForContainer.rawValue {
            lastMenuSelectedURLs = []
        } else {
            lastMenuSelectedURLs = selected.map(Array.init) ?? []
        }

        #if DEBUG
        let creationPath = creationDirectory?.path ?? "nil"
        let observedPath = lastObservedDirectoryURL?.path ?? "nil"
        logger.info("context kind=\(menuKind.rawValue) creationDir=\(creationPath, privacy: .public) lastObserved=\(observedPath, privacy: .public)")
        #endif

        let settings = RCBSettings.loadCached()
        applyScopeIfNeeded(settings: settings)

        #if DEBUG
        let precheckCreationPath = creationDirectory?.path ?? "nil"
        logger.info("menu precheck kind=\(menuKind.rawValue) creationDir=\(precheckCreationPath, privacy: .public) scopeRootsCount=\(settings.scopeRoots.count)")
        #endif

        // Hide menu outside configured scope roots.
        if !isMenuAllowed(in: creationDirectory, settings: settings) {
            let deniedCreationPath = creationDirectory?.path ?? "nil"
            logger.info("menu denied creationDir=\(deniedCreationPath, privacy: .public) scopeRootsCount=\(settings.scopeRoots.count) resolvedRootCount=\(self.lastResolvedScopeRootURLs.count)")

            #if DEBUG
            let roots = lastResolvedScopeRootURLs.map { $0.path }.sorted().joined(separator: " | ")
            logger.info("menu denied resolvedRoots=\(roots, privacy: .public)")
            #endif

            return menu
        }

        if !settings.menu.enabled {
            return menu
        }

        if settings.menu.showNew {
            let createMenu = NSMenu(title: RCLocalizedString("新建"))

            let createFolderItem = NSMenuItem(title: RCLocalizedString("新建文件夹"), action: #selector(createNewFolder(_:)), keyEquivalent: "")
            if let creationDirectory { createFolderItem.representedObject = creationDirectory }
            createFolderItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(createFolderItem)

            let createTxtItem = NSMenuItem(title: RCLocalizedString("新建文本 (txt)"), action: #selector(createNewTextFile(_:)), keyEquivalent: "")
            if let creationDirectory { createTxtItem.representedObject = creationDirectory }
            createTxtItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(createTxtItem)

            let createMdItem = NSMenuItem(title: RCLocalizedString("新建 Markdown (.md)"), action: #selector(createNewMarkdownFile(_:)), keyEquivalent: "")
            if let creationDirectory { createMdItem.representedObject = creationDirectory }
            createMdItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(createMdItem)

            let createJsonItem = NSMenuItem(title: RCLocalizedString("新建 JSON (.json)"), action: #selector(createNewJSONFile(_:)), keyEquivalent: "")
            if let creationDirectory { createJsonItem.representedObject = creationDirectory }
            createJsonItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(createJsonItem)

            let createShItem = NSMenuItem(title: RCLocalizedString("新建 Shell (.sh)"), action: #selector(createNewShellScript(_:)), keyEquivalent: "")
            if let creationDirectory { createShItem.representedObject = creationDirectory }
            createShItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(createShItem)

            let createEnvItem = NSMenuItem(title: RCLocalizedString("新建 .env"), action: #selector(createNewDotEnvFile(_:)), keyEquivalent: "")
            if let creationDirectory { createEnvItem.representedObject = creationDirectory }
            createEnvItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(createEnvItem)

            let createPagesItem = NSMenuItem(title: RCLocalizedString("新建 Pages 文档 (.pages)"), action: #selector(createNewPagesDocument(_:)), keyEquivalent: "")
            if let creationDirectory { createPagesItem.representedObject = creationDirectory }
            createPagesItem.isEnabled = (creationDirectory != nil) && canCreatePagesDocument
            createMenu.addItem(createPagesItem)

            let pasteTextItem = NSMenuItem(title: RCLocalizedString("从剪贴板新建文本 (txt)"), action: #selector(createTextFromPasteboard(_:)), keyEquivalent: "")
            if let creationDirectory { pasteTextItem.representedObject = creationDirectory }
            pasteTextItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(pasteTextItem)

            let pasteImageItem = NSMenuItem(title: RCLocalizedString("从剪贴板新建图片 (png)"), action: #selector(createPNGFromPasteboard(_:)), keyEquivalent: "")
            if let creationDirectory { pasteImageItem.representedObject = creationDirectory }
            pasteImageItem.isEnabled = (creationDirectory != nil)
            createMenu.addItem(pasteImageItem)

            let createNumbersItem = NSMenuItem(title: RCLocalizedString("新建 Numbers 表格 (.numbers)"), action: #selector(createNewNumbersDocument(_:)), keyEquivalent: "")
            if let creationDirectory { createNumbersItem.representedObject = creationDirectory }
            createNumbersItem.isEnabled = (creationDirectory != nil) && canCreateNumbersDocument
            createMenu.addItem(createNumbersItem)

            let createKeynoteItem = NSMenuItem(title: RCLocalizedString("新建 Keynote 演示文稿 (.key)"), action: #selector(createNewKeynoteDocument(_:)), keyEquivalent: "")
            if let creationDirectory { createKeynoteItem.representedObject = creationDirectory }
            createKeynoteItem.isEnabled = (creationDirectory != nil) && canCreateKeynoteDocument
            createMenu.addItem(createKeynoteItem)

            if settings.menu.showTemplates {
                let templatesMenu = NSMenu(title: RCLocalizedString("模板"))

                for (idx, spec) in settings.allTemplateSpecs.enumerated() {
                    guard settings.isTemplateEnabled(spec.id) else { continue }

                    let item = NSMenuItem(title: spec.title, action: #selector(createFromTemplate(_:)), keyEquivalent: "")
                    item.tag = idx
                    item.identifier = NSUserInterfaceItemIdentifier(spec.id)

                    if let creationDirectory {
                        item.representedObject = creationDirectory
                        item.isEnabled = true
                    } else {
                        item.isEnabled = false
                    }
                    templatesMenu.addItem(item)
                }
                if !templatesMenu.items.isEmpty {
                    let templatesSubmenuItem = NSMenuItem(title: RCLocalizedString("模板"), action: nil, keyEquivalent: "")
                    createMenu.addItem(templatesSubmenuItem)
                    createMenu.setSubmenu(templatesMenu, for: templatesSubmenuItem)
                }
            }

            let createSubmenuItem = NSMenuItem(title: RCLocalizedString("创建新文件"), action: nil, keyEquivalent: "")
            menu.addItem(createSubmenuItem)
            menu.setSubmenu(createMenu, for: createSubmenuItem)
        }


        if settings.menu.showOffice {
            let createOfficeMenu = NSMenu(title: RCLocalizedString("Office"))

            let createDocxItem = NSMenuItem(title: RCLocalizedString("新建 Word (.docx)"), action: #selector(createNewWordDocument(_:)), keyEquivalent: "")
            if let creationDirectory { createDocxItem.representedObject = creationDirectory }
            createDocxItem.isEnabled = (creationDirectory != nil)
            createOfficeMenu.addItem(createDocxItem)

            let createXlsxItem = NSMenuItem(title: RCLocalizedString("新建 Excel (.xlsx)"), action: #selector(createNewExcelDocument(_:)), keyEquivalent: "")
            if let creationDirectory { createXlsxItem.representedObject = creationDirectory }
            createXlsxItem.isEnabled = (creationDirectory != nil)
            createOfficeMenu.addItem(createXlsxItem)

            let createPptxItem = NSMenuItem(title: RCLocalizedString("新建 PowerPoint (.pptx)"), action: #selector(createNewPowerPointDocument(_:)), keyEquivalent: "")
            if let creationDirectory { createPptxItem.representedObject = creationDirectory }
            createPptxItem.isEnabled = (creationDirectory != nil)
            createOfficeMenu.addItem(createPptxItem)

            let createOfficeSubmenuItem = NSMenuItem(title: RCLocalizedString("新建 Office 文档"), action: nil, keyEquivalent: "")
            menu.addItem(createOfficeSubmenuItem)
            menu.setSubmenu(createOfficeMenu, for: createOfficeSubmenuItem)
        }


        // Open With
        if settings.menu.showOpenWith {
            let openWithMenu = NSMenu(title: RCLocalizedString("打开方式"))

            let openWithSpecs = RCBSettings.openWithSpecs
            logger.info("openWith menu build specsCount=\(openWithSpecs.count)")
            for (idx, spec) in openWithSpecs.enumerated() {
                guard settings.isOpenWithEnabled(spec.id) else { continue }
                guard let appURL = FinderCommandHandler.resolveOpenWithAppURL(specId: spec.id, bundleIdCandidates: spec.bundleIdCandidates) else {
                    logger.info("openWith skip specId=\(spec.id, privacy: .public) title=\(spec.title, privacy: .public) — not resolved")
                    continue
                }

                let displayName: String = {
                    if let bundle = Bundle(url: appURL) {
                        if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
                            return name
                        }
                        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
                            return name
                        }
                    }
                    return spec.title
                }()

                logger.info("openWith add specId=\(spec.id, privacy: .public) displayName=\(displayName, privacy: .public)")

                let folderItem = NSMenuItem(
                    title: String(format: RCLocalizedString("在 %@ 打开目录"), displayName),
                    action: #selector(openFolderInOpenWithApp(_:)),
                    keyEquivalent: ""
                )
                folderItem.tag = idx
                folderItem.identifier = NSUserInterfaceItemIdentifier(spec.id)
                folderItem.representedObject = creationDirectory

                // NOTE: We skip the isObsidianVaultDirectory check during menu creation
                // because FileManager access in menu(for:) can trigger macOS sandbox
                // permission dialogs for certain directories (e.g. those created by
                // third-party tools). Vault validation is deferred to the click handler.
                folderItem.isEnabled = (creationDirectory != nil)

                openWithMenu.addItem(folderItem)

                let selectionItem = NSMenuItem(
                    title: String(format: RCLocalizedString("在 %@ 打开选择项"), displayName),
                    action: #selector(openSelectionInOpenWithApp(_:)),
                    keyEquivalent: ""
                )
                selectionItem.tag = idx
                selectionItem.identifier = NSUserInterfaceItemIdentifier(spec.id)
                selectionItem.representedObject = creationDirectory

                let hasSelection = !lastMenuSelectedURLs.isEmpty
                if spec.id == "openwith.obsidian" {
                    // Obsidian cannot open arbitrary folders reliably; only enable when selection contains files.
                    let hasFileSelection = lastMenuSelectedURLs.contains { !$0.hasDirectoryPath }
                    selectionItem.isEnabled = hasFileSelection

                } else {
                    selectionItem.isEnabled = hasSelection || (creationDirectory != nil)
                }

                openWithMenu.addItem(selectionItem)
            }

            if !openWithMenu.items.isEmpty {
                let openWithSubmenuItem = NSMenuItem(title: RCLocalizedString("打开方式"), action: nil, keyEquivalent: "")
                menu.addItem(openWithSubmenuItem)
                menu.setSubmenu(openWithMenu, for: openWithSubmenuItem)
            }
        }

        let copyDirItem = NSMenuItem(title: RCLocalizedString("复制当前目录"), action: #selector(copyCurrentDirectory(_:)), keyEquivalent: "")
        if let creationDirectory { copyDirItem.representedObject = creationDirectory }
        copyDirItem.isEnabled = (creationDirectory != nil)
        menu.addItem(copyDirItem)

        menu.addItem(NSMenuItem(title: RCLocalizedString("复制路径"), action: #selector(copyPath), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: RCLocalizedString("复制文件名"), action: #selector(copyFilename), keyEquivalent: ""))

        let terminalDirItem = NSMenuItem(title: RCLocalizedString("在当前目录打开终端"), action: #selector(openTerminalHere(_:)), keyEquivalent: "")
        if let creationDirectory { terminalDirItem.representedObject = creationDirectory }
        terminalDirItem.isEnabled = (creationDirectory != nil)
        menu.addItem(terminalDirItem)

        let terminalItem = NSMenuItem(title: RCLocalizedString("在终端打开"), action: #selector(openInTerminal(_:)), keyEquivalent: "")
        if let url = targeted ?? selected?.first { terminalItem.representedObject = url }
        menu.addItem(terminalItem)


        // Ensure all submenu items have an explicit target as well.
        func setTargetRecursively(_ menu: NSMenu) {
            for item in menu.items {
                item.target = self
                if let submenu = item.submenu {
                    setTargetRecursively(submenu)
                }
            }
        }
        setTargetRecursively(menu)

        return menu
    }


    /// For copy actions we prefer the full multi-selection when available.
    private func currentSelectedURLs() -> [URL] {
        if let selected = FIFinderSyncController.default().selectedItemURLs(), !selected.isEmpty {
            return Array(selected)
        }
        if let targeted = FIFinderSyncController.default().targetedURL() {
            return [targeted]
        }
        return []
    }

    /// For single-target actions we prefer the item under the cursor.
    private func currentTargetURL() -> URL? {
        if let targeted = FIFinderSyncController.default().targetedURL() {
            return targeted
        }
        if let selected = FIFinderSyncController.default().selectedItemURLs(), let first = selected.first {
            return first
        }
        return nil
    }

    private func currentDirectoryForCreation() -> URL? {
        guard let url = currentTargetURL() else { return nil }
        if url.hasDirectoryPath {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func urlFromRepresentedObject(_ representedObject: Any?) -> URL? {
        if let url = representedObject as? URL { return url }
        if let nsurl = representedObject as? NSURL { return nsurl as URL }
        return nil
    }

    private func bundleIdCandidatesForOpenWithItem(_ sender: NSMenuItem) -> [String] {
        let id: String = sender.identifier?.rawValue ?? ""
        if !id.isEmpty, let spec = RCBSettings.openWithSpecs.first(where: { $0.id == id }) {
            return spec.bundleIdCandidates
        }
        if sender.tag >= 0, sender.tag < RCBSettings.openWithSpecs.count {
            return RCBSettings.openWithSpecs[sender.tag].bundleIdCandidates
        }
        return []
    }

    private func isObsidianVaultDirectory(_ directoryURL: URL) -> Bool {
        var isDir: ObjCBool = false
        let marker = directoryURL.appendingPathComponent(".obsidian", isDirectory: true)
        return FileManager.default.fileExists(atPath: marker.path, isDirectory: &isDir) && isDir.boolValue
    }

    @objc private func copyCurrentDirectory(_ sender: NSMenuItem) {
        guard let directoryURL = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject) else { return }
        FinderCommandHandler.copyPOSIXPaths([directoryURL])
    }

    @objc private func copyPath() {
        let urls = currentSelectedURLs()
        guard !urls.isEmpty else { return }
        FinderCommandHandler.copyPOSIXPaths(urls)
    }

    @objc private func copyFilename() {
        let urls = currentSelectedURLs()
        guard !urls.isEmpty else { return }
        FinderCommandHandler.copyFilenames(urls)
    }

    @objc private func openTerminalHere(_ sender: NSMenuItem) {
        guard let directoryURL = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject) else { return }
        openInTerminalApp(directoryURL)
    }

    @objc private func openInTerminal(_ sender: NSMenuItem) {
        guard let url = (sender.representedObject as? URL) ?? currentTargetURL() else { return }
        openInTerminalApp(url)
    }

    /// Open the containing folder in Terminal. Like Open With, this is delegated to the
    /// non-sandboxed main app over IPC — the sandboxed extension itself isn't allowed to hand
    /// a folder to another app (NSWorkspace.open fails with a sandbox permission error).
    private func openInTerminalApp(_ url: URL) {
        let dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let terminalURL = FinderCommandHandler.resolveInstalledApplicationURL(bundleIdCandidates: ["com.apple.Terminal"]) else {
            logger.error("openInTerminal: Terminal.app not found")
            return
        }
        openURLs([dir], inAppAt: terminalURL, context: "terminal")
    }

    private func showAlert(messageText: String, informativeText: String) {
        // FinderSync is an extension; ensure we’re on main and foreground ourselves.
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.showAlert(messageText: messageText, informativeText: informativeText)
            }
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: RCLocalizedString("好"))
        _ = alert.runModal()
    }

    /// Open the given URLs in the target app.
    ///
    /// A sandboxed FinderSync extension is NOT allowed to hand a folder/file URL to another
    /// application (LaunchServices denies it — macOS shows "… does not have permission to open …").
    /// So we delegate to the NON-sandboxed main app over IPC, which runs `/usr/bin/open -a`.
    /// The IPC layer auto-launches the main app if it isn't running, so this works even after a
    /// cold start.
    private func openURLs(_ urls: [URL], inAppAt appURL: URL, context: String) {
        let filePaths = urls.map { $0.standardizedFileURL.path }
        logger.info("openWith(\(context, privacy: .public)) delegate app=\(appURL.path, privacy: .public) count=\(filePaths.count)")

        // IPC blocks on a socket round-trip (and may launch the main app) — keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                try IPCTcpClient.openWithApps(appPath: appURL.path, filePaths: filePaths)
                self.logger.info("openWith(\(context, privacy: .public)) success")
            } catch {
                self.logger.error("openWith(\(context, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    self.showAlert(messageText: RCLocalizedString("无法打开"), informativeText: error.localizedDescription)
                }
            }
        }
    }

    @objc private func openFolderInOpenWithApp(_ sender: NSMenuItem) {
        // AppKit UI must be on the main thread; Finder may invoke actions off-main.
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.openFolderInOpenWithApp(sender)
            }
            return
        }

        guard let directoryURL = lastMenuCreationDirectoryURL else {
            logger.error("openFolderInOpenWithApp no directory")
            showAlert(messageText: RCLocalizedString("无法确定目录"), informativeText: RCLocalizedString("Finder 没有提供当前目录。\n\n请对某个文件/文件夹右键，或先点击文件列表再试。"))
            return
        }

        let ids = bundleIdCandidatesForOpenWithItem(sender)
        if ids.isEmpty {
            logger.error("openFolderInOpenWithApp no ids")
            return
        }

        // Obsidian: only allow opening folders that look like a Vault (contain .obsidian/).
        if sender.identifier?.rawValue == "openwith.obsidian" {
            if !isObsidianVaultDirectory(directoryURL) {
                logger.info("openWith(folder) obsidian blocked (not a vault) dir=\(directoryURL.path, privacy: .public)")
                return
            }
        }

        guard let appURL = FinderCommandHandler.resolveOpenWithAppURL(specId: sender.identifier?.rawValue ?? "", bundleIdCandidates: ids) else {
            logger.error("openFolderInOpenWithApp app not found")
            showAlert(messageText: RCLocalizedString("未找到应用"), informativeText: ids.joined(separator: "\n"))
            return
        }

        let standardizedDir = directoryURL.standardizedFileURL
        openURLs([standardizedDir], inAppAt: appURL, context: "folder")
    }

    @objc private func openSelectionInOpenWithApp(_ sender: NSMenuItem) {
        // AppKit UI must be on the main thread; Finder may invoke actions off-main.
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.openSelectionInOpenWithApp(sender)
            }
            return
        }

        let ids = bundleIdCandidatesForOpenWithItem(sender)
        if ids.isEmpty {
            logger.error("openSelectionInOpenWithApp no ids")
            return
        }

        guard let appURL = FinderCommandHandler.resolveOpenWithAppURL(specId: sender.identifier?.rawValue ?? "", bundleIdCandidates: ids) else {
            logger.error("openSelectionInOpenWithApp app not found")
            showAlert(messageText: RCLocalizedString("未找到应用"), informativeText: ids.joined(separator: "\n"))
            return
        }

        // Prefer snapshot from menu creation time to avoid selection drift.
        var urls = lastMenuSelectedURLs

        if urls.isEmpty, let directoryURL = lastMenuCreationDirectoryURL {
            urls = [directoryURL]
        }

        guard !urls.isEmpty else {
            logger.error("openSelectionInOpenWithApp no urls")
            showAlert(messageText: RCLocalizedString("没有选择项"), informativeText: RCLocalizedString("请先选中文件/文件夹，或使用 Open Folder。"))
            return
        }

        logger.info("openWith(selection) urlsCount=\(urls.count)")
        openURLs(urls, inAppAt: appURL, context: "selection")
    }

    @objc private func createNewFolder(_ sender: NSMenuItem) {
        createAndRevealFolder(folderName: "New Folder", sender: sender)
    }

    @objc private func createNewTextFile(_ sender: NSMenuItem) {
        createAndReveal(fileName: "New File.txt", sender: sender)
    }

    @objc private func createNewMarkdownFile(_ sender: NSMenuItem) {
        createAndReveal(fileName: "New File.md", sender: sender)
    }

    @objc private func createNewJSONFile(_ sender: NSMenuItem) {
        createAndReveal(fileName: "New File.json", sender: sender)
    }

    @objc private func createNewShellScript(_ sender: NSMenuItem) {
        createAndReveal(fileName: "New File.sh", sender: sender)
    }

    @objc private func createNewDotEnvFile(_ sender: NSMenuItem) {
        createAndReveal(fileName: ".env", sender: sender)
    }

    @objc private func createNewPagesDocument(_ sender: NSMenuItem) {
        createAndRevealIWorkDocument(kind: .pages, sender: sender)
    }

    @objc private func createFromTemplate(_ sender: NSMenuItem) {
        // AppKit UI must be on the main thread; Finder may invoke actions off-main.
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.createFromTemplate(sender)
            }
            return
        }

        // Always prefer the captured context from menu construction time.
        // Finder can change the "current" targeted/selected URL due to other windows
        // gaining focus after the menu is shown.
        let directoryURL: URL? = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject)

        fileLog.info("▶ createFromTemplate id=\(sender.identifier?.rawValue ?? "?") title=\(sender.title)")

        guard let directoryURL else {
            logger.error("createFromTemplate no directory")
            return
        }

        let id: String = sender.identifier?.rawValue ?? ""

        let allSpecs = RCBSettings.loadCached().allTemplateSpecs
        let spec: RCBSettings.TemplateSpec? = {
            if !id.isEmpty, let s = allSpecs.first(where: { $0.id == id }) {
                return s
            }
            if sender.tag >= 0, sender.tag < allSpecs.count {
                return allSpecs[sender.tag]
            }
            return allSpecs.first(where: { $0.title == sender.title })
        }()

        guard let spec else {
            logger.error("createFromTemplate spec not found title=\(sender.title, privacy: .public) id=\(id, privacy: .public) tag=\(sender.tag)")
            return
        }

        logger.info("template id=\(spec.id, privacy: .public) title=\(spec.title, privacy: .public) fileName=\(spec.fileName, privacy: .public) dir=\(directoryURL.path, privacy: .public)")

        do {
            let createdURL = try FinderCommandHandler.createNewTemplateFile(
                in: directoryURL,
                fileName: spec.fileName,
                contents: Data(spec.contents.utf8)
            )
            logger.info("template created \(createdURL.path, privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            fileLog.info("  error=\(error.localizedDescription)")
            logger.error("createFromTemplate failed id=\(spec.id, privacy: .public) fileName=\(spec.fileName, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func createTextFromPasteboard(_ sender: NSMenuItem) {
        createAndRevealPasteboardText(sender: sender)
    }

    @objc private func createPNGFromPasteboard(_ sender: NSMenuItem) {
        createAndRevealPasteboardPNG(sender: sender)
    }

    @objc private func createNewNumbersDocument(_ sender: NSMenuItem) {
        createAndRevealIWorkDocument(kind: .numbers, sender: sender)
    }

    @objc private func createNewKeynoteDocument(_ sender: NSMenuItem) {
        createAndRevealIWorkDocument(kind: .keynote, sender: sender)
    }

    @objc private func createNewWordDocument(_ sender: NSMenuItem) {
        createAndRevealOfficeDocument(kind: .docx, sender: sender)
    }

    @objc private func createNewExcelDocument(_ sender: NSMenuItem) {
        createAndRevealOfficeDocument(kind: .xlsx, sender: sender)
    }

    @objc private func createNewPowerPointDocument(_ sender: NSMenuItem) {
        createAndRevealOfficeDocument(kind: .pptx, sender: sender)
    }

    private enum OfficeKind {
        case docx
        case xlsx
        case pptx

        var fileExtension: String {
            switch self {
            case .docx: return "docx"
            case .xlsx: return "xlsx"
            case .pptx: return "pptx"
            }
        }

        var defaultFileName: String {
            "New Document.\(fileExtension)"
        }
    }

    private func createAndRevealOfficeDocument(kind: OfficeKind, sender: NSMenuItem) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.createAndRevealOfficeDocument(kind: kind, sender: sender)
            }
            return
        }

        fileLog.info("▶ createAndRevealOfficeDocument kind=\(kind.fileExtension)")

        let directoryURL: URL? = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject)

        guard let directoryURL else {
            fileLog.info("  no directory URL")
            logger.debug("Cannot create office document: no directory URL")
            return
        }

        do {
            logger.debug("Creating office document kind=\(kind.fileExtension, privacy: .public) dir=\(directoryURL.path, privacy: .public)")
            let createdURL = try FinderCommandHandler.createNewOfficeDocument(in: directoryURL, fileName: kind.defaultFileName, kind: kind.fileExtension)
            logger.debug("Office document created successfully at \(createdURL.path, privacy: .public)")
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            fileLog.info("  error=\(error.localizedDescription)")
            logger.error("Office document creation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum IWorkKind {
        case pages
        case numbers
        case keynote

        var displayName: String {
            switch self {
            case .pages: return "Pages"
            case .numbers: return "Numbers"
            case .keynote: return "Keynote"
            }
        }

        var fileExtension: String {
            switch self {
            case .pages: return "pages"
            case .numbers: return "numbers"
            case .keynote: return "key"
            }
        }

        var defaultFileName: String {
            "New Document.\(fileExtension)"
        }
    }

    private func locateIWorkTemplate(appName: String) -> URL? {
        // iWork templates are stored inside the app bundle as .template (zip).
        // We pick a known blank portrait template.
        let path = "/Applications/\(appName).app/Contents/SharedSupport/Templates/00B_Blank_Portrait/ISO.template"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func templateURL(for kind: IWorkKind) -> URL? {
        switch kind {
        case .pages: return pagesTemplateURL
        case .numbers: return numbersTemplateURL
        case .keynote: return keynoteTemplateURL
        }
    }

    private func createAndRevealIWorkDocument(kind: IWorkKind, sender: NSMenuItem) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.createAndRevealIWorkDocument(kind: kind, sender: sender)
            }
            return
        }

        fileLog.info("▶ createAndRevealIWorkDocument kind=\(kind.displayName)")

        let directoryURL: URL? = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject)

        guard let directoryURL else {
            fileLog.info("  no directory")
            logger.debug("Cannot create iWork document: no directory URL")
            return
        }

        guard let templateURL = templateURL(for: kind) else {
            fileLog.info("  template not found for kind=\(kind.displayName)")
            logger.info("iWork template not available for \(kind.displayName, privacy: .public)")
            return
        }

        do {
            let createdURL = try FinderCommandHandler.createNewIWorkDocument(in: directoryURL, fileName: kind.defaultFileName, templateURL: templateURL)
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            fileLog.info("  error=\(error.localizedDescription)")
            logger.error("Create iWork file error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createAndRevealFolder(folderName: String, sender: NSMenuItem) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.createAndRevealFolder(folderName: folderName, sender: sender)
            }
            return
        }

        fileLog.info("▶ createAndRevealFolder folderName=\(folderName)")

        let directoryURL: URL? = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject)

        guard let directoryURL else {
            fileLog.info("  no directory")
            logger.debug("Cannot create folder: no directory URL")
            return
        }

        logger.info("create folder \(folderName, privacy: .public) in \(directoryURL.path, privacy: .public)")

        do {
            let createdURL = try FinderCommandHandler.createNewFolder(in: directoryURL, folderName: folderName)
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            fileLog.info("  error=\(error.localizedDescription)")
            logger.error("Create folder error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createAndRevealPasteboardText(sender: NSMenuItem) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.createAndRevealPasteboardText(sender: sender)
            }
            return
        }

        fileLog.info("▶ createAndRevealPasteboardText")

        let directoryURL: URL? = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject)

        guard let directoryURL else {
            fileLog.info("  no directory")
            return
        }

        do {
            fileLog.info("  calling createNewTextFileFromPasteboard")
            let createdURL = try FinderCommandHandler.createNewTextFileFromPasteboard(in: directoryURL)
            fileLog.info("  success")
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            fileLog.info("  failed: \(error.localizedDescription)")
            logger.error("Pasteboard text creation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createAndRevealPasteboardPNG(sender: NSMenuItem) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.createAndRevealPasteboardPNG(sender: sender)
            }
            return
        }

        fileLog.info("▶ createAndRevealPasteboardPNG")

        let directoryURL: URL? = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject)

        guard let directoryURL else {
            fileLog.info("  no directory")
            return
        }

        do {
            fileLog.info("  calling createNewPNGFileFromPasteboard")
            let createdURL = try FinderCommandHandler.createNewPNGFileFromPasteboard(in: directoryURL)
            fileLog.info("  success")
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
        } catch {
            fileLog.info("  failed: \(error.localizedDescription)")
            logger.error("Pasteboard PNG creation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createAndReveal(fileName: String, sender: NSMenuItem) {
        // AppKit UI must be on the main thread; Finder may invoke actions off-main.
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.createAndReveal(fileName: fileName, sender: sender)
            }
            return
        }

        fileLog.info("▶ createAndReveal fileName=\(fileName)")

        let directoryURL: URL? = lastMenuCreationDirectoryURL ?? urlFromRepresentedObject(sender.representedObject)

        guard let directoryURL else {
            fileLog.info("  no directory")
            logger.debug("Cannot determine directory for file creation")
            return
        }

        logger.info("create file \(fileName, privacy: .public) in \(directoryURL.path, privacy: .public)")
        fileLog.info("  dir=\(directoryURL.path)")

        do {
            fileLog.info("  calling createNewFile")
            let createdURL = try FinderCommandHandler.createNewFile(in: directoryURL, fileName: fileName)
            fileLog.info("  success, revealing")
            NSWorkspace.shared.activateFileViewerSelecting([createdURL])
            fileLog.info("  done reveal")
        } catch {
            fileLog.info("  error=\(error.localizedDescription)")
            logger.error("Create file error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - End of class

}