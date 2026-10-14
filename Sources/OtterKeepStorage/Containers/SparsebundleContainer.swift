import Foundation

/// Controller for creating, attaching, detaching, and managing encrypted APFS sparsebundle disk image containers.
public final class SparsebundleContainer: Sendable {
    /// Errors thrown during sparsebundle lifecycle management.
    public struct ContainerError: Error, CustomStringConvertible, Sendable {
        public let message: String
        public var description: String { "SparsebundleContainerError: \(message)" }
    }

    public init() {}

    /// Creates an AES-256 encrypted APFS sparsebundle at the designated file URL.
    /// - Parameters:
    ///   - url: Destination URL (typically with `.sparsebundle` extension).
    ///   - volumeName: Name for the internal APFS volume.
    ///   - sizeGB: Maximum expandable capacity in Gigabytes (default: 500 GB).
    ///   - passphrase: Encryption passphrase.
    public func create(
        at url: URL,
        volumeName: String,
        sizeGB: Int = 500,
        passphrase: String
    ) throws {
        let path = url.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: path) else {
            throw ContainerError(message: "Sparsebundle container already exists at '\(path)'.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "create",
            "-size", "\(sizeGB)g",
            "-type", "SPARSEBUNDLE",
            "-fs", "APFS",
            "-volname", volumeName,
            "-encryption", "AES-256",
            "-stdinpass",
            path
        ]

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = stderrPipe

        try process.run()

        if let passData = (passphrase + "\n").data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(passData)
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown hdiutil error"
            throw ContainerError(message: "Failed to create sparsebundle: \(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// Attaches and mounts the encrypted sparsebundle.
    /// - Parameters:
    ///   - url: URL to the `.sparsebundle`.
    ///   - mountPoint: Optional custom mount directory.
    ///   - passphrase: Decryption passphrase.
    /// - Returns: URL of the mounted filesystem volume root.
    public func attach(
        at url: URL,
        mountPoint: URL? = nil,
        passphrase: String
    ) throws -> URL {
        let (attached, existingMount) = isAttached(at: url)
        if attached, let existing = existingMount {
            return existing
        }

        let path = url.path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")

        var args = [
            "attach",
            path,
            "-nobrowse",
            "-stdinpass",
            "-plist"
        ]

        if let mp = mountPoint {
            try FileManager.default.createDirectory(at: mp, withIntermediateDirectories: true)
            args.append(contentsOf: ["-mountpoint", mp.path(percentEncoded: false)])
        }

        process.arguments = args

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let passData = (passphrase + "\n").data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(passData)
            try? stdinPipe.fileHandleForWriting.close()
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown hdiutil error"
            throw ContainerError(message: "Failed to attach sparsebundle: \(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if let plist = try? PropertyListSerialization.propertyList(from: outData, options: [], format: nil) as? [String: Any],
           let entities = plist["system-entities"] as? [[String: Any]] {
            for entity in entities {
                if let mp = entity["mount-point"] as? String {
                    return URL(fileURLWithPath: mp, isDirectory: true)
                }
            }
        }

        if let mp = mountPoint {
            return mp
        }

        throw ContainerError(message: "Sparsebundle attached but mount point could not be determined.")
    }

    /// Detaches and unmounts a mounted sparsebundle container.
    /// - Parameter mountPoint: Mount URL to detach.
    public func detach(mountPoint: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "detach",
            mountPoint.path(percentEncoded: false),
            "-force"
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown hdiutil error"
            throw ContainerError(message: "Failed to detach sparsebundle: \(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    /// Checks if a sparsebundle at the given URL is currently attached.
    /// - Parameter url: Path to the `.sparsebundle`.
    /// - Returns: Tuple indicating attached status and current mount point URL.
    public func isAttached(at url: URL) -> (attached: Bool, mountPoint: URL?) {
        let targetPath = (url.path(percentEncoded: false) as NSString).standardizingPath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe

        guard (try? process.run()) != nil else { return (false, nil) }
        process.waitUntilExit()

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: outData, options: [], format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return (false, nil)
        }

        for image in images {
            if let imgPath = image["image-path"] as? String {
                let stdImgPath = (imgPath as NSString).standardizingPath
                if stdImgPath == targetPath {
                    if let entities = image["system-entities"] as? [[String: Any]] {
                        for entity in entities {
                            if let mp = entity["mount-point"] as? String {
                                return (true, URL(fileURLWithPath: mp, isDirectory: true))
                            }
                        }
                    }
                    return (true, nil)
                }
            }
        }

        return (false, nil)
    }
}
