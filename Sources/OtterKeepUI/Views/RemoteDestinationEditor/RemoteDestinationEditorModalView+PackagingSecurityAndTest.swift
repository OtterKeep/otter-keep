import SwiftUI
import OtterKeepCore

extension RemoteDestinationEditorModalView {
    private var archivePackagingBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorArchivePackagingEnabled }, set: { appState.destinationEditorArchivePackagingEnabled = $0 })
    }

    private var isClientEncryptionBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorIsClientEncryptionEnabled }, set: { appState.destinationEditorIsClientEncryptionEnabled = $0 })
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorIsEnabled }, set: { appState.destinationEditorIsEnabled = $0 })
    }

    // MARK: - Section 3: Archive Packaging (Tar.Zst / Tar.Gz)
    var archivePackagingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(OtterTheme.otterAmber)
                        Text(L10n.t(.archivePackagingSectionTitle))
                            .font(.caption.bold())
                    }
                    Text(L10n.t(.archivePackagingToggleDesc))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: archivePackagingBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }

            if appState.destinationEditorArchivePackagingEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.t(.archiveCompressionLevelLabel))
                            .font(.caption2.bold())
                        Spacer()
                        Text(String(format: L10n.t(.archiveCompressionLevelFormat), appState.destinationEditorArchiveCompressionLevel))
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(OtterTheme.otterAmber)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(appState.destinationEditorArchiveCompressionLevel) },
                            set: { appState.destinationEditorArchiveCompressionLevel = Int($0) }
                        ),
                        in: 1...9,
                        step: 1
                    )

                    HStack {
                        Text(L10n.t(.compressionFast))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L10n.t(.compressionRecommended))
                            .font(.caption2.bold())
                            .foregroundStyle(appState.destinationEditorArchiveCompressionLevel == 3 ? OtterTheme.otterAmber : .secondary)
                        Spacer()
                        Text(L10n.t(.compressionMaximum))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Section 4: Security & Options
    var securityOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(OtterTheme.oceanicTeal)
                        Text(L10n.t(.remoteDestEditorEncryptionTitle))
                            .font(.caption.bold())
                    }
                    Text(L10n.t(.remoteDestEditorEncryptionDesc))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: isClientEncryptionBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }

            Divider()

            HStack {
                Text(L10n.t(.remoteDestEditorEnabledToggle))
                    .font(.caption.weight(.medium))
                Spacer(minLength: 12)
                Toggle("", isOn: isEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Live Connection Test Banner
    @ViewBuilder
    var connectionTestBanner: some View {
        if appState.destinationEditorIsTesting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.t(.remoteDestEditorTesting))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else if let success = appState.destinationEditorTestSuccessMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OtterTheme.statusSuccess)
                Text(success)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OtterTheme.statusSuccess)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.statusSuccess.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OtterTheme.statusSuccess.opacity(0.3), lineWidth: 1)
            )
        } else if let error = appState.destinationEditorTestErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(OtterTheme.statusError)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(OtterTheme.statusError)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.statusError.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(OtterTheme.statusError.opacity(0.3), lineWidth: 1)
            )
        }
    }
}
