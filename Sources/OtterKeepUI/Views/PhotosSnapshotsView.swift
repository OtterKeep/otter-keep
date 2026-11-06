import SwiftUI
import UniformTypeIdentifiers
import OtterKeepCore
import OtterKeepDomain

/// Dedicated explorer view for browsing and restoring historical Apple Photos backup snapshots and media assets.
public struct PhotosSnapshotsView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            if appState.photosSnapshots.isEmpty {
                ContentUnavailableView(
                    L10n.t(.noSnapshotsAvailable),
                    systemImage: "photo.stack",
                    description: Text(L10n.t(.noSnapshotsAvailableDesc))
                )
            } else {
                HSplitView {
                    // Left side: snapshots list
                    snapshotsList
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

                    // Right side: media assets browser
                    assetsBrowser
                        .frame(minWidth: 400)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.loadPhotosSnapshots()
        }
    }

    // MARK: - Snapshots List
    private var snapshotsList: some View {
        List(appState.photosSnapshots, selection: Binding(
            get: { appState.selectedPhotosSnapshotId },
            set: { if let id = $0 { appState.selectPhotosSnapshot(id: id) } }
        )) { snap in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snap.timestamp, style: .date)
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(snap.timestamp, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("\(snap.totalFiles) \(L10n.t(.filesCountUnit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: snap.totalBytes, countStyle: .file))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .tag(snap.id)
        }
        .listStyle(.inset)
    }

    // MARK: - Media Assets Browser
    private var assetsBrowser: some View {
        VStack(spacing: 0) {
            if appState.photosAssets.isEmpty {
                ContentUnavailableView(
                    L10n.t(.noMatchingFilesInSnapshot),
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(L10n.t(.noMatchingFilesInSnapshotDesc))
                )
            } else {
                Table(appState.photosAssets, selection: Binding<Int64?>(
                    get: { appState.selectedPhotosAsset?.id },
                    set: { selectedId in
                        appState.selectedPhotosAsset = appState.photosAssets.first(where: { $0.id == selectedId })
                    }
                )) {
                    TableColumn(L10n.t(.selectedFileLabel)) { (asset: PhotosAssetRecord) in
                        HStack(spacing: 6) {
                            Image(systemName: asset.mediaType == "video" ? "video.fill" : "photo.fill")
                                .foregroundStyle(asset.mediaType == "video" ? .purple : .blue)
                            Text(asset.originalFilename)
                                .font(.body.monospaced())
                        }
                    }

                    TableColumn(L10n.t(.columnDate)) { (asset: PhotosAssetRecord) in
                        Text(asset.modificationTime, style: .date)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    TableColumn(L10n.t(.columnSize)) { (asset: PhotosAssetRecord) in
                        Text(ByteCountFormatter.string(fromByteCount: asset.fileSize, countStyle: .file))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    TableColumn(L10n.t(.columnType)) { (asset: PhotosAssetRecord) in
                        Text(asset.mediaType)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Bottom action toolbar
                if let selectedAsset = appState.selectedPhotosAsset {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedAsset.originalFilename)
                                .font(.body.bold())
                            Text(selectedAsset.relativePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            appState.revealPhotosAssetInFinder(selectedAsset)
                        } label: {
                            Label(L10n.t(.revealInFinderButton), systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(OtterTheme.otterAmber)
                    }
                    .padding(12)
                    .background(OtterTheme.cardBackground)
                }
            }
        }
    }
}
