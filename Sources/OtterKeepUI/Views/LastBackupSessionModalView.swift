//
//  LastBackupSessionModalView.swift
//  OtterKeepUI
//
//  Modal sheet displaying the comprehensive outcome of the active profile's
//  latest backup session.
//

import SwiftUI
import AppKit
import OtterKeepCore

/// Modal view displaying the detailed operational result of the active profile's latest backup.
public struct LastBackupSessionModalView: View {
    public let appState: AppState
    public let summary: BackupSessionSummary

    public init(appState: AppState, summary: BackupSessionSummary) {
        self.appState = appState
        self.summary = summary
    }

    private var isSuccess: Bool {
        summary.errorCount == 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(isSuccess ? OtterTheme.statusGreen : OtterTheme.statusWarning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.lastBackupResultTitle))
                        .font(.headline.bold())
                    Text(L10n.t(.lastBackupResultSubtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.t(.okDone)) {
                    appState.showLastBackupSummaryModal = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Headline Banner
                    HStack(spacing: 14) {
                        Image(systemName: isSuccess ? "shield.checkmark.fill" : "shield.lefthalf.filled.trianglebadge.exclamationmark")
                            .font(.system(size: 32))
                            .foregroundStyle(isSuccess ? OtterTheme.statusGreen : OtterTheme.statusWarning)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isSuccess ? L10n.t(.lastBackupSuccess) : L10n.t(.lastBackupWarning))
                                .font(.title3.bold())

                            Text(L10n.format(.sessionSummaryStatsFormat, summary.totalScannedFiles, summary.copiedCount, summary.clonedCount, summary.durationSeconds))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((isSuccess ? OtterTheme.statusGreen : OtterTheme.statusWarning).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke((isSuccess ? OtterTheme.statusGreen : OtterTheme.statusWarning).opacity(0.2), lineWidth: 1)
                    )

                    // Telemetry Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metricBox(
                            title: L10n.t(.telemetryCopied),
                            value: "\(summary.copiedCount)",
                            subvalue: ByteCountFormatter.string(fromByteCount: summary.copiedBytes, countStyle: .file),
                            color: OtterTheme.statusGreen,
                            icon: "arrow.down.doc.fill"
                        )

                        metricBox(
                            title: L10n.t(.telemetryCloned),
                            value: "\(summary.clonedCount)",
                            subvalue: ByteCountFormatter.string(fromByteCount: summary.clonedBytes, countStyle: .file),
                            color: OtterTheme.oceanicTeal,
                            icon: "link.badge.plus"
                        )

                        metricBox(
                            title: L10n.t(.telemetrySkipped),
                            value: "\(summary.skippedCount)",
                            subvalue: "Unmodified",
                            color: .secondary,
                            icon: "hand.raised.fill"
                        )

                        metricBox(
                            title: "Scanned Files",
                            value: "\(summary.totalScannedFiles)",
                            subvalue: ByteCountFormatter.string(fromByteCount: summary.totalScannedBytes, countStyle: .file),
                            color: .primary,
                            icon: "doc.text.magnifyingglass"
                        )

                        metricBox(
                            title: "Duration",
                            value: String(format: "%.1fs", summary.durationSeconds),
                            subvalue: "Elapsed time",
                            color: OtterTheme.otterAmber,
                            icon: "clock.fill"
                        )

                        metricBox(
                            title: L10n.t(.telemetryErrors),
                            value: "\(summary.errorCount)",
                            subvalue: summary.errorCount == 0 ? "Clean pass" : "Attention needed",
                            color: summary.errorCount == 0 ? OtterTheme.statusGreen : OtterTheme.statusError,
                            icon: summary.errorCount == 0 ? "checkmark.seal.fill" : "exclamationmark.octagon.fill"
                        )
                    }

                    // Target Snapshot Path
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t(.diffTargetSnapshotLabel))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(summary.snapshotId)
                            .font(.caption.monospaced())
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 580, idealWidth: 620, minHeight: 400, idealHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func metricBox(title: String, value: String, subvalue: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(subvalue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}
