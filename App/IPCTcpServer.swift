import Foundation
import Network
import os

// MARK: - TCP Server (runs in main app, not sandboxed)

/// Listens on localhost TCP for requests from the FinderSync extension
/// and performs file operations on behalf of the sandboxed extension.
final class IPCTcpServer {
    private let logger = Logger(subsystem: "com.karry.RightClickBuddy", category: "IPCTcpServer")
    private var listener: NWListener?
    private var port: UInt16 = 0

    func start() {
        do {
            // Bind a fixed loopback port so the sandboxed extension can connect without
            // needing the App Group container to publish an ephemeral port.
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: RCBIPC.port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = self.listener?.port {
                        self.port = port.rawValue
                        self.writePortFile()
                        self.logger.info("TCP server ready on port \(port.rawValue)")
                        AppLogger.app.info("IPC TCP server ready on port \(port.rawValue)")
                    }
                case .failed(let error):
                    self.logger.error("Listener failed: \(error.localizedDescription)")
                    AppLogger.app.error("IPC TCP listener failed: \(error.localizedDescription)")
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .global())
        } catch {
            logger.error("Failed to start TCP listener: \(error.localizedDescription)")
            AppLogger.app.error("IPC TCP server start failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Port File

    private func writePortFile() {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.karry.RightClickBuddy")
        else {
            AppLogger.app.error("IPC TCP: containerURL is nil")
            return
        }
        let portURL = container.appendingPathComponent("tcp_port", isDirectory: false)
        do {
            try "\(port)".write(to: portURL, atomically: true, encoding: .utf8)
            AppLogger.app.info("IPC TCP: wrote port \(port) to \(portURL.path)")
        } catch {
            AppLogger.app.error("IPC TCP: failed to write port: \(error.localizedDescription)")
        }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                self?.receiveRequest(on: connection)
            }
        }
        connection.start(queue: .global())
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.logger.error("Receive error: \(error.localizedDescription)")
                return
            }
            guard let data, !data.isEmpty else {
                if isComplete { return }
                self.receiveRequest(on: connection)
                return
            }

            do {
                let request = try JSONDecoder().decode(IPCRequest.self, from: data)
                AppLogger.app.info("IPC TCP: request id=\(request.id) type=\(request.type)")

                let response = self.processRequest(request)

                let responseData = try JSONEncoder().encode(response)
                connection.send(content: responseData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } catch {
                self.logger.error("Failed to decode request: \(error.localizedDescription)")
                AppLogger.app.error("IPC TCP: decode error: \(error.localizedDescription)")
                connection.cancel()
            }
        }
    }

    private func processRequest(_ request: IPCRequest) -> IPCResponse {
        switch request.type {
        case "createFile":
            return handleCreateFile(request)
        case "createDirectory":
            return handleCreateDirectory(request)
        case "copyItem":
            return handleCopyItem(request)
        case "openWithApps":
            return handleOpenWithApps(request)
        default:
            return IPCResponse(id: request.id, success: false, path: nil, error: "Unknown request type: \(request.type)")
        }
    }

    private func handleCreateFile(_ request: IPCRequest) -> IPCResponse {
        let fm = FileManager.default
        guard fm.fileExists(atPath: request.directoryPath) else {
            return IPCResponse(id: request.id, success: false, path: nil, error: "Directory does not exist")
        }

        let fileURL = URL(fileURLWithPath: request.directoryPath).appendingPathComponent(request.fileName)
        var destURL = fileURL

        // Deduplicate
        if fm.fileExists(atPath: destURL.path) {
            let ext = destURL.pathExtension
            let base = destURL.deletingPathExtension().lastPathComponent
            var counter = 1
            repeat {
                destURL = URL(fileURLWithPath: request.directoryPath).appendingPathComponent("\(base) \(counter).\(ext)")
                counter += 1
            } while fm.fileExists(atPath: destURL.path)
        }

        do {
            try (request.fileContents ?? Data()).write(to: destURL, options: .atomic)
            if let mode = request.fileMode, mode != 0o644 {
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: destURL.path)
            }
            AppLogger.app.info("IPC TCP: created file \(destURL.path)")
            return IPCResponse(id: request.id, success: true, path: destURL.path, error: nil)
        } catch {
            AppLogger.app.error("IPC TCP: createFile failed: \(error.localizedDescription)")
            return IPCResponse(id: request.id, success: false, path: nil, error: error.localizedDescription)
        }
    }

    private func handleCreateDirectory(_ request: IPCRequest) -> IPCResponse {
        let destURL = URL(fileURLWithPath: request.directoryPath).appendingPathComponent(request.fileName)
        do {
            try FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: false)
            AppLogger.app.info("IPC TCP: created directory \(destURL.path)")
            return IPCResponse(id: request.id, success: true, path: destURL.path, error: nil)
        } catch {
            AppLogger.app.error("IPC TCP: createDirectory failed: \(error.localizedDescription)")
            return IPCResponse(id: request.id, success: false, path: nil, error: error.localizedDescription)
        }
    }

    private func handleCopyItem(_ request: IPCRequest) -> IPCResponse {
        let destURL = URL(fileURLWithPath: request.directoryPath).appendingPathComponent(request.fileName)
        guard let sourcePath = request.sourcePath else {
            return IPCResponse(id: request.id, success: false, path: nil, error: "Missing sourcePath")
        }
        do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: destURL)
            AppLogger.app.info("IPC TCP: copied \(sourcePath) to \(destURL.path)")
            return IPCResponse(id: request.id, success: true, path: destURL.path, error: nil)
        } catch {
            AppLogger.app.error("IPC TCP: copyItem failed: \(error.localizedDescription)")
            return IPCResponse(id: request.id, success: false, path: nil, error: error.localizedDescription)
        }
    }

    private func handleOpenWithApps(_ request: IPCRequest) -> IPCResponse {
        guard let appPath = request.appPath else {
            return IPCResponse(id: request.id, success: false, path: nil, error: "Missing appPath")
        }
        guard let filePaths = request.filePaths, !filePaths.isEmpty else {
            return IPCResponse(id: request.id, success: false, path: nil, error: "No file paths provided")
        }

        AppLogger.app.info("IPC TCP: openWithApps app=\(appPath) files=\(filePaths.count)")

        // Use /usr/bin/open -a to avoid macOS Automation permission prompt
        var args = ["-a", appPath]
        args.append(contentsOf: filePaths)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = args

        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return IPCResponse(id: request.id, success: true, path: nil, error: nil)
            }
            AppLogger.app.error("IPC TCP: open -a exited with status \(task.terminationStatus)")
            return IPCResponse(id: request.id, success: false, path: nil, error: "open command failed")
        } catch {
            AppLogger.app.error("IPC TCP: openWithApps failed: \(error.localizedDescription)")
            return IPCResponse(id: request.id, success: false, path: nil, error: error.localizedDescription)
        }
    }
}
