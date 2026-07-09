import Foundation
import Network
import os
#if canImport(AppKit)
import AppKit
#endif

// MARK: - TCP Client (runs in FinderSync extension)

/// Connects to the main app via localhost TCP to perform file operations.
/// Each method creates a fresh connection, sends a request, waits for reply, and disconnects.
enum IPCTcpClient {
    private static let logger = Logger(subsystem: "com.karry.RightClickBuddy", category: "IPCTcpClient")
    private static let callTimeout: TimeInterval = 5.0

    // MARK: - Error

    enum IPCError: LocalizedError {
        case serverNotRunning
        case timeout
        case operationFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .serverNotRunning:
                return "Main app is not running. Please launch RightClickBuddy first."
            case .timeout:
                return "Operation timed out. Please try again."
            case .operationFailed(let detail):
                return detail
            case .invalidResponse:
                return "Received an invalid response from the main app."
            }
        }
    }

    // MARK: - Public API

    /// Create a file at the given directory with contents.
    /// - Returns: The path of the created file (deduplicated by server).
    static func createFile(directoryPath: String, fileName: String, contents: Data, fileMode: UInt16) throws -> String {
        let request = IPCRequest(
            id: UUID().uuidString,
            type: "createFile",
            directoryPath: directoryPath,
            fileName: fileName,
            fileContents: contents,
            fileMode: fileMode,
            sourcePath: nil,
            appPath: nil,
            filePaths: nil
        )
        let response = try sendRequest(request)
        guard response.success, let path = response.path else {
            throw IPCError.operationFailed(response.error ?? "Unknown error")
        }
        return path
    }

    /// Create a directory.
    /// - Returns: The path of the created directory.
    static func createDirectory(directoryPath: String, fileName: String) throws -> String {
        let request = IPCRequest(
            id: UUID().uuidString,
            type: "createDirectory",
            directoryPath: directoryPath,
            fileName: fileName,
            fileContents: nil,
            fileMode: nil,
            sourcePath: nil,
            appPath: nil,
            filePaths: nil
        )
        let response = try sendRequest(request)
        guard response.success, let path = response.path else {
            throw IPCError.operationFailed(response.error ?? "Unknown error")
        }
        return path
    }

    /// Copy an item (file or directory bundle) from source to destination.
    /// - Returns: The path of the copied item.
    static func copyItem(sourcePath: String, directoryPath: String, fileName: String) throws -> String {
        let request = IPCRequest(
            id: UUID().uuidString,
            type: "copyItem",
            directoryPath: directoryPath,
            fileName: fileName,
            fileContents: nil,
            fileMode: nil,
            sourcePath: sourcePath,
            appPath: nil,
            filePaths: nil
        )
        let response = try sendRequest(request)
        guard response.success, let path = response.path else {
            throw IPCError.operationFailed(response.error ?? "Unknown error")
        }
        return path
    }

    /// Fetch the current settings JSON from the main app.
    /// Uses a single attempt (no auto-launch) so it stays fast on the menu-building path;
    /// callers fall back to their local cache if the app isn't reachable.
    static func getSettings() throws -> Data {
        let request = IPCRequest(
            id: UUID().uuidString,
            type: "getSettings",
            directoryPath: "",
            fileName: "",
            fileContents: nil,
            fileMode: nil,
            sourcePath: nil,
            appPath: nil,
            filePaths: nil
        )
        let response = try attemptSend(request)
        guard response.success, let payload = response.payload else {
            throw IPCError.operationFailed(response.error ?? "no settings payload")
        }
        return payload
    }

    /// Open files with the given app (delegated to non-sandboxed main app).
    static func openWithApps(appPath: String, filePaths: [String]) throws {
        let request = IPCRequest(
            id: UUID().uuidString,
            type: "openWithApps",
            directoryPath: "",
            fileName: "",
            fileContents: nil,
            fileMode: nil,
            sourcePath: nil,
            appPath: appPath,
            filePaths: filePaths
        )
        let response = try sendRequest(request)
        guard response.success else {
            throw IPCError.operationFailed(response.error ?? "Unknown error")
        }
    }

    // MARK: - Private

    /// Derive the host application bundle URL from this extension's bundle:
    ///   <MainApp>.app/Contents/PlugIns/<Extension>.appex  →  <MainApp>.app
    private static func mainAppURL() -> URL? {
        var url = Bundle.main.bundleURL
        for _ in 0..<3 { url = url.deletingLastPathComponent() }
        guard url.pathExtension == "app" else {
            logger.error("mainAppURL: could not derive host app from \(Bundle.main.bundleURL.path, privacy: .public)")
            return nil
        }
        return url
    }

    /// Launch the main app (a background/LSUIElement process) so its IPC server starts.
    /// Returns true if the launch was requested successfully, after giving the server a
    /// moment to bind the fixed port.
    private static func launchMainApp() -> Bool {
        #if canImport(AppKit)
        guard let appURL = mainAppURL() else { return false }

        let launchSem = DispatchSemaphore(value: 0)
        var launchOK = false
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            launchOK = (error == nil)
            if let error { logger.error("launch main app failed: \(error.localizedDescription, privacy: .public)") }
            launchSem.signal()
        }
        _ = launchSem.wait(timeout: .now() + 3.0)
        guard launchOK else { return false }

        // Give the server a moment to bind the fixed port before we retry.
        Thread.sleep(forTimeInterval: 1.0)
        logger.info("main app launched; retrying IPC")
        return true
        #else
        return false
        #endif
    }

    /// Send a request to the main app. If the IPC server can't be reached, launch the main app
    /// once and retry — so the extension keeps working even when the app was quit or not yet started.
    private static func sendRequest(_ request: IPCRequest) throws -> IPCResponse {
        do {
            return try attemptSend(request)
        } catch {
            logger.info("IPC unreachable (\(error.localizedDescription, privacy: .public)); launching main app and retrying once")
            guard launchMainApp() else { throw error }
            return try attemptSend(request)
        }
    }

    /// One attempt: connect to the fixed IPC port, send the request, and wait for the reply.
    private static func attemptSend(_ request: IPCRequest) throws -> IPCResponse {
        let port = RCBIPC.port

        let semaphore = DispatchSemaphore(value: 0)
        var response: IPCResponse?
        var connectionError: Error?

        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )

        connection.stateUpdateHandler = { state in
            if case .ready = state {
                // Connected. Send the request.
                do {
                    let data = try JSONEncoder().encode(request)
                    connection.send(content: data, completion: .contentProcessed({ error in
                        if let error {
                            connectionError = error
                            semaphore.signal()
                        }
                    }))
                } catch {
                    connectionError = error
                    semaphore.signal()
                }
            }
            if case .failed(let error) = state {
                connectionError = IPCError.serverNotRunning
                logger.error("Connection failed: \(error.localizedDescription)")
                semaphore.signal()
            }
            if case .waiting(let error) = state {
                // For a 127.0.0.1 endpoint, .waiting almost always means the server isn't
                // listening (ECONNREFUSED). Fail fast instead of stalling until callTimeout,
                // so sendRequest can launch the main app and retry promptly.
                logger.error("Connection waiting: \(error.localizedDescription)")
                connectionError = IPCError.serverNotRunning
                semaphore.signal()
            }
        }

        // Receive response
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { data, _, _, error in
            if let data, !data.isEmpty {
                do {
                    response = try JSONDecoder().decode(IPCResponse.self, from: data)
                } catch {
                    connectionError = error
                }
            } else if let error {
                connectionError = error
            }
            semaphore.signal()
        }

        connection.start(queue: .global())

        let waitResult = semaphore.wait(timeout: .now() + callTimeout)
        connection.cancel()

        if waitResult == .timedOut {
            logger.error("TCP request timed out")
            throw IPCError.timeout
        }

        if let connectionError {
            logger.error("TCP request error: \(connectionError.localizedDescription)")
            throw IPCError.serverNotRunning
        }

        guard let response else {
            throw IPCError.invalidResponse
        }

        return response
    }
}
