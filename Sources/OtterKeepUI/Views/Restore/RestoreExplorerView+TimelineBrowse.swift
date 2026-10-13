import SwiftUI
import QuickLook
import OtterKeepDatabase
import OtterKeepCore

extension RestoreExplorerView {

    var fileTimelineBrowseView: some View {
        HSplitView {
            // Left Panel: Directory tree with search
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t(.searchFileTitle))
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.t(.searchFilePlaceholder), text: timelineQueryBinding)
                        .textFieldStyle(.plain)
                    if !appState.timelineSearchQuery.isEmpty {
                        Button {
                            appState.timelineSearchQuery = ""
                            appState.searchTimelinePaths(query: "")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                let filteredTree = FileTreeBuilder.filterTree(appState.timelineTreeNodes, query: appState.timelineSearchQuery)

                if filteredTree.isEmpty {
                    ContentUnavailableView(
                        L10n.t(.noMatchingFilesFound),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(L10n.t(.noMatchingFilesFoundDesc))
                    )
                } else {
                    List(filteredTree, children: \.children) { node in
                        timelineTreeNodeRow(node: node)
                            .tag(node.id)
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 280, maxWidth: 380)

            // Right Panel: Vertical timeline cards
            VStack(alignment: .leading, spacing: 0) {
                if let selectedPath = appState.selectedTimelinePath, !appState.selectedPathVersions.isEmpty {
                    // File header
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((selectedPath as NSString).lastPathComponent)
                                .font(.title3.bold())
                            Text(selectedPath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(appState.selectedPathVersions.count) \(L10n.t(.versionsCountLabel))")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(OtterTheme.oceanicTeal.opacity(0.12), in: Capsule())
                            .foregroundStyle(OtterTheme.oceanicTeal)
                    }
                    .padding()
                    .background(.background.secondary)

                    Divider()

                    // Vertical timeline cards
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(appState.selectedPathVersions.enumerated()), id: \.element.snapshot.id) { index, item in
                                let changeState = computeStateChange(at: index, in: appState.selectedPathVersions)
                                let isSelected = appState.selectedTimelineVersion?.snapshot.id == item.snapshot.id

                                timelineNodeRow(
                                    item: item,
                                    changeState: changeState,
                                    isFirst: index == 0,
                                    isLast: index == appState.selectedPathVersions.count - 1,
                                    isSelected: isSelected
                                )
                                .onTapGesture {
                                    appState.selectedTimelineVersion = item
                                    appState.updateQuickLookForCurrentSelection()
                                }
                            }
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView(
                        L10n.t(.selectFileToRestorePrompt),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(L10n.t(.timelineSelectPrompt))
                    )
                }
            }
        }
    }

    private func timelineTreeNodeRow(node: FileTreeNode) -> some View {
        let isSelected = appState.selectedTimelinePath == node.relativePath
        return HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text.fill")
                .foregroundStyle(node.isDirectory ? OtterTheme.oceanicTeal : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body.weight(node.isDirectory ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !node.isDirectory {
                    Text(node.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if !node.isDirectory {
                appState.loadTimeline(for: node.relativePath)
            }
        }
    }

    // MARK: - Timeline Node

    private struct StateChangeInfo {
        let label: String
        let color: Color
        let icon: String
    }

    private func computeStateChange(at index: Int, in versions: [(snapshot: SnapshotRecord, file: FileCatalogRecord)]) -> StateChangeInfo {
        guard !versions.isEmpty, index >= 0, index < versions.count else {
            return StateChangeInfo(label: L10n.t(.timelineInitialVersion), color: OtterTheme.statusGreen, icon: "plus.circle.fill")
        }

        guard index + 1 < versions.count else {
            return StateChangeInfo(label: L10n.t(.timelineInitialCreated), color: OtterTheme.statusGreen, icon: "plus.circle.fill")
        }

        let current = versions[index].file
        let previous = versions[index + 1].file

        if let c1 = current.checksum, let c2 = previous.checksum, c1 != c2 {
            return StateChangeInfo(label: L10n.t(.timelineModifiedContent), color: OtterTheme.otterAmber, icon: "pencil.circle.fill")
        } else if current.fileSize != previous.fileSize || abs(current.modificationTime.timeIntervalSince(previous.modificationTime)) > 0.001 {
            return StateChangeInfo(label: L10n.t(.timelineModifiedMeta), color: OtterTheme.otterAmber, icon: "pencil.circle.fill")
        } else {
            return StateChangeInfo(label: L10n.t(.timelineUnmodifiedCoW), color: OtterTheme.oceanicTeal, icon: "equal.circle.fill")
        }
    }

    private func timelineNodeRow(
        item: (snapshot: SnapshotRecord, file: FileCatalogRecord),
        changeState: StateChangeInfo,
        isFirst: Bool,
        isLast: Bool,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Left timeline indicator
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.secondary.opacity(0.3))
                    .frame(width: 2, height: 16)

                ZStack {
                    Circle()
                        .fill(changeState.color)
                        .frame(width: 16, height: 16)
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 16, height: 16)
                }

                Rectangle()
                    .fill(isLast ? Color.clear : Color.secondary.opacity(0.3))
                    .frame(width: 2)
                    .frame(minHeight: 80)
            }
            .frame(width: 20)

            // Right side version card
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateFormatter.string(from: item.snapshot.timestamp))
                            .font(.headline)
                        Text("Snapshot: \(item.snapshot.snapshotPath)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // State change badge
                    HStack(spacing: 4) {
                        Image(systemName: changeState.icon)
                        Text(changeState.label)
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(changeState.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(changeState.color)
                }

                Divider()

                // Detailed attributes
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
                }

                // Card action buttons
                HStack(spacing: 10) {
                    Button {
                        appState.selectedTimelineVersion = item
                        appState.toggleQuickLook()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                            Text(L10n.t(.previewSpaceButton))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        appState.versionToRestore = item
                        appState.showRestoreDialog = true
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
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
            )
            .padding(.bottom, 14)
        }
    }

    // MARK: - Restore Modal Sheet

}
