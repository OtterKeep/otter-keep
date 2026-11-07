import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepDomain

/// Modal sheet displaying point-in-time snapshot versions of a specific file with Quick Look and in-place restore.
public struct FileVersionHistoryModalView: View {
    public let appState: AppState

    private var showConfirmDialogBinding: Binding<Bool> {
        Binding(
            get: { appState.showConfirmInPlaceRestore },
            set: { appState.showConfirmInPlaceRestore = $0 }
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

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if appState.isLoadingFileVersions {
                loadingView
            } else if appState.activeVersionHistoryRecords.isEmpty {
                emptyStateView
            } else {
                versionsListView
            }

            Divider()
            footerActionsView
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 480, idealHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            QuickLookCoordinator.shared.startKeyboardMonitoring(for: appState)
        }
        .onDisappear {
            QuickLookCoordinator.shared.stopKeyboardMonitoring()
        }
        .onKeyPress(.space) {
            triggerQuickLookForSelected()
            return .handled
        }
        .confirmationDialog(
            L10n.t(.confirmRestoreTitle),
            isPresented: showConfirmDialogBinding,
            titleVisibility: .visible,
            presenting: appState.versionForInPlaceRestore
        ) { version in
            Button(L10n.t(.confirmRestoreOverwrite), role: .destructive) {
                appState.restoreFileInPlace(version: version, collision: .overwrite)
            }
            Button(L10n.t(.confirmRestoreKeepBoth)) {
                appState.restoreFileInPlace(version: version, collision: .keepBoth)
            }
            Button(L10n.t(.cancel), role: .cancel) {
                appState.versionForInPlaceRestore = nil
            }
        } message: { version in
            let dateStr = Self.dateFormatter.string(from: version.snapshot.timestamp)
            let destPath = appState.activeVersionHistoryFile?.path ?? ""
            Text(L10n.format(.confirmRestoreMessage, dateStr, destPath))
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 14) {
            if let fileURL = appState.activeVersionHistoryFile {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: "doc.text.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(appState.activeVersionHistoryFile?.lastPathComponent ?? L10n.t(.fileVersionsHistoryTitle))
                        .font(.headline)
                        .lineLimit(1)

                    if let profile = appState.activeVersionHistoryProfile {
                        Text(profile.name)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(appState.activeVersionHistoryFile?.path ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                appState.showFileVersionHistoryModal = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityLabel(L10n.t(.closeButton))
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
            Text(L10n.t(.fileVersionsHistorySubtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            L10n.t(.noMatchingFilesFound),
            systemImage: "clock.badge.questionmark",
            description: Text(L10n.t(.noVersionsFoundForFile))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Versions List

    private var versionsListView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(Array(appState.activeVersionHistoryRecords.enumerated()), id: \.element.snapshot.id) { index, item in
                    let isSelected = appState.selectedFileVersionHistoryRecord?.snapshot.id == item.snapshot.id
                    let changeState = computeStateChange(at: index, in: appState.activeVersionHistoryRecords)

                    versionCard(item: item, changeState: changeState, isSelected: isSelected)
                        .onTapGesture {
                            appState.selectedFileVersionHistoryRecord = item
                        }
                }
            }
            .padding(16)
        }
    }

    private func versionCard(
        item: (snapshot: SnapshotRecord, file: FileCatalogRecord),
        changeState: StateChangeInfo,
        isSelected: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.dateFormatter.string(from: item.snapshot.timestamp))
                        .font(.body.bold())
                    Text(L10n.format(.snapshotPathLabelFormat, item.snapshot.snapshotPath))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // State badge
                HStack(spacing: 4) {
                    Image(systemName: changeState.icon)
                    Text(changeState.label)
                }
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(changeState.color.opacity(0.15), in: Capsule())
                .foregroundStyle(changeState.color)
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.fileSizeLabel))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatBytes(item.file.fileSize))
                        .font(.caption.bold().monospacedDigit())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.modificationDateLabel))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Self.dateFormatter.string(from: item.file.modificationTime))
                        .font(.caption)
                }

                if let hash = item.file.checksum {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.sha256IntegrityLabel))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(hash.prefix(12)) + "...")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Actions for this card
                HStack(spacing: 8) {
                    Button {
                        appState.selectedFileVersionHistoryRecord = item
                        triggerQuickLookForSelected()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                            Text(L10n.t(.previewSpaceButton))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appState.versionForInPlaceRestore = item
                        appState.showConfirmInPlaceRestore = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward")
                            Text(L10n.t(.restoreThisVersionButton))
                        }
                        .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
        )
    }

    // MARK: - Footer Actions

    private var footerActionsView: some View {
        HStack {
            Text("\(appState.activeVersionHistoryRecords.count) \(L10n.t(.versionsCountLabel))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.t(.cancel)) {
                appState.showFileVersionHistoryModal = false
            }
            .keyboardShortcut(.cancelAction)

            if let selected = appState.selectedFileVersionHistoryRecord {
                Button {
                    appState.versionForInPlaceRestore = selected
                    appState.showConfirmInPlaceRestore = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                        Text(L10n.t(.restoreThisVersionButton))
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func triggerQuickLookForSelected() {
        guard let selected = appState.selectedFileVersionHistoryRecord,
              let previewURL = appState.urlForVersionHistoryRecord(selected) else { return }
        QuickLookCoordinator.shared.toggleQuickLook(for: previewURL)
    }

    private struct StateChangeInfo {
        let label: String
        let color: Color
        let icon: String
    }

    private func computeStateChange(at index: Int, in versions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)]) -> StateChangeInfo {
        guard !versions.isEmpty, index >= 0, index < versions.count else {
            return StateChangeInfo(label: L10n.t(.timelineInitialVersion), color: .green, icon: "plus.circle.fill")
        }

        guard index + 1 < versions.count else {
            return StateChangeInfo(label: L10n.t(.timelineInitialCreated), color: .green, icon: "plus.circle.fill")
        }

        let current = versions[index].file
        let previous = versions[index + 1].file

        if let c1 = current.checksum, let c2 = previous.checksum, c1 != c2 {
            return StateChangeInfo(label: L10n.t(.timelineModifiedContent), color: .orange, icon: "pencil.circle.fill")
        } else if current.fileSize != previous.fileSize || abs(current.modificationTime.timeIntervalSince(previous.modificationTime)) > 0.001 {
            return StateChangeInfo(label: L10n.t(.timelineModifiedMeta), color: .orange, icon: "pencil.circle.fill")
        } else {
            return StateChangeInfo(label: L10n.t(.timelineUnmodifiedCoW), color: .blue, icon: "equal.circle.fill")
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
