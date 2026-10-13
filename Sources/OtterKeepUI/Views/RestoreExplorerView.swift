import SwiftUI
import QuickLook
import OtterKeepDatabase
import OtterKeepCore

public struct RestoreExplorerView: View {
    public let appState: AppState

    var searchFilterBinding: Binding<String> {
        Binding(get: { appState.searchFilter }, set: { appState.searchFilter = $0 })
    }

    var timelineQueryBinding: Binding<String> {
        Binding(
            get: { appState.timelineSearchQuery },
            set: {
                appState.timelineSearchQuery = $0
                appState.searchTimelinePaths(query: $0, force: true)
            }
        )
    }

    var showRestoreDialogBinding: Binding<Bool> {
        Binding(get: { appState.showRestoreDialog }, set: { appState.showRestoreDialog = $0 })
    }

    var showRestoreSnapshotDialogBinding: Binding<Bool> {
        Binding(get: { appState.showRestoreSnapshotDialog }, set: { appState.showRestoreSnapshotDialog = $0 })
    }

    var collisionChoiceBinding: Binding<CollisionResolution> {
        Binding(get: { appState.collisionChoice }, set: { appState.collisionChoice = $0 })
    }

    static let dateFormatter: DateFormatter = {
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
            // Top Bar: Mode Selector (Snapshot vs. Timeline)
            headerModeSelector

            Divider()

            // View content based on selected mode
            switch appState.restoreBrowseMode {
            case .snapshot:
                snapshotBrowseView
            case .timeline:
                fileTimelineBrowseView
            case .globalSearch:
                globalSearchBrowseView
            }

        }
        .onAppear {
            appState.loadSnapshots()
            QuickLookCoordinator.shared.startKeyboardMonitoring(for: appState)
        }
        .onDisappear {
            QuickLookCoordinator.shared.stopKeyboardMonitoring()
        }
        .onKeyPress(.space) {
            appState.toggleQuickLook()
            return .handled
        }
        .sheet(isPresented: showRestoreDialogBinding) {
            restoreSheetView
        }
        .sheet(isPresented: showRestoreSnapshotDialogBinding) {
            restoreSnapshotSheetView
        }
        .sheet(isPresented: Binding(
            get: { appState.showDiffSheet },
            set: { appState.showDiffSheet = $0 }
        )) {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.t(.diffCompareAction))
                        .font(.headline)
                    Spacer()
                    Button(L10n.t(.cancel)) {
                        appState.showDiffSheet = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
                Divider()
                SnapshotDiffView(appState: appState)
            }
            .frame(minWidth: 700, minHeight: 520)
        }
        .sheet(isPresented: Binding(
            get: { appState.showSideBySideDiffModal },
            set: { appState.showSideBySideDiffModal = $0 }
        )) {
            SideBySideDiffModalView(appState: appState)
        }
    }

    // MARK: - Top Mode Selector Header

    var headerModeSelector: some View {
        HStack(spacing: 14) {
            Picker("", selection: Binding(
                get: { appState.restoreBrowseMode },
                set: { newMode in
                    appState.restoreBrowseMode = newMode
                    appState.updateQuickLookForCurrentSelection()
                }
            )) {
                ForEach(RestoreBrowseMode.allCases) { mode in
                    Label(mode.localizedTitle, systemImage: mode.iconName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)

            Spacer()

            // Quick Look preview button with Space indicator
            Button {
                appState.toggleQuickLook()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eye")
                    Text(L10n.t(.previewSpaceButton))
                    Text("⎵")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                }
                .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.currentSelectedFileURL() == nil)
            .help(L10n.t(.quickLookKeyboardHint))

            // Side-by-Side comparison button
            Button {
                if appState.restoreBrowseMode == .globalSearch, let hit = appState.selectedGlobalSearchResult {
                    appState.openSideBySideDiff(forGlobalSearchResult: hit)
                } else if appState.restoreBrowseMode == .timeline, let item = appState.selectedTimelineVersion {
                    appState.openSideBySideDiff(forFileRecord: item.file, inSnapshotId: item.snapshot.id)
                } else if appState.restoreBrowseMode == .snapshot, let file = appState.selectedFile, let snapId = appState.selectedSnapshotId {
                    appState.openSideBySideDiff(forFileRecord: file, inSnapshotId: snapId)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.split.2x1")
                    Text(L10n.t(.diffSideBySideCompare))
                }
                .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isSideBySideDiffDisabled)
            .help(L10n.t(.diffSideBySideCompare))

            Button {
                appState.loadSnapshots(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(L10n.t(.searchPlaceholder))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    var isSideBySideDiffDisabled: Bool {
        if appState.restoreBrowseMode == .globalSearch {
            guard let hit = appState.selectedGlobalSearchResult else { return true }
            return hit.fileRecord.isDirectory
        } else if appState.restoreBrowseMode == .timeline {
            guard let item = appState.selectedTimelineVersion else { return true }
            return item.file.isDirectory
        } else {
            guard let file = appState.selectedFile, appState.selectedSnapshotId != nil else { return true }
            return file.isDirectory
        }
    }

    // MARK: - 1. Snapshot Tree Structure & Search Browsing
}
