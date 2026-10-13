import SwiftUI
import QuickLook
import OtterKeepDatabase
import OtterKeepCore

extension RestoreExplorerView {

    var globalSearchBrowseView: some View {
        VStack(spacing: 0) {
            // Search Input Header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TextField(L10n.t(.searchAllSnapshots), text: Binding(
                    get: { appState.globalSearchQuery },
                    set: { appState.searchGlobalSnapshots(query: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.body)

                if appState.isGlobalSearching {
                    ProgressView()
                        .controlSize(.small)
                } else if !appState.globalSearchResults.isEmpty && !appState.globalSearchQuery.isEmpty {
                    Text("\(appState.globalSearchResults.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                if !appState.globalSearchQuery.isEmpty {
                    Button {
                        appState.searchGlobalSnapshots(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .padding(14)

            Divider()

            // Results Content
            if appState.globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    L10n.t(.searchAllSnapshotsTitle),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(L10n.t(.searchAllSnapshotsDesc))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.globalSearchResults.isEmpty && !appState.isGlobalSearching {
                ContentUnavailableView(
                    L10n.t(.searchAllSnapshotsEmpty),
                    systemImage: "magnifyingglass",
                    description: Text(L10n.t(.searchAllSnapshotsDesc))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { appState.selectedGlobalSearchResult?.id },
                    set: { selectedId in
                        if let hit = appState.globalSearchResults.first(where: { $0.id == selectedId }) {
                            appState.selectedGlobalSearchResult = hit
                            appState.updateQuickLookForCurrentSelection()
                        }
                    }
                )) {
                    ForEach(appState.globalSearchResults) { result in
                        globalSearchResultRow(result)
                            .tag(result.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func globalSearchResultRow(_ result: GlobalSearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconForPath(result.fileRecord.relativePath))
                .font(.title3)
                .foregroundStyle(OtterTheme.oceanicTeal)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: result.fileRecord.relativePath).lastPathComponent)
                    .font(.body.weight(.medium))

                Text(result.fileRecord.relativePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Self.dateFormatter.string(from: result.snapshotDate))
                        .font(.caption.bold())
                    Text(result.snapshotId)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }

                HStack(spacing: 10) {
                    Text(formatBytes(result.fileRecord.fileSize))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let hash = result.fileRecord.checksum {
                        Text(String(hash.prefix(8)))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack(spacing: 6) {
                Button {
                    appState.selectedGlobalSearchResult = result
                    appState.toggleQuickLook()
                } label: {
                    Image(systemName: "eye")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t(.previewSpaceButton))

                if !result.fileRecord.isDirectory {
                    Button {
                        appState.openSideBySideDiff(forGlobalSearchResult: result)
                    } label: {
                        Image(systemName: "square.split.2x1")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(L10n.t(.diffSideBySideCompare))
                }

                Button {
                    appState.revealGlobalSearchResultInSnapshot(result)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(L10n.t(.snapshotsCountTitle))

                Button {
                    let fakeSnap = SnapshotRecord(
                        id: result.snapshotId,
                        timestamp: result.snapshotTimestamp,
                        status: "completed",
                        totalFiles: 0,
                        totalBytes: 0,
                        snapshotPath: result.snapshotPath,
                        backupType: "incremental"
                    )
                    appState.versionToRestore = (snapshot: fakeSnap, file: result.fileRecord)
                    appState.showRestoreDialog = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward")
                        Text(L10n.t(.restoreThisVersionButton))
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                appState.selectedGlobalSearchResult = result
                appState.toggleQuickLook()
            } label: {
                Label(L10n.t(.previewSpaceButton), systemImage: "eye")
            }

            if !result.fileRecord.isDirectory {
                Button {
                    appState.openSideBySideDiff(forGlobalSearchResult: result)
                } label: {
                    Label(L10n.t(.diffSideBySideCompare), systemImage: "square.split.2x1")
                }
            }

            Button {
                appState.revealGlobalSearchResultInSnapshot(result)
            } label: {
                Label(L10n.t(.snapshotsCountTitle), systemImage: "arrow.up.right.square")
            }

            Button {
                let fakeSnap = SnapshotRecord(
                    id: result.snapshotId,
                    timestamp: result.snapshotTimestamp,
                    status: "completed",
                    totalFiles: 0,
                    totalBytes: 0,
                    snapshotPath: result.snapshotPath,
                    backupType: "incremental"
                )
                appState.versionToRestore = (snapshot: fakeSnap, file: result.fileRecord)
                appState.showRestoreDialog = true
            } label: {
                Label(L10n.t(.restoreThisVersionButton), systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.fileRecord.relativePath, forType: .string)
            } label: {
                Label(L10n.t(.copyRelativePathAction), systemImage: "doc.on.doc")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.snapshotId, forType: .string)
            } label: {
                Label(L10n.t(.copySnapshotIdAction), systemImage: "number")
            }
        }
    }

    private func iconForPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "heic", "gif", "svg": return "photo"
        case "mp4", "mov", "m4v", "mkv": return "film"
        case "mp3", "m4a", "flac", "wav": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "7z": return "doc.zipper"
        case "swift", "py", "js", "ts", "json", "c", "cpp", "h", "rs", "go": return "curlybraces"
        default: return "doc.text"
        }
    }
}
