import Foundation
import os
import OtterKeepStorage

/// Execution outcome of a pre-backup or post-backup shell hook.
public struct HookExecutionResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let isSuccess: Bool

    public init(exitCode: Int32, standardOutput: String, standardError: String, isSuccess: Bool) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.isSuccess = isSuccess
    }
}

/// Actor managing the discovery and sandboxed/isolated execution of lifecycle shell hook scripts.
public actor HookExecutionManager {
    public static let shared = HookExecutionManager()
    private let logger = Logger(subsystem: "com.otterkeep", category: "HookExecution")

    public init() {}

    /// Verifies that a hook script is a regular file owned by the current user (or root) and not world/group writable.
    public func isTrustedHookScript(at url: URL) -> Bool {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        var statBuf = stat()
        guard stat(path, &statBuf) == 0 else { return false }

        // Must be a regular file
        guard (statBuf.st_mode & S_IFMT) == S_IFREG else { return false }

        // Ownership: must be owned by current user (geteuid()) or root (0)
        let currentUID = geteuid()
        guard statBuf.st_uid == currentUID || statBuf.st_uid == 0 else {
            logger.warning("Rejecting untrusted hook script '\(path)': owner UID (\(statBuf.st_uid)) does not match current user UID (\(currentUID)).")
            return false
        }

        // Permissions: must not be group-writable or other-writable (0o022)
        if (statBuf.st_mode & 0o022) != 0 {
            logger.warning("Rejecting untrusted hook script '\(path)': file is group or world writable (mode: \(String(statBuf.st_mode, radix: 8))).")
            return false
        }

        return true
    }

    /// Searches for a hook script following the conventional resolution order:
    /// 1. ~/.otterkeep/hooks/<ProfileUUID-or-ProfileName>/<hookName>.sh
    /// 2. <destinationURL>/.otterkeep/hooks/<hookName>.sh
    /// 3. <sourceURL>/.otterkeep/hooks/<hookName>.sh
    ///
    /// - Parameters:
    ///   - hookName: The hook name, typically "pre-backup" or "post-backup".
    ///   - profile: The backup profile.
    /// - Returns: URL of the executable hook script if found, or nil.
    public func resolveHookScript(
        hookName: String,
        profile: BackupProfile
    ) -> URL? {
        let fileManager = FileManager.default
        let scriptName = "\(hookName).sh"

        let homeDir = fileManager.homeDirectoryForCurrentUser
        let globalHooksDir = homeDir.appendingPathComponent(".otterkeep/hooks")

        // 1. Profile-specific global directory: by UUID then by profile Name
        let byUUID = globalHooksDir.appendingPathComponent(profile.id.uuidString).appendingPathComponent(scriptName)
        if fileManager.isExecutableFile(atPath: byUUID.path) && isTrustedHookScript(at: byUUID) {
            return byUUID
        }

        let byName = globalHooksDir.appendingPathComponent(profile.name).appendingPathComponent(scriptName)
        if fileManager.isExecutableFile(atPath: byName.path) && isTrustedHookScript(at: byName) {
            return byName
        }

        // 2. Profile-specific source and destination directory: .otterkeep/hooks/ (strictly validated for security)
        let sourceHook = profile.sourceURL.appendingPathComponent(".otterkeep/hooks").appendingPathComponent(scriptName)
        if fileManager.isExecutableFile(atPath: sourceHook.path) && isTrustedHookScript(at: sourceHook) {
            return sourceHook
        }

        let destHook = profile.destinationURL.appendingPathComponent(".otterkeep/hooks").appendingPathComponent(scriptName)
        if fileManager.isExecutableFile(atPath: destHook.path) && isTrustedHookScript(at: destHook) {
            return destHook
        }

        return nil
    }

    /// Executes a shell hook script with injected environment variables and a safety timeout.
    /// - Parameters:
    ///   - scriptURL: The executable script URL.
    ///   - environment: Custom environment variables passed to the process.
    ///   - timeoutSeconds: Maximum runtime before termination (default: 300s).
    /// - Returns: `HookExecutionResult` with exit code and captured stdio.
    public func executeHook(
        scriptURL: URL,
        environment: [String: String],
        timeoutSeconds: TimeInterval = 300
    ) async throws -> HookExecutionResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: scriptURL.path) else {
            throw FileSystemError.itemNotFound(path: scriptURL.path)
        }

        guard isTrustedHookScript(at: scriptURL) else {
            throw FileSystemError.permissionDenied(path: "Untrusted hook script rejected for security reasons: \(scriptURL.path)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]

        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment {
            env[k] = v
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw FileSystemError.unknown("Failed to execute hook script '\(scriptURL.path)': \(error.localizedDescription)")
        }

        let pid = process.processIdentifier

        // Monitor timeout asynchronously
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if process.isRunning {
                    kill(pid, SIGKILL)
                }
            }
        }

        async let outData = Task.detached { outPipe.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }.value

        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }
        timeoutTask.cancel()

        let stdout = await outData
        let stderr = await errData

        let outStr = String(data: stdout, encoding: .utf8) ?? ""
        let errStr = String(data: stderr, encoding: .utf8) ?? ""
        let code = process.terminationStatus

        return HookExecutionResult(
            exitCode: code,
            standardOutput: outStr,
            standardError: errStr,
            isSuccess: code == 0
        )
    }
}
