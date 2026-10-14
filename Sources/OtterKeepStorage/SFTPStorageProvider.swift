import Foundation
import Network
import os

/// Authentication method for SFTP connection.
public enum SFTPAuthMethod: Sendable, Codable, Equatable {
    case password
    case privateKey(keyPath: String)

    enum CodingKeys: String, CodingKey {
        case type, keyPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeStr = try container.decode(String.self, forKey: .type)
        if typeStr == "privateKey" {
            let path = try container.decode(String.self, forKey: .keyPath)
            self = .privateKey(keyPath: path)
        } else {
            self = .password
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .password:
            try container.encode("password", forKey: .type)
        case .privateKey(let path):
            try container.encode("privateKey", forKey: .type)
            try container.encode(path, forKey: .keyPath)
        }
    }
}

/// Configuration options for connecting to an SFTP (SSH File Transfer Protocol) remote storage server.
public struct SFTPConfiguration: Sendable, Codable, Equatable {
    /// Remote server hostname or IP address (e.g. "nas.local", "192.168.1.100", "sftp.example.com").
    public var host: String
    /// SSH port number (default: 22).
    public var port: Int
    /// Username for SSH authentication.
    public var username: String
    /// Base destination subfolder path on the remote filesystem (e.g. "/data/backups/otterkeep").
    public var remotePath: String
    /// Selected authentication mechanism (password or private key).
    public var authMethod: SFTPAuthMethod

    public init(
        host: String = "",
        port: Int = 22,
        username: String = "",
        remotePath: String = "/backups",
        authMethod: SFTPAuthMethod = .password
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.remotePath = remotePath
        self.authMethod = authMethod
    }
}

/// Metadata item returned by an SFTP directory listing.
public struct SFTPItem: Sendable, Equatable {
    public let filename: String
    public let isDirectory: Bool
    public let fileSize: Int64
    public let modificationDate: Date?

    public init(filename: String, isDirectory: Bool, fileSize: Int64, modificationDate: Date? = nil) {
        self.filename = filename
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

/// Errors occurring during SFTP operations.
public enum SFTPError: Error, Sendable, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case transferFailed(String)
    case commandFailed(exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg):
            return "SFTP configuration invalid: \(msg)"
        case .connectionFailed(let details):
            return "Failed to connect to SFTP server: \(details)"
        case .transferFailed(let details):
            return "SFTP file transfer failed: \(details)"
        case .commandFailed(let exitCode, let message):
            return "SFTP command exited with status \(exitCode): \(message)"
        }
    }
}

