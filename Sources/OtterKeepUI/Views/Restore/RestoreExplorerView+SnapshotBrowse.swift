import SwiftUI
import QuickLook
import OtterKeepDatabase
import OtterKeepCore

extension RestoreExplorerView {

    var snapshotBrowseView: some View {
        HSplitView {
            // Left side panel: Snapshots list
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(L10n.t(.snapshotsCountTitle)) (\(appState.snapshots.count))")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if appState.snapshots.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.noSnapshotsAvailable),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(L10n.t(.noSnapshotsAvailableDesc))
                    )
                } else {
                    List(selection: Binding(
                        get: { appState.selectedSnapshotId },
                        set: {
                            if appState.selectedSnapshotId != $0 {
                                appState.selectedSnapshotId = $0
                                appState.loadFilesForSelectedSnapshot(force: true)
                            }
                        }
                    )) {
                        ForEach(appState.snapshots) { snap in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(Self.dateFormatter.string(from: snap.timestamp))
                                        .font(.body.bold())
                                    if snap.backupType == "full" {
                                        Text(L10n.t(.backupTypeFull))
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(OtterTheme.oceanicTeal.opacity(0.20), in: Capsule())
                                            .foregroundStyle(OtterTheme.oceanicTeal)
                                    }
                                    if snap.isLocked {
                                        HStack(spacing: 3) {
                                            Image(systemName: "lock.shield.fill")
                                            Text(L10n.t(.wormLockedBadge))
                                        }
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(OtterTheme.accentPurple.opacity(0.20), in: Capsule())
                                        .foregroundStyle(OtterTheme.accentPurple)
                                    }
                                    Spacer()
                                    Text(formatBytes(snap.totalBytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(snap.totalFiles) \(L10n.t(.snapshotFilesCount)) • \(snap.snapshotPath)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .tag(snap.id)
                            .padding(.vertical, 4)
                            .contextMenu {
                                Button {
                                    appState.snapshotToRestoreEntirely = snap
                                    appState.showRestoreSnapshotDialog = true
                                } label: {
                                    Label(L10n.t(.restoreEntireSnapshotButton), systemImage: "arrow.counterclockwise.circle")
                                }

                                Button {
                                    appState.selectedDiffTargetSnapshotId = snap.id
                                    appState.selectedDiffBaseSnapshotId = nil
                                    appState.loadSnapshotDiff(targetId: snap.id, baseId: nil)
                                    appState.showDiffSheet = true
                                } label: {
                                    Label(L10n.t(.diffCompareAction), systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    VStack(spacing: 6) {
                        if let selectedSnap = appState.snapshots.first(where: { $0.id == appState.selectedSnapshotId }) {
                            Button {
                                appState.snapshotToRestoreEntirely = selectedSnap
                                appState.showRestoreSnapshotDialog = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                    Text(L10n.t(.restoreEntireSnapshotButton))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }

                        Button {
                            appState.performManualScrub()
                        } label: {
                            HStack(spacing: 6) {
                                if appState.isDataScrubInProgress {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                }
                                Text(L10n.t(.verifySnapshotIntegrityButton))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(appState.isDataScrubInProgress || appState.snapshots.isEmpty)
                        .help(L10n.t(.verifySnapshotIntegrityTooltip))
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .frame(minWidth: 260, maxWidth: 340)

            // Right Panel: Directory tree and file browser with search
            VStack(alignment: .leading, spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.t(.searchTreePlaceholder), text: searchFilterBinding)
                        .textFieldStyle(.plain)
                    if !appState.searchFilter.isEmpty {
                        Button { appState.searchFilter = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.top, 8)

                let filteredTree = FileTreeBuilder.filterTree(appState.snapshotTreeNodes, query: appState.searchFilter)

                if filteredTree.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.noMatchingFilesInSnapshot),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.t(.noMatchingFilesInSnapshotDesc))
                    )
                } else {
                    // Directory tree outline view
                    List(filteredTree, children: \.children) { node in
                        treeNodeRow(node: node)
                            .tag(node.id)
                    }
                    .listStyle(.inset)
                }

                // Bottom restore action bar
                HStack {
                    if let file = appState.selectedFile {
                        HStack(spacing: 8) {
                            Text("\(L10n.t(.selectedFileLabel)) \(file.relativePath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !file.isDirectory {
                                Button {
                                    appState.toggleQuickLook()
                                } label: {
                                    Image(systemName: "eye")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.t(.previewSpaceButton))

                                Button {
                                    if let snapId = appState.selectedSnapshotId {
                                        appState.openSideBySideDiff(forFileRecord: file, inSnapshotId: snapId)
                                    }
                                } label: {
                                    Image(systemName: "square.split.2x1")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.t(.diffSideBySideCompare))
                            }
                        }
                    } else {
                        Text(L10n.t(.selectFileToRestorePrompt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(L10n.t(.restoreThisVersionButton)) {
                        appState.versionToRestore = nil
                        appState.showRestoreDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.selectedFile == nil)
                }
                .padding()
                .background(.background.secondary)
            }
        }
    }

    private func treeNodeRow(node: FileTreeNode) -> some View {
        let isSelected = appState.selectedFile?.relativePath == node.relativePath
        return HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(node.isDirectory ? OtterTheme.oceanicTeal : .secondary)
                .font(.body)

            if !node.isDirectory {
                let status = appState.snapshotFileDiffStatuses[node.relativePath] ?? .unchanged
                Circle()
                    .fill(diffStatusColor(status))
                    .frame(width: 7, height: 7)
                    .help(diffStatusTooltip(status))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body.weight(node.isDirectory ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !node.isDirectory {
                    Text(node.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if !node.isDirectory {
                Text(formatBytes(node.fileSize))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(Self.dateFormatter.string(from: node.modificationTime))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let count = node.children?.count {
                Text(L10n.format(.restoreItemsCountFormat, count))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            selectNode(node)
        }
        .onTapGesture(count: 2) {
            selectNode(node)
            if !node.isDirectory {
                appState.toggleQuickLook()
            }
        }
        .contextMenu {
            if !node.isDirectory {
                Button {
                    selectNode(node)
                    appState.toggleQuickLook()
                } label: {
                    Label(L10n.t(.previewSpaceButton), systemImage: "eye")
                }

                Button {
                    let fileToDiff = node.record ?? appState.snapshotFiles.first(where: { $0.relativePath == node.relativePath })
                    if let file = fileToDiff, let snapId = appState.selectedSnapshotId {
                        appState.openSideBySideDiff(forFileRecord: file, inSnapshotId: snapId)
                    }
                } label: {
                    Label(L10n.t(.diffSideBySideCompare), systemImage: "square.split.2x1")
                }
            }

            Button {
                selectNode(node)
                appState.versionToRestore = nil
                appState.showRestoreDialog = true
            } label: {
                Label(L10n.t(.restoreThisVersionButton), systemImage: "arrow.uturn.backward")
            }

            Button {
                selectNode(node)
                if let url = appState.currentSelectedFileURL() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } label: {
                Label(L10n.t(.revealInFinderButton), systemImage: "arrow.right.circle")
            }
        }
    }

    private func selectNode(_ node: FileTreeNode) {
        appState.selectedTreeNode = node
        if node.isDirectory {
            if let rec = node.record {
                appState.selectedFile = rec
            } else {
                appState.selectedFile = FileCatalogRecord(
                    id: 0,
                    snapshotId: appState.selectedSnapshotId ?? "",
                    relativePath: node.relativePath,
                    fileSize: node.fileSize,
                    modificationTime: node.modificationTime,
                    inode: 0,
                    checksum: nil,
                    sampleHash: nil,
                    isDirectory: true,
                    isSymlink: false
                )
            }
        } else {
            if let rec = node.record {
                appState.selectedFile = rec
            } else {
                appState.selectedFile = appState.snapshotFiles.first(where: { $0.relativePath == node.relativePath })
            }
            appState.updateQuickLookForCurrentSelection()
        }
    }

    private func diffStatusColor(_ status: DiffChangeType) -> Color {
        switch status {
        case .added: return OtterTheme.statusGreen
        case .modified: return OtterTheme.otterAmber
        case .unchanged: return Color.secondary.opacity(0.4)
        case .deleted: return OtterTheme.statusError
        }
    }

    private func diffStatusTooltip(_ status: DiffChangeType) -> String {
        switch status {
        case .added: return L10n.t(.diffTabAdded)
        case .modified: return L10n.t(.diffTabModified)
        case .unchanged: return L10n.t(.timelineUnmodifiedCoW)
        case .deleted: return L10n.t(.diffTabDeleted)
        }
    }

}
