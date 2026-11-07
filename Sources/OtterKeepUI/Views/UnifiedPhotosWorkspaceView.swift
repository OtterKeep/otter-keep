import SwiftUI
import AppKit
import OtterKeepCore

/// Unified workspace for Apple Photos backup management and historical snapshot exploration.
public struct UnifiedPhotosWorkspaceView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var activeTabBinding: Binding<PhotosWorkspaceTab> {
        Binding(
            get: { appState.activePhotosTab },
            set: { appState.activePhotosTab = $0 }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Segmented Workspace Header
            workspaceHeaderBar

            Divider()

            // Tab Content
            switch appState.activePhotosTab {
            case .syncAndBackup:
                PhotosBackupView(appState: appState)
            case .snapshots:
                PhotosSnapshotsView(appState: appState)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var workspaceHeaderBar: some View {
        HStack(spacing: 16) {
            // Apple Photos Brand Header
            HStack(spacing: 8) {
                Image(systemName: "photo.stack.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.otterAmber)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.photosBackupHeroTitle))
                        .font(.headline.bold())

                    HStack(spacing: 4) {
                        Circle()
                            .fill(appState.isPhotosBackupRunning ? OtterTheme.otterAmber : OtterTheme.statusGreen)
                            .frame(width: 6, height: 6)
                        Text(appState.isPhotosBackupRunning ? L10n.t(.statusRunning) : L10n.t(.statusReady))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Centered Segmented Control
            Picker("", selection: activeTabBinding) {
                ForEach(PhotosWorkspaceTab.allCases) { tab in
                    Label(tab.localizedTitle, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .frame(maxWidth: 320)

            Spacer()

            // Snapshots count badge
            HStack(spacing: 6) {
                Text("\(appState.photosSnapshots.count)")
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Text(L10n.t(.snapshotsCountTitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
