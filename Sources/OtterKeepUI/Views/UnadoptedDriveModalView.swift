import SwiftUI
import AppKit
import OtterKeepCore

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
        VStack(spacing: 20) {
            // Ottie calming sanctuary mascot
            OttieSanctuaryMascotView(mood: .safe, size: 96)

            VStack(spacing: 8) {
                Text(LocalizationManager.shared.effectiveLanguage == .hungarian
                     ? "Létező mentés található a meghajtón"
                     : "Existing Sanctuary Discovered")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(LocalizationManager.shared.effectiveLanguage == .hungarian
                     ? "A(z) „\(volumeName)” meghajtón megtaláltuk a(z) „\(profileName)” mentési archívumot. Szeretnéd hozzáadni a helyi profiljaidhoz, hogy biztonságban tudd és böngészhesd a pillanatképeit?"
                     : "We discovered an existing backup archive for „\(profileName)” on „\(volumeName)”. Would you like to adopt this profile into your sanctuary to safeguard and explore its historical snapshots?")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Divider()

            HStack(spacing: 12) {
                Button(LocalizationManager.shared.effectiveLanguage == .hungarian ? "Most nem" : "Not Now") {
                    appState.dismissDiscoveredDrive()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    appState.adoptDiscoveredDrive()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                        Text(LocalizationManager.shared.effectiveLanguage == .hungarian ? "Hozzáadás a Menedékhez" : "Adopt into Sanctuary")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 4)
        }
        .padding(24)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
