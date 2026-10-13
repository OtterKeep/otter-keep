import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepStorage

extension MenuBarContentView {
    // MARK: - Apple Photos Backup Card
    var photosBackupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(L10n.t(.navPhotosBackup))
                        .font(.caption.bold())
                } icon: {
                    Image(systemName: "photo.stack.fill")
                        .font(.caption)
                        .foregroundStyle(OtterTheme.otterAmber)
                }

                Spacer()

                if appState.isPhotosBackupRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else if appState.photosLibraryTotalCount > 0 {
                    Text(L10n.format(.assetsCountUnitFormat, appState.photosLibraryTotalCount))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                appState.startPhotosBackup()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.isPhotosBackupRunning ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                    Text(appState.isPhotosBackupRunning ? L10n.t(.photosBackupRunningButton) : L10n.t(.photosStartBackupButton))
                }
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isPhotosBackupRunning)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Storage Glance Card
    @ViewBuilder
    var storageGlanceCard: some View {
        if let profile = appState.selectedProfile {
            let isReachable = appState.isDestinationReachable(for: profile)
            let isRemovable = appState.isDestinationRemovable(for: profile)
            let volName = appState.destinationVolumeName(for: profile) ?? profile.destinationURL.lastPathComponent

            if !isReachable {
                // Destination offline / unmounted notice
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(OtterTheme.statusWarning)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(volName)
                            .font(.caption2.bold())
                        Text(L10n.t(.menuBarExternalVolumeDisconnected))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(8)
                .background(OtterTheme.statusWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else if let capacity = appState.destinationStorageCapacity() {
                let usedBytes = max(0, capacity.totalBytes - capacity.availableBytes)
                let usedFraction = capacity.totalBytes > 0 ? Double(usedBytes) / Double(capacity.totalBytes) : 0.0
                let gaugeColor: Color = {
                    if usedFraction > 0.9 {
                        return OtterTheme.statusError
                    } else if usedFraction > 0.8 {
                        return OtterTheme.statusWarning
                    } else {
                        return OtterTheme.oceanicTeal
                    }
                }()

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label {
                            Text(volName)
                                .font(.caption2.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: isRemovable ? "externaldrive.fill" : "internaldrive.fill")
                                .font(.caption2)
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }

                        Spacer()

                        Text(ByteCountFormatter.string(fromByteCount: capacity.availableBytes, countStyle: .file) + " " + L10n.t(.storageFreeLabel))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)

                        if isRemovable {
                            Button {
                                appState.ejectDestinationVolume(for: profile)
                            } label: {
                                Image(systemName: "eject.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t(.menuBarEjectVolume))
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 4)
                            Capsule()
                                .fill(gaugeColor)
                                .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, usedFraction))), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
