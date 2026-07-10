import Foundation

enum RCBAppGroup {
    static let id = "group.com.karry.RightClickBuddy"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: id)
    }
}

enum RCBScopeRootBookmarkStore {
    /// UserDefaults key storing a [String: Data] dictionary.
    /// - key: scope root string (exactly the same as RCBSettings.scopeRoots entries)
    /// - value: security-scoped bookmark data
    static let userDefaultsKey = "RCB.scopeRootBookmarks.v1"

    static func loadAll() -> [String: Data] {
        guard let defaults = RCBAppGroup.defaults else { return [:] }
        guard let anyDict = defaults.dictionary(forKey: userDefaultsKey) else { return [:] }

        var out: [String: Data] = [:]
        for (k, v) in anyDict {
            if let d = v as? Data {
                out[k] = d
            }
        }
        return out
    }

    static func saveAll(_ dict: [String: Data]) {
        guard let defaults = RCBAppGroup.defaults else { return }
        defaults.set(dict as NSDictionary, forKey: userDefaultsKey)
    }

    static func setBookmark(_ data: Data, forScopeRoot scopeRoot: String) {
        var dict = loadAll()
        dict[scopeRoot] = data
        saveAll(dict)
    }

    static func removeBookmark(forScopeRoot scopeRoot: String) {
        var dict = loadAll()
        dict.removeValue(forKey: scopeRoot)
        saveAll(dict)
    }

    static func removeAll() {
        guard let defaults = RCBAppGroup.defaults else { return }
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

struct RCBSettings: Codable, Equatable {
    struct Menu: Codable, Equatable {
        var enabled: Bool = true
        var showNew: Bool = true
        var showTemplates: Bool = true
        var showOffice: Bool = true
        var showOpenWith: Bool = true
        var showMenuBarIcon: Bool = true

        // Use decodeIfPresent for all properties so adding new fields doesn't
        // break decoding of existing persisted settings files.
        init(enabled: Bool = true, showNew: Bool = true, showTemplates: Bool = true, showOffice: Bool = true, showOpenWith: Bool = true, showMenuBarIcon: Bool = true) {
            self.enabled = enabled
            self.showNew = showNew
            self.showTemplates = showTemplates
            self.showOffice = showOffice
            self.showOpenWith = showOpenWith
            self.showMenuBarIcon = showMenuBarIcon
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            self.showNew = try container.decodeIfPresent(Bool.self, forKey: .showNew) ?? true
            self.showTemplates = try container.decodeIfPresent(Bool.self, forKey: .showTemplates) ?? true
            self.showOffice = try container.decodeIfPresent(Bool.self, forKey: .showOffice) ?? true
            self.showOpenWith = try container.decodeIfPresent(Bool.self, forKey: .showOpenWith) ?? true
            self.showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        }
    }

    struct TemplateSpec: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var fileName: String
        var category: String
        var contents: String
    }

    struct OpenWithSpec: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var category: String
        var bundleIdCandidates: [String]
    }

    var menu: Menu = .init()

    /// FinderSync scope roots (directory paths). Empty = default scope.
    ///
    /// - Empty: Home + common user folders (Desktop/Downloads/Movies/Music/Pictures)
    /// - Non-empty: only show FinderSync menu under these roots (and subdirectories)
    var scopeRoots: [String] = []

    /// User-defined template specs (persisted).
    var customTemplateSpecs: [TemplateSpec] = []

    /// Per-template enable flags by TemplateSpec.id.
    var templates: [String: Bool] = [:]

    /// Per-openWith enable flags by OpenWithSpec.id.
    var openWith: [String: Bool] = [:]

    /// OpenWithSpec.id of the terminal used by the top-level "Open in Terminal" menu items.
    /// Optional for backward-compatible decoding of older settings files (nil → Terminal.app).
    var defaultTerminalSpecId: String?

    static let appSupportFolderName = "RightClickBuddy"
    static let settingsFileName = "settings.json"

