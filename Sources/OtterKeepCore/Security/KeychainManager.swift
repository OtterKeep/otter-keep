import Foundation
import Security
import LocalAuthentication
import os

/// Thread-safe manager storing and retrieving encryption passphrases from the native macOS Keychain.
public enum KeychainManager {
    private static let serviceName = "com.otterkeep.encryption"
    private static let logger = Logger(subsystem: "com.otterkeep", category: "Keychain")

    /// Stores or updates an encryption passphrase in the Keychain for a specific profile ID.
    /// - Parameters:
    ///   - passphrase: The secret string.
    ///   - profileId: Backup profile UUID.
    ///   - requireSecureEnclave: Whether to wrap the item with hardware Secure Enclave user-presence protection.
    public static func savePassphrase(_ passphrase: String, for profileId: UUID, requireSecureEnclave: Bool = false) throws {
        guard let data = passphrase.data(using: .utf8) else { return }
        let account = profileId.uuidString

        // First remove any existing item
        deletePassphrase(for: profileId)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        if requireSecureEnclave {
            var accessError: Unmanaged<CFError>?
            if let accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                .userPresence,
                &accessError
            ) {
                query[kSecAttrAccessControl as String] = accessControl
            } else {
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to save passphrase to Keychain: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to store passphrase in macOS Keychain [Status: \(status)]"
            ])
        }
        logger.info("Passphrase securely stored in Keychain for profile: \(account) (SecureEnclave: \(requireSecureEnclave))")
    }

    /// Retrieves an encryption passphrase from the Keychain for a specific profile ID.
    /// - Parameters:
    ///   - profileId: Backup profile UUID.
    ///   - prompt: Optional user-visible prompt when Secure Enclave biometrics are required.
    /// - Returns: Passphrase string if found, nil otherwise.
    public static func getPassphrase(for profileId: UUID, prompt: String? = nil) -> String? {
        let account = profileId.uuidString
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let prompt = prompt {
            let authContext = LAContext()
            authContext.localizedReason = prompt
            query[kSecUseAuthenticationContext as String] = authContext
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    /// Deletes an encryption passphrase from the Keychain for a specific profile ID.
    /// - Parameter profileId: Backup profile UUID.
    public static func deletePassphrase(for profileId: UUID) {
        let account = profileId.uuidString
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Arbitrary Remote Credential & Secret Key Storage

    public static let remoteSecretsService = "com.otterkeep.remotesecrets"

    /// Stores a secret token, API key, or password in the Keychain for a specific account key.
    public static func saveSecret(_ secret: String, for account: String, service: String = remoteSecretsService) throws {
        guard let data = secret.data(using: .utf8) else { return }
        deleteSecret(for: account, service: service)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Failed to save remote secret to Keychain: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to store secret in macOS Keychain [Status: \(status)]"
            ])
        }
    }

    /// Retrieves a secret token, API key, or password from the Keychain with smart prefix fallback.
    public static func getSecret(for account: String, service: String = remoteSecretsService) -> String? {
        if let direct = getDirectSecret(for: account, service: service) {
            return direct
        }

        // Fallback variants to tolerate key mismatches (e.g. "smb_<uuid>" vs "<uuid>")
        var candidates: [String] = []
        if account.hasPrefix("smb_") {
            candidates.append(String(account.dropFirst(4)))
        } else if account.hasPrefix("s3_") {
            candidates.append(String(account.dropFirst(3)))
        } else {
            candidates.append("smb_\(account)")
            candidates.append("s3_\(account)")
        }

        for candidate in candidates {
            if let found = getDirectSecret(for: candidate, service: service) {
                return found
            }
        }
        return nil
    }

    private static func getDirectSecret(for account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    /// Deletes a stored secret from the Keychain.
    public static func deleteSecret(for account: String, service: String = remoteSecretsService) {
        var targets = [account]
        if account.hasPrefix("smb_") {
            targets.append(String(account.dropFirst(4)))
        } else if account.hasPrefix("s3_") {
            targets.append(String(account.dropFirst(3)))
        } else {
            targets.append("smb_\(account)")
            targets.append("s3_\(account)")
        }

        for target in targets {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: target
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

