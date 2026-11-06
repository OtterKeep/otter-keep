import Foundation
import os

/// Message payload transmitted across Unix Domain Socket IPC between GUI instances and Finder extensions.
public struct SingleInstanceMessage: Codable, Sendable {
    /// Supported action types.
    public enum Action: String, Codable, Sendable {
        /// Activates the primary application window and brings it to the foreground.
        case activate
        /// Opens the point-in-time version history modal for the specified file path.
        case openVersionHistory
    }

    /// The target action.
    public let action: Action
    /// Optional absolute or relative file path associated with the action.
    public let filePath: String?

    /// Initializes a `SingleInstanceMessage`.
    /// - Parameters:
    ///   - action: Action to perform.
    ///   - filePath: Target file path.
    public init(action: Action, filePath: String? = nil) {
        self.action = action
        self.filePath = filePath
    }
}

/// Thread-safe manager responsible for single-instance GUI enforcement and Unix Domain Socket IPC.
///
/// This manager ensures that only one graphical instance of OtterKeepApp runs simultaneously,
/// while allowing headless command-line interface (`otterkeep` CLI) commands to run completely
/// unrestricted in parallel.
public final class SingleInstanceManager: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = SingleInstanceManager()

    private let logger = Logger(subsystem: "com.otterkeep.desktop", category: "SingleInstance")
    private let lock = NSLock()
    private var serverSocketFD: Int32 = -1
    private var isListening: Bool = false
    private var listeningThread: Thread?

    /// File path to the active Unix Domain Socket (`~/.otterkeep/gui.sock`).
    public var socketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".otterkeep/gui.sock").path(percentEncoded: false)
    }

    /// File path to the single-instance lock file (`~/.otterkeep/otterkeep_gui.lock`).
    public var lockFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".otterkeep/otterkeep_gui.lock").path(percentEncoded: false)
    }

    private init() {
        ensureDirectoryPermissions()
    }

    /// Enforces strict 0700 permissions on the base ~/.otterkeep/ directory to protect IPC sockets and lock files.
    public func ensureDirectoryPermissions() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".otterkeep", isDirectory: true)
        let dirPath = dir.path(percentEncoded: false)
        if !FileManager.default.fileExists(atPath: dirPath) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dirPath)
        chmod(dirPath, 0o700)
    }

    private func createOtterKeepDirectoryIfNeeded() {
        ensureDirectoryPermissions()
    }

    /// Attempts to connect to an existing running primary GUI instance and forward the launch parameters.
    ///
    /// - Parameter arguments: Command-line arguments from the launching process.
    /// - Returns: `true` if an existing instance was found and notified (the secondary process should terminate); `false` otherwise.
    public func checkAndForward(arguments: [String]) -> Bool {
        createOtterKeepDirectoryIfNeeded()
        let path = socketPath

        // If socket file does not exist, no primary instance is running.
        guard FileManager.default.fileExists(atPath: path) else {
            return false
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress, buf.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, addrLen)
            }
        }

        if connectResult != 0 {
            // Stale socket from previous crash; remove it so current process can become primary
            unlink(path)
            return false
        }

        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        // Parse command line arguments to determine message payload
        let message = parseArgumentsToMessage(arguments)
        if let data = try? JSONEncoder().encode(message) {
            var length = UInt32(data.count).bigEndian
            _ = withUnsafeBytes(of: &length) { lenBuf in
                write(fd, lenBuf.baseAddress, lenBuf.count)
            }
            _ = data.withUnsafeBytes { dataBuf in
                write(fd, dataBuf.baseAddress, dataBuf.count)
            }
        }

        logger.info("Successfully forwarded launch message to existing primary GUI instance.")
        return true
    }

    /// Sends a direct IPC message to the running primary GUI instance (e.g., from Finder extension or CLI).
    ///
    /// - Parameter message: The message to transmit.
    /// - Returns: `true` if delivered successfully; `false` otherwise.
    @discardableResult
    public func sendMessageToRunningInstance(_ message: SingleInstanceMessage) -> Bool {
        let path = socketPath
        guard FileManager.default.fileExists(atPath: path) else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress, buf.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, addrLen)
            }
        }

        guard connectResult == 0 else { return false }

        guard let data = try? JSONEncoder().encode(message) else { return false }
        var length = UInt32(data.count).bigEndian
        _ = withUnsafeBytes(of: &length) { lenBuf in
            write(fd, lenBuf.baseAddress, lenBuf.count)
        }
        _ = data.withUnsafeBytes { dataBuf in
            write(fd, dataBuf.baseAddress, dataBuf.count)
        }

        return true
    }

    /// Starts the background Unix Domain Socket IPC server on the primary GUI instance.
    ///
    /// - Parameter onMessage: Callback invoked when a message arrives from secondary instances or the Finder extension.
    public func startServer(onMessage: @escaping @Sendable (SingleInstanceMessage) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard !isListening else { return }

        createOtterKeepDirectoryIfNeeded()
        let path = socketPath
        unlink(path) // Remove any leftover stale socket

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            logger.error("Failed to create Unix Domain Socket: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString

        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            logger.error("Unix socket path exceeds maximum AF_UNIX length (104 bytes): \(path)")
            close(fd)
            return
        }

        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = pathBytes.withUnsafeBufferPointer { buf in
                memcpy(ptr, buf.baseAddress, buf.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, addrLen)
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind Unix Domain Socket at '\(path)': \(errno)")
            close(fd)
            return
        }

        // Restrict socket communication strictly to the current user (0600)
        chmod(path, 0o600)

        guard listen(fd, 5) == 0 else {
            logger.error("Failed to listen on Unix Domain Socket: \(errno)")
            close(fd)
            return
        }

        serverSocketFD = fd
        isListening = true

        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.runServerLoop(onMessage: onMessage)
        }
        thread.name = "OtterKeep.SingleInstanceIPC"
        thread.qualityOfService = .userInteractive
        listeningThread = thread
        thread.start()

        logger.info("Single-instance IPC server listening at '\(path)'")
    }

    /// Stops the IPC server and cleans up the socket file.
    public func stopServer() {
        lock.lock()
        defer { lock.unlock() }

        guard isListening else { return }
        isListening = false

        if serverSocketFD >= 0 {
            close(serverSocketFD)
            serverSocketFD = -1
        }
        unlink(socketPath)
        logger.info("Single-instance IPC server stopped.")
    }

    private var safeIsListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isListening
    }

    /// Decides whether an IPC peer may talk to this process.
    ///
    /// Only peers running as the same effective user are accepted; the check is intentionally
    /// fail-closed so that an unverifiable peer can never be trusted.
    /// - Parameters:
    ///   - peerUID: Effective user ID reported by `getpeereid`.
    ///   - currentUID: Effective user ID of the current process.
    /// - Returns: `true` when the peer belongs to the current user.
    public static func isPeerAllowed(peerUID: uid_t, currentUID: uid_t) -> Bool {
        peerUID == currentUID
    }

    private func runServerLoop(onMessage: @escaping @Sendable (SingleInstanceMessage) -> Void) {
        while safeIsListening {
            let clientFD = accept(serverSocketFD, nil, nil)
            guard clientFD >= 0 else {
                if !safeIsListening { break }
                continue
            }

            // Verify peer UID matches current process UID to prevent cross-user spoofing.
            // Fail closed: an unverifiable peer is rejected rather than trusted.
            var peerUID: uid_t = 0
            var peerGID: gid_t = 0
            guard getpeereid(clientFD, &peerUID, &peerGID) == 0 else {
                logger.error("Rejected IPC connection: peer credentials could not be verified (errno \(errno)).")
                close(clientFD)
                continue
            }
            guard Self.isPeerAllowed(peerUID: peerUID, currentUID: geteuid()) else {
                logger.error("Rejected unauthorized IPC connection from UID \(peerUID) (expected \(geteuid()))")
                close(clientFD)
                continue
            }

            var nosigpipe: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

            // Read message payload
            var rawLen: UInt32 = 0
            let bytesRead = withUnsafeMutableBytes(of: &rawLen) { lenBuf in
                read(clientFD, lenBuf.baseAddress, 4)
            }

            if bytesRead == 4 {
                let payloadLen = Int(UInt32(bigEndian: rawLen))
                if payloadLen > 0 && payloadLen < 65536 {
                    var buffer = [UInt8](repeating: 0, count: payloadLen)
                    var totalRead = 0
                    while totalRead < payloadLen {
                        let n = buffer.withUnsafeMutableBytes { buf in
                            read(clientFD, buf.baseAddress?.advanced(by: totalRead), payloadLen - totalRead)
                        }
                        if n <= 0 { break }
                        totalRead += n
                    }

                    if totalRead == payloadLen {
                        let data = Data(buffer)
                        if let msg = try? JSONDecoder().decode(SingleInstanceMessage.self, from: data) {
                            DispatchQueue.main.async {
                                onMessage(msg)
                            }
                        }
                    }
                }
            }

            close(clientFD)
        }
    }

    private func parseArgumentsToMessage(_ args: [String]) -> SingleInstanceMessage {
        var filePath: String?
        for i in 0..<args.count {
            let arg = args[i]
            if arg == "--restore-file" || arg == "--file-history" || arg == "-f" {
                if i + 1 < args.count {
                    filePath = args[i + 1]
                }
            } else if let url = URL(string: arg), url.scheme == "otterkeep", url.host == "restore-versions" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    filePath = components.queryItems?.first(where: { $0.name == "path" })?.value
                }
            } else if arg.hasPrefix("otterkeep://restore-versions?path=") {
                let encoded = String(arg.dropFirst("otterkeep://restore-versions?path=".count))
                filePath = encoded.removingPercentEncoding
            }
        }

        if let rawPath = filePath {
            let standardized = URL(fileURLWithPath: rawPath).standardizedFileURL.path(percentEncoded: false)
            return SingleInstanceMessage(action: .openVersionHistory, filePath: standardized)
        }
        return SingleInstanceMessage(action: .activate)
    }

    deinit {
        stopServer()
    }
}