    static let templateSpecs: [TemplateSpec] = [
        // 模板 — 项目通用基础文件
        TemplateSpec(id: "template.readme", title: "README.md", fileName: "README.md", category: "基础文件", contents: "# README\n\n"),
        TemplateSpec(id: "template.license_mit", title: "LICENSE (MIT)", fileName: "LICENSE", category: "基础文件", contents: "MIT License\n\nCopyright (c) <YEAR> <YOUR NAME>\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the \"Software\"), to deal\nin the Software without restriction, including without limitation the rights\nto use, copy, modify, merge, publish, distribute, sublicense, and/or sell\ncopies of the Software, and to permit persons to whom the Software is\nfurnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all\ncopies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\nIMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\nFITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\nAUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\nLIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\nOUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\nSOFTWARE.\n"),

        // Git
        TemplateSpec(id: "template.gitignore", title: ".gitignore", fileName: ".gitignore", category: "Git", contents: "# macOS\n.DS_Store\n\n# Xcode\nDerivedData/\n*.xcuserstate\n\n# SwiftPM\n.build/\n"),
        TemplateSpec(id: "git.gitattributes", title: ".gitattributes", fileName: ".gitattributes", category: "Git", contents: "# See: https://git-scm.com/docs/gitattributes\n\n* text=auto\n"),

        // DevOps — 构建与部署
        TemplateSpec(id: "template.makefile", title: "Makefile", fileName: "Makefile", category: "DevOps", contents: "# Makefile\n\n.PHONY: help\nhelp:\n\t@echo \"targets: help\"\n"),
        TemplateSpec(id: "devops.dockerfile", title: "Dockerfile", fileName: "Dockerfile", category: "DevOps", contents: "# Dockerfile\n\nFROM alpine:latest\n\nWORKDIR /app\n\nCMD [\"sh\"]\n"),
        TemplateSpec(id: "devops.docker_compose", title: "docker-compose.yml", fileName: "docker-compose.yml", category: "DevOps", contents: "services:\n  app:\n    image: alpine:latest\n    command: [\"sh\"]\n"),

        // 配置 — 通用配置文件
        TemplateSpec(id: "config.info_plist", title: "Info.plist", fileName: "Info.plist", category: "配置", contents: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n</dict>\n</plist>\n"),
        TemplateSpec(id: "config.config_yaml", title: "config.yaml", fileName: "config.yaml", category: "配置", contents: "# config\n"),

        // Python
        TemplateSpec(id: "config.pyproject", title: "pyproject.toml", fileName: "pyproject.toml", category: "Python", contents: "[project]\nname = \"example\"\nversion = \"0.1.0\"\n"),
        TemplateSpec(id: "py.requirements", title: "requirements.txt", fileName: "requirements.txt", category: "Python", contents: "\n"),

        // JavaScript / TypeScript
        TemplateSpec(id: "js.package_json", title: "package.json", fileName: "package.json", category: "JavaScript / TypeScript", contents: "{\n  \"name\": \"example\",\n  \"version\": \"0.1.0\",\n  \"private\": true\n}\n"),
        TemplateSpec(id: "js.tsconfig", title: "tsconfig.json", fileName: "tsconfig.json", category: "JavaScript / TypeScript", contents: "{\n  \"compilerOptions\": {\n    \"target\": \"ES2022\",\n    \"module\": \"ESNext\",\n    \"moduleResolution\": \"Bundler\",\n    \"strict\": true\n  }\n}\n"),
        TemplateSpec(id: "js.prettierrc", title: ".prettierrc", fileName: ".prettierrc", category: "JavaScript / TypeScript", contents: "{\n  \"semi\": false,\n  \"singleQuote\": true\n}\n"),

        // Go
        TemplateSpec(id: "go.gomod", title: "go.mod", fileName: "go.mod", category: "Go", contents: "module example.com/project\n\ngo 1.22\n"),

        // Rust
        TemplateSpec(id: "rust.cargo_toml", title: "Cargo.toml", fileName: "Cargo.toml", category: "Rust", contents: "[package]\nname = \"example\"\nversion = \"0.1.0\"\nedition = \"2021\"\n\n[dependencies]\n"),

        // 入口文件 — 各语言 main 模板
        TemplateSpec(id: "code.main_swift", title: "main.swift", fileName: "main.swift", category: "入口文件", contents: "\n"),
        TemplateSpec(id: "code.main_py", title: "main.py", fileName: "main.py", category: "入口文件", contents: "\n"),
        TemplateSpec(id: "code.index_ts", title: "index.ts", fileName: "index.ts", category: "入口文件", contents: "\n"),
        TemplateSpec(id: "code.main_go", title: "main.go", fileName: "main.go", category: "入口文件", contents: "\n"),
        TemplateSpec(id: "code.main_rs", title: "main.rs", fileName: "main.rs", category: "入口文件", contents: "\n"),
        TemplateSpec(id: "code.main_js", title: "main.js", fileName: "main.js", category: "入口文件", contents: "\n"),
    ]

    static let openWithSpecs: [OpenWithSpec] = [
        // Terminal
        OpenWithSpec(id: "openwith.terminal", title: "Terminal", category: "Terminal", bundleIdCandidates: ["com.apple.Terminal"]),
        OpenWithSpec(id: "openwith.iterm2", title: "iTerm2", category: "Terminal", bundleIdCandidates: ["com.googlecode.iterm2"]),
        OpenWithSpec(id: "openwith.warp", title: "Warp", category: "Terminal", bundleIdCandidates: ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview"]),
        OpenWithSpec(id: "openwith.wezterm", title: "WezTerm", category: "Terminal", bundleIdCandidates: ["com.github.wez.wezterm"]),

        // Editors
        OpenWithSpec(id: "openwith.vscode", title: "VS Code", category: "Editors", bundleIdCandidates: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]),
        OpenWithSpec(id: "openwith.xcode", title: "Xcode", category: "Editors", bundleIdCandidates: ["com.apple.dt.Xcode"]),
        OpenWithSpec(id: "openwith.cursor", title: "Cursor", category: "Editors", bundleIdCandidates: [
            "com.todesktop.230313mzl4w4u92",
            "com.todesktop.230313mzl4w4u92.dev"
        ]),
        OpenWithSpec(id: "openwith.zed", title: "Zed", category: "Editors", bundleIdCandidates: ["dev.zed.Zed"]),
        OpenWithSpec(id: "openwith.textmate", title: "TextMate", category: "Editors", bundleIdCandidates: ["com.macromates.TextMate"]),
        OpenWithSpec(id: "openwith.coteditor", title: "CotEditor", category: "Editors", bundleIdCandidates: ["com.coteditor.CotEditor"]),
        OpenWithSpec(id: "openwith.sublime", title: "Sublime Text", category: "Editors", bundleIdCandidates: ["com.sublimetext.4"]),
        OpenWithSpec(id: "openwith.bbedit", title: "BBEdit", category: "Editors", bundleIdCandidates: ["com.barebones.bbedit"]),
        OpenWithSpec(id: "openwith.nova", title: "Nova", category: "Editors", bundleIdCandidates: ["com.panic.Nova"]),
        OpenWithSpec(id: "openwith.macvim", title: "MacVim", category: "Editors", bundleIdCandidates: ["org.vim.MacVim"]),
        OpenWithSpec(id: "openwith.vimr", title: "VimR", category: "Editors", bundleIdCandidates: ["com.qvacua.VimR"]),

        // Notes / Writing
        OpenWithSpec(id: "openwith.typora", title: "Typora", category: "Notes", bundleIdCandidates: ["abnerworks.Typora"]),
        OpenWithSpec(id: "openwith.obsidian", title: "Obsidian", category: "Notes", bundleIdCandidates: ["md.obsidian"]),

        // JetBrains
        OpenWithSpec(id: "openwith.intellij", title: "IntelliJ IDEA", category: "JetBrains", bundleIdCandidates: [
            "com.jetbrains.intellij",
            "com.jetbrains.intellij.ce",
            "com.jetbrains.intellij-EAP",
            "com.jetbrains.intellij.ce-EAP"
        ]),
        OpenWithSpec(id: "openwith.pycharm", title: "PyCharm", category: "JetBrains", bundleIdCandidates: [
            "com.jetbrains.pycharm",
            "com.jetbrains.pycharm.ce",
            "com.jetbrains.pycharm-EAP",
            "com.jetbrains.pycharm.ce-EAP"
        ]),
        OpenWithSpec(id: "openwith.webstorm", title: "WebStorm", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.WebStorm", "com.jetbrains.WebStorm-EAP"]),
        OpenWithSpec(id: "openwith.goland", title: "GoLand", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.goland", "com.jetbrains.goland-EAP"]),
        OpenWithSpec(id: "openwith.clion", title: "CLion", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.CLion", "com.jetbrains.CLion-EAP"]),
        OpenWithSpec(id: "openwith.rider", title: "Rider", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.rider", "com.jetbrains.rider-EAP"]),
        OpenWithSpec(id: "openwith.datagrip", title: "DataGrip", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.datagrip", "com.jetbrains.datagrip-EAP"]),
        OpenWithSpec(id: "openwith.androidstudio", title: "Android Studio", category: "JetBrains", bundleIdCandidates: ["com.google.android.studio"]),
        OpenWithSpec(id: "openwith.rubymine", title: "RubyMine", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.rubymine", "com.jetbrains.rubymine-EAP"]),
        OpenWithSpec(id: "openwith.phpstorm", title: "PhpStorm", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.PhpStorm", "com.jetbrains.PhpStorm-EAP"]),
        OpenWithSpec(id: "openwith.dataspell", title: "DataSpell", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.dataspell", "com.jetbrains.dataspell-EAP"]),
        OpenWithSpec(id: "openwith.fleet", title: "Fleet", category: "JetBrains", bundleIdCandidates: ["com.jetbrains.fleet", "com.jetbrains.fleet-EAP"])
    ]

    /// All template specs: built-in + user-defined.
    var allTemplateSpecs: [TemplateSpec] {
        Self.templateSpecs + customTemplateSpecs
    }

    /// Terminal apps selectable as the default terminal (the "Terminal" category).
    static var terminalSpecs: [OpenWithSpec] {
        openWithSpecs.filter { $0.category == "Terminal" }
    }

    /// The terminal chosen for the top-level "Open in Terminal" items (falls back to Terminal.app).
    var defaultTerminalSpec: OpenWithSpec {
        let id = defaultTerminalSpecId ?? "openwith.terminal"
        return Self.openWithSpecs.first { $0.id == id }
            ?? Self.openWithSpecs.first { $0.id == "openwith.terminal" }!
    }

    // MARK: - Custom Template CRUD

    mutating func addCustomTemplate(_ template: TemplateSpec) {
        var t = template
        if t.id.isEmpty {
            t.id = UUID().uuidString
        }
        customTemplateSpecs.append(t)
    }

    mutating func updateCustomTemplate(_ template: TemplateSpec) {
        guard let idx = customTemplateSpecs.firstIndex(where: { $0.id == template.id }) else { return }
        customTemplateSpecs[idx] = template
    }

    mutating func removeCustomTemplate(id: String) {
        customTemplateSpecs.removeAll(where: { $0.id == id })
        templates.removeValue(forKey: id)
    }

    mutating func renameCategory(from oldName: String, to newName: String) {
        for i in customTemplateSpecs.indices where customTemplateSpecs[i].category == oldName {
            customTemplateSpecs[i].category = newName
        }
    }

    /// Returns the custom template IDs that belong to a category.
    func customTemplateIDs(inCategory category: String) -> [String] {
        customTemplateSpecs.filter { $0.category == category }.map(\.id)
    }

    mutating func removeAllCustomTemplates(inCategory category: String) {
        let ids = customTemplateSpecs.filter { $0.category == category }.map(\.id)
        customTemplateSpecs.removeAll { $0.category == category }
        for id in ids {
            templates.removeValue(forKey: id)
        }
    }

    static var defaultSettings: RCBSettings {
        var s = RCBSettings()
        for t in templateSpecs {
            s.templates[t.id] = true
        }
        for a in openWithSpecs {
            s.openWith[a.id] = true
        }
        // Stability: Obsidian is opt-in.
        s.openWith["openwith.obsidian"] = false
        return s
    }

    func isTemplateEnabled(_ id: String) -> Bool {
        templates[id] ?? true
    }

    func isOpenWithEnabled(_ id: String) -> Bool {
        openWith[id] ?? true
    }

    func normalized() -> RCBSettings {
        var s = self
        // Fill defaults for any newly-added items.
        for t in Self.templateSpecs where s.templates[t.id] == nil {
            s.templates[t.id] = true
        }
        for t in s.customTemplateSpecs where s.templates[t.id] == nil {
            s.templates[t.id] = true
        }
        for a in Self.openWithSpecs where s.openWith[a.id] == nil {
            // Stability: Obsidian is opt-in.
            if a.id == "openwith.obsidian" {
                s.openWith[a.id] = false
            } else {
                s.openWith[a.id] = true
            }
        }
        return s
    }

    private static func realUserHomeDirectoryForSettings() -> URL {
        // FinderSync runs in a sandbox container where homeDirectoryForCurrentUser points to:
        //   ~/Library/Containers/<bundle>/Data
        // The main app runs unsandboxed, so this returns the real user home there.
        let home = FileManager.default.homeDirectoryForCurrentUser
        if home.path.contains("/Library/Containers/") {
            return URL(fileURLWithPath: "/Users/\(NSUserName())", isDirectory: true)
        }
        return home
    }

    /// True when this code runs inside the FinderSync app extension (vs. the main app).
    static var isRunningInExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// Canonical settings file, owned by the (non-sandboxed) main app in the real user home.
    ///
    /// We deliberately DON'T use the App Group container: an ad-hoc-signed build can't access the
    /// data-vault-protected group container. A plain Application Support path is always writable by
    /// the unsandboxed main app, and the sandboxed extension gets a copy over IPC (see
    /// `refreshExtensionCacheFromMainApp`). This lets the whole app work fully with ad-hoc signing.
    static func mainAppSettingsURL() -> URL {
        realUserHomeDirectoryForSettings()
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent(settingsFileName, isDirectory: false)
    }

    /// Read-through cache kept inside the extension's OWN sandbox container (always writable by the
    /// extension itself). Refreshed from the main app via `refreshExtensionCacheFromMainApp()`.
    private static func extensionCacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(appSupportFolderName, isDirectory: true)
            .appendingPathComponent("settings-cache.json", isDirectory: false)
    }

    private static func decodeNormalized(_ data: Data) -> RCBSettings? {
        (try? JSONDecoder().decode(RCBSettings.self, from: data))?.normalized()
    }

    static func load() -> RCBSettings {
        isRunningInExtension ? loadExtensionCache() : loadMainAppFile()
    }

    private static func loadMainAppFile() -> RCBSettings {
        let url = mainAppSettingsURL()
        guard let data = try? Data(contentsOf: url), let decoded = decodeNormalized(data) else {
            AppLogger.settings.info("No settings file found, using defaults")
            return defaultSettings
        }
        AppLogger.settings.info("Settings loaded from \(url.path)")
        return decoded
    }

    private static func loadExtensionCache() -> RCBSettings {
        guard let data = try? Data(contentsOf: extensionCacheURL()), let decoded = decodeNormalized(data) else {
            return defaultSettings
        }
        return decoded
    }

    static func save(_ settings: RCBSettings) throws {
        // Only the main app persists settings.
        let url = mainAppSettingsURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings.normalized())
        try data.write(to: url, options: [.atomic])
        AppLogger.settings.info("Settings saved to \(url.path)")
    }

    /// Extension only: pull the latest settings from the main app over IPC and refresh the local
    /// cache. Fails silently to the existing cache if the app isn't reachable, so it's safe to call
    /// on the menu-building path.
    static func refreshExtensionCacheFromMainApp() {
        guard isRunningInExtension else { return }
        guard let data = try? IPCTcpClient.getSettings(), decodeNormalized(data) != nil else { return }
        let url = extensionCacheURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    static func loadCached() -> RCBSettings {
        load()
    }
}