/// Actor managing SSH File Transfer Protocol (SFTP) remote backup transfers.
public actor SFTPStorageProvider {
    public let config: SFTPConfiguration
    public let password: String?
    private let logger = Logger(subsystem: "com.otterkeep", category: "SFTP")

    public init(config: SFTPConfiguration, password: String? = nil) {
        self.config = config
        self.password = password
    }

    /// Resolves full target path on remote server.
    public func resolveRemotePath(for relativePath: String = "") -> String {
        var base = config.remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty && !base.hasPrefix("/") {
            base = "/" + base
        }
        while base.hasSuffix("/") {
            base.removeLast()
        }

        var rel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rel.isEmpty && !rel.hasPrefix("/") {
            rel = "/" + rel
        }

        return "\(base)\(rel)"
    }

    /// Tests TCP connectivity and port availability on the SFTP host.
    public func testConnection(timeoutSeconds: TimeInterval = 4.0) async throws -> Bool {
        let trimmedHost = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            throw SFTPError.invalidConfiguration("Hostname cannot be empty.")
        }
        guard config.port > 0 && config.port <= 65535 else {
            throw SFTPError.invalidConfiguration("Port must be between 1 and 65535.")
        }
        guard !config.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SFTPError.invalidConfiguration("Username cannot be empty.")
        }

        // Test network socket connectivity
        let endpointHost = NWEndpoint.Host(trimmedHost)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(config.port)) else {
            throw SFTPError.invalidConfiguration("Invalid port number: \(config.port)")
        }

        let connection = NWConnection(host: endpointHost, port: endpointPort, using: .tcp)
        return try await withCheckedThrowingContinuation { continuation in
            let hasResponded = OSAllocatedUnfairLock(initialState: false)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let won = hasResponded.withLock { isDone -> Bool in
                        if !isDone {
                            isDone = true
                            return true
                        }
                        return false
                    }
                    if won {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed(let error):
                    let won = hasResponded.withLock { isDone -> Bool in
                        if !isDone {
                            isDone = true
                            return true
                        }
                        return false
                    }
                    if won {
                        connection.cancel()
                        continuation.resume(throwing: SFTPError.connectionFailed(error.localizedDescription))
                    }
                case .cancelled:
                    break
                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout watchdog
            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                let won = hasResponded.withLock { isDone -> Bool in
                    if !isDone {
                        isDone = true
                        return true
                    }
                    return false
                }
                if won {
                    connection.cancel()
                    continuation.resume(throwing: SFTPError.connectionFailed("Connection timed out after \(Int(timeoutSeconds))s"))
                }
            }
        }
    }

    /// Uploads a local file to the remote SFTP destination path.
    public func uploadFile(localURL: URL, remotePath: String) async throws {
        guard FileManager.default.fileExists(atPath: localURL.path(percentEncoded: false)) else {
            throw SFTPError.transferFailed("Local file not found: \(localURL.path)")
        }

        let targetPath = resolveRemotePath(for: remotePath)
        logger.info("Uploading local file '\(localURL.lastPathComponent)' to SFTP '\(self.config.host):\(targetPath)'")

        // In macOS environment, execute scp / sftp batch operation with batch mode
        let portArg = String(config.port)
        let destinationStr = "\(config.username)@\(config.host):\(targetPath)"

        var arguments = ["-P", portArg, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10"]
        if case .privateKey(let keyPath) = config.authMethod, !keyPath.isEmpty {
            arguments.append(contentsOf: ["-i", keyPath])
        }

        arguments.append(contentsOf: [localURL.path(percentEncoded: false), destinationStr])

        var extraEnv: [String: String] = [:]
        if let pwd = password, !pwd.isEmpty {
            extraEnv["SSHPASS"] = pwd
        }
        let process = createIsolatedProcess(executable: "/usr/bin/scp", arguments: arguments, extraEnvironment: extraEnv)

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8) ?? ""
                throw SFTPError.commandFailed(exitCode: process.terminationStatus, message: errString)
            }
        } catch let err as SFTPError {
            throw err
        } catch {
            throw SFTPError.transferFailed(error.localizedDescription)
        }
    }

    /// Downloads a remote file to a local destination.
    public func downloadFile(remotePath: String, to localURL: URL) async throws {
        let targetPath = resolveRemotePath(for: remotePath)
        let sourceStr = "\(config.username)@\(config.host):\(targetPath)"
        let portArg = String(config.port)

        var arguments = ["-P", portArg, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10"]
        if case .privateKey(let keyPath) = config.authMethod, !keyPath.isEmpty {
            arguments.append(contentsOf: ["-i", keyPath])
        }
        arguments.append(contentsOf: [sourceStr, localURL.path(percentEncoded: false)])

        var extraEnv: [String: String] = [:]
        if let pwd = password, !pwd.isEmpty {
            extraEnv["SSHPASS"] = pwd
        }
        let process = createIsolatedProcess(executable: "/usr/bin/scp", arguments: arguments, extraEnvironment: extraEnv)

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errString = String(data: errData, encoding: .utf8) ?? ""
                throw SFTPError.commandFailed(exitCode: process.terminationStatus, message: errString)
            }
        } catch let err as SFTPError {
            throw err
        } catch {
            throw SFTPError.transferFailed(error.localizedDescription)
        }
    }

    /// Creates an isolated Process configured with strict minimal environment variables to avoid credential leakage.
    private func createIsolatedProcess(executable: String, arguments: [String], extraEnvironment: [String: String] = [:]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env: [String: String] = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        ]
        for (k, v) in extraEnvironment {
            env[k] = v
        }
        process.environment = env
        return process
    }

    /// Sanitizes an argument for safe passing into a POSIX shell command.
    private func sanitizeShellArgument(_ argument: String) -> String {
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Creates a directory on the remote SFTP host via SSH command.
    public func createDirectory(remotePath: String) async throws {
        let fullPath = resolveRemotePath(for: remotePath)
        let escapedPath = sanitizeShellArgument(fullPath)
        let portArg = String(config.port)
        var arguments = ["-p", portArg, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes"]
        if case .privateKey(let keyPath) = config.authMethod, !keyPath.isEmpty {
            arguments.append(contentsOf: ["-i", keyPath])
        }
        arguments.append(contentsOf: ["\(config.username)@\(config.host)", "mkdir -p \(escapedPath)"])

        var extraEnv: [String: String] = [:]
        if let pwd = password, !pwd.isEmpty {
            extraEnv["SSHPASS"] = pwd
        }
        let process = createIsolatedProcess(executable: "/usr/bin/ssh", arguments: arguments, extraEnvironment: extraEnv)
        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SFTPError.commandFailed(exitCode: -1, message: "Failed to launch ssh process: \(error.localizedDescription)")
        }

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            throw SFTPError.commandFailed(exitCode: process.terminationStatus, message: "mkdir failed: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// Deletes a file on the remote host via SSH command.
    public func deleteFile(remotePath: String) async throws {
        let fullPath = resolveRemotePath(for: remotePath)
        let escapedPath = sanitizeShellArgument(fullPath)
        let portArg = String(config.port)
        var arguments = ["-p", portArg, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes"]
        if case .privateKey(let keyPath) = config.authMethod, !keyPath.isEmpty {
            arguments.append(contentsOf: ["-i", keyPath])
        }
        arguments.append(contentsOf: ["\(config.username)@\(config.host)", "rm -f \(escapedPath)"])

        var extraEnv: [String: String] = [:]
        if let pwd = password, !pwd.isEmpty {
            extraEnv["SSHPASS"] = pwd
        }
        let process = createIsolatedProcess(executable: "/usr/bin/ssh", arguments: arguments, extraEnvironment: extraEnv)
        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw SFTPError.commandFailed(exitCode: -1, message: "Failed to launch ssh process: \(error.localizedDescription)")
        }

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            throw SFTPError.commandFailed(exitCode: process.terminationStatus, message: "rm failed: \(errStr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
