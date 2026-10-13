import SwiftUI
import AppKit
import Network
import OtterKeepCore
import OtterKeepStorage

/// Modal sheet for adding and editing remote 3-2-1 backup targets (S3 Cloud / SMB NAS).
public struct RemoteDestinationEditorModalView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var isS3: Bool {
        appState.destinationEditorTypeIndex == 0
    }

    private var headerIcon: String {
        switch appState.destinationEditorTypeIndex {
        case 0: return "icloud.and.arrow.up.fill"
        case 1: return "server.rack"
        case 2: return "network"
        case 3: return "terminal.fill"
        default: return "flame.fill"
        }
    }

    private var headerColor: Color {
        switch appState.destinationEditorTypeIndex {
        case 0: return OtterTheme.oceanicTeal
        case 1: return OtterTheme.otterAmber
        case 2: return OtterTheme.oceanicTeal
        case 3: return OtterTheme.accentPurple
        default: return OtterTheme.statusError
        }
    }

    private var canSave: Bool {
        let trimmedName = appState.destinationEditorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return false }

        switch appState.destinationEditorTypeIndex {
        case 0:
            return !appState.destinationEditorS3Endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !appState.destinationEditorS3Bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return !appState.destinationEditorSmbShareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2:
            return !appState.destinationEditorWebDAVURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 3:
            return !appState.destinationEditorSFTPHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !appState.destinationEditorSFTPUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 4:
            return !appState.destinationEditorB2KeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !appState.destinationEditorB2AppKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !appState.destinationEditorB2BucketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - Header
            headerView
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Divider()

            // MARK: - Form Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Destination Overview (Name & Type Selection)
                    destinationOverviewSection

                    // 2. Storage Backend Specific Form
                    switch appState.destinationEditorTypeIndex {
                    case 0:
                        s3ConfigurationCard
                    case 1:
                        smbConfigurationCard
                    case 2:
                        webdavConfigurationCard
                    case 3:
                        sftpConfigurationCard
                    default:
                        b2ConfigurationCard
                    }

                    // 3. Compressed Packaging Card
                    archivePackagingCard

                    // 4. Security & Options Card
                    securityOptionsCard

                    // 5. Live Connection Test Banner
                    connectionTestBanner
                }
                .padding(24)
            }
            .frame(maxHeight: 520)

            Divider()

            // MARK: - Footer Actions
            footerView
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: headerIcon)
                .font(.title2)
                .foregroundStyle(headerColor)
                .frame(width: 42, height: 42)
                .background(headerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.destinationEditorTargetId == nil ? L10n.t(.remoteDestEditorAddTitle) : L10n.t(.remoteDestEditorEditTitle))
                    .font(.title3.bold())
                Text(L10n.t(.remoteDestEditorSubtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.showRemoteDestinationEditorSheet = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer View
    private var footerView: some View {
        HStack(spacing: 12) {
            Button {
                appState.testDestinationEditorConnection()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                    Text(L10n.t(.remoteDestEditorTestButton))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.destinationEditorIsTesting || !canSave)

            if let targetId = appState.destinationEditorTargetId {
                Button(role: .destructive) {
                    appState.deleteDestinationEditor(destinationId: targetId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text(L10n.t(.delete))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer()

            Button(L10n.t(.cancel)) {
                appState.showRemoteDestinationEditorSheet = false
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .keyboardShortcut(.cancelAction)

            Button(appState.destinationEditorTargetId == nil ? L10n.t(.remoteDestEditorAddButton) : L10n.t(.save)) {
                appState.saveDestinationEditor()
            }
            .buttonStyle(.borderedProminent)
            .tint(OtterTheme.otterAmber)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }
}
