import Foundation
import CryptoKit

/// Content-Defined Chunking (FastCDC) engine for variable-length block deduplication.
///
/// Implements the FastCDC algorithm with Gear rolling hash, sub-chunk normalization,
/// and Content-Addressable Storage (CAS) container management.
public final class FastCDCEngine: Sendable {
    /// A content-defined slice of data identified by its cryptographic SHA-256 fingerprint.
    public struct Chunk: Sendable, Equatable {
        public let offset: Int
        public let length: Int
        public let sha256: String
        public let data: Data

        public init(offset: Int, length: Int, sha256: String, data: Data) {
            self.offset = offset
            self.length = length
            self.sha256 = sha256
            self.data = data
        }
    }

    /// Configuration parameters for the chunking boundaries.
    public struct Configuration: Sendable, Equatable {
        public let minSize: Int
        public let avgSize: Int
        public let maxSize: Int
        public let maskS: UInt64
        public let maskL: UInt64

        public static let standard = Configuration(
            minSize: 64 * 1024,      // 64 KB
            avgSize: 256 * 1024,     // 256 KB
            maxSize: 1024 * 1024,    // 1 MB
            maskS: 0x0000d90f03530000,
            maskL: 0x0000d90303530000
        )

        public init(minSize: Int, avgSize: Int, maxSize: Int, maskS: UInt64, maskL: UInt64) {
            self.minSize = minSize
            self.avgSize = avgSize
            self.maxSize = maxSize
            self.maskS = maskS
            self.maskL = maskL
        }
    }

    private let config: Configuration

    public init(configuration: Configuration = .standard) {
        self.config = configuration
    }

    /// Segments a continuous data buffer into variable-length content-defined chunks.
    /// - Parameter data: Input data buffer.
    /// - Returns: Ordered array of identified chunks.
    public func chunk(data: Data) -> [Chunk] {
        guard !data.isEmpty else { return [] }

        var chunks: [Chunk] = []
        let totalLength = data.count
        var offset = 0

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            while offset < totalLength {
                let remaining = totalLength - offset
                if remaining <= config.minSize {
                    // Remainder is smaller than minimum chunk size
                    let sliceData = Data(bytes: baseAddress + offset, count: remaining)
                    let hash = SHA256.hash(data: sliceData).compactMap { String(format: "%02x", $0) }.joined()
                    chunks.append(Chunk(offset: offset, length: remaining, sha256: hash, data: sliceData))
                    break
                }

                var chunkLen = config.minSize
                let maxScan = min(remaining, config.maxSize)
                var fingerprint: UInt64 = 0

                // FastCDC normalization: Stage 1 (minSize .. avgSize) with MaskS
                let normalWindow = min(config.avgSize, maxScan)
                while chunkLen < normalWindow {
                    let byte = baseAddress[offset + chunkLen]
                    fingerprint = (fingerprint << 1) &+ GEAR_TABLE[Int(byte)]
                    if (fingerprint & config.maskS) == 0 {
                        break
                    }
                    chunkLen += 1
                }

                // Stage 2 (avgSize .. maxSize) with MaskL if boundary not found yet
                if chunkLen >= normalWindow && chunkLen < maxScan {
                    while chunkLen < maxScan {
                        let byte = baseAddress[offset + chunkLen]
                        fingerprint = (fingerprint << 1) &+ GEAR_TABLE[Int(byte)]
                        if (fingerprint & config.maskL) == 0 {
                            break
                        }
                        chunkLen += 1
                    }
                }

                let sliceData = Data(bytes: baseAddress + offset, count: chunkLen)
                let hash = SHA256.hash(data: sliceData).compactMap { String(format: "%02x", $0) }.joined()
                chunks.append(Chunk(offset: offset, length: chunkLen, sha256: hash, data: sliceData))

                offset += chunkLen
            }
        }

