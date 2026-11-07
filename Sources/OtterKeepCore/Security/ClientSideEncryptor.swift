import CommonCrypto
import CryptoKit
import Foundation

/// Structured errors encountered during zero-knowledge client-side encryption.
public enum ClientEncryptionError: Error, Sendable, LocalizedError, Equatable {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidHeader
    case authenticationMismatch

    public var errorDescription: String? {
        switch self {
        case .encryptionFailed(let msg): return "Client-side encryption error: \(msg)"
        case .decryptionFailed(let msg): return "Client-side decryption error: \(msg)"
        case .invalidHeader: return "Invalid encrypted blob format or header magic"
        case .authenticationMismatch: return "Decryption failed: incorrect passphrase or corrupted data"
        }
    }
}

/// Zero-Knowledge Client-Side Authenticated Encryption Engine (AES-256-GCM with PBKDF2-HMAC-SHA256 key derivation).
public enum ClientSideEncryptor: Sendable {
    /// Modern PBKDF2-HMAC-SHA256 header magic identifier (OtterKeep standard envelope format).
    public static let headerMagicOKENC2 = Data([0x4F, 0x4B, 0x45, 0x4E, 0x43, 0x32, 0x00])  // "OKENC2\0"
    /// Legacy HKDF-SHA256 header magic identifier retained for backwards-compatible reading of existing archives.
    public static let headerMagicV1 = Data([0x44, 0x53, 0x45, 0x4E, 0x43, 0x31, 0x00])  // "DSENC1\0"

    private static let saltLengthV2 = 32
    private static let saltLengthV1 = 16
    private static let pbkdf2Rounds: UInt32 = 600_000

    /// Derives a 256-bit symmetric key from a passphrase and salt using PBKDF2-HMAC-SHA256 (600,000 iterations).
    private static func deriveKeyPBKDF2(from passphrase: String, salt: Data, rounds: UInt32 = pbkdf2Rounds) throws -> SymmetricKey {
        var derivedKeyData = Data(count: 32)
        let passwordData = Data(passphrase.utf8)

        let status = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw ClientEncryptionError.encryptionFailed("PBKDF2 key derivation failed with status: \(status)")
        }
        return SymmetricKey(data: derivedKeyData)
    }

    /// Derives a deterministic hexadecimal key fingerprint from a passphrase and salt using PBKDF2-HMAC-SHA256.
    /// Uses computationally hard PBKDF2 key derivation (100,000 rounds) rather than fast hashing algorithms,
    /// adhering to CWE-328 standards against offline brute-forcing.
    public static func deriveFingerprintPBKDF2(from passphrase: String, salt: Data, rounds: UInt32 = 100_000) -> String {
        var fingerprintBytes = Data(count: 8)
        let passwordData = Data(passphrase.utf8)

        let status = fingerprintBytes.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        outBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        8
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            return "PBKDF2:UNAVAILABLE"
        }
        return "PBKDF2:" + fingerprintBytes.map { String(format: "%02x", $0) }.joined().uppercased()
    }

    /// Legacy key derivation using HKDF-SHA256 for backward compatibility with existing DSENC1 blobs.
    private static func deriveKeyLegacyHKDF(from passphrase: String, salt: Data) -> SymmetricKey {
        let inputKey = SymmetricKey(data: Data(passphrase.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: Data("OtterKeep-S3-Envelope-Key".utf8),
            outputByteCount: 32
        )
    }

    /// Encrypts raw data using AES-256-GCM with PBKDF2-HMAC-SHA256 key derivation.
    /// - Parameters:
    ///   - data: Plaintext data.
    ///   - passphrase: Encryption passphrase.
    ///   - magic: Header magic identifier (defaults to `headerMagicOKENC2`).
    /// - Returns: Encrypted envelope with header magic, 32-byte salt, and AES-GCM sealed box.
    public static func encrypt(data: Data, passphrase: String, magic: Data = headerMagicOKENC2) throws -> Data {
        var saltBytes = [UInt8](repeating: 0, count: saltLengthV2)
        guard SecRandomCopyBytes(kSecRandomDefault, saltLengthV2, &saltBytes) == errSecSuccess else {
            throw ClientEncryptionError.encryptionFailed("Failed to generate secure random salt")
        }
        let salt = Data(saltBytes)
        let key = try deriveKeyPBKDF2(from: passphrase, salt: salt)

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw ClientEncryptionError.encryptionFailed("Failed to generate combined sealed box")
            }

            var envelope = Data()
            envelope.append(magic)
            envelope.append(salt)
            envelope.append(combined)
            return envelope
        } catch {
            throw ClientEncryptionError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypts an encrypted envelope using AES-256-GCM.
    ///
    /// Primary path: OKENC2 (PBKDF2-HMAC-SHA256, 600,000 iterations).
    /// Legacy fallback: DSENC1 (HKDF-SHA256) for read-compatibility with pre-existing backups.
    /// - Parameters:
    ///   - envelope: Encrypted data payload.
    ///   - passphrase: Encryption passphrase.
    /// - Returns: Decrypted plaintext data.
    public static func decrypt(envelope: Data, passphrase: String) throws -> Data {
        guard envelope.count > headerMagicOKENC2.count + saltLengthV1 + 28 else {
            throw ClientEncryptionError.invalidHeader
        }

        if envelope.starts(with: headerMagicOKENC2) {
            guard envelope.count > headerMagicOKENC2.count + saltLengthV2 + 28 else {
                throw ClientEncryptionError.invalidHeader
            }
            let saltStart = headerMagicOKENC2.count
            let salt = envelope.subdata(in: saltStart..<(saltStart + saltLengthV2))
            let boxData = envelope.suffix(from: saltStart + saltLengthV2)

            let key = try deriveKeyPBKDF2(from: passphrase, salt: salt)

            do {
                let sealedBox = try AES.GCM.SealedBox(combined: boxData)
                return try AES.GCM.open(sealedBox, using: key)
            } catch {
                throw ClientEncryptionError.authenticationMismatch
            }
        } else if envelope.starts(with: headerMagicV1) {
            // Documented legacy recovery branch: HKDF-SHA256 key derivation with 16-byte salt
            guard envelope.count > headerMagicV1.count + saltLengthV1 + 28 else {
                throw ClientEncryptionError.invalidHeader
            }
            let saltStart = headerMagicV1.count
            let salt = envelope.subdata(in: saltStart..<(saltStart + saltLengthV1))
            let boxData = envelope.suffix(from: saltStart + saltLengthV1)

            let key = deriveKeyLegacyHKDF(from: passphrase, salt: salt)

            do {
                let sealedBox = try AES.GCM.SealedBox(combined: boxData)
                return try AES.GCM.open(sealedBox, using: key)
            } catch {
                throw ClientEncryptionError.authenticationMismatch
            }
        } else {
            throw ClientEncryptionError.invalidHeader
        }
    }
}
