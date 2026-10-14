import SwiftUI
import AppKit
import OtterKeepCore

/// Overview and primary backup dashboard view for the currently selected folder profile,
/// featuring the visual APFS CoW pipeline, Apple-style storage gauge, and live telemetry.
public struct MainDashboardView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OtterTheme.spacing16) {
                if let profile = appState.selectedProfile {
                    // MARK: - Zone 1: Sanctuary Hero & Live Status (Top Priority)
                    if appState.isBackupRunning(for: profile.id) {
                        liveTelemetryHUD(for: profile)
                    } else {
                        sanctuaryHeroCard(for: profile)
                    }

                    // Live Replication Banner
                    if appState.isReplicationRunning {
                        liveReplicationBanner
                    }

                    // Hardware Redundancy Recommendation (SPOF)
                    if appState.volumeEvaluation?.isSameVolume == true {
                        spofRecommendationBanner()
                    }

                    // Profile Settings Locked Banner (While Active)
                    if appState.isBackupRunning(for: profile.id) {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title3)
                                .foregroundStyle(OtterTheme.otterAmber)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t(.profileLockedBannerTitle))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(OtterTheme.otterAmber)
                                Text(L10n.t(.profileLockedBannerMessage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .otterCard(padding: OtterTheme.spacing12)
                    }

                    // MARK: - Zone 2: Protection Pipeline & Storage Harmony
                    BackupPipelineView(
                        sourceURL: profile.sourceURL,
                        destinationURL: profile.destinationURL,
                        cowMode: appState.volumeEvaluation?.cowMode ?? .intraVolumeCoW,
                        isActive: appState.isBackupRunning(for: profile.id),
                        onSelectSource: { appState.selectSourceDirectory() },
                        onRevealSource: { NSWorkspace.shared.activateFileViewerSelecting([profile.sourceURL]) },
                        onSelectDestination: { appState.selectDestinationDirectory() },
                        onRevealDestination: { NSWorkspace.shared.activateFileViewerSelecting([profile.destinationURL]) }
                    )

                    // MARK: - Zone 3: Guardianship & Resilience
                    rule321ComplianceCard(profile: profile)

                    // Storage Capacity Depletion Forecast
                    StorageForecastCardView(appState: appState)

                    // Quick Statistics
                    quickStatsSection(profile: profile)

                } else {
                    VStack(spacing: 16) {
                        OttieSanctuaryMascotView(mood: .safe, size: 104)

                        VStack(spacing: 6) {
                            Text(L10n.t(.welcomeSanctuaryTitle))
                                .font(.title2.bold())
                            Text(L10n.t(.welcomeSanctuarySubtitle))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 460)
                        }

                        Button {
                            appState.resetNewProfileDraft()
                            appState.showNewProfileSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text(L10n.t(.createFirstProfileButton))
                            }
                            .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(OtterTheme.otterAmber)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .padding(32)
                    .otterCard()
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if appState.storageForecastReport == nil {
                appState.refreshStorageForecast()
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showDryRunModal },
            set: { appState.showDryRunModal = $0 }
        )) {
            if let summary = appState.dryRunSummary {
                DryRunModalView(appState: appState, summary: summary)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showLastBackupSummaryModal },
            set: { appState.showLastBackupSummaryModal = $0 }
        )) {
            if let summary = appState.selectedProfile.flatMap({ appState.lastStatusInfo(for: $0).lastSessionSummary }) ?? appState.lastSessionSummary {
                LastBackupSessionModalView(appState: appState, summary: summary)
            }
        }
    }

    private static let forecastDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    // MARK: - Sanctuary Hero Card
    private func sanctuaryMood(for profile: BackupProfile) -> SanctuaryMascotMood {
        let status = appState.lastStatusInfo(for: profile)
        let forecast = appState.storageForecastReport

        if forecast?.isQuotaExceeded == true || forecast?.healthStatus == .critical {
            return .danger
        }
        if let sum = status.lastSessionSummary, sum.errorCount > 0 {
            return .danger
        }
        if forecast?.healthStatus == .warning || !status.hasSnapshots {
            return .warning
        }
        return .safe
    }

    private func sanctuaryTitle(for mood: SanctuaryMascotMood) -> String {
        switch mood {
        case .safe: return L10n.t(.sanctuaryHeroTitle)
        case .warning: return L10n.t(.sanctuaryHeroWarningTitle)
        case .danger: return L10n.t(.sanctuaryHeroDangerTitle)
        }
    }

    private func colorForHealth(_ status: ForecastHealthStatus) -> Color {
        switch status {
        case .healthy: return OtterTheme.statusGreen
        case .moderate: return OtterTheme.oceanicTeal
        case .warning: return OtterTheme.statusWarning
        case .critical: return OtterTheme.statusError
        }
    }

    private func sanctuaryHeroCard(for profile: BackupProfile) -> some View {
        let status = appState.lastStatusInfo(for: profile)
        let mood = sanctuaryMood(for: profile)
        let forecast = appState.storageForecastReport

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                // Ottie mascot with dynamic emotional state
                OttieSanctuaryMascotView(mood: mood, size: 88)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(sanctuaryTitle(for: mood))
                            .font(OtterTheme.cardTitleFont)
                            .foregroundStyle(.primary)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(mood == .safe ? OtterTheme.statusGreen : (mood == .warning ? OtterTheme.otterAmber : OtterTheme.statusError))
                                .frame(width: 7, height: 7)
                            Text(status.displayStatusText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(mood == .safe ? OtterTheme.statusGreen : (mood == .warning ? OtterTheme.otterAmber : OtterTheme.statusError))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((mood == .safe ? OtterTheme.statusGreen : (mood == .warning ? OtterTheme.otterAmber : OtterTheme.statusError)).opacity(0.12), in: Capsule())
                    }

                    if status.hasSnapshots {
                        HStack(spacing: 8) {
                            Text(status.displayDetailText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("•")
                                .foregroundStyle(.tertiary)

                            Text(L10n.format(.profileStatusSnapshotsFormat, status.totalSnapshots))
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }
                    } else {
                        Text(L10n.t(.sanctuaryNeverBackedUp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // S.M.A.R.T. Drive Health & Mode Badge
                    let isDriveHealthy = appState.volumeEvaluation?.isTargetReadOnly != true &&
                                         status.lastSessionSummary?.errorCount == 0 &&
                                         forecast?.isQuotaExceeded != true

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: isDriveHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(isDriveHealthy ? OtterTheme.statusGreen : OtterTheme.statusWarning)
                            Text(isDriveHealthy ? L10n.t(.smartHeroHealthy) : L10n.t(.smartHeroWarning))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isDriveHealthy ? OtterTheme.statusGreen : OtterTheme.statusWarning)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((isDriveHealthy ? OtterTheme.statusGreen : OtterTheme.statusWarning).opacity(0.12), in: Capsule())

                        if profile.executionMode.isContinuous {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(OtterTheme.oceanicTeal)
                                Text(L10n.t(.executionModeContinuous))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(OtterTheme.oceanicTeal)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OtterTheme.oceanicTeal.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    if let sum = status.lastSessionSummary {
                        Button {
                            appState.showLastBackupSummaryModal = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: sum.errorCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(sum.errorCount == 0 ? OtterTheme.statusGreen : OtterTheme.statusWarning)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(sum.errorCount == 0 ? L10n.t(.lastBackupSuccess) : L10n.t(.lastBackupWarning))
                                        .font(.caption.bold())
                                    HStack(spacing: 4) {
                                        Text(String(format: "%.1fs", sum.durationSeconds))
                                        Text("•")
                                        Text(ByteCountFormatter.string(fromByteCount: sum.totalScannedBytes, countStyle: .file))
                                    }
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t(.lastBackupResultSubtitle))
                    }

                    HStack(spacing: 8) {
                        // Dry-Run Button
                        Button {
                            appState.performDryRun()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: appState.isDryRunRunning ? "arrow.triangle.2.circlepath" : "magnifyingglass")
                                    .symbolEffect(.rotate, isActive: appState.isDryRunRunning)
                                Text(appState.isDryRunRunning ? L10n.t(.analyzingProgress) : L10n.t(.quickDryRunAction))
                            }
                            .font(.callout.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .keyboardShortcut("d", modifiers: .command)
                        .disabled(appState.isBackupRunning(for: profile.id) || appState.isDryRunRunning)

                        // Backup Now / Stop Button
                        if appState.isBackupRunning(for: profile.id) {
                            Button(role: .destructive) {
                                appState.cancelBackup(for: profile.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "stop.circle.fill")
                                    Text(L10n.t(.stopBackupButton))
                                }
                                .font(.callout.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OtterTheme.statusError)
                            .controlSize(.regular)
                            .keyboardShortcut(".", modifiers: .command)
                        } else {
                            Button {
                                appState.startBackup(for: profile)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                    Text(L10n.t(.quickBackupAction))
                                }
                                .font(.callout.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OtterTheme.otterAmber)
                            .controlSize(.regular)
                            .keyboardShortcut("b", modifiers: .command)
                            .disabled(appState.isDryRunRunning)
                        }
                    }
                }
            }

            // Integrated Storage Forecast Telemetry Strip
            if let forecast = forecast {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.caption2)
                            .foregroundStyle(OtterTheme.otterAmber)
                        Text(forecast.formattedDailyGrowth)
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(OtterTheme.oceanicTeal)
                        Text(L10n.t(.forecastDailyGrowthLabel))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text("•")
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 4) {
                        Image(systemName: forecast.healthStatus.sfSymbol)
                            .font(.caption2)
                            .foregroundStyle(colorForHealth(forecast.healthStatus))
                        Text(forecast.formattedDepletionText)
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(colorForHealth(forecast.healthStatus))

                        if let fullDate = forecast.estimatedFullDate {
                            Text("(\(Self.forecastDateFormatter.string(from: fullDate)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        appState.refreshStorageForecast()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh Storage Forecast")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // Quota Exceeded alert banner if active
            if let forecast = forecast, forecast.isQuotaExceeded {
                HStack(spacing: OtterTheme.spacing8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(OtterTheme.statusError)
                    Text(L10n.t(.forecastQuotaExceededBanner))
                        .font(.caption.bold())
                        .foregroundStyle(OtterTheme.statusError)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OtterTheme.statusError.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            // Integrated Destination Storage Capacity Statistics
            if let capacity = appState.destinationStorageCapacity() {
                Divider()
                    .padding(.vertical, 2)

                StorageGaugeBar(
                    totalBytes: capacity.totalBytes,
                    backupBytes: appState.totalBackupSize(),
                    freeBytes: capacity.availableBytes,
                    title: L10n.t(.destinationFolderTitle),
                    subtitle: profile.destinationURL.lastPathComponent
                )
            }
        }
        .otterHeroCard(padding: 18)
        .onAppear {
            if appState.storageForecastReport == nil {
                appState.refreshStorageForecast()
            }
        }
    }

    // MARK: - Hardware Redundancy Recommendation Banner (SPOF)
    private func spofRecommendationBanner() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(OtterTheme.otterAmber)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(.spofBannerTitle))
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)

                Text(L10n.t(.spofBannerDesc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(OtterTheme.otterAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(OtterTheme.otterAmber.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 3-2-1 Compliance Card
    private func rule321ComplianceCard(profile: BackupProfile) -> some View {
        let compliance = appState.rule321Compliance
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: profile.copyJobConfig.isEnabled ? "shield.lefthalf.filled.badge.checkmark" : "shield.slash")
                .font(.title2)
                .foregroundStyle(compliance.color)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L10n.t(.rule321Title))
                        .font(.subheadline.bold())

                    Text(compliance.badgeText)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(compliance.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(compliance.color)
                }

                Text(L10n.t(.rule321Desc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if profile.copyJobConfig.isEnabled {
                Button {
                    appState.startReplication(for: profile)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.isReplicationRunning ? "arrow.triangle.2.circlepath" : "arrow.up.forward.circle")
                            .symbolEffect(.rotate, isActive: appState.isReplicationRunning)
                        Text(appState.isReplicationRunning ? L10n.t(.replicatingProgress) : L10n.t(.runReplicationButton))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isReplicationRunning)
            }
        }
        .otterCard()
    }

    // MARK: - Live Replication Banner
    private var liveReplicationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.up.fill")
                .font(.title3)
                .foregroundStyle(OtterTheme.oceanicTeal)
                .symbolEffect(.pulse)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.replicationProgressState.statusMessage)
                    .font(.subheadline.bold())
                if !appState.replicationProgressState.currentFile.isEmpty {
                    Text(appState.replicationProgressState.currentFile)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if appState.replicationProgressState.totalFiles > 0 {
                Text("\(appState.replicationProgressState.processedFiles)/\(appState.replicationProgressState.totalFiles)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(OtterTheme.oceanicTeal.opacity(0.1), in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                .stroke(OtterTheme.oceanicTeal.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Live Telemetry HUD
    private func liveTelemetryHUD(for profile: BackupProfile) -> some View {
        let progress = appState.progressState(for: profile.id)
        let isRunning = appState.isBackupRunning(for: profile.id)
        let progressValue: Double = {
            if progress.totalFiles > 0 {
                let processed = progress.copiedCount + progress.clonedCount + progress.skippedCount
                return Double(processed) / Double(progress.totalFiles)
            }
            return 0.0
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(OtterTheme.statusGreen)
                    }

                    Text(L10n.t(progress.phase.localizedKey))
                        .font(.headline)
                }

                Spacer()

                if progress.speedBytesPerSecond > 0 {
                    let formattedSpeed = ByteCountFormatter.string(fromByteCount: Int64(progress.speedBytesPerSecond), countStyle: .file)
                    Label("\(formattedSpeed)/s", systemImage: "bolt.fill")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(OtterTheme.oceanicTeal)
                }

                if progress.totalFiles > 0 {
                    let processed = progress.copiedCount + progress.clonedCount + progress.skippedCount
                    Text("\(processed) / \(progress.totalFiles) (\(Int(progressValue * 100))%)")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: progressValue)
                .progressViewStyle(.linear)

            HStack(spacing: 12) {
                Label("\(progress.copiedCount) \(L10n.t(.telemetryCopied))", systemImage: "arrow.down.doc.fill")
                    .foregroundStyle(OtterTheme.statusGreen)
                Label("\(progress.clonedCount) \(L10n.t(.telemetryCloned))", systemImage: "link.badge.plus")
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Label("\(progress.skippedCount) \(L10n.t(.telemetrySkipped))", systemImage: "hand.raised.fill")
                    .foregroundStyle(.secondary)
                if progress.errorCount > 0 {
                    Label("\(progress.errorCount) \(L10n.t(.telemetryErrors))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(OtterTheme.statusError)
                }
                Spacer()
            }
            .font(.caption.monospacedDigit())

            if !progress.currentItem.isEmpty {
                Text(progress.currentItem)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .otterCard()
    }
    // MARK: - 5. Quick Statistics
    private func quickStatsSection(profile: BackupProfile) -> some View {
        HStack(spacing: 14) {
            // Snapshots count
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.quickStatsSnapshotsTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.format(.itemCountUnitFormat, appState.snapshots.count))
                    .font(.title3.bold().monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)

            // Next scheduled run
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.quickStatsNextRunTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(profile.schedule.isEnabled ? appState.nextScheduledRunDescription : L10n.t(.scheduleNotScheduled))
                    .font(.title3.bold())
                    .foregroundStyle(profile.schedule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)

            // Exclusion rules
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.quickStatsActiveRulesTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.format(.quickStatsExcludeRulesCountFormat, profile.excludePatterns.count))
                    .font(.title3.bold().monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .otterCard(padding: OtterTheme.spacing12)
        }
        .frame(maxWidth: .infinity)
    }
}
