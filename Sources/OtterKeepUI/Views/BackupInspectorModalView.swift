import SwiftUI
import AppKit
import OtterKeepCore

/// Backup inspector modal view.
/// Provides complete operational transparency: displays copied, cloned, unmodified, skipped, and error items with root causes.
public struct BackupInspectorModalView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var selectedTabBinding: Binding<String> {
        Binding(
            get: { appState.inspectorSelectedTab },
            set: { appState.inspectorSelectedTab = $0 }
        )
    }

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { appState.inspectorSearchQuery },
            set: { appState.inspectorSearchQuery = $0 }
        )
    }

    private var summary: BackupSessionSummary? {
        appState.lastSessionSummary ?? appState.progressState.lastSummary
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Tab / Segment selector
            tabSelectorView

            // Content
            Group {
                switch appState.inspectorSelectedTab {
                case "summary":
                    overviewTabView
                case "skipped":
                    skippedItemsTabView
                case "errors":
                    errorsTabView
                default:
                    overviewTabView
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Bottom toolbar
            footerView
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 560, idealHeight: 620)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 16) {
            OtterKeepLogoView(size: 48, withGlow: true, withBorder: true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(L10n.t(.inspectorTitle))
                        .font(.title2.bold())

                    statusBadge
                }

                if let sum = summary {
                    Text("\(sum.profileName) • Snapshot: \(sum.snapshotId)")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.t(.inspectorSubtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                appState.showInspectorModal = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(.closeButton))
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var statusBadge: some View {
        let isError = (summary?.errorCount ?? appState.progressState.errorCount) > 0
        let isWarning = (summary?.skippedCount ?? appState.progressState.skippedCount) > 0

        let title: String
        let color: Color
        let icon: String

        if isError {
            title = L10n.t(.phaseFailed)
            color = OtterTheme.statusError
            icon = "exclamationmark.octagon.fill"
        } else if isWarning {
            title = L10n.t(.lastBackupWarning)
            color = OtterTheme.statusWarning
            icon = "exclamationmark.triangle.fill"
        } else {
            title = L10n.t(.lastBackupSuccess)
            color = OtterTheme.statusGreen
            icon = "checkmark.seal.fill"
        }

        return HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.subheadline.bold())
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }

    // MARK: - Tab Selector

    private var tabSelectorView: some View {
        HStack {
            let errorCount = summary?.errorCount ?? appState.progressState.errorCount
            let skippedCount = summary?.skippedCount ?? appState.progressState.skippedCount

            Picker("", selection: selectedTabBinding) {
                Text(L10n.t(.inspectorTabSummary)).tag("summary")
                Text("\(L10n.t(.inspectorTabSkipped)) (\(skippedCount))").tag("skipped")
                Text("\(L10n.t(.inspectorTabErrors)) (\(errorCount))").tag("errors")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    // MARK: - Tab 1: Overview

    private var overviewTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 4 Primary Metric Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metricCard(
                        title: L10n.t(.telemetryCopied),
                        value: L10n.format(.unitCountFormat, summary?.copiedCount ?? appState.progressState.copiedCount),
                        detail: formatBytes(summary?.copiedBytes ?? appState.progressState.copiedBytes),
                        icon: "arrow.down.doc.fill",
                        color: OtterTheme.statusGreen
                    )

                    metricCard(
                        title: L10n.t(.telemetryCloned),
                        value: L10n.format(.unitCountFormat, summary?.clonedCount ?? appState.progressState.clonedCount),
                        detail: L10n.t(.cowBadgeSnapshotTarget),
                        icon: "link.badge.plus",
                        color: OtterTheme.cyberTeal
                    )

                    metricCard(
                        title: L10n.t(.telemetrySkipped),
                        value: L10n.format(.unitCountFormat, summary?.skippedCount ?? appState.progressState.skippedCount),
                        detail: L10n.t(.excludeRulesTitle),
                        icon: "hand.raised.fill",
                        color: OtterTheme.statusWarning
                    )

                    metricCard(
                        title: L10n.t(.telemetryErrors),
                        value: L10n.format(.unitCountFormat, summary?.errorCount ?? appState.progressState.errorCount),
                        detail: (summary?.errorCount ?? appState.progressState.errorCount) == 0 ? L10n.t(.inspectorNoErrorsNotice) : L10n.t(.phaseFailed),
                        icon: "xmark.octagon.fill",
                        color: (summary?.errorCount ?? appState.progressState.errorCount) == 0 ? OtterTheme.statusNeutral : OtterTheme.statusError
                    )
                }

                // Duration and transfer metrics
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.t(.inspectorOperationalParams))
                        .font(.title3.bold())

                    HStack(spacing: 24) {
                        if let sum = summary {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.t(.inspectorDuration))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f s", sum.durationSeconds))
                                    .font(.body.bold().monospacedDigit())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.t(.inspectorAverageSpeed))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                let speedMB = sum.averageSpeedBytesPerSecond / (1024 * 1024)
                                Text(String(format: "%.2f MB/s", speedMB))
                                    .font(.body.bold().monospacedDigit())
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.t(.inspectorTotalScanned))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                Text("\(sum.totalScannedFiles) \(L10n.t(.snapshotFilesCount)) (\(formatBytes(sum.totalScannedBytes)))")
                                    .font(.body.bold().monospacedDigit())
                            }
                        } else {
                            Text(L10n.t(.inspectorInProgressNotice))
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }

                // APFS integrity and safety confirmation
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title2)
                        .foregroundStyle(OtterTheme.cyberTeal)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.inspectorDataIntegrityTitle))
                            .font(.body.bold())
                        Text(L10n.t(.inspectorDataIntegrityDesc))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OtterTheme.cyberTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(OtterTheme.cyberTeal.opacity(0.2), lineWidth: 1)
                )
            }
            .padding()
        }
    }

    // MARK: - Tab 2: Kihagyott Elemek (Okokkal)

    private var skippedItemsTabView: some View {
        let items = (summary?.skippedItems ?? appState.progressState.skippedItems).filter { item in
            appState.inspectorSearchQuery.isEmpty ||
            item.relativePath.localizedCaseInsensitiveContains(appState.inspectorSearchQuery) ||
            item.reason.localizedCaseInsensitiveContains(appState.inspectorSearchQuery)
        }

        return VStack(spacing: 10) {
            // Filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.t(.searchPlaceholder), text: searchQueryBinding)
                    .textFieldStyle(.plain)
                if !appState.inspectorSearchQuery.isEmpty {
                    Button { appState.inspectorSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t(.clearSearchButton))
                }
            }
            .padding(8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.top, 8)

            if items.isEmpty {
                ContentUnavailableView(
                    L10n.t(.inspectorNoErrorsNotice),
                    systemImage: "checkmark.circle",
                    description: Text(L10n.t(.logEmptyDesc))
                )
            } else {
                List(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.isPermissionError ? "lock.fill" : "nosign")
                            .foregroundStyle(item.isPermissionError ? OtterTheme.statusError : OtterTheme.statusWarning)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.relativePath)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            HStack(spacing: 8) {
                                Text(item.isPermissionError ? "TCC / Permission" : "Excluded")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background((item.isPermissionError ? Color.red : Color.orange).opacity(0.15), in: Capsule())
                                    .foregroundStyle(item.isPermissionError ? Color.red : Color.orange)

                                Text(item.reason)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.body)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t(.revealInFinderButton))
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Tab 3: Errors & Remediation Guide

    private var errorsTabView: some View {
        let errors = (summary?.errorItems ?? appState.progressState.errorItems).filter { err in
            appState.inspectorSearchQuery.isEmpty ||
            err.relativePath.localizedCaseInsensitiveContains(appState.inspectorSearchQuery) ||
            err.errorMessage.localizedCaseInsensitiveContains(appState.inspectorSearchQuery)
        }

        return VStack(spacing: 12) {
            if errors.isEmpty {
                ContentUnavailableView(
                    L10n.t(.inspectorNoErrorsNotice),
                    systemImage: "checkmark.seal.fill",
                    description: Text(L10n.t(.inspectorNoErrorsNotice))
                        .font(.body)
                )
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(OtterTheme.statusError)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.inspectorPermissionWarningTitle))
                            .font(.title3.bold())
                        Text(L10n.t(.inspectorPermissionWarningDesc))
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Button(L10n.t(.inspectorFullDiskAccessButton)) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.body)
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(OtterTheme.statusError.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                List(errors) { errorItem in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(OtterTheme.statusError)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(errorItem.relativePath)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Text(errorItem.errorMessage)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(OtterTheme.statusError)
                        }

                        Spacer()

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([errorItem.url])
                        } label: {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.body)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t(.revealInFinderButton))
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Bottom Toolbar

    private var footerView: some View {
        HStack {
            Button {
                appState.activeNavigation = .logs
                appState.showInspectorModal = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                    Text(L10n.t(.inspectorOpenLogsButton))
                        .font(.body)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()

            Button(L10n.t(.inspectorCloseButton)) {
                appState.showInspectorModal = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func metricCard(title: String, value: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(detail)
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
