//
//  DeleteProfileConfirmationModalView.swift
//  OtterKeepUI
//
//  Charming, reassuring mascot-adorned confirmation modal for profile deletion.
//

import SwiftUI
import AppKit
import OtterKeepCore

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
                            .font(.system(size: 18, weight: .bold))
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

            Divider()

            // Footer Actions
            HStack(spacing: 12) {
                Button(L10n.t(.cancel)) {
                    appState.showDeleteProfileConfirmation = false
                    appState.profilePendingDeletion = nil
                }
                .keyboardShortcut(.cancelAction)
                .controlSize(.regular)

                Spacer()

                Button(role: .destructive) {
                    if let profile = targetProfile {
                        appState.deleteProfile(id: profile.id)
                    }
                    appState.showDeleteProfileConfirmation = false
                    appState.profilePendingDeletion = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text(L10n.t(.deleteProfileButton))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(OtterTheme.statusError)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
        .frame(width: 440, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
