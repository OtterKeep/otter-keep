import Foundation
import os
import Darwin
import OtterKeepDomain

/// Structured errors encountered during network share operations.
public enum NetworkShareError: Error, Sendable, LocalizedError, Equatable {
    case invalidShareURL(String)
    case mountFailed(String)
    case unmountFailed(String)
    case notMounted(String)
    case hostUnreachable(String)
    case authenticationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidShareURL(let url): return "Invalid network share URL: \(url)"
        case .mountFailed(let msg): return "Failed to mount network share: \(msg)"
        case .unmountFailed(let msg): return "Failed to unmount network share: \(msg)"
        case .notMounted(let path): return "Share is not mounted at: \(path)"
        case .hostUnreachable(let host): return "Remote NAS host is unreachable: \(host)"
        case .authenticationFailed(let msg): return "Authentication failed for network share: \(msg)"
        }
    }
}

/// Parsed elements from an SMB URL string.
public struct SMBShareComponents: Sendable, Equatable {
    public let host: String
    public let shareName: String
    public let urlSubpath: String
    public let username: String?

    public init(host: String, shareName: String, urlSubpath: String, username: String? = nil) {
        self.host = host
        self.shareName = shareName
        self.urlSubpath = urlSubpath
        self.username = username
    }
}

/// Result of an SMB share mount operation containing local mount point and resolved destination subfolder.
public struct SMBMountResult: Sendable, Equatable {
    public let mountPoint: URL
    public let resolvedSubpath: String
    public let wasAlreadyMounted: Bool

    public init(mountPoint: URL, resolvedSubpath: String, wasAlreadyMounted: Bool) {
        self.mountPoint = mountPoint
        self.resolvedSubpath = resolvedSubpath
        self.wasAlreadyMounted = wasAlreadyMounted
    }
}

