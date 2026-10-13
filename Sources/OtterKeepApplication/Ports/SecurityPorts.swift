import Foundation

/// Abstract security port for content hashing and bit-rot validation.
public protocol ChecksumPort: Sendable {
    /// Computes full SHA-256 cryptographic digest of a file.
    func computeSHA256(for fileURL: URL) throws -> String

    /// Computes fast sampling hash (head/mid/tail digest) for quick change checks.
    func computeSampleHash(for fileURL: URL) throws -> String?
}

/// Abstract security port for client-side encryption and decryption.
public protocol EncryptionPort: Sendable {
    /// Encrypts a source file to destination using the specified passphrase.
    func encryptFile(at source: URL, to destination: URL, passphrase: String) throws

    /// Decrypts a ciphertext file to plaintext destination using the specified passphrase.
    func decryptFile(at source: URL, to destination: URL, passphrase: String) throws
}