        return chunks
    }

    /// Reads and chunks a file from disk.
    /// - Parameter fileURL: Filesystem URL of source file.
    /// - Returns: Ordered chunks.
    public func chunk(fileURL: URL) throws -> [Chunk] {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return chunk(data: data)
    }

    /// Stores chunks into a content-addressable storage (CAS) folder hierarchy.
    /// - Parameters:
    ///   - chunks: Array of chunks to persist.
    ///   - casRootURL: Base directory of the chunk repository.
    public func store(chunks: [Chunk], in casRootURL: URL) throws {
        let chunksDir = casRootURL.appendingPathComponent("chunks", isDirectory: true)

        for chunk in chunks {
            guard chunk.sha256.count >= 4 else { continue }
            let p1 = String(chunk.sha256.prefix(2))
            let p2 = String(chunk.sha256.dropFirst(2).prefix(2))
            let targetSubdir = chunksDir.appendingPathComponent(p1, isDirectory: true).appendingPathComponent(p2, isDirectory: true)

            if !FileManager.default.fileExists(atPath: targetSubdir.path(percentEncoded: false)) {
                try FileManager.default.createDirectory(at: targetSubdir, withIntermediateDirectories: true)
            }

            let chunkFile = targetSubdir.appendingPathComponent("\(chunk.sha256).chunk")
            if !FileManager.default.fileExists(atPath: chunkFile.path(percentEncoded: false)) {
                try chunk.data.write(to: chunkFile, options: .atomic)
            }
        }
    }

    /// Reconstructs a file from ordered chunk hashes stored in CAS repository.
    /// - Parameters:
    ///   - chunkHashes: Ordered array of SHA-256 chunk hashes.
    ///   - casRootURL: Base directory of the chunk repository.
    ///   - destinationURL: Output file path.
    public func reconstruct(
        chunkHashes: [String],
        from casRootURL: URL,
        to destinationURL: URL
    ) throws {
        let chunksDir = casRootURL.appendingPathComponent("chunks", isDirectory: true)

        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        FileManager.default.createFile(atPath: destinationURL.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }

        for hash in chunkHashes {
            guard hash.count >= 4 else { continue }
            let p1 = String(hash.prefix(2))
            let p2 = String(hash.dropFirst(2).prefix(2))
            let chunkFile = chunksDir.appendingPathComponent(p1, isDirectory: true)
                                     .appendingPathComponent(p2, isDirectory: true)
                                     .appendingPathComponent("\(hash).chunk")

            guard FileManager.default.fileExists(atPath: chunkFile.path(percentEncoded: false)) else {
                throw NSError(domain: "FastCDC", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "Missing CAS chunk with hash '\(hash)'."
                ])
            }

            let chunkData = try Data(contentsOf: chunkFile)
            handle.write(chunkData)
        }
    }
}

// MARK: - FastCDC Precomputed Gear Matrix Table (256 64-bit values)

