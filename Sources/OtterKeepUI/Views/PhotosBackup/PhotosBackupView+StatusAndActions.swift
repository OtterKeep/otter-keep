import SwiftUI
import Photos
import UniformTypeIdentifiers
import OtterKeepCore
import OtterKeepDatabase

extension PhotosBackupView {
    // MARK: - Authorization Banner
    @ViewBuilder
    var authorizationBanner: some View {
        if appState.photosAuthorizationStatus != .authorized && appState.photosAuthorizationStatus != .limited {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.statusWarning)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.photosStatusNotAuthorized))
                        .font(.subheadline.bold())
                    Text(L10n.t(.photosAuthRequiredDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.t(.photosRequestPermissionButton)) {
                    appState.requestPhotosAuthorization()
                }
                .buttonStyle(.borderedProminent)
                .tint(OtterTheme.otterAmber)
                .controlSize(.regular)
            }
            .padding(14)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.statusWarning.opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Status Cards Grid
    var statusCardsGrid: some View {
        HStack(spacing: 14) {
            // Total media items
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(.photosCardLibraryTotal), systemImage: "photo.on.rectangle.angled")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)

                if appState.isScanningPhotosLibrary {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(L10n.format(.assetsCountUnitFormat, appState.photosLibraryTotalCount))
                        .font(.title2.bold().monospacedDigit())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )

            // Buffer protection
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(.photosBufferStatus), systemImage: "shield.lefthalf.filled")
                    .font(.caption.bold())
                    .foregroundStyle(.green)

                Text("Max \(appState.photosConfig.maxInFlightCacheBytes / 1024 / 1024) MB")
                    .font(.title2.bold().monospacedDigit())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )

            // APFS Reflink Savings
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(.photosSavedByReflink), systemImage: "leaf.fill")
                    .font(.caption.bold())
                    .foregroundStyle(OtterTheme.cyberTeal)

                let saved = appState.lastPhotosSessionSummary?.reflinkClonedBytes ?? appState.photosProgressState.clonedBytes
                Text(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file))
                    .font(.title2.bold().monospacedDigit())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Action & Live Telemetry Section
    var actionAndTelemetrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.isPhotosBackupRunning {
                HStack {
                    Text(appState.photosProgressState.phaseDescription)
                        .font(.headline)
                        .foregroundStyle(OtterTheme.otterAmber)
                    Spacer()
                    Text("\(Int(appState.photosProgressState.progressFraction * 100))%")
                        .font(.subheadline.bold().monospacedDigit())
                }

                ProgressView(value: appState.photosProgressState.progressFraction)
                    .progressViewStyle(.linear)

                HStack {
                    Text("\(appState.photosProgressState.processedAssetsCount) / \(appState.photosProgressState.totalAssetsCount) \(L10n.t(.assetsCountUnit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L10n.format(.photosDownloadedClonedFormat, ByteCountFormatter.string(fromByteCount: appState.photosProgressState.downloadedBytes, countStyle: .file), ByteCountFormatter.string(fromByteCount: appState.photosProgressState.clonedBytes, countStyle: .file)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if !appState.photosProgressState.currentAssetFilename.isEmpty {
                    Text(appState.photosProgressState.currentAssetFilename)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Spacer()
                    Button(L10n.t(.cancel), role: .destructive) {
                        appState.cancelPhotosBackup()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.photosBackupCardTitle))
                            .font(.headline)
                        Text(L10n.t(.photosBackupCardSubtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        appState.startPhotosBackup()
                    } label: {
                        Label(L10n.t(.photosStartBackupButton), systemImage: "arrow.down.circle.fill")
                            .font(.body.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.otterAmber)
                    .controlSize(.regular)
                }
            }
        }
        .padding(14)
        .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                .stroke(appState.isPhotosBackupRunning ? OtterTheme.otterAmber.opacity(0.3) : OtterTheme.subtleBorder, lineWidth: 1)
        )
    }
}
