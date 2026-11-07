import AppKit
import OtterKeepCore
import SwiftUI

/// A reassuring, calm modal presented when an external drive with an unadopted OtterKeep backup is discovered.
public struct UnadoptedDriveModalView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var profileName: String {
        appState.discoveredUnadoptedMetadata?.profileName ?? "Sanctuary Archive"
    }

    private var volumeName: String {
        appState.discoveredUnadoptedVolumeURL?.lastPathComponent ?? "External Drive"
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                // Ottie calming sanctuary mascot
                OttieSanctuaryMascotView(mood: .safe, size: 96)

                VStack(spacing: 8) {
                    Text(L10n.t(.unadoptedDriveDiscoveredTitle))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(L10n.format(.unadoptedDriveDiscoveredMessageFormat, profileName, volumeName))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
            .padding(24)

            // Pinned Footer
            ModalFooterActionsView(
                cancelTitle: L10n.t(.unadoptedDriveDismissAction),
                primaryTitle: L10n.t(.unadoptedDriveAdoptAction),
                onCancel: {
                    appState.dismissDiscoveredDrive()
                },
                onPrimary: {
                    appState.adoptDiscoveredDrive()
                }
            )
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .id(appState.currentLanguage)
    }
}
