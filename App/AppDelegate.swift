import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let ipcServer = IPCTcpServer()

    private let firstLaunchKey = "RightClickBuddy.hasRunOnce"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppLogger.setupCrashHandling()
        AppLogger.app.info("Application did finish launching")

        // Start XPC server for extension file creation requests.
        ipcServer.start()
        AppLogger.app.info("IPC server started")

        let settings = RCBSettings.load()
        if settings.menu.showMenuBarIcon {
            setupStatusItem()
        }
        enableLaunchAtLoginIfNeededOnFirstLaunch()

        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange), name: .RCBLanguageDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuBarIconDidChange), name: .RCBMenuBarIconDidChange, object: nil)
    }

    @objc private func languageDidChange() {
        AppLogger.settings.info("Language changed, rebuilding menu")
        refreshMenuLanguage()
    }

    private func refreshMenuLanguage() {
        if statusItem != nil {
            statusItem.menu = buildMenu()
        }
        settingsWindow?.contentView = NSHostingView(rootView: SettingsView())
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: RCLocalizedString("RightClickBuddy"))
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: RCLocalizedString("设置"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: RCLocalizedString("开机启动"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let hiddenItem = NSMenuItem(title: RCLocalizedString("显示隐藏文件"), action: #selector(toggleShowHiddenFiles), keyEquivalent: "")
        hiddenItem.target = self
        hiddenItem.state = isShowingHiddenFiles ? .on : .off
        menu.addItem(hiddenItem)

        let showIcon = RCBSettings.load().menu.showMenuBarIcon
        let iconItem = NSMenuItem(title: showIcon ? RCLocalizedString("隐藏菜单栏图标") : RCLocalizedString("显示菜单栏图标"), action: #selector(toggleMenuBarIcon), keyEquivalent: "")
        iconItem.target = self
        menu.addItem(iconItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: RCLocalizedString("退出"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func refreshMenuState() {
        // statusItem is nil while the menu-bar icon is hidden — bail out safely
        // (avoids a force-unwrap crash when toggling the icon off).
        guard let items = statusItem?.menu?.items else { return }
        for item in items {
            if item.action == #selector(toggleLaunchAtLogin) {
                item.state = LaunchAtLoginManager.isEnabled ? .on : .off
            }
            if item.action == #selector(toggleShowHiddenFiles) {
                item.state = isShowingHiddenFiles ? .on : .off
            }
            if item.action == #selector(toggleMenuBarIcon) {
                let showIcon = RCBSettings.load().menu.showMenuBarIcon
                item.title = showIcon ? RCLocalizedString("隐藏菜单栏图标") : RCLocalizedString("显示菜单栏图标")
            }
        }
    }

    private func enableLaunchAtLoginIfNeededOnFirstLaunch() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: firstLaunchKey) == false {
            defaults.set(true, forKey: firstLaunchKey)
            defaults.synchronize()

            if !LaunchAtLoginManager.isEnabled {
                LaunchAtLoginManager.setEnabled(true)
            }
            refreshMenuState()
        }
    }

    @objc private func openSettings() {
        AppLogger.app.info("Open settings window")

        if let settingsWindow {
            // Rebuild SwiftUI content — same approach as refreshMenuLanguage(),
            // which reliably resolves incorrect rendering on first open.
            settingsWindow.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow()
        window.title = RCLocalizedString("设置")
        window.setContentSize(NSSize(width: 740, height: 640))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openExtensionsSettings() {
        AppLogger.app.info("Open extension settings")
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private var isShowingHiddenFiles: Bool {
        (UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles")) ?? false
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !LaunchAtLoginManager.isEnabled
        AppLogger.app.info("Toggle launch at login: \(newValue)")
        LaunchAtLoginManager.setEnabled(newValue)
        refreshMenuState()
    }

    @objc private func toggleMenuBarIcon() {
        var settings = RCBSettings.load()
        settings.menu.showMenuBarIcon.toggle()
        try? RCBSettings.save(settings)
        AppLogger.app.info("Toggle menu bar icon: \(settings.menu.showMenuBarIcon)")
        refreshStatusItemVisibility()
        refreshMenuState()
    }

    @objc private func menuBarIconDidChange() {
        refreshStatusItemVisibility()
    }

    private func refreshStatusItemVisibility() {
        let showIcon = RCBSettings.load().menu.showMenuBarIcon
        if showIcon, statusItem == nil {
            NSApp.setActivationPolicy(.accessory)
            setupStatusItem()
            AppLogger.app.info("Menu bar icon shown")
        } else if !showIcon, statusItem != nil {
            statusItem = nil
            NSApp.setActivationPolicy(.regular)
            AppLogger.app.info("Menu bar icon hidden, app now in Dock")
        }
    }

    // When in Dock mode (icon hidden), clicking the Dock icon opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    @objc private func toggleShowHiddenFiles() {
        let newValue = !isShowingHiddenFiles
        AppLogger.app.info("Toggle show hidden files: \(newValue)")
        let defaults = UserDefaults(suiteName: "com.apple.finder")
        defaults?.set(newValue, forKey: "AppleShowAllFiles")
        defaults?.synchronize()

        do {
            try restartFinder()
        } catch {
            AppLogger.app.error("Toggle hidden files failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = RCLocalizedString("操作失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: RCLocalizedString("好"))
            _ = alert.runModal()
        }

        refreshMenuState()
    }

    private func restartFinder() throws {
        AppLogger.app.info("Restarting Finder")
        try runProcess("/usr/bin/killall", ["Finder"])
    }

    private func runProcess(_ executable: String, _ args: [String]) throws {
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
            throw NSError(domain: "RightClickBuddy", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? String(format: RCLocalizedString("Command failed: %@ %@"), executable, args.joined(separator: " ")) : output])
        }
    }

    @objc func reloadFinderExtension() {
        AppLogger.app.info("Reload Finder extension")
        do {
            try reloadFinderSyncExtension()
        } catch {
            AppLogger.app.error("Reload extension failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = RCLocalizedString("重载失败")
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: RCLocalizedString("好"))
            _ = alert.runModal()
        }
    }

    private func reloadFinderSyncExtension() throws {
        let extId = "com.karry.RightClickBuddy.FinderSync"
        try runProcess("/usr/bin/pluginkit", ["-e", "ignore", "-i", extId])
        try runProcess("/usr/bin/pluginkit", ["-e", "use", "-i", extId])
        try runProcess("/usr/bin/killall", ["Finder"])
    }

    @objc private func showUninstallHelp() {
        AppLogger.app.info("Show uninstall help")
        let alert = NSAlert()
        alert.messageText = RCLocalizedString("卸载")
        alert.informativeText = RCLocalizedString("1) 退出应用\n2) 运行卸载包 RightClickBuddy-Uninstall.pkg（如果你已生成）\n   或者删除 /Applications/RightClickBuddy.app\n\nFinder 扩展可在系统设置中关闭。")
        alert.addButton(withTitle: RCLocalizedString("打开 Applications"))
        alert.addButton(withTitle: RCLocalizedString("好"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
    }

    @objc private func quitApp() {
        AppLogger.app.info("Quit app")
        NSApplication.shared.terminate(nil)
    }
}
