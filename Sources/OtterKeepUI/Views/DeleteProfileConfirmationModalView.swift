//
//  DeleteProfileConfirmationModalView.swift
//  OtterKeepUI
//
//  Charming, reassuring mascot-adorned confirmation modal for profile deletion.
//

import AppKit
import OtterKeepCore
import SwiftUI

/// Charming, reassuring modal dialog with Ottie looking questioningly and adorably at the user
/// before confirming profile deletion.
public struct DeleteProfileConfirmationModalView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var targetProfile: BackupProfile? {
        appState.profilePendingDeletion ?? appState.selectedProfile
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Hero Presentation: Questioning Ottie Mascot
            VStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    OttieSanctuaryMascotView(mood: .warning, size: 120)

                    // Adorable questioning badge
                    HStack(spacing: 3) {
                        Image(systemName: "questionmark.bubble.fill")
                            .font(.title3.bold())
                            .foregroundStyle(OtterTheme.otterAmber)
                    }
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .offset(x: 10, y: -2)
                }
                .padding(.top, 24)

                Text(L10n.t(.deleteProfileConfirmTitle))
                    .font(OtterTheme.heroTitleFont)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                if let profile = targetProfile {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.subheadline)
                            .foregroundStyle(OtterTheme.oceanicTeal)
                        Text(profile.name)
                            .font(.subheadline.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(OtterTheme.oceanicTeal.opacity(0.12), in: Capsule())
                }

                Text(L10n.t(.deleteProfileConfirmMessage))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                    .lineSpacing(2)
            }

            Spacer(minLength: 20)

            // Pinned Footer Actions
            ModalFooterActionsView(
                cancelTitle: L10n.t(.cancel),
                primaryTitle: L10n.t(.deleteProfileButton),
                isPrimaryDestructive: true,
                onCancel: {
                    appState.showDeleteProfileConfirmation = false
                    appState.profilePendingDeletion = nil
                },
                onPrimary: {
                    if let profile = targetProfile {
                        Task { @MainActor in
                            if appState.isBiometricsEnabled && appState.requireBiometricsForProfileDeletion {
                                let authResult = await BiometricSecurityService.shared.authenticate(
                                    reason: L10n.t(.biometricsAuthPromptDelete)
                                )
                                if case .failure = authResult {
                                    appState.showError(L10n.t(.biometricsAuthFailed))
                                    return
                                }
                            }
                            appState.deleteProfile(id: profile.id)
                            appState.showDeleteProfileConfirmation = false
                            appState.profilePendingDeletion = nil
                        }
                    } else {
                        appState.showDeleteProfileConfirmation = false
                        appState.profilePendingDeletion = nil
                    }
                }
            )
        }
        .frame(
            minWidth: 400, idealWidth: 440, maxWidth: 560,
            minHeight: 320, idealHeight: 380, maxHeight: 620
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
