import Foundation
import OSLog

// MARK: - Category Logger

struct CategoryLogger {
    let category: String

    private var logger: Logger {
        Logger(subsystem: "com.karry.RightClickBuddy", category: category)
    }

    func info(_ message: @autoclosure () -> String) {
        let m = message()
        logger.info("\(m, privacy: .public)")
        AppLogger.enqueueWrite(level: "INFO", category: category, message: m)
    }

    func debug(_ message: @autoclosure () -> String) {
        let m = message()
        logger.debug("\(m, privacy: .public)")
        AppLogger.enqueueWrite(level: "DEBUG", category: category, message: m)
    }

    func error(_ message: @autoclosure () -> String) {
        let m = message()
        logger.error("\(m, privacy: .public)")
        AppLogger.enqueueWrite(level: "ERROR", category: category, message: m)
    }

    func fault(_ message: @autoclosure () -> String) {
        let m = message()
        logger.fault("\(m, privacy: .public)")
        AppLogger.enqueueWrite(level: "FAULT", category: category, message: m)
    }
}

// MARK: - AppLogger

enum AppLogger {
    fileprivate static let fileQueue = DispatchQueue(label: "com.karry.RightClickBuddy.logfile", qos: .utility)

    static let app       = CategoryLogger(category: "App")
    static let settings  = CategoryLogger(category: "Settings")
    static let files     = CategoryLogger(category: "Files")
    static let menu      = CategoryLogger(category: "Menu")
    static let crash     = CategoryLogger(category: "Crash")
    static let lifecycle = CategoryLogger(category: "Lifecycle")
}

// MARK: - File Logging

extension AppLogger {
    private static var logsDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RightClickBuddy/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var crashReportsDir: URL = {
        let dir = logsDir.appendingPathComponent("crash_reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let logFileURL: URL = logsDir.appendingPathComponent("app.log")

    static let maxLogSize: UInt64 = 512 * 1024
    static let maxArchivedLogs = 3

    fileprivate static func enqueueWrite(level: String, category: String, message: String) {
        fileQueue.async {
            doAppend(level: level, category: category, message: message)
        }
    }

    private static func doAppend(level: String, category: String, message: String) {
        let ts = timestamp()
        let line = "\(ts) | \(leftPad(level, width: 5)) | \(leftPad(category, width: 9)) | \(message)\n"

        // Rotate if current log exceeds size limit
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let size = attrs[.size] as? UInt64, size >= maxLogSize {
            rotateLogs()
        }

        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            try? handle.seekToEnd()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    private static func timestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df.string(from: Date())
    }

    private static func rotateLogs() {
        // Remove oldest archive
        try? FileManager.default.removeItem(
            at: logsDir.appendingPathComponent("app.\(maxArchivedLogs).log"))
        // Shift
        for i in (1 ..< maxArchivedLogs).reversed() {
            let src = logsDir.appendingPathComponent("app.\(i).log")
            let dst = logsDir.appendingPathComponent("app.\(i + 1).log")
            try? FileManager.default.moveItem(at: src, to: dst)
        }
        // Archive current log
        try? FileManager.default.moveItem(
            at: logFileURL, to: logsDir.appendingPathComponent("app.1.log"))
    }

    private static func leftPad(_ s: String, width: Int) -> String {
        s.count >= width ? s : String(repeating: " ", count: width - s.count) + s
    }
}

// MARK: - Log Reading

extension AppLogger {
    static func readRecentLogs(limit: Int = 200) -> [String] {
        guard let data = try? Data(contentsOf: logFileURL),
              let content = String(data: data, encoding: .utf8)
        else { return [] }
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        // Prepend archive content if current log has fewer lines than limit
        if lines.count < limit {
            let needed = limit - lines.count
            let archived = readArchivedSuffix(limit: needed)
            return archived + lines
        }
        return Array(lines.suffix(limit))
    }

    private static func readArchivedSuffix(limit: Int) -> [String] {
        var result: [String] = []
        for i in (1 ... maxArchivedLogs).reversed() {
            guard result.count < limit else { break }
            let url = logsDir.appendingPathComponent("app.\(i).log")
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8)
            else { continue }
            let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
            result = Array(lines.suffix(limit - result.count)) + result
        }
        return result
    }

    static func logsDirectoryURL() -> URL { logsDir }

    static func exportAllLogs() -> String {
        var all: [String] = []
        for i in (1 ... maxArchivedLogs).reversed() {
            let url = logsDir.appendingPathComponent("app.\(i).log")
            if let data = try? Data(contentsOf: url),
               let content = String(data: data, encoding: .utf8) {
                all.append(contentsOf: content.components(separatedBy: .newlines).filter { !$0.isEmpty })
            }
        }
        if let data = try? Data(contentsOf: logFileURL),
           let content = String(data: data, encoding: .utf8) {
            all.append(contentsOf: content.components(separatedBy: .newlines).filter { !$0.isEmpty })
        }
        return all.joined(separator: "\n")
    }
}

// MARK: - Crash Handling

extension AppLogger {
    /// Call once at app launch (from AppDelegate).
    static func setupCrashHandling() {
        checkAndLogPreviousCrash()

        NSSetUncaughtExceptionHandler { exception in
            let info = """
            CRASH: Uncaught Exception
            Time: \(Date())
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "nil")
            UserInfo: \(exception.userInfo ?? [:])
            Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """
            Self.writeSyncCrashReport(info)
        }

        let sigs: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        let crashDirPath = crashReportsDir.path
        for sig in sigs {
            signal(sig) { s in
                let ts = Date().timeIntervalSince1970
                let msg = "CRASH: Signal \(s) at \(ts)"
                Self.writeSyncCrashReport(msg)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    // MARK: - Pending Crash Report

    static func hasPendingCrashReport() -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: crashReportsDir, includingPropertiesForKeys: nil)) ?? []
        return !contents.isEmpty
    }

    /// Returns the most recent crash report text, if any.
    static func pendingCrashReport() -> String? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: crashReportsDir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        guard let newest = contents.sorted(by: { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }).first, let data = try? Data(contentsOf: newest),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    static func clearCrashReports() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: crashReportsDir, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Private

    private static func checkAndLogPreviousCrash() {
        if let report = pendingCrashReport() {
            let lines = report.components(separatedBy: .newlines)
            for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                AppLogger.crash.error("Previous session: \(line)")
            }
            clearCrashReports()
        }
    }

    /// Writes a crash report synchronously. May be called from signal handlers.
    fileprivate static func writeSyncCrashReport(_ text: String) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        let name = "crash_\(df.string(from: Date())).crash"
        let url = crashReportsDir.appendingPathComponent(name)
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    }
}
