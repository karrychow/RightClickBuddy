import Foundation
import OSLog

/// Synchronous file logger using POSIX syscalls (most reliable in sandboxed extensions).
struct ExtensionLogger {
    let category: String

    init(category: String) {
        self.category = category
    }

    func info(_ message: @autoclosure () -> String) { write(level: "INFO", message: message()) }
    func debug(_ message: @autoclosure () -> String) { write(level: "DEBUG", message: message()) }
    func error(_ message: @autoclosure () -> String) { write(level: "ERROR", message: message()) }
    func fault(_ message: @autoclosure () -> String) { write(level: "FAULT", message: message()) }

    // MARK: - POSIX File I/O

    /// Use getenv instead of NSHomeDirectory() to avoid any Foundation shenanigans.
    /// In extension sandbox: ~/Library/Containers/com.karry.RightClickBuddy.FinderSync/Data/
    private static var logPath: String = {
        let home = NSHomeDirectory()
        let dir = home + "/Library/Application Support/RightClickBuddy"
        // POSIX mkdir is simpler and more reliable than FileManager
        _ = Darwin.mkdir((dir as NSString).fileSystemRepresentation, 0o755)
        return dir + "/findersync.log"
    }()

    private func write(level: String, message: String) {
        // OSLog for Console.app
        let osLogger = Logger(subsystem: "com.karry.RightClickBuddy", category: category)
        switch level {
        case "ERROR": osLogger.error("\(message, privacy: .public)")
        case "FAULT": osLogger.fault("\(message, privacy: .public)")
        case "DEBUG": osLogger.debug("\(message, privacy: .public)")
        default:      osLogger.info("\(message, privacy: .public)")
        }

        // POSIX write — survives crashes, async-signal-safe
        let line = "\(Self.timestamp()) | \(Self.leftPad(level, width: 5)) | \(Self.leftPad(category, width: 9)) | \(message)\n"
        guard let data = line.data(using: String.Encoding.utf8) else { return }
        let fd = Darwin.open(Self.logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd >= 0 {
            data.withUnsafeBytes { buf in
                _ = Darwin.write(fd, buf.baseAddress, buf.count)
            }
            Darwin.close(fd)
        }
    }

    // MARK: - Helpers

    private static func timestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df.string(from: Date())
    }

    private static func leftPad(_ s: String, width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}
