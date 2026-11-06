import SwiftUI
import QuickLook
import OtterKeepDomain
import OtterKeepCore

/// Visual diff and change log browser comparing files between two backup snapshots.
public struct SnapshotDiffView: View {
    public let appState: AppState

    private var searchQueryBinding: Binding<String> {
        Binding(
            get: { appState.diffSearchQuery },
            set: { appState.diffSearchQuery = $0 }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .medium
        return df
    }()

    public init(appState: AppState) {
        self.appState = appState
    }

    private var targetSnapshotBinding: Binding<String?> {
        Binding(
            get: { appState.selectedDiffTargetSnapshotId ?? appState.snapshots.first?.id },
            set: { newTarget in
                appState.selectedDiffTargetSnapshotId = newTarget
                appState.loadSnapshotDiff(targetId: newTarget, baseId: appState.selectedDiffBaseSnapshotId)
            }
        )
    }

    private var baseSnapshotBinding: Binding<String?> {
        Binding(
            get: { appState.selectedDiffBaseSnapshotId },
            set: { newBase in
                appState.selectedDiffBaseSnapshotId = newBase
                appState.loadSnapshotDiff(targetId: appState.selectedDiffTargetSnapshotId, baseId: newBase)
            }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Selector & Control Header
            diffControlsHeader

            Divider()

            // 2. Summary KPI Ribbon
            if let report = appState.snapshotDiffReport {
                summaryKPIRibbon(report: report)
                Divider()
            }

            // 3. Search & Filter Bar
            filterAndSearchBar

            Divider()

            // 4. Differential File List
            if appState.isLoadingDiff {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(L10n.t(.details))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = appState.snapshotDiffReport {
                let filteredItems = filterItems(report.items)
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.diffNoChanges),
                        systemImage: "checkmark.circle.fill",
                        description: Text(appState.diffSearchQuery.isEmpty ? "" : L10n.t(.searchAllSnapshotsEmpty))
                    )
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    diffItemsList(filteredItems)
                }
            } else {
                ContentUnavailableView(
                    L10n.t(.diffNoChanges),
                    systemImage: "square.split.2x2",
                    description: Text(L10n.t(.noProfileSelectedDesc))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if appState.snapshotDiffReport == nil {
                appState.loadSnapshotDiff()
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.showSideBySideDiffModal },
            set: { appState.showSideBySideDiffModal = $0 }
        )) {
            SideBySideDiffModalView(appState: appState)
        }
    }

