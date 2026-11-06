import Foundation
import CryptoKit
import CoreImage
import OtterKeepDomain

#if canImport(AppKit)
import AppKit
#endif

/// Service responsible for building the Emergency Kit metadata and recovery tokens from a backup profile.
public enum EmergencyKitBuilder: Sendable {

    /// Builds the structured `EmergencyKitMetadata` for a specific backup profile.
    /// - Parameters:
    ///   - profile: The backup profile to document.
    ///   - passphrase: The encryption passphrase set at creation time.
    ///   - includePassphrase: True if the user opted to embed the passphrase directly in the document.
    /// - Returns: Complete `EmergencyKitMetadata`.
    public static func buildMetadata(
        for profile: BackupProfile,
        passphrase: String? = nil,
        includePassphrase: Bool = false
    ) -> EmergencyKitMetadata {
        let effectivePassphrase = passphrase ?? KeychainManager.getPassphrase(for: profile.id)

        // Derive deterministic key fingerprint and salt indicator
        let secretMaterial = (effectivePassphrase ?? "") + profile.id.uuidString
        let fingerprintHash = SHA256.hash(data: Data(secretMaterial.utf8))
        let keyFingerprint = "SHA256:" + fingerprintHash.compactMap { String(format: "%02x", $0) }.prefix(8).joined().uppercased()

        let saltData = SHA256.hash(data: Data((profile.id.uuidString + "_salt").utf8))
        let saltHex = saltData.compactMap { String(format: "%02x", $0) }.prefix(16).joined()

        // Map secondary replication destinations (3-2-1 targets)
        var remoteDestinations: [EmergencyRemoteDestination] = []
        for dest in profile.copyJobConfig.destinations {
            let (endpoint, bucket): (String, String) = {
                switch dest.type {
                case .s3(let cfg):
                    return (cfg.endpoint, cfg.bucket)
                case .backblazeB2(let cfg):
                    return ("https://api.backblazeb2.com", cfg.bucketName)
                case .sftp(let cfg):
                    return (cfg.host + ":\(cfg.port)", cfg.remotePath)
                case .webdav(let cfg):
                    return (cfg.serverURL, cfg.destinationPath)
                case .smb(let cfg):
                    return (cfg.shareURL, cfg.subfolder)
                }
            }()

            remoteDestinations.append(
                EmergencyRemoteDestination(
                    name: dest.name,
                    serviceType: dest.type.typeDisplayName,
                    endpointOrHost: endpoint,
                    bucketOrPath: bucket,
                    isEncrypted: dest.isClientEncryptionEnabled
                )
            )
        }

        // Construct standardized terminal restore command
        let cliRestore = "otterkeep restore --profile \"\(profile.name)\" --target \"\(profile.destinationURL.path)\""

        // Construct standard recovery QR payload
        let qrPayload = "otterkeep://sanctuary-recover?id=\(profile.id.uuidString)&name=\(profile.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&fp=\(keyFingerprint)"

        return EmergencyKitMetadata(
            profileId: profile.id,
            profileName: profile.name,
            generatedAt: Date(),
            sourceDirectory: profile.sourceURL.path,
            destinationDescription: profile.destinationURL.path,
            encryptionAlgorithm: "OKENC2 (PBKDF2-HMAC-SHA256 600k + AES-256-GCM)",
            keyFingerprint: keyFingerprint,
            saltHex: saltHex,
            remoteDestinations: remoteDestinations,
            cliRestoreCommand: cliRestore,
            qrPayload: qrPayload,
            embeddedPassphrase: includePassphrase ? effectivePassphrase : nil
        )
    }

    /// Generates a high-contrast black-and-white QR code PNG image data from the given payload.
    /// - Parameters:
    ///   - payload: String data to encode in the QR matrix.
    ///   - targetDimension: Width and height of the generated image in pixels.
    /// - Returns: PNG Data representation of the QR code, or nil if generation failed.
    public static func generateQRCodePNGData(for payload: String, targetDimension: CGFloat = 300) -> Data? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputCIImage = filter.outputImage else { return nil }

        // Scale up the low-resolution QR code bitmap cleanly without interpolation blur
        let extent = outputCIImage.extent
        let scale = max(targetDimension / extent.width, targetDimension / extent.height)
        let transformed = outputCIImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }

        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}
