import SwiftUI
import AppKit
import OtterKeepDomain
import OtterKeepCore

/// Printable and renderable A4 document layout for the OtterKeep Emergency Recovery Kit.
public struct EmergencyKitDocumentView: View {
    public let metadata: EmergencyKitMetadata

    public init(metadata: EmergencyKitMetadata) {
        self.metadata = metadata
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // MARK: - Header
            HStack(alignment: .top, spacing: 16) {
                OtterKeepLogoView(size: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text("OTTERKEEP DIGITAL SANCTUARY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(OtterTheme.oceanicTeal)

                    Text(L10n.t(.emergencyKitTitle))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.primary)

                    Text(L10n.t(.emergencyKitSubtitle))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("GENERATED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(metadata.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    Text("PROFILE ID: \(metadata.profileId.uuidString.prefix(8))...")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, 6)

            Divider()

            // MARK: - Profile & Storage Parameters
            VStack(alignment: .leading, spacing: 8) {
                Label("1. BACKUP PROFILE IDENTIFICATION", systemImage: "folder.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OtterTheme.otterAmber)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Profile Name:").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(metadata.profileName).font(.system(size: 11, weight: .semibold))
                    }
                    GridRow {
                        Text("Profile UUID:").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(metadata.profileId.uuidString).font(.system(size: 10, design: .monospaced))
                    }
                    GridRow {
                        Text("Source Path:").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(metadata.sourceDirectory).font(.system(size: 10, design: .monospaced))
                    }
                    GridRow {
                        Text("Destination:").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(metadata.destinationDescription).font(.system(size: 10, design: .monospaced))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }

            // MARK: - Cryptographic Blueprint
            VStack(alignment: .leading, spacing: 8) {
                Label("2. \(L10n.t(.emergencyKitSecuritySummary).uppercased())", systemImage: "lock.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OtterTheme.oceanicTeal)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("Cipher / Mode:").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(metadata.encryptionAlgorithm).font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    GridRow {
                        Text("Key Fingerprint:").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(metadata.keyFingerprint).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(OtterTheme.oceanicTeal)
                    }
                    GridRow {
                        Text("PBKDF2 Salt (Hex):").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(metadata.saltHex).font(.system(size: 10, design: .monospaced))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }

            // MARK: - Secret Passphrase Section
            VStack(alignment: .leading, spacing: 8) {
                Label("3. ENCRYPTION PASSPHRASE (SECRET)", systemImage: "key.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OtterTheme.statusError)

                if let pass = metadata.embeddedPassphrase, !pass.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pass)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange.opacity(0.4), lineWidth: 1))
                        Text(L10n.t(.emergencyKitIncludePasswordDesc))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t(.emergencyKitHandwriteNotice))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        // Handwriting block grid for manual pen entry
                        HStack(spacing: 4) {
                            ForEach(0..<20, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                    .frame(width: 22, height: 26)
                            }
                        }

                        HStack(spacing: 4) {
                            ForEach(20..<40, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                    .frame(width: 22, height: 26)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // MARK: - Offsite Secondary Replication Targets (if any)
            if !metadata.remoteDestinations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("4. 3-2-1 REMOTE OFFSITE REPLICATION TARGETS", systemImage: "cloud.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OtterTheme.oceanicTeal)

                    VStack(spacing: 4) {
                        ForEach(metadata.remoteDestinations, id: \.name) { dest in
                            HStack {
                                Text(dest.name).font(.system(size: 10, weight: .bold))
                                Spacer()
                                Text(dest.serviceType).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                Text("•")
                                Text(dest.endpointOrHost).font(.system(size: 9, design: .monospaced))
                                Text("•")
                                Text(dest.bucketOrPath).font(.system(size: 9, design: .monospaced))
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 6)
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // MARK: - Disaster Recovery Steps & QR Code
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("5. \(L10n.t(.emergencyKitRestoreSteps).uppercased())", systemImage: "arrow.clockwise.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(OtterTheme.otterAmber)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Install OtterKeep on the recovery Mac (brew install otterkeep).")
                        Text("2. Connect your backup drive or configure remote S3/B2 credentials.")
                        Text("3. Execute the CLI recovery command below in Terminal:")
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)

                    Text(metadata.cliRestoreCommand)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }

                Spacer()

                // Recovery QR Code
                VStack(spacing: 4) {
                    if let qrData = EmergencyKitBuilder.generateQRCodePNGData(for: metadata.qrPayload, targetDimension: 180),
                       let qrImage = NSImage(data: qrData) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                            .padding(4)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    }

                    Text("RECOVERY QR")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // MARK: - Footer Notice
            HStack {
                Text("OtterKeep v2.1 Sanctuary Engine • Store this document in a physically secure vault.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("CONFIDENTIAL")
                    .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(OtterTheme.otterAmber)
            }
        }
        .padding(32)
        .frame(width: 595, height: 842) // Strict A4 proportions (points)
        .background(Color.white)
        .environment(\.colorScheme, .light) // Emergency kit is always light-mode for clean printing
    }
}
