//
//  ProfileSettingsModalView.swift
//  OtterKeepUI
//
//  Tabbed popup sheet for profile-level configuration, rules, automation,
//  retention policy, and WORM immutability.
//

import AppKit
import OtterKeepCore
import SwiftUI

/// Tabbed popup modal sheet for configuring all parameters of an individual backup profile.
public struct ProfileSettingsModalView: View {
    public let appState: AppState
    public let profile: BackupProfile

    public init(appState: AppState, profile: BackupProfile) {
        self.appState = appState
        self.profile = profile
    }

    private var currentProfile: BackupProfile {
        appState.selectedProfile ?? profile
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(OtterTheme.otterAmber)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.profileSettingsTitle))
                        .font(.headline.bold())
                    Text(currentProfile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.cancelProfileSettings()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(.closeButton))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Tabbed Content
            ProfileRulesAndMaintenanceView(appState: appState, profile: currentProfile)

            // Pinned Action Buttons Footer
            ModalFooterActionsView(
                cancelTitle: L10n.t(.cancel),
                primaryTitle: L10n.t(.save),
                onCancel: {
                    appState.cancelProfileSettings()
                },
                onPrimary: {
                    appState.saveProfileSettings()
                }
            )
        }
        .frame(minWidth: 720, idealWidth: 760, maxWidth: .infinity, minHeight: 520, idealHeight: 580, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if appState.profileSettingsBaseline == nil {
                appState.profileSettingsBaseline = currentProfile
            }
        }
        .onDisappear {
            if appState.profileSettingsBaseline != nil {
                appState.cancelProfileSettings()
            }
        }
        .onChange(of: appState.showRemoteDestinationEditorSheet) { _, isShowing in
            if !isShowing, let current = appState.selectedProfile {
                appState.profileSettingsBaseline = current
            }
        }
        .id(appState.currentLanguage)
    }
}
