import AppKit
import SwiftUI

// MARK: - Styling Components

private struct SectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor).opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
    }
}

private struct ToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.body)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

private struct SearchBar: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor).opacity(0.15), lineWidth: 1)
        )
    }
}

struct SettingsView: View {
    @State private var settings: RCBSettings = RCBSettings.load()
    @State private var saveError: String?

    @State private var scopeRootsError: String?

    @State private var templateSearchText = ""
    @State private var openWithSearchText = ""

    @State private var showTemplateEditor = false
    @State private var editingTemplate = RCBSettings.TemplateSpec(id: "", title: "", fileName: "", category: "", contents: "")
    @State private var isNewTemplate = false

    @State private var showCategoryRenameAlert = false
    @State private var categoryToRename = ""
    @State private var newCategoryName = ""
    @State private var showDeleteCategoryConfirm = false
    @State private var categoryToDelete = ""

    @State private var expandedCategories: Set<String> = []
    @State private var owExpandedCategories: Set<String> = []

    /// nil = still checking; true/false = pluginkit election state.
    @State private var extensionEnabled: Bool? = nil
    @State private var showResetConfirm = false
    @State private var showLogs = false

    var body: some View {
        TabView {
            menuTab
                .tabItem { Label(RCLocalizedString("菜单"), systemImage: "list.bullet") }

            templatesTab
                .tabItem { Label(RCLocalizedString("模板"), systemImage: "doc.badge.plus") }

            openWithTab
                .tabItem { Label(RCLocalizedString("打开方式"), systemImage: "arrow.up.forward.app") }

            generalTab
                .tabItem { Label(RCLocalizedString("通用"), systemImage: "gearshape") }
        }
        .padding(16)
        .frame(width: 740, height: 640)
        .onChange(of: settings) { _ in
            Task { saveSettings() }
        }
    }

    // MARK: - Menu Tab