private let GEAR_TABLE: [UInt64] = [
    0x356f8f53a7b74823, 0x1f7481f9b33a218d, 0x6e902e88a18357a7, 0x24e6a0d4b971a1c3,
    0x5be595168e217277, 0xa16f7be2d3c94511, 0x05a76e1081e9d1bf, 0x48e184f479a293cb,
    0x29849202518f87a3, 0xd0f21876a3e14589, 0xb842a198e3b09235, 0x334a1789c927f8a1,
    0x78a104f5e82193b5, 0x90f23b8178e24c91, 0x5a18e20239b17643, 0x8a230f8174e921d3,
    0x4f128e0349b172a5, 0xc1839e2058b1a7d1, 0x173a0e9284f183b5, 0x6291a0f8e17245b3,
    0x8e21049b78a123f5, 0x3a920f1784e1b293, 0xb2830e1847a192c5, 0x71829e0184b273a5,
    0x2847a1098e2173b5, 0x51829f0284e172a3, 0x938210f847a1b2e5, 0x41829e01847a12b3,
    0x61829a0f847a12c5, 0x829104f847a123b5, 0x18290f847a123b45, 0xa2830e1847a192d5,
    0x54829e01847a12c3, 0x738210f847a1b2a5, 0x21829e01847a12f5, 0x92830e1847a192b3,
    0x31829e01847a12a5, 0x829104f847a123c5, 0x18290f847a123b55, 0xb4829e01847a12d3,
    0x638210f847a1b2f5, 0x41829e01847a12e5, 0x72830e1847a192c3, 0x21829e01847a12d5,
    0x91829a0f847a12b5, 0x529104f847a123a5, 0x82830e1847a192e3, 0x31829e01847a12c5,
    0x14829e01847a12a3, 0x738210f847a1b2d5, 0xa1829e01847a12b5, 0x62830e1847a192f3,
    0x21829e01847a12e5, 0x929104f847a123b5, 0x42830e1847a192a3, 0x81829e01847a12d5,
    0x34829e01847a12b3, 0x538210f847a1b2e5, 0x11829e01847a12c5, 0x72830e1847a192a3,
    0xb1829e01847a12f5, 0x429104f847a123c5, 0x62830e1847a192b3, 0x91829e01847a12e5,
    0x24829e01847a12c3, 0x838210f847a1b2f5, 0x31829e01847a12d5, 0x52830e1847a192b3,
    0x71829e01847a12a5, 0x129104f847a123d5, 0xa2830e1847a192c3, 0x41829e01847a12f5,
    0x94829e01847a12d3, 0x638210f847a1b2a5, 0x21829e01847a12e5, 0x82830e1847a192c3,
    0x31829e01847a12b5, 0x729104f847a123e5, 0x52830e1847a192d3, 0x11829e01847a12a5,
    0x44829e01847a12e3, 0x938210f847a1b2b5, 0x61829e01847a12f5, 0x22830e1847a192d3,
    0x81829e01847a12c5, 0x329104f847a123f5, 0x72830e1847a192e3, 0x51829e01847a12b5,
    0x14829e01847a12f3, 0x438210f847a1b2c5, 0x91829e01847a12a5, 0x62830e1847a192e3,
    0x21829e01847a12b5, 0x829104f847a123a5, 0x32830e1847a192f3, 0x71829e01847a12c5,
    0x54829e01847a12a3, 0x138210f847a1b2d5, 0x41829e01847a12b5, 0x92830e1847a192f3,
    0x61829e01847a12c5, 0x229104f847a123b5, 0x82830e1847a192a3, 0x31829e01847a12d5,
    0x74829e01847a12b3, 0x538210f847a1b2e5, 0x11829e01847a12f5, 0x42830e1847a192a3,
    0x91829e01847a12c5, 0x629104f847a123c5, 0x22830e1847a192b3, 0x81829e01847a12e5,
    0x34829e01847a12c3, 0x738210f847a1b2f5, 0x51829e01847a12a5, 0x12830e1847a192b3,
    0x41829e01847a12d5, 0x929104f847a123d5, 0x62830e1847a192c3, 0x21829e01847a12f5,
    0x84829e01847a12d3, 0x338210f847a1b2a5, 0x71829e01847a12b5, 0x52830e1847a192c3,
    0x11829e01847a12e5, 0x429104f847a123e5, 0x92830e1847a192d3, 0x61829e01847a12a5,
    0x24829e01847a12e3, 0x838210f847a1b2b5, 0x31829e01847a12c5, 0x72830e1847a192d3,
    0x51829e01847a12f5, 0x129104f847a123f5, 0x42830e1847a192e3, 0x91829e01847a12b5,
    0x64829e01847a12f3, 0x238210f847a1b2c5, 0x81829e01847a12d5, 0x32830e1847a192e3,
    0x71829e01847a12a5, 0x529104f847a123a5, 0x12830e1847a192f3, 0x41829e01847a12c5,
    0x94829e01847a12a3, 0x638210f847a1b2d5, 0x21829e01847a12b5, 0x82830e1847a192f3,
    0x31829e01847a12e5, 0x729104f847a123b5, 0x52830e1847a192a3, 0x11829e01847a12d5,
    0x44829e01847a12b3, 0x938210f847a1b2e5, 0x61829e01847a12c5, 0x22830e1847a192a3,
    0x81829e01847a12f5, 0x329104f847a123c5, 0x72830e1847a192b3, 0x51829e01847a12e5,
    0x14829e01847a12c3, 0x438210f847a1b2f5, 0x91829e01847a12d5, 0x62830e1847a192b3,
    0x21829e01847a12a5, 0x829104f847a123d5, 0x32830e1847a192c3, 0x71829e01847a12f5,
    0x54829e01847a12d3, 0x138210f847a1b2a5, 0x41829e01847a12e5, 0x92830e1847a192c3,
    0x61829e01847a12b5, 0x229104f847a123e5, 0x82830e1847a192d3, 0x31829e01847a12a5,
    0x74829e01847a12e3, 0x538210f847a1b2b5, 0x11829e01847a12c5, 0x42830e1847a192d3,
    0x91829e01847a12f5, 0x629104f847a123f5, 0x22830e1847a192e3, 0x81829e01847a12b5,
    0x34829e01847a12f3, 0x738210f847a1b2c5, 0x51829e01847a12d5, 0x12830e1847a192e3,
    0x41829e01847a12a5, 0x929104f847a123a5, 0x62830e1847a192f3, 0x21829e01847a12c5,
    0x84829e01847a12a3, 0x338210f847a1b2d5, 0x71829e01847a12b5, 0x52830e1847a192f3,
    0x11829e01847a12e5, 0x429104f847a123b5, 0x92830e1847a192a3, 0x61829e01847a12d5,
    0x24829e01847a12b3, 0x838210f847a1b2e5, 0x31829e01847a12c5, 0x72830e1847a192a3,
    0x51829e01847a12f5, 0x129104f847a123c5, 0x42830e1847a192b3, 0x91829e01847a12e5,
    0x64829e01847a12c3, 0x238210f847a1b2f5, 0x81829e01847a12d5, 0x32830e1847a192b3,
    0x71829e01847a12a5, 0x529104f847a123d5, 0x12830e1847a192c3, 0x41829e01847a12f5,
    0x94829e01847a12d3, 0x638210f847a1b2a5, 0x21829e01847a12e5, 0x82830e1847a192c3,
    0x31829e01847a12b5, 0x729104f847a123e5, 0x52830e1847a192d3, 0x11829e01847a12a5,
    0x44829e01847a12e3, 0x938210f847a1b2b5, 0x61829e01847a12f5, 0x22830e1847a192d3,
    0x81829e01847a12c5, 0x329104f847a123f5, 0x72830e1847a192e3, 0x51829e01847a12b5,
    0x14829e01847a12f3, 0x438210f847a1b2c5, 0x91829e01847a12a5, 0x62830e1847a192e3,
    0x21829e01847a12b5, 0x829104f847a123a5, 0x32830e1847a192f3, 0x71829e01847a12c5,
    0x54829e01847a12a3, 0x138210f847a1b2d5, 0x41829e01847a12b5, 0x92830e1847a192f3,
    0x61829e01847a12c5, 0x229104f847a123b5, 0x82830e1847a192a3, 0x31829e01847a12d5,
    0x74829e01847a12b3, 0x538210f847a1b2e5, 0x11829e01847a12f5, 0x42830e1847a192a3,
    0x91829e01847a12c5, 0x629104f847a123c5, 0x22830e1847a192b3, 0x81829e01847a12e5
]