/// Actor managing the automatic mounting, status inspection, and unmounting of SMB / NFS network shares on macOS.
public actor NetworkShareMounter {
    private let logger = Logger(subsystem: "com.otterkeep", category: "NetworkShare")

    public init() {}

    /// Parses an SMB URL into components, correctly extracting host, server-level share name, and subpath.
    public static func parseShareURL(_ rawURL: String) throws -> SMBShareComponents {
        var trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("//") {
            trimmed = "smb:" + trimmed
        } else if !trimmed.contains("://") {
            trimmed = "smb://" + trimmed
        }

        guard let components = URLComponents(string: trimmed),
              let host = components.host, !host.isEmpty else {
            throw NetworkShareError.invalidShareURL(rawURL)
        }

        let rawPath = components.percentEncodedPath
        let segments = rawPath.split(separator: "/").map {
            $0.removingPercentEncoding ?? String($0)
        }.filter { !$0.isEmpty }

        guard let first = segments.first, !first.isEmpty else {
            throw NetworkShareError.invalidShareURL("No share name found in SMB URL: \(rawURL)")
        }

        let shareName = first
        let urlSubpath = segments.dropFirst().joined(separator: "/")
        let user = components.user?.removingPercentEncoding

        return SMBShareComponents(
            host: host,
            shareName: shareName,
            urlSubpath: urlSubpath,
            username: user
        )
    }

    /// Combines subpath defined in the SMB URL with the user-configured subfolder.
    public static func resolveSubpath(urlSubpath: String, configuredSubfolder: String) -> String {
        let cleanURLSubpath = urlSubpath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let cleanConfigured = configuredSubfolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        if !cleanURLSubpath.isEmpty && !cleanConfigured.isEmpty {
            return "\(cleanURLSubpath)/\(cleanConfigured)"
        } else if !cleanURLSubpath.isEmpty {
            return cleanURLSubpath
        } else if !cleanConfigured.isEmpty {
            return cleanConfigured
        } else {
            return "OtterKeep_Backups"
        }
    }

    /// Resolves bare NetBIOS host names to local IP addresses using smbutil lookup if DNS fails.
    public static func resolveNetBIOSHostIfNeeded(_ host: String) -> String {
        if host.contains(".") || host.contains(":") {
            return host
        }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, nil, &hints, &res) == 0 {
            freeaddrinfo(res)
            return host
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/smbutil")
        process.arguments = ["lookup", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                if let outStr = String(data: outData, encoding: .utf8) {
                    let lines = outStr.components(separatedBy: .newlines)
                    var foundIPs: [String] = []
                    for line in lines {
                        if line.contains("IP address of") || line.contains("Got response from") {
                            let tokens = line.components(separatedBy: .whitespaces)
                            if let last = tokens.last, !last.isEmpty, last.contains(".") {
                                foundIPs.append(last)
                            }
                        }
                    }
                    if let lanIP = foundIPs.first(where: { $0.hasPrefix("192.168.") || $0.hasPrefix("10.") }) {
                        return lanIP
                    }
                    if let firstIP = foundIPs.first {
                        return firstIP
                    }
                }
            }
        } catch {
            // Keep original host
        }

        return host
    }

    /// Tests whether a TCP port (default 445 for SMB) is reachable on the given host.
    public static func testTCPPort(host: String, port: Int = 445, timeoutSeconds: Double = 3.0) -> Bool {
        let resolved = resolveNetBIOSHostIfNeeded(host)
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, resolved, &addr.sin_addr)

        let connectRes = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(sock, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectRes == 0 {
            return true
        }

        if errno == EINPROGRESS {
            var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
            let pollRes = poll(&pfd, 1, Int32(timeoutSeconds * 1000))
            if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 {
                var err: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)
                return err == 0
            }
        }

        return false
    }

    /// Checks if a share is already mounted at a given mount point or in `/Volumes` or system mount table.
    public func findMountedShareURL(shareName: String, host: String? = nil) -> URL? {
        var mntbuf: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mntbuf, MNT_NOWAIT)
        if let mntbuf = mntbuf, count > 0 {
            for i in 0..<Int(count) {
                let entry = mntbuf[i]
                let fstype = withUnsafePointer(to: entry.f_fstypename) { ptr -> String in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
                }
                guard fstype == "smbfs" else { continue }
                let fromName = withUnsafePointer(to: entry.f_mntfromname) { ptr -> String in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
                }
                let toName = withUnsafePointer(to: entry.f_mntonname) { ptr -> String in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
                }

                let lowerFrom = fromName.lowercased()
                let lowerShare = shareName.lowercased()
                let shareSuffix = "/" + lowerShare

                let matchesShare = lowerFrom.hasSuffix(shareSuffix) ||
                                   lowerFrom.contains(shareSuffix + "/") ||
                                   URL(fileURLWithPath: toName).lastPathComponent.lowercased() == lowerShare

                if matchesShare {
                    if let host = host, !host.isEmpty {
                        let lowerHost = host.lowercased()
                        if lowerFrom.contains(lowerHost) {
                            return URL(fileURLWithPath: toName)
                        }
                    } else {
                        return URL(fileURLWithPath: toName)
                    }
                }
            }
        }

        let volumesDir = URL(fileURLWithPath: "/Volumes")
        if let contents = try? FileManager.default.contentsOfDirectory(at: volumesDir, includingPropertiesForKeys: [.volumeURLKey], options: .skipsHiddenFiles) {
            for vol in contents {
                if vol.lastPathComponent.lowercased() == shareName.lowercased() {
                    return vol
                }
            }
        }

        let tempMount = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_Mounts/\(shareName)")
        if FileManager.default.fileExists(atPath: tempMount.path) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: tempMount.path, isDirectory: &isDir), isDir.boolValue {
                if let sub = try? FileManager.default.contentsOfDirectory(atPath: tempMount.path), !sub.isEmpty {
                    return tempMount
                }
            }
        }

        return nil
    }

    /// Mounts an SMB share to a local mount directory or uses existing mount, returning the root mount URL and resolved subpath.
    public func mountShare(config: NetworkShareConfiguration, password: String?) async throws -> SMBMountResult {
        let components = try Self.parseShareURL(config.shareURL)

        // 1. Build candidates for shareName and subpath
        struct MountCandidate {
            let shareName: String
            let resolvedSubpath: String
        }

        var candidates: [MountCandidate] = []
        let primarySubpath = Self.resolveSubpath(urlSubpath: components.urlSubpath, configuredSubfolder: config.subfolder)
        candidates.append(MountCandidate(shareName: components.shareName, resolvedSubpath: primarySubpath))

        // If URL had subpaths (e.g. "Users/richard/test"), try the last segment as shareName (e.g. "test")
        if !components.urlSubpath.isEmpty {
            let lastSegment = components.urlSubpath.split(separator: "/").last.map(String.init) ?? ""
            if !lastSegment.isEmpty && lastSegment != components.shareName {
                let secondarySubpath = config.subfolder.isEmpty ? "OtterKeep_Backups" : config.subfolder
                candidates.append(MountCandidate(shareName: lastSegment, resolvedSubpath: secondarySubpath))
            }
        }

        // 2. Check if any candidate is already mounted
        for cand in candidates {
            if let existing = findMountedShareURL(shareName: cand.shareName, host: components.host) {
                logger.info("Share '\(cand.shareName)' is already mounted at: \(existing.path)")
                return SMBMountResult(mountPoint: existing, resolvedSubpath: cand.resolvedSubpath, wasAlreadyMounted: true)
            }
        }

        let resolvedHost = Self.resolveNetBIOSHostIfNeeded(components.host)
        let effectiveUser = (components.username ?? config.username).trimmingCharacters(in: .whitespacesAndNewlines)
        var candidateUsers: [String] = []
        if !effectiveUser.isEmpty {
            candidateUsers.append(effectiveUser)
        } else if let pwd = password, !pwd.isEmpty {
            let localUser = NSUserName()
            candidateUsers.append(localUser)
            candidateUsers.append("")
        } else {
            candidateUsers.append("")
        }

        // Securely ensure password is in Keychain so mount_smbfs -N can retrieve it without command-line exposure
        if let pwd = password, !pwd.isEmpty {
            for u in candidateUsers where !u.isEmpty {
                let addQuery: [String: Any] = [
                    kSecClass as String: kSecClassInternetPassword,
                    kSecAttrServer as String: resolvedHost,
                    kSecAttrAccount as String: u,
                    kSecAttrProtocol as String: kSecAttrProtocolSMB,
                    kSecValueData as String: Data(pwd.utf8),
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                ]
                SecItemAdd(addQuery as CFDictionary, nil)
            }
        }

        var lastError: Error = NetworkShareError.mountFailed("No viable SMB configuration found")

        for cand in candidates {
            let mountBaseDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_Mounts/\(cand.shareName)")
            try? FileManager.default.createDirectory(at: mountBaseDir, withIntermediateDirectories: true)

            // Build credential variations across candidate usernames (passwords omitted from CLI arguments)
            var smbSources: [String] = []

            for u in candidateUsers {
                if !u.isEmpty {
                    let encUser = u.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? u
                    smbSources.append("//\(encUser)@\(resolvedHost)/\(cand.shareName)")

                    if !u.contains(";") && !u.contains("\\") && !components.host.isEmpty {
                        smbSources.append("//\(components.host);\(encUser)@\(resolvedHost)/\(cand.shareName)")
                    }
                } else {
                    smbSources.append("//\(resolvedHost)/\(cand.shareName)")
                }
            }

            for smbSource in smbSources {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/mount_smbfs")
                process.arguments = [
                    "-N",
                    "-o", "soft",
                    smbSource,
                    mountBaseDir.standardizedFileURL.path(percentEncoded: false)
                ]

                let errPipe = Pipe()
                let outPipe = Pipe()
                process.standardError = errPipe
                process.standardOutput = outPipe

                do {
                    try process.run()
                } catch {
                    lastError = NetworkShareError.mountFailed("Failed to execute mount_smbfs: \(error.localizedDescription)")
                    continue
                }

                // Read pipes concurrently with Swift concurrency to prevent 64 KB pipe buffer deadlocks
                async let errTask = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }.value
                async let outTask = Task.detached { outPipe.fileHandleForReading.readDataToEndOfFile() }.value

                process.waitUntilExit()

                let errData = await errTask
                let outData = await outTask

                if process.terminationStatus == 0 {
                    logger.info("Successfully mounted SMB share '\(cand.shareName)' to \(mountBaseDir.path)")
                    return SMBMountResult(mountPoint: mountBaseDir, resolvedSubpath: cand.resolvedSubpath, wasAlreadyMounted: false)
                }

                let rawErr = String(data: errData, encoding: .utf8) ?? ""
                let rawOut = String(data: outData, encoding: .utf8) ?? ""
                let fullMsg = (rawErr.isEmpty ? rawOut : rawErr).trimmingCharacters(in: .whitespacesAndNewlines)

                logger.warning("SMB attempt failed for '\(cand.shareName)': \(fullMsg)")

                let lower = fullMsg.lowercased()
                if lower.contains("authentication error") || lower.contains("rejected the connection") || lower.contains("permission denied") {
                    lastError = NetworkShareError.authenticationFailed(fullMsg.isEmpty ? "Server rejected credentials" : fullMsg)
                } else if lower.contains("timed out") || lower.contains("no route to host") || lower.contains("host is down") {
                    lastError = NetworkShareError.hostUnreachable(components.host)
                } else {
                    lastError = NetworkShareError.mountFailed(fullMsg.isEmpty ? "mount_smbfs failed with code \(process.terminationStatus)" : fullMsg)
                }
            }
        }

        throw lastError
    }

    /// Mounts an SMB share to a local mount directory or default `/Volumes/` path.
    /// - Parameters:
    ///   - config: The network share configuration.
    ///   - password: The password retrieved from Keychain.
    /// - Returns: The local mounted filesystem URL.
    public func mountSMB(config: NetworkShareConfiguration, password: String?) async throws -> URL {
        let result = try await mountShare(config: config, password: password)
        return result.mountPoint
    }

    /// Unmounts a mounted share.
    public func unmount(at mountPoint: URL) async throws {
        let path = mountPoint.standardizedFileURL.path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/umount")
        process.arguments = [path]

        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "umount failed"
            logger.warning("Notice: umount returned \(process.terminationStatus): \(errStr)")
            throw NetworkShareError.unmountFailed(errStr)
        }
        logger.info("Successfully unmounted share at \(path)")
    }
}
