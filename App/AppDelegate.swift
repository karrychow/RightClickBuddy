import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    private let firstLaunchKey = "RightClickBuddy.hasRunOnce"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only app
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        enableLaunchAtLoginIfNeededOnFirstLaunch()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "RightClickBuddy")
        }

        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "设置 / Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let extensionsItem = NSMenuItem(title: "启用 Finder 扩展 / Enable Finder Extension…", action: #selector(openExtensionsSettings), keyEquivalent: "")
        extensionsItem.target = self
        menu.addItem(extensionsItem)

        #if DEBUG
        let reloadItem = NSMenuItem(title: "重载 Finder 扩展 / Reload Finder Extension", action: #selector(reloadFinderExtension), keyEquivalent: "")
        reloadItem.target = self
        menu.addItem(reloadItem)
        #endif

        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(title: "开机启动 / Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let hiddenItem = NSMenuItem(title: "显示隐藏文件 / Show Hidden Files", action: #selector(toggleShowHiddenFiles), keyEquivalent: "")
        hiddenItem.target = self
        hiddenItem.state = isShowingHiddenFiles ? .on : .off
        menu.addItem(hiddenItem)

        menu.addItem(NSMenuItem.separator())

        let uninstallItem = NSMenuItem(title: "卸载 / Uninstall…", action: #selector(showUninstallHelp), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 / Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func refreshMenuState() {
        guard let items = statusItem.menu?.items else { return }
        for item in items {
            if item.action == #selector(toggleLaunchAtLogin) {
                item.state = LaunchAtLoginManager.isEnabled ? .on : .off
            }
            if item.action == #selector(toggleShowHiddenFiles) {
                item.state = isShowingHiddenFiles ? .on : .off
            }
        }
    }

    private func enableLaunchAtLoginIfNeededOnFirstLaunch() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: firstLaunchKey) == false {
            defaults.set(true, forKey: firstLaunchKey)
            defaults.synchronize()

            // Default ON as requested
            if !LaunchAtLoginManager.isEnabled {
                LaunchAtLoginManager.setEnabled(true)
            }
            refreshMenuState()
        }
    }

    @objc private func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "设置 / Settings"
        window.setContentSize(NSSize(width: 640, height: 640))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()

        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openExtensionsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private var isShowingHiddenFiles: Bool {
        (UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles")) ?? false
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.setEnabled(!LaunchAtLoginManager.isEnabled)
        refreshMenuState()
    }

    @objc private func toggleShowHiddenFiles() {
        let newValue = !isShowingHiddenFiles
        let defaults = UserDefaults(suiteName: "com.apple.finder")
        defaults?.set(newValue, forKey: "AppleShowAllFiles")
        defaults?.synchronize()

        do {
            try restartFinder()
        } catch {
            let alert = NSAlert()
            alert.messageText = "操作失败 / Failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好 / OK")
            _ = alert.runModal()
        }

        refreshMenuState()
    }

    private func restartFinder() throws {
        // Use osascript to gracefully quit Finder (preserves window state).
        try runOSA("tell application \"Finder\" to quit")
        Thread.sleep(forTimeInterval: 0.5)
        try runOSA("tell application \"Finder\" to activate")
    }

    private func runOSA(_ script: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            throw NSError(domain: "RightClickBuddy", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "osascript failed" : output])
        }
    }

    #if DEBUG
    @objc private func reloadFinderExtension() {
        do {
            try reloadFinderSyncExtension()
        } catch {
            let alert = NSAlert()
            alert.messageText = "重载失败 / Reload failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好 / OK")
            _ = alert.runModal()
        }
    }

    private func reloadFinderSyncExtension() throws {
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
                throw NSError(domain: "RightClickBuddy", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Command failed: \(executable) \(args.joined(separator: " "))" : output])
            }
        }

        // Mimic MacNewFile: ignore -> use, then restart Finder.
        try run("/usr/bin/pluginkit", ["-e", "ignore", "-i", extId])
        try run("/usr/bin/pluginkit", ["-e", "use", "-i", extId])
        try run("/usr/bin/killall", ["Finder"])
    }
    #endif

    @objc private func showUninstallHelp() {
        let alert = NSAlert()
        alert.messageText = "卸载 / Uninstall"
        alert.informativeText = "1) 退出应用 / Quit the app\n2) 运行卸载包 RightClickBuddy-Uninstall.pkg（如果你已生成）\n   或者删除 /Applications/RightClickBuddy.app\n\nFinder 扩展可在系统设置中关闭。"
        alert.addButton(withTitle: "打开 Applications / Open Applications")
        alert.addButton(withTitle: "好 / OK")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
