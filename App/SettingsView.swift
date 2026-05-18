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

    var body: some View {
        TabView {
            menuTab
                .tabItem { Label(RCLocalizedString("菜单"), systemImage: "list.bullet") }

            templatesTab
                .tabItem { Label(RCLocalizedString("模板"), systemImage: "doc.badge.plus") }

            openWithTab
                .tabItem { Label(RCLocalizedString("打开方式"), systemImage: "arrow.up.forward.app") }

            tipsTab
                .tabItem { Label(RCLocalizedString("提示"), systemImage: "info.circle") }
        }
        .padding(16)
        .frame(width: 740, height: 640)
        .onChange(of: settings) { _ in
            saveSettings()
        }
    }

    // MARK: - Menu Tab

    private var menuTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    languageCard
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
                ToggleRow(icon: "plus.square", label: RCLocalizedString("显示 New"), isOn: bindingForShowNew())
                ToggleRow(icon: "doc.text", label: RCLocalizedString("显示 Templates"), isOn: bindingForShowTemplates())
                ToggleRow(icon: "doc.fill", label: RCLocalizedString("显示 Office"), isOn: bindingForShowOffice())
                ToggleRow(icon: "arrow.up.forward.app", label: RCLocalizedString("显示 Open With"), isOn: bindingForShowOpenWith())
            }
        }
    }

    private var scopeCard: some View {
        SectionCard {
            SectionHeader(icon: "folder", title: RCLocalizedString("生效目录"))

            if settings.scopeRoots.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tertiary)
                    Text(RCLocalizedString("默认范围：Home + 常用用户目录。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    templateList
                }
            }

            settingsFooter
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
                if !trimmed.isEmpty, trimmed != categoryToRename {
                    settings.renameCategory(from: categoryToRename, to: trimmed)
                }
            }
        } message: {
            Text(String(format: RCLocalizedString("将「%@」重命名为："), categoryToRename))
        }
        .alert(RCLocalizedString("删除分类"), isPresented: $showDeleteCategoryConfirm) {
            Button(RCLocalizedString("取消"), role: .cancel) { }
            Button(RCLocalizedString("删除"), role: .destructive) {
                settings.removeAllCustomTemplates(inCategory: categoryToDelete)
            }
        } message: {
            Text(String(format: RCLocalizedString("确定删除分类「%@」及其所有自定义模板？此操作不可撤销。"), categoryToDelete))
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    openWithToggles
                }
            }

            settingsFooter
        }
    }


    // MARK: - Tips Tab

    private var tipsTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    SectionCard {
                        SectionHeader(icon: "app.gift", title: "RightClickBuddy")

                        HStack(spacing: 10) {
                            Image(systemName: "hand.point.right")
                                .font(.body)
                                .foregroundStyle(.tint)
                                .frame(width: 20)
                            Text(RCLocalizedString("Finder 右键增强"))
                                .font(.body)
                        }
                    }

                    SectionCard {
                        SectionHeader(icon: "lightbulb", title: RCLocalizedString("提示"))

                        VStack(alignment: .leading, spacing: 12) {
                            TipRow(icon: "arrow.triangle.2.circlepath",
                                   text: RCLocalizedString("修改设置后，重新打开 Finder 右键菜单即可生效。"))
                            TipRow(icon: "terminal",
                                   text: RCLocalizedString("若 Finder 未刷新，可在主 App 菜单里 Reload Finder Extension（Debug）或运行 scripts/dev-reload-findersync.sh。"))
                            TipRow(icon: "gearshape.2",
                                   text: RCLocalizedString("Finder 扩展启用位置：系统设置 → 通用 → 登录项与扩展 → 扩展。"))
                        }
                    }

                    SectionCard {
                        SectionHeader(icon: "arrow.counterclockwise", title: RCLocalizedString("恢复默认设置"))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(RCLocalizedString("遇到异常行为时，可尝试恢复所有设置为默认值。此操作不可撤销。"))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button(RCLocalizedString("恢复默认"), role: .destructive) {
                                settings = RCBSettings.defaultSettings
                                saveSettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            settingsFooter
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
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
        if expandedCategories.isEmpty {
            expandedCategories = Set(allSpecs.map(\.category))
        }
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
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(RCLocalizedString(category))
                        .font(.body)
                        .fontWeight(.medium)
                    Spacer()
                    Menu {
                        Button(RCLocalizedString("重命名分类")) {
                            categoryToRename = category
                            newCategoryName = category
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
            DisclosureGroup {
                VStack(spacing: 2) {
                    ForEach(specs) { spec in
                        let installed = spec.bundleIdCandidates.contains { bundleId in
                            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "app")
                                .font(.body)
                                .foregroundStyle(installed ? .secondary : .tertiary)
                                .frame(width: 20)
                            Text(spec.title + (installed ? "" : RCLocalizedString(" (未安装)")))
                                .font(.body)
                                .foregroundStyle(installed ? .primary : .tertiary)
                            Spacer()
                            Toggle("", isOn: bindingForOpenWith(id: spec.id))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .disabled(!installed)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.windowBackgroundColor))
                        )
                        .opacity(installed ? 1 : 0.6)
                    }
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text(RCLocalizedString(category))
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 20)
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

        // Create and persist security-scoped bookmark (in App Group UserDefaults).
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
}

// MARK: - Template Editor Sheet

struct TemplateEditView: View {
    @Binding var spec: RCBSettings.TemplateSpec
    let isNew: Bool
    let onSave: (RCBSettings.TemplateSpec) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(isNew ? RCLocalizedString("添加模板") : RCLocalizedString("编辑模板"))
                .font(.headline)

            Form {
                TextField(RCLocalizedString("标题（显示名称）"), text: $spec.title)
                TextField(RCLocalizedString("文件名"), text: $spec.fileName)
                TextField(RCLocalizedString("分类"), text: $spec.category)

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