    // MARK: - 1. Top Controls Header
    private var diffControlsHeader: some View {
        HStack(alignment: .center, spacing: OtterTheme.spacing16) {
            // Target Snapshot Picker
            VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                Text(L10n.t(.diffTargetSnapshotLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: targetSnapshotBinding) {
                    ForEach(appState.snapshots) { snap in
                        Text(Self.dateFormatter.string(from: snap.timestamp))
                            .tag(Optional(snap.id))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 200)
            }

            VStack(spacing: 0) {
                Text(" ").font(.caption)
                Image(systemName: "arrow.left")
                    .font(.callout.bold())
                    .foregroundStyle(OtterTheme.otterAmber)
            }

            // Base Snapshot Picker
            VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                Text(L10n.t(.diffBaseSnapshotLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: baseSnapshotBinding) {
                    Text(L10n.t(.diffPreviousSnapshot))
                        .tag(nil as String?)

                    Divider()

                    ForEach(appState.snapshots.filter { $0.id != appState.selectedDiffTargetSnapshotId }) { snap in
                        Text(Self.dateFormatter.string(from: snap.timestamp))
                            .tag(Optional(snap.id))
                    }
                }
                .labelsHidden()
                .frame(minWidth: 200)
            }

            Spacer()

            // Refresh Diff Button
            Button {
                appState.loadSnapshotDiff(
                    targetId: appState.selectedDiffTargetSnapshotId,
                    baseId: appState.selectedDiffBaseSnapshotId
                )
            } label: {
                Label(L10n.t(.diffCompareAction), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, OtterTheme.spacing16)
        .padding(.vertical, OtterTheme.spacing12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 2. Summary KPI Ribbon
    private func summaryKPIRibbon(report: SnapshotDiffReport) -> some View {
        HStack(spacing: OtterTheme.spacing20) {
            // Added Badge
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(OtterTheme.statusGreen)
                VStack(alignment: .leading, spacing: 1) {
                    Text("+\(report.addedCount) " + L10n.t(.diffTabAdded).lowercased())
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(OtterTheme.statusGreen)
                    Text(ByteCountFormatter.string(fromByteCount: report.addedBytes, countStyle: .file))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider().frame(height: 24)

            // Modified Badge
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(OtterTheme.otterAmber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("~\(report.modifiedCount) " + L10n.t(.diffTabModified).lowercased())
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(OtterTheme.otterAmber)
                    Text(ByteCountFormatter.string(fromByteCount: abs(report.modifiedBytes), countStyle: .file))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider().frame(height: 24)

            // Deleted Badge
            HStack(spacing: 6) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(OtterTheme.statusError)
                VStack(alignment: .leading, spacing: 1) {
                    Text("-\(report.deletedCount) " + L10n.t(.diffTabDeleted).lowercased())
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundStyle(OtterTheme.statusError)
                    Text(ByteCountFormatter.string(fromByteCount: report.deletedBytes, countStyle: .file))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Net Size Delta Pill
            HStack(spacing: 6) {
                Text(L10n.t(.diffNetChange))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let netStr = ByteCountFormatter.string(fromByteCount: abs(report.netBytesDelta), countStyle: .file)
                let sign = report.netBytesDelta >= 0 ? "+" : "-"
                Text("\(sign)\(netStr)")
                    .font(.caption.bold().monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(report.netBytesDelta >= 0 ? OtterTheme.statusGreen.opacity(0.15) : OtterTheme.otterAmber.opacity(0.15), in: Capsule())
                    .foregroundStyle(report.netBytesDelta >= 0 ? OtterTheme.statusGreen : OtterTheme.otterAmber)
            }
        }
        .padding(.horizontal, OtterTheme.spacing16)
        .padding(.vertical, OtterTheme.spacing8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - 3. Filter and Search Bar
    private var filterAndSearchBar: some View {
        HStack(spacing: OtterTheme.spacing12) {
            Picker("", selection: Binding(
                get: { appState.diffFilterType },
                set: { appState.diffFilterType = $0 }
            )) {
                Text(L10n.t(.diffTabAll)).tag(nil as DiffChangeType?)
                Text(L10n.t(.diffTabAdded)).tag(Optional(DiffChangeType.added))
                Text(L10n.t(.diffTabModified)).tag(Optional(DiffChangeType.modified))
                Text(L10n.t(.diffTabDeleted)).tag(Optional(DiffChangeType.deleted))
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(L10n.t(.searchPlaceholder), text: searchQueryBinding)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !appState.diffSearchQuery.isEmpty {
                    Button {
                        appState.diffSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(maxWidth: 240)
        }
        .padding(.horizontal, OtterTheme.spacing16)
        .padding(.vertical, OtterTheme.spacing8)
    }

    // MARK: - 4. Items List
    private func diffItemsList(_ items: [SnapshotDiffItem]) -> some View {
        List {
            ForEach(items) { item in
                diffItemRow(item)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func diffItemRow(_ item: SnapshotDiffItem) -> some View {
        HStack(spacing: 12) {
            // Status Icon
            statusIcon(for: item.changeType)
                .frame(width: 20)

            // File Type Icon
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(item.isDirectory ? OtterTheme.oceanicTeal : .secondary)

            // File Name & Parent Folder
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !item.parentDirectory.isEmpty {
                    Text(item.parentDirectory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            // Size Transition / Delta
            sizeChangeLabel(for: item)

            // Context Actions
            if item.changeType == .modified && !item.isDirectory {
                Button {
                    appState.openSideBySideDiff(for: item)
                } label: {
                    Image(systemName: "square.split.2x1")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(L10n.t(.diffSideBySideCompare))
            }

            if let record = item.newRecord ?? item.oldRecord {
                Button {
                    appState.selectedFile = record
                    appState.toggleQuickLook()
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Quick Look")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusIcon(for changeType: DiffChangeType) -> some View {
        switch changeType {
        case .added:
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(OtterTheme.statusGreen)
                .font(.headline)
        case .modified:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundStyle(OtterTheme.otterAmber)
                .font(.headline)
        case .deleted:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(OtterTheme.statusError)
                .font(.headline)
        case .unchanged:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
                .font(.headline)
        }
    }

    @ViewBuilder
    private func sizeChangeLabel(for item: SnapshotDiffItem) -> some View {
        switch item.changeType {
        case .added:
            let sizeStr = ByteCountFormatter.string(fromByteCount: max(0, item.sizeDelta), countStyle: .file)
            Text("+\(sizeStr)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OtterTheme.statusGreen)
                .lineLimit(1)
                .layoutPriority(1)
        case .deleted:
            let sizeStr = ByteCountFormatter.string(fromByteCount: abs(item.sizeDelta), countStyle: .file)
            Text("-\(sizeStr)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OtterTheme.statusError)
                .lineLimit(1)
                .layoutPriority(1)
        case .modified:
            if let oldRec = item.oldRecord, let newRec = item.newRecord {
                let oldStr = ByteCountFormatter.string(fromByteCount: oldRec.fileSize, countStyle: .file)
                let newStr = ByteCountFormatter.string(fromByteCount: newRec.fileSize, countStyle: .file)
                let sign = item.sizeDelta >= 0 ? "+" : ""
                let deltaStr = ByteCountFormatter.string(fromByteCount: abs(item.sizeDelta), countStyle: .file)
                Text("\(oldStr) → \(newStr) (\(sign)\(deltaStr))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OtterTheme.otterAmber)
                    .lineLimit(1)
                    .layoutPriority(1)
            } else {
                let deltaStr = ByteCountFormatter.string(fromByteCount: abs(item.sizeDelta), countStyle: .file)
                Text("~\(deltaStr)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(OtterTheme.otterAmber)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        case .unchanged:
            EmptyView()
        }
    }

    private func filterItems(_ items: [SnapshotDiffItem]) -> [SnapshotDiffItem] {
        items.filter { item in
            if let filter = appState.diffFilterType, item.changeType != filter {
                return false
            }
            if !appState.diffSearchQuery.isEmpty {
                return item.relativePath.localizedCaseInsensitiveContains(appState.diffSearchQuery)
            }
            return true
        }
    }
}
