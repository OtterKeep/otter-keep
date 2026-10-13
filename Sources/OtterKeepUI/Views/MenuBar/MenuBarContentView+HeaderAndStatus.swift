import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepStorage

extension MenuBarContentView {
    private var statusSummaryText: String {
        if appState.isPhotosBackupRunning {
            return "\(L10n.t(.navPhotosBackup)): " + appState.photosProgressState.phaseDescription
        } else if appState.isBackupRunning {
            return L10n.t(.menuBarStatusRunning)
        } else if appState.isReplicationRunning {
            return L10n.t(.menuBarReplicationRunning)
        } else {
            return L10n.t(.menuBarStatusIdle)
        }
    }

    // MARK: - Header
    var headerView: some View {
        HStack(spacing: 8) {
            OtterKeepLogoView(size: 26, withGlow: true, withBorder: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("OtterKeep")
                    .font(.body.bold())
                HStack(spacing: 5) {
                    Circle()
                        .fill(isAnyOperationRunning ? OtterTheme.otterAmber : OtterTheme.statusGreen)
                        .frame(width: 6, height: 6)
                    Text(statusSummaryText)
                        .font(.caption2)
                        .foregroundStyle(isAnyOperationRunning ? OtterTheme.otterAmber : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Quick Time Machine / Restore Explorer Shortcut Button
            Button {
                openRestoreExplorer()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OtterTheme.oceanicTeal)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarTimeMachine))

            // Quick Theme Switcher Button
            Button {
                cycleTheme()
            } label: {
                Image(systemName: appState.currentTheme.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarQuickTheme))

            // Settings Shortcut Button
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.t(.menuBarOpenSettings))
        }
    }

    // MARK: - Running Operation Banner
    var runningOperationBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)

                VStack(alignment: .leading, spacing: 1) {
                    Text(runningTitle)
                        .font(.caption.bold())
                        .foregroundStyle(OtterTheme.otterAmber)
                    Text(runningDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(role: .destructive) {
                    appState.cancelBackup()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                        Text(L10n.t(.stopBackupButton))
                    }
                    .font(.caption2.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(OtterTheme.statusError)
                .controlSize(.mini)
            }

            // Live Linear Progress & Telemetry
            if let fraction = runningProgressFraction {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(OtterTheme.otterAmber)

                    HStack {
                        Text("\(Int(fraction * 100))%")
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(OtterTheme.otterAmber)

                        if let speed = runningSpeedText {
                            Spacer()
                            Label(speed, systemImage: "bolt.fill")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }

                        if let metrics = runningMetricsText {
                            Spacer()
                            Text(metrics)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(OtterTheme.otterAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(OtterTheme.otterAmber.opacity(0.2), lineWidth: 1)
        )
    }

    private var runningProgressFraction: Double? {
        if appState.isPhotosBackupRunning {
            return appState.photosProgressState.progressFraction
        } else if appState.isBackupRunning {
            let prog = appState.progressState
            if prog.totalBytes > 0 {
                return min(1.0, max(0.0, Double(prog.processedBytes) / Double(prog.totalBytes)))
            } else if prog.totalFiles > 0 {
                let processed = prog.copiedCount + prog.clonedCount + prog.skippedCount
                return min(1.0, max(0.0, Double(processed) / Double(prog.totalFiles)))
            }
        }
        return nil
    }

    private var runningSpeedText: String? {
        if appState.isPhotosBackupRunning && appState.photosProgressState.currentSpeedBytesPerSecond > 0 {
            let spd = ByteCountFormatter.string(fromByteCount: Int64(appState.photosProgressState.currentSpeedBytesPerSecond), countStyle: .file)
            return "\(spd)/s"
        } else if appState.isBackupRunning && appState.progressState.speedBytesPerSecond > 0 {
            let spd = ByteCountFormatter.string(fromByteCount: Int64(appState.progressState.speedBytesPerSecond), countStyle: .file)
            return "\(spd)/s"
        }
        return nil
    }

    private var runningMetricsText: String? {
        if appState.isPhotosBackupRunning {
            if appState.photosProgressState.totalAssetsCount > 0 {
                return "\(appState.photosProgressState.processedAssetsCount)/\(appState.photosProgressState.totalAssetsCount)"
            }
        } else if appState.isBackupRunning {
            let prog = appState.progressState
            if prog.totalFiles > 0 {
                let processed = prog.copiedCount + prog.clonedCount + prog.skippedCount
                return "\(processed)/\(prog.totalFiles)"
            }
        }
        return nil
    }

    private var runningTitle: String {
        if appState.isPhotosBackupRunning {
            return L10n.t(.navPhotosBackup)
        } else if appState.isReplicationRunning {
            return L10n.t(.menuBarReplicationRunning)
        } else {
            let runningProfiles = appState.profiles.filter { appState.isBackupRunning(for: $0.id) }
            if runningProfiles.count == 1, let single = runningProfiles.first {
                return single.name
            } else if runningProfiles.count > 1 {
                return "\(L10n.t(.menuBarStatusRunning)) (\(runningProfiles.count))"
            }
            return L10n.t(.menuBarStatusRunning)
        }
    }

    private var runningDetail: String {
        if appState.isPhotosBackupRunning {
            return appState.photosProgressState.phaseDescription
        } else if appState.isBackupRunning {
            let item = appState.progressState.currentItem
            return item.isEmpty ? appState.progressState.phase.rawValue.capitalized : item
        } else {
            return ""
        }
    }

    // MARK: - Software Update Notice Banner
    func updateAvailableBanner(update: SoftwareUpdateInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(OtterTheme.otterAmber)

            Text(L10n.format(.settingsUpdateStatusAvailableFormat, update.version))
                .font(.caption2.bold())
                .lineLimit(1)

            Spacer()

            Button {
                openSettings()
            } label: {
                Text(L10n.t(.settingsDownloadInBrowser))
                    .font(.caption2.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(OtterTheme.otterAmber)
            .controlSize(.mini)
        }
        .padding(8)
        .background(OtterTheme.otterAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
