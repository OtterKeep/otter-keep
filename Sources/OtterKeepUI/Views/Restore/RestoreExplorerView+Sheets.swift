import SwiftUI
import QuickLook
import OtterKeepDatabase
import OtterKeepCore

extension RestoreExplorerView {

    var restoreSheetView: some View {
        let activeVersion = appState.versionToRestore ?? {
            guard let file = appState.selectedFile,
                  let sId = appState.selectedSnapshotId,
                  let snap = appState.snapshots.first(where: { $0.id == sId }) else { return nil }
            return (snapshot: snap, file: file)
        }()

        return VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t(.restoreSheetTitle))
                .font(.title2.bold())

            if let (snap, file) = activeVersion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(L10n.t(.restoreItemLabel)) \(file.relativePath)")
                        .font(.subheadline.bold())
                    Text("\(L10n.t(.sourceSnapshotLabel)) \(snap.snapshotPath) (\(Self.dateFormatter.string(from: snap.timestamp)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.collisionResolutionLabel))
                    .fontWeight(.medium)
                Picker("", selection: collisionChoiceBinding) {
                    Text(L10n.t(.collisionKeepBoth)).tag(CollisionResolution.keepBoth)
                    Text(L10n.t(.collisionOverwrite)).tag(CollisionResolution.overwrite)
                    Text(L10n.t(.collisionSkip)).tag(CollisionResolution.skip)
                }
                .pickerStyle(.radioGroup)
            }

            HStack {
                Button(L10n.t(.cancel)) {
                    appState.showRestoreDialog = false
                    appState.versionToRestore = nil
                }
                Spacer()
                Button(L10n.t(.restoreToFolderButton)) {
                    appState.showRestoreDialog = false
                    if let target = activeVersion {
                        chooseRestoreDestination { targetURL in
                            appState.restoreVersion(
                                snapshot: target.snapshot,
                                file: target.file,
                                to: targetURL,
                                collision: appState.collisionChoice
                            )
                            appState.versionToRestore = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    var restoreSnapshotSheetView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Text(L10n.t(.restoreEntireSnapshotTitle))
                    .font(.title2.bold())
            }

            if let snap = appState.snapshotToRestoreEntirely {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(L10n.t(.sourceSnapshotLabel)) \(snap.snapshotPath)")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(Self.dateFormatter.string(from: snap.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("\(snap.totalFiles) \(L10n.t(.snapshotFilesCount)) • \(formatBytes(snap.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.collisionResolutionLabel))
                    .fontWeight(.medium)
                Picker("", selection: collisionChoiceBinding) {
                    Text(L10n.t(.collisionKeepBoth)).tag(CollisionResolution.keepBoth)
                    Text(L10n.t(.collisionOverwrite)).tag(CollisionResolution.overwrite)
                    Text(L10n.t(.collisionSkip)).tag(CollisionResolution.skip)
                }
                .pickerStyle(.radioGroup)
            }

            if appState.isSnapshotRestoreInProgress {
                VStack(alignment: .leading, spacing: 6) {
                    if let prog = appState.snapshotRestoreProgress {
                        ProgressView(value: Double(prog.processedFiles), total: max(1.0, Double(prog.totalFiles)))
                        HStack {
                            Text("\(prog.processedFiles) / \(prog.totalFiles) \(L10n.t(.snapshotFilesCount))")
                                .font(.caption2.monospacedDigit())
                            Spacer()
                            Text(formatBytes(prog.processedBytes))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if !prog.currentItem.isEmpty {
                            Text(prog.currentItem)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button(L10n.t(.cancel)) {
                    appState.showRestoreSnapshotDialog = false
                    appState.snapshotToRestoreEntirely = nil
                }
                .disabled(appState.isSnapshotRestoreInProgress)

                Spacer()

                Button(L10n.t(.restoreToFolderButton)) {
                    if let snap = appState.snapshotToRestoreEntirely {
                        chooseRestoreDestination { targetURL in
                            appState.showRestoreSnapshotDialog = false
                            appState.restoreEntireSnapshot(
                                snapshot: snap,
                                to: targetURL,
                                collision: appState.collisionChoice
                            )
                            appState.snapshotToRestoreEntirely = nil
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.isSnapshotRestoreInProgress || appState.snapshotToRestoreEntirely == nil)
            }
        }
        .padding()
        .frame(minWidth: 480)
    }

    private func chooseRestoreDestination(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t(.restoreChoosePrompt)
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - 3. Cross-Snapshot Global Search

}