    private var menuTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    menuCard
                    scopeCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            settingsFooter
        }
    }

    private var languageCard: some View {
        SectionCard {
            SectionHeader(icon: "globe", title: RCLocalizedString("语言"))

            Picker(selection: Binding(
                get: { LanguageManager.preferredLanguage },
                set: { newValue in
                    LanguageManager.preferredLanguage = newValue
                    NotificationCenter.default.post(name: .RCBLanguageDidChange, object: nil)
                }
            )) {
                Text(RCLocalizedString("跟随系统")).tag("")
                Text("中文").tag("zh-Hans")
                Text("English").tag("en")
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var menuCard: some View {
        SectionCard {
            SectionHeader(icon: "menucard", title: RCLocalizedString("菜单项"))

            VStack(spacing: 4) {
                ToggleRow(icon: "switch.2", label: RCLocalizedString("启用 Finder 菜单"), isOn: bindingForMenuEnabled())
                Divider()
                    .padding(.leading, 30)
                Group {
                    ToggleRow(icon: "plus.square", label: RCLocalizedString("显示 New"), isOn: bindingForShowNew())
                    ToggleRow(icon: "doc.text", label: RCLocalizedString("显示 Templates"), isOn: bindingForShowTemplates())
                    ToggleRow(icon: "doc.fill", label: RCLocalizedString("显示 Office"), isOn: bindingForShowOffice())
                    ToggleRow(icon: "arrow.up.forward.app", label: RCLocalizedString("显示 Open With"), isOn: bindingForShowOpenWith())
                }
                .disabled(!settings.menu.enabled)
                .opacity(settings.menu.enabled ? 1 : 0.5)
            }
        }
    }

    private var scopeCard: some View {
        SectionCard {
            SectionHeader(icon: "folder", title: RCLocalizedString("生效目录"))

            if settings.scopeRoots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(RCLocalizedString("默认在以下目录（及其子目录）生效："))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(["~/Desktop", "~/Downloads", "~/Movies", "~/Music", "~/Pictures"], id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .frame(width: 20)
                            Text(path)
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(settings.scopeRoots, id: \.self) { path in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .font(.body)
                                .foregroundStyle(.tint)
                                .frame(width: 20)
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .font(.body.monospacedDigit())
                            Spacer()
                            Button {
                                settings.scopeRoots.removeAll(where: { $0 == path })
                                RCBScopeRootBookmarkStore.removeBookmark(forScopeRoot: path)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help(RCLocalizedString("Remove"))
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 8)
                        .padding(.trailing, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.windowBackgroundColor))
                        )

                        if path != settings.scopeRoots.last {
                            Divider()
                                .padding(.leading, 30)
                        }
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(RCLocalizedString("已设置自定义目录：菜单仅在所列目录（及其子目录）中显示，默认目录不再生效。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 12)
            }

            HStack(spacing: 10) {
                Button {
                    addScopeRootFromOpenPanel()
                } label: {
                    Label(RCLocalizedString("添加目录…"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(RCLocalizedString("恢复默认范围")) {
                    settings.scopeRoots = []
                    RCBScopeRootBookmarkStore.removeAll()
                }
                .buttonStyle(.link)
                .controlSize(.small)
            }

            if let scopeRootsError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(scopeRootsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Extension Management

    /// Extension health: live pluginkit election status + the enable/reload tools.
    /// This is the first thing a user needs to see — "no menu in Finder" is the #1 issue.
    private var finderExtensionCard: some View {
        SectionCard {
            SectionHeader(icon: "puzzlepiece.extension", title: RCLocalizedString("Finder 扩展"))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(extensionEnabled == nil ? Color.gray : (extensionEnabled! ? Color.green : Color.red))
                        .frame(width: 9, height: 9)
                    Text(extensionEnabled == nil
                         ? RCLocalizedString("检测中…")
                         : (extensionEnabled! ? RCLocalizedString("扩展已启用") : RCLocalizedString("扩展未启用")))
                        .font(.body)
                }

                if extensionEnabled == false {
                    Text(RCLocalizedString("右键菜单不可用。请在系统设置中启用 Finder 扩展。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    if extensionEnabled == false {
                        Button(RCLocalizedString("打开系统扩展设置…")) { openSystemExtensionSettings() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Button(RCLocalizedString("打开系统扩展设置…")) { openSystemExtensionSettings() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Button(RCLocalizedString("重载 Finder 扩展")) {
                        reloadFinderExtensionAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .task {
            while !Task.isCancelled {
                refreshExtensionStatus()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func openSystemExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Query pluginkit for the extension's election state ('+' prefix = enabled).
    private func refreshExtensionStatus() {
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            task.arguments = ["-m", "-i", "com.karry.RightClickBuddy.FinderSync"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            var enabled = false
            do {
                try task.run()
                task.waitUntilExit()
                let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                enabled = out.trimmingCharacters(in: .whitespaces).hasPrefix("+")
            } catch {
                enabled = false
            }
            DispatchQueue.main.async { extensionEnabled = enabled }
        }
    }

    // MARK: - Templates Tab

    private var templatesTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchBar(
                    placeholder: RCLocalizedString("搜索模板…"),
                    text: $templateSearchText
                )
                Button {
                    isNewTemplate = true
                    editingTemplate = RCBSettings.TemplateSpec(id: "", title: "", fileName: "", category: "", contents: "")
                    showTemplateEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help(RCLocalizedString("添加模板"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            hiddenGroupBanner(groupVisible: settings.menu.showTemplates, groupName: RCLocalizedString("模板")) {
                settings.menu.showTemplates = true
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    templateList
                }
            }

            settingsFooter
        }
        .onAppear {
            if expandedCategories.isEmpty {
                expandedCategories = Set(settings.allTemplateSpecs.map(\.category))
            }
        }
        .sheet(isPresented: $showTemplateEditor) {
            TemplateEditView(
                spec: $editingTemplate,
                isNew: isNewTemplate,
                onSave: { spec in
                    if isNewTemplate {
                        settings.addCustomTemplate(spec)
                    } else if RCBSettings.templateSpecs.contains(where: { $0.id == spec.id }) {
                        var copy = spec
                        copy.id = UUID().uuidString
                        settings.addCustomTemplate(copy)
                        settings.templates[spec.id] = false
                    } else {
                        settings.updateCustomTemplate(spec)
                    }
                    showTemplateEditor = false
                },
                onCancel: { showTemplateEditor = false }
            )
        }
        .alert(RCLocalizedString("重命名分类"), isPresented: $showCategoryRenameAlert) {
            TextField(RCLocalizedString("新分类名称"), text: $newCategoryName)
            Button(RCLocalizedString("取消"), role: .cancel) { }
            Button(RCLocalizedString("确定")) {
                let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
                let targetKey = LanguageManager.originalKey(for: trimmed) ?? trimmed
                if !targetKey.isEmpty, targetKey != categoryToRename {
                    settings.renameCategory(from: categoryToRename, to: targetKey)
                }
            }
        } message: {
            Text(String(format: RCLocalizedString("将「%@」重命名为："), RCLocalizedString(categoryToRename)))
        }
        .alert(RCLocalizedString("删除分类"), isPresented: $showDeleteCategoryConfirm) {
            Button(RCLocalizedString("取消"), role: .cancel) { }
            Button(RCLocalizedString("删除"), role: .destructive) {
                settings.removeAllCustomTemplates(inCategory: categoryToDelete)
            }
        } message: {
            Text(String(format: RCLocalizedString("确定删除分类「%@」及其所有自定义模板？此操作不可撤销。"), RCLocalizedString(categoryToDelete)))
        }
    }


    // MARK: - OpenWith Tab

    private var openWithTab: some View {
        VStack(spacing: 0) {
            SearchBar(
                placeholder: RCLocalizedString("搜索应用…"),
                text: $openWithSearchText
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            hiddenGroupBanner(groupVisible: settings.menu.showOpenWith, groupName: RCLocalizedString("打开方式")) {
                settings.menu.showOpenWith = true
            }

            defaultTerminalCard
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    openWithToggles
                }
            }

            settingsFooter
        }
        .onAppear {
            if owExpandedCategories.isEmpty {
                owExpandedCategories = Set(RCBSettings.openWithSpecs.map(\.category))
            }
        }
    }

    /// Whether any of the spec's candidate bundle IDs resolves to an installed app.
    private func isInstalled(_ spec: RCBSettings.OpenWithSpec) -> Bool {
        spec.bundleIdCandidates.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// The real icon for an installed app, or a faded placeholder when not installed.
    @ViewBuilder
    private func appIcon(for spec: RCBSettings.OpenWithSpec, installed: Bool) -> some View {
        if installed,
           let url = spec.bundleIdCandidates.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
    }

    /// Terminal apps that are actually installed (Terminal.app is always present).
    private var installedTerminalSpecs: [RCBSettings.OpenWithSpec] {
        RCBSettings.terminalSpecs.filter { isInstalled($0) }
    }

    /// Picker for the terminal used by the top-level "Open in Terminal" menu items.
    private var defaultTerminalCard: some View {
        SectionCard {
            SectionHeader(icon: "terminal", title: RCLocalizedString("默认终端"))

            Picker(selection: Binding(
                get: { settings.defaultTerminalSpec.id },
                set: { newValue in
                    settings.defaultTerminalSpecId = newValue
                    saveSettings()
                }
            )) {
                ForEach(installedTerminalSpecs) { spec in
                    Text(spec.title).tag(spec.id)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Text(String(format: RCLocalizedString("用于右键菜单中的「在 %@ 打开」。"), settings.defaultTerminalSpec.title))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
    }


    // MARK: - General Tab

    private var generalTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    finderExtensionCard
                    appPreferencesCard
                    languageCard
                    logCard
                    restoreDefaultsCard
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            settingsFooter
        }
    }

    /// App-level preferences: menu-bar presence + launch at login.
    private var appPreferencesCard: some View {
        SectionCard {
            SectionHeader(icon: "app.badge", title: RCLocalizedString("应用"))

            VStack(alignment: .leading, spacing: 4) {
                ToggleRow(icon: "menubar.rectangle", label: RCLocalizedString("显示菜单栏图标"), isOn: bindingForShowMenuBarIcon())
                Text(RCLocalizedString("隐藏后，可通过 Dock 图标重新打开设置。"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 30)
                ToggleRow(icon: "power", label: RCLocalizedString("开机启动"), isOn: Binding(
                    get: { LaunchAtLoginManager.isEnabled },
                    set: { LaunchAtLoginManager.setEnabled($0) }
                ))
            }
        }
    }

    private var restoreDefaultsCard: some View {
        SectionCard {
            SectionHeader(icon: "arrow.counterclockwise", title: RCLocalizedString("恢复默认设置"))

            VStack(alignment: .leading, spacing: 8) {
                Text(RCLocalizedString("遇到异常行为时，可尝试恢复所有设置为默认值。此操作不可撤销。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(RCLocalizedString("恢复默认"), role: .destructive) {
                    showResetConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .alert(RCLocalizedString("恢复默认设置"), isPresented: $showResetConfirm) {
            Button(RCLocalizedString("取消"), role: .cancel) { }
            Button(RCLocalizedString("恢复默认"), role: .destructive) {
                settings = RCBSettings.defaultSettings
                saveSettings()
            }
        } message: {
            Text(RCLocalizedString("所有设置（包括生效目录、默认终端与各项开关）将恢复为默认值。此操作不可撤销。"))
        }
    }

    private var aboutCard: some View {
        SectionCard {
            SectionHeader(icon: "info.circle", title: RCLocalizedString("关于"))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RightClickBuddy")
                            .font(.body.weight(.semibold))
                        Text(RCLocalizedString("Finder 右键增强"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")) · MIT License")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button {
                        if let url = URL(string: "https://github.com/karrychow/RightClickBuddy") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("GitHub", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                TipRow(icon: "arrow.triangle.2.circlepath",
                       text: RCLocalizedString("修改设置后，重新打开 Finder 右键菜单即可生效。"))
                TipRow(icon: "gearshape.2",
                       text: RCLocalizedString("Finder 扩展启用位置：系统设置 → 通用 → 登录项与扩展 → 扩展。"))
            }
        }
    }

    // MARK: - Footer

    private var settingsFooter: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                if let saveError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()

                Text("RightClickBuddy v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Hidden-Group Banner

    /// Shown at the top of the Templates / Open With tabs when that menu group (or the whole
    /// Finder menu) is switched off — otherwise users tweak toggles here and see no effect.
    @ViewBuilder
    private func hiddenGroupBanner(groupVisible: Bool, groupName: String, enable: @escaping () -> Void) -> some View {
        if !settings.menu.enabled || !groupVisible {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(!settings.menu.enabled
                     ? RCLocalizedString("Finder 菜单已停用，以下配置暂不会生效。")
                     : String(format: RCLocalizedString("「%@」菜单当前已隐藏，以下配置暂不会生效。"), groupName))
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                Button(RCLocalizedString("去开启")) {
                    settings.menu.enabled = true
                    enable()
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Tip Row

    private struct TipRow: View {
        let icon: String
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Template List

    private var templateList: some View {
        let allSpecs = settings.allTemplateSpecs
        let grouped = Dictionary(grouping: allSpecs, by: { $0.category })
        let filtered: [(String, [RCBSettings.TemplateSpec])]
        if templateSearchText.isEmpty {
            filtered = grouped.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        } else {
            filtered = grouped.compactMap { category, specs in
                let matched = specs.filter { spec in
                    spec.title.localizedCaseInsensitiveContains(templateSearchText) ||
                    category.localizedCaseInsensitiveContains(templateSearchText)
                }
                return matched.isEmpty ? nil : (category, matched)
            }.sorted { $0.0 < $1.0 }
        }
        return ForEach(filtered, id: \.0) { category, specs in
            DisclosureGroup(isExpanded: Binding(
                get: { expandedCategories.contains(category) },
                set: { if $0 { expandedCategories.insert(category) } else { expandedCategories.remove(category) } }
            )) {
                VStack(spacing: 2) {
                    ForEach(specs) { spec in
                        templateRow(spec: spec, category: category)
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 4)
            } label: {
                let enabledCount = specs.filter { settings.isTemplateEnabled($0.id) }.count
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(RCLocalizedString(category))
                        .font(.body)
                        .fontWeight(.medium)
                    Text("\(enabledCount)/\(specs.count)")
                        .font(.caption)
                        .foregroundStyle(enabledCount > 0 ? .secondary : .tertiary)
                    Spacer()
                    Menu {
                        Button(RCLocalizedString("全部启用")) {
                            for spec in specs { settings.templates[spec.id] = true }
                        }
                        Button(RCLocalizedString("全部禁用")) {
                            for spec in specs { settings.templates[spec.id] = false }
                        }
                        Divider()
                        Button(RCLocalizedString("重命名分类")) {
                            categoryToRename = category
                            newCategoryName = RCLocalizedString(category)
                            showCategoryRenameAlert = true
                        }
                        if !settings.customTemplateIDs(inCategory: category).isEmpty {
                            Divider()
                            Button(RCLocalizedString("删除分类"), role: .destructive) {
                                categoryToDelete = category
                                showDeleteCategoryConfirm = true
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 20)
        }
    }

    private func templateRow(spec: RCBSettings.TemplateSpec, category: String) -> some View {
        let isBuiltin = RCBSettings.templateSpecs.contains(where: { $0.id == spec.id })
        return HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(spec.title)
                .font(.body)
            Spacer()

            Toggle("", isOn: bindingForTemplate(id: spec.id))
                .toggleStyle(.switch)
                .controlSize(.small)

            Button {
                isNewTemplate = false
                editingTemplate = spec
                showTemplateEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(RCLocalizedString("编辑"))

            if !isBuiltin {
                Button {
                    settings.removeCustomTemplate(id: spec.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(RCLocalizedString("删除"))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor))
        )
    }

    // MARK: - OpenWith Toggles

    private var openWithToggles: some View {
        let grouped = Dictionary(grouping: RCBSettings.openWithSpecs, by: { $0.category })
        let filtered: [(String, [RCBSettings.OpenWithSpec])]
        if openWithSearchText.isEmpty {
            filtered = grouped.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
        } else {
            filtered = grouped.compactMap { category, specs in
                let matched = specs.filter { spec in
                    spec.title.localizedCaseInsensitiveContains(openWithSearchText) ||
                    category.localizedCaseInsensitiveContains(openWithSearchText)
                }
                return matched.isEmpty ? nil : (category, matched)
            }.sorted { $0.0 < $1.0 }
        }
        return ForEach(filtered, id: \.0) { category, specs in
            DisclosureGroup(isExpanded: Binding(
                get: { owExpandedCategories.contains(category) },
                set: { if $0 { owExpandedCategories.insert(category) } else { owExpandedCategories.remove(category) } }
            )) {
                VStack(spacing: 2) {
                    // Installed apps first, then not-installed.
                    ForEach(specs.sorted { isInstalled($0) && !isInstalled($1) }) { spec in
                        let installed = isInstalled(spec)

                        HStack(spacing: 10) {
                            appIcon(for: spec, installed: installed)
                                .frame(width: 18, height: 18)

                            Text(spec.title + (installed ? "" : RCLocalizedString(" (未安装)")))
                                .font(.body)
                                .foregroundStyle(installed ? .primary : .tertiary)

                            Spacer()

                            // Not-installed apps show a clearly-off, disabled switch (never a
                            // misleading faded-on state).
                            if installed {
                                Toggle("", isOn: bindingForOpenWith(id: spec.id))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            } else {
                                Toggle("", isOn: .constant(false))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .disabled(true)
                            }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.windowBackgroundColor))
                        )
                        .opacity(installed ? 1 : 0.55)
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
            } label: {
                let installed = specs.filter { isInstalled($0) }
                let enabledCount = installed.filter { settings.isOpenWithEnabled($0.id) }.count
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(RCLocalizedString(category))
                        .font(.body)
                        .fontWeight(.medium)
                    Text("\(enabledCount)/\(installed.count)")
                        .font(.caption)
                        .foregroundStyle(enabledCount > 0 ? .secondary : .tertiary)
                    Spacer()
                    Menu {
                        Button(RCLocalizedString("全部启用")) {
                            for spec in installed { settings.openWith[spec.id] = true }
                        }
                        Button(RCLocalizedString("全部禁用")) {
                            for spec in specs { settings.openWith[spec.id] = false }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Log Viewer

    @State private var logLines: [String] = []
    @State private var logRefreshPaused = false
    @State private var logTimer: Task<Void, Never>?

    private var logCard: some View {
        SectionCard {
            // Collapsed by default — logs are a support tool, not everyday content.
            Button {
                withAnimation { showLogs.toggle() }
            } label: {
                HStack(spacing: 6) {
                    SectionHeader(icon: "doc.text.magnifyingglass", title: RCLocalizedString("日志"))
                    Spacer()
                    Image(systemName: showLogs ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showLogs {
            VStack(alignment: .leading, spacing: 8) {
                // Toolbar
                HStack(spacing: 8) {
                    Toggle(RCLocalizedString("暂停刷新"), isOn: $logRefreshPaused)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.caption)

                    Spacer()

                    Button(RCLocalizedString("打开日志文件夹")) {
                        NSWorkspace.shared.open(AppLogger.logsDirectoryURL())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(RCLocalizedString("复制日志")) {
                        let text = AppLogger.exportAllLogs()
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(text, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Log content
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(logLines.suffix(100).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(logLineColor(line))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 200)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.separatorColor).opacity(0.15), lineWidth: 1)
                )

                // Crash report banner
                if AppLogger.hasPendingCrashReport() {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(RCLocalizedString("检测到上次会话存在崩溃"))
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        if let report = AppLogger.pendingCrashReport() {
                            Button(RCLocalizedString("复制崩溃报告")) {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(report, forType: .string)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .foregroundStyle(.red)
                        }
                        Button(RCLocalizedString("清除")) {
                            AppLogger.clearCrashReports()
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.08))
                    )
                }
            }
            }
        }
        .task {
            await refreshLogsLoop()
        }
        .onAppear {
            // Surface crash info immediately instead of hiding it behind the fold.
            if AppLogger.hasPendingCrashReport() { showLogs = true }
        }
        .onDisappear {
            logTimer?.cancel()
        }
    }

    private func logLineColor(_ line: String) -> Color {
        if line.contains("| ERROR |") || line.contains("| FAULT |") || line.contains("| CRASH |") {
            return .red
        }
        if line.contains("| INFO |") {
            return .secondary
        }
        return .primary
    }

    private func refreshLogsLoop() async {
        while !Task.isCancelled {
            if !logRefreshPaused {
                logLines = AppLogger.readRecentLogs(limit: 200)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    // MARK: - Save

    private func saveSettings() {
        do {
            try RCBSettings.save(settings)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Bindings

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

    private func bindingForShowMenuBarIcon() -> Binding<Bool> {
        Binding(
            get: { settings.menu.showMenuBarIcon },
            set: {
                settings.menu.showMenuBarIcon = $0
                NotificationCenter.default.post(name: .RCBMenuBarIconDidChange, object: nil)
            }
        )
    }

    private func bindingForTemplate(id: String) -> Binding<Bool> {
        Binding(
            get: { settings.templates[id] ?? true },
            set: { settings.templates[id] = $0 }
        )
    }

    private func isAppInstalled(_ id: String) -> Bool {
        guard let spec = RCBSettings.openWithSpecs.first(where: { $0.id == id }) else { return false }
        return spec.bundleIdCandidates.contains { bundleId in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        }
    }

    private func bindingForOpenWith(id: String) -> Binding<Bool> {
        let installed = isAppInstalled(id)
        return Binding(
            get: { settings.openWith[id] ?? installed },
            set: { settings.openWith[id] = $0 }
        )
    }

    // MARK: - Scope Root

    private func addScopeRootFromOpenPanel() {
        scopeRootsError = nil

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = RCLocalizedString("Choose")
        panel.title = RCLocalizedString("选择生效目录")
        panel.message = RCLocalizedString("可选择任意目录（iCloud Drive / 外置磁盘等需要授权）。")

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

        // Home-directory paths don't need security-scoped bookmarks — the extension accesses them directly.
        if standardized.path.hasPrefix(home.path) {
            if !settings.scopeRoots.contains(scopeRootKey) {
                settings.scopeRoots.append(scopeRootKey)
            }
            return
        }

        // Create and persist security-scoped bookmark for non-home paths.
        do {
            let bookmark = try standardized.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            RCBScopeRootBookmarkStore.setBookmark(bookmark, forScopeRoot: scopeRootKey)

            if !settings.scopeRoots.contains(scopeRootKey) {
                settings.scopeRoots.append(scopeRootKey)
            }
        } catch {
            scopeRootsError = String(format: RCLocalizedString("保存目录授权失败：%@"), error.localizedDescription)
        }
    }

    // MARK: - Reload Finder Extension

    private func reloadFinderExtensionAction() {
        let extId = "com.karry.RightClickBuddy.FinderSync"

        func run(_ executable: String, _ args: [String]) throws {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = args

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                throw NSError(domain: "RightClickBuddy", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
            }
        }

        do {
            try run("/usr/bin/pluginkit", ["-e", "ignore", "-i", extId])
            try run("/usr/bin/pluginkit", ["-e", "use", "-i", extId])
            try run("/usr/bin/killall", ["Finder"])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Reload Failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }
}

// MARK: - Template Editor Sheet

struct TemplateEditView: View {
    @Binding var spec: RCBSettings.TemplateSpec
    let isNew: Bool
    let onSave: (RCBSettings.TemplateSpec) -> Void
    let onCancel: () -> Void

    @State private var displayCategory: String = ""

    init(spec: Binding<RCBSettings.TemplateSpec>, isNew: Bool, onSave: @escaping (RCBSettings.TemplateSpec) -> Void, onCancel: @escaping () -> Void) {
        self._spec = spec
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        self._displayCategory = State(initialValue: RCLocalizedString(spec.wrappedValue.category))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isNew ? RCLocalizedString("添加模板") : RCLocalizedString("编辑模板"))
                .font(.headline)

            Form {
                TextField(RCLocalizedString("标题"), text: $spec.title, prompt: Text(RCLocalizedString("显示名称")))
                TextField(RCLocalizedString("文件名"), text: $spec.fileName, prompt: Text("README.md"))
                TextField(RCLocalizedString("分类"), text: $displayCategory, prompt: Text("DevOps"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(RCLocalizedString("模板内容"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $spec.contents)
                        .font(.body.monospaced())
                        .frame(minHeight: 200, maxHeight: 300)
                        .scrollContentBackground(.visible)
                        .border(Color(.gridColor))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(RCLocalizedString("取消"), action: onCancel)
                    .keyboardShortcut(.escape)

                Spacer()

                Button(RCLocalizedString("保存")) {
                    if let originalKey = LanguageManager.originalKey(for: displayCategory) {
                        spec.category = originalKey
                    } else {
                        spec.category = displayCategory
                    }
                    onSave(spec)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(spec.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .frame(width: 520, height: 480)
    }
}
