import Foundation

// MARK: - IPC channel configuration

/// Configuration for the localhost TCP channel between the main app (server) and the
/// sandboxed FinderSync extension (client).
///
/// We use a FIXED port instead of an OS-assigned ephemeral port published via the App Group
/// container. The sandboxed extension only needs the `network.client` entitlement to connect,
/// so IPC keeps working even if the shared container is unavailable (e.g. locked to a previous
/// code-signing identity after re-signing).
enum RCBIPC {
    /// Fixed loopback port. Chosen in the IANA dynamic range and unlikely to collide.
    static let port: UInt16 = 52847
}

// MARK: - IPC Protocol for TCP socket between extension and main app

/// Request from extension to main app.
struct IPCRequest: Codable {
    let id: String  // UUID
    let type: String  // "createFile", "createDirectory", "copyItem", "openWithApps"
    let directoryPath: String
    let fileName: String
    let fileContents: Data?  // for createFile
    let fileMode: UInt16?  // for createFile
    let sourcePath: String?  // for copyItem
    let appPath: String?  // for openWithApps
    let filePaths: [String]?  // for openWithApps
}

/// Response from main app to extension.
struct IPCResponse: Codable {
    let id: String  // matches request
    let success: Bool
    let path: String?
    let error: String?
}
