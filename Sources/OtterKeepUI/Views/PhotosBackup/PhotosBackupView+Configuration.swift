import SwiftUI
import Photos
import UniformTypeIdentifiers
import OtterKeepCore
import OtterKeepDatabase

extension PhotosBackupView {
    // MARK: - Configuration
    var configurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.photosConfigCardTitle))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                // Destination directory row
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive.fill")
                        .font(.title3)
                        .foregroundStyle(OtterTheme.otterAmber)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.destinationFolderTitle))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(appState.photosConfig.destinationURL.path)
                            .font(.callout.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button(L10n.t(.changeFolderButton)) {
                        selectDestinationFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([appState.photosConfig.destinationURL])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                            Text(L10n.t(.revealInFinderButton))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                // Directory structure
                HStack {
                    Text(L10n.t(.photosExportStructureLabel))
                        .font(.body)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { appState.photosConfig.exportStructure },
                        set: {
                            appState.photosConfig.exportStructure = $0
                            appState.savePhotosConfig()
                        }
                    )) {
                        ForEach(PhotosExportStructure.allCases, id: \.self) { structure in
                            Text(structure.localizedTitle).tag(structure)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 260)
                }

                Divider()

                // Edited versions
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.includeEditedVersions },
                    set: {
                        appState.photosConfig.includeEditedVersions = $0
                        appState.savePhotosConfig()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t(.photosIncludeEditedToggle))
                            .font(.body)
                        Text(L10n.t(.photosIncludeEditedDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Live Photo videos
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.includeLivePhotoVideos },
                    set: {
                        appState.photosConfig.includeLivePhotoVideos = $0
                        appState.savePhotosConfig()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t(.photosIncludeLivePhotoVideosToggle))
                            .font(.body)
                        Text(L10n.t(.photosIncludeLivePhotoVideosDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                // XMP Sidecar
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.generateXMPSidecars },
                    set: {
                        appState.photosConfig.generateXMPSidecars = $0
                        appState.savePhotosConfig()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t(.photosGenerateXMPToggle))
                            .font(.body)
                        Text(L10n.t(.photosGenerateXMPDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )
        }
    }

    private func selectDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.t(.changeFolderButton)

        if panel.runModal() == .OK, let url = panel.url {
            appState.photosConfig.destinationURL = url
            appState.savePhotosConfig()
        }
    }
}
