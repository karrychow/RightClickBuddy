import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var settings: RCBSettings = RCBSettings.load()
    @State private var saveError: String?

    @State private var scopeRootsError: String?

    var body: some View {
        TabView {
            menuTab
                .tabItem { Label("菜单 / Menu", systemImage: "list.bullet") }

            templatesTab
                .tabItem { Label("模板 / Templates", systemImage: "doc.badge.plus") }

            openWithTab
                .tabItem { Label("打开方式 / Open With", systemImage: "arrow.up.forward.app") }

            tipsTab
                .tabItem { Label("提示 / Tips", systemImage: "info.circle") }
        }
        .padding(16)
        .frame(width: 640, height: 640)
        .onChange(of: settings) { _ in
            saveSettings()
        }
    }

    private var menuTab: some View {
        VStack(spacing: 12) {
            ScrollView {
                Form {
                    Section("菜单 / Menu") {
                        Toggle("启用 Finder 菜单 / Enable Finder Menu", isOn: bindingForMenuEnabled())
                        Toggle("显示 New / Show New", isOn: bindingForShowNew())
                        Toggle("显示 Templates / Show Templates", isOn: bindingForShowTemplates())
                        Toggle("显示 Office / Show Office", isOn: bindingForShowOffice())
                        Toggle("显示 Open With / Show Open With", isOn: bindingForShowOpenWith())
                    }

                    Section("生效目录 / Scope") {
                        if settings.scopeRoots.isEmpty {
                            Text("默认范围：Home + 常用用户目录。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(settings.scopeRoots, id: \.self) { path in
                                HStack {
                                    Text(path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("Remove") {
                                        settings.scopeRoots.removeAll(where: { $0 == path })
                                        RCBScopeRootBookmarkStore.removeBookmark(forScopeRoot: path)
                                    }
                                }
                            }
                        }

                        HStack {
                            Button("Add Folder…") {
                                addScopeRootFromOpenPanel()
                            }

                            Button("Restore Defaults") {
                                settings.scopeRoots = []
                                RCBScopeRootBookmarkStore.removeAll()
                            }
                        }

                        if let scopeRootsError {
                            Text(scopeRootsError)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            footerBar
        }
    }

    private var templatesTab: some View {
        VStack(spacing: 12) {
            ScrollView {
                Form {
                    templateToggles
                }
            }
            footerBar
        }
    }

    private var openWithTab: some View {
        VStack(spacing: 12) {
            ScrollView {
                Form {
                    openWithToggles
                }
            }
            footerBar
        }
    }

    private var tipsTab: some View {
        VStack(spacing: 12) {
            Form {
                Section("RightClickBuddy") {
                    Text("Finder 右键增强 / Finder context actions")
                        .foregroundStyle(.secondary)
                }

                Section("提示 / Tips") {
                    Text("- 修改设置后，重新打开 Finder 右键菜单即可生效。")
                    Text("- 若 Finder 未刷新，可在主 App 菜单里 Reload Finder Extension（Debug）或运行 scripts/dev-reload-findersync.sh。")
                    Text("- Finder 扩展启用位置：系统设置 → 通用 → 登录项与扩展 → 扩展。")
                }
            }
            footerBar
        }
    }

    private var footerBar: some View {
        HStack {
            Button("恢复默认 / Restore Defaults") {
                settings = RCBSettings.defaultSettings
                saveSettings()
            }

            Spacer()

            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
            }
        }
    }

    private var templateToggles: some View {
        let grouped = Dictionary(grouping: RCBSettings.templateSpecs, by: { $0.category })
        return ForEach(grouped.keys.sorted(), id: \.self) { category in
            let specs = grouped[category] ?? []
            Section(category) {
                ForEach(specs) { spec in
                    Toggle(spec.title, isOn: bindingForTemplate(id: spec.id))
                }
            }
        }
    }

    private var openWithToggles: some View {
        let grouped = Dictionary(grouping: RCBSettings.openWithSpecs, by: { $0.category })
        return ForEach(grouped.keys.sorted(), id: \.self) { category in
            let specs = grouped[category] ?? []
            Section(category) {
                ForEach(specs) { spec in
                    let installed = spec.bundleIdCandidates.contains { bundleId in
                        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
                    }

                    Toggle(spec.title + (installed ? "" : " (未安装)"), isOn: bindingForOpenWith(id: spec.id))
                        .disabled(!installed)
                }
            }
        }
    }

    private func saveSettings() {
        do {
            try RCBSettings.save(settings)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func bindingForMenuEnabled() -> Binding<Bool> {
        Binding(
            get: { settings.menu.enabled },
            set: { settings.menu.enabled = $0 }
        )
    }

    private func bindingForShowNew() -> Binding<Bool> {
        Binding(get: { settings.menu.showNew }, set: { settings.menu.showNew = $0 })
    }

    private func bindingForShowTemplates() -> Binding<Bool> {
        Binding(get: { settings.menu.showTemplates }, set: { settings.menu.showTemplates = $0 })
    }

    private func bindingForShowOffice() -> Binding<Bool> {
        Binding(get: { settings.menu.showOffice }, set: { settings.menu.showOffice = $0 })
    }

    private func bindingForShowOpenWith() -> Binding<Bool> {
        Binding(get: { settings.menu.showOpenWith }, set: { settings.menu.showOpenWith = $0 })
    }

    private func bindingForTemplate(id: String) -> Binding<Bool> {
        Binding(
            get: { settings.templates[id] ?? true },
            set: { settings.templates[id] = $0 }
        )
    }

    private func bindingForOpenWith(id: String) -> Binding<Bool> {
        Binding(
            get: { settings.openWith[id] ?? true },
            set: { settings.openWith[id] = $0 }
        )
    }

    private func addScopeRootFromOpenPanel() {
        scopeRootsError = nil

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.title = "选择生效目录 / Choose scope root"
        panel.message = "可选择任意目录（iCloud Drive / 外置磁盘等需要授权）。"

        if panel.runModal() != .OK {
            return
        }
        guard let url = panel.url else {
            return
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let standardized = url.resolvingSymlinksInPath().standardizedFileURL

        // Store a stable string key in settings (prefer ~ for home paths).
        let scopeRootKey: String = {
            if standardized.path.hasPrefix(home.path) {
                let tildePath = "~" + standardized.path.dropFirst(home.path.count)
                return String(tildePath)
            }
            return standardized.path
        }()

        // Create and persist security-scoped bookmark (in App Group UserDefaults).
        do {
            let bookmark = try standardized.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            RCBScopeRootBookmarkStore.setBookmark(bookmark, forScopeRoot: scopeRootKey)

            if !settings.scopeRoots.contains(scopeRootKey) {
                settings.scopeRoots.append(scopeRootKey)
            }
        } catch {
            scopeRootsError = "保存目录授权失败：\(error.localizedDescription)"
        }
    }
}
