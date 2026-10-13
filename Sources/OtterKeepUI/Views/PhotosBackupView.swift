import SwiftUI
import Photos
import UniformTypeIdentifiers
import OtterKeepCore
import OtterKeepDatabase

/// Modern Apple Photos backup view presenting library metrics, export settings, and live synchronization.
public struct PhotosBackupView: View {
    @Bindable var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Permission banner
                authorizationBanner

                if appState.photosAuthorizationStatus == .authorized || appState.photosAuthorizationStatus == .limited {
                    // Status cards grid
                    statusCardsGrid

                    // Primary Action and Live Telemetry Section
                    actionAndTelemetrySection

                    // Destination Directory & Export Settings
                    configurationSection

                    // Schedule Settings
                    scheduleSection
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.checkPhotosAuthorization()
            appState.refreshPhotosLibraryStats()
            appState.loadPhotosSnapshots()
        }
    }
}
