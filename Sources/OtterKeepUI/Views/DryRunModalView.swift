import SwiftUI
import OtterKeepCore

public struct DryRunModalView: View {
    public let appState: AppState
    public let summary: DryRunSummary

    public init(appState: AppState, summary: DryRunSummary) {
        self.appState = appState
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text(L10n.t(.dryRunTitle))
                            .font(.title2.bold())
                    }
                    Text("\(L10n.t(.sourceFolderTitle)): \(appState.selectedProfile?.sourceURL.path ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    appState.showDryRunModal = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(L10n.t(.closeButton))
                .buttonStyle(.plain)
            }

            // Metric Cards (HIG-compliant Grid)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    metricCard(
                        title: L10n.t(.dryRunTabAdded),
                        count: "\(summary.addedCount)",
                        detail: formatBytes(summary.addedBytes),
                        icon: "plus.circle.fill",
                        color: .green
                    )
                    metricCard(
                        title: L10n.t(.dryRunTabModified),
                        count: "\(summary.modifiedCount)",
                        detail: formatBytes(summary.modifiedBytes),
                        icon: "pencil.circle.fill",
                        color: .orange
                    )
                    metricCard(
                        title: L10n.t(.dryRunTabDeleted),
                        count: "\(summary.deletedCount)",
                        detail: L10n.t(.telemetrySkipped),
                        icon: "minus.circle.fill",
                        color: .red
                    )
                }
                GridRow {
                    metricCard(
                        title: L10n.t(.timelineUnmodifiedCoW),
                        count: "\(summary.unmodifiedCount)",
                        detail: L10n.t(.cowBadgeSnapshotTarget),
                        icon: "equal.circle.fill",
                        color: .blue
                    )
                    // Highlighted estimated storage demand card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "internaldrive.fill")
                                .foregroundStyle(.purple)
                            Text(L10n.t(.dryRunEstimatedStorage))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        Text(formatBytes(summary.estimatedNewBytes))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(.purple)
                        Text(L10n.t(.dryRunCoWGrowth))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )

                    metricCard(
                        title: L10n.t(.inspectorTotalScanned),
                        count: "\(summary.totalScannedFiles)",
                        detail: formatBytes(summary.totalScannedBytes),
                        icon: "doc.on.doc.fill",
                        color: .secondary
                    )
                }
            }

            // Category filter segmented control
            Picker("", selection: Binding(
                get: { appState.dryRunSelectedCategory },
                set: { appState.dryRunSelectedCategory = $0 }
            )) {
                Text("\(L10n.t(.dryRunTabAll)) (\(summary.addedCount + summary.modifiedCount + summary.deletedCount))").tag("all")
                Text("\(L10n.t(.dryRunTabAdded)) (\(summary.addedCount))").tag("added")
                Text("\(L10n.t(.dryRunTabModified)) (\(summary.modifiedCount))").tag("modified")
                Text("\(L10n.t(.dryRunTabDeleted)) (\(summary.deletedCount))").tag("deleted")
            }
            .pickerStyle(.segmented)

            // Changed paths list
            VStack(alignment: .leading, spacing: 6) {
                if visiblePaths.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.dryRunNoChangesInTab),
                        systemImage: "checkmark.circle",
                        description: Text(L10n.t(.dryRunNoChangesInTab))
                    )
                    .frame(height: 180)
                } else {
                    List {
                        ForEach(visiblePaths, id: \.path) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .foregroundStyle(item.color)
                                    .frame(width: 16)
                                Text(item.path)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(item.badge)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.color.opacity(0.15), in: Capsule())
                                    .foregroundStyle(item.color)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }
            }

            // Bottom action buttons bar
            HStack {
                Button(L10n.t(.cancel)) {
                    appState.showDryRunModal = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    appState.showDryRunModal = false
                    appState.startBackup()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text(L10n.t(.startBackupButton))
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 660, minHeight: 520, idealHeight: 560)
    }

    private struct DisplayItem: Identifiable {
        let id = UUID()
        let path: String
        let badge: String
        let icon: String
        let color: Color
    }

    private var visiblePaths: [DisplayItem] {
        var items: [DisplayItem] = []
        let cat = appState.dryRunSelectedCategory
        let newBadge = L10n.t(.dryRunTabAdded)
        let modifiedBadge = L10n.t(.dryRunTabModified)
        let deletedBadge = L10n.t(.dryRunTabDeleted)

        if cat == "all" || cat == "added" {
            items.append(contentsOf: summary.addedPaths.map {
                DisplayItem(path: $0, badge: newBadge, icon: "plus.circle.fill", color: .green)
            })
        }
        if cat == "all" || cat == "modified" {
            items.append(contentsOf: summary.modifiedPaths.map {
                DisplayItem(path: $0, badge: modifiedBadge, icon: "pencil.circle.fill", color: .orange)
            })
        }
        if cat == "all" || cat == "deleted" {
            items.append(contentsOf: summary.deletedPaths.map {
                DisplayItem(path: $0, badge: deletedBadge, icon: "minus.circle.fill", color: .red)
            })
        }
        return items
    }

    private func metricCard(title: String, count: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            Text(count)
                .font(.title3.bold().monospacedDigit())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
