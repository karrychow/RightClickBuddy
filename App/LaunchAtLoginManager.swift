import Foundation
import ServiceManagement
import os

enum LaunchAtLoginManager {
    private static var logger: Logger {
        Logger(subsystem: "com.karry.RightClickBuddy", category: "LaunchAtLoginManager")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("LaunchAtLoginManager error: \(error.localizedDescription, privacy: .public)")
        }
    }
}
