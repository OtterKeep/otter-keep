//
//  ProfileSettingsModalView.swift
//  OtterKeepUI
//
//  Tabbed popup sheet for profile-level configuration, rules, automation,
//  retention policy, and WORM immutability.
//

import SwiftUI
import AppKit
import OtterKeepCore

/// Tabbed popup modal sheet for configuring all parameters of an individual backup profile.
public struct ProfileSettingsModalView: View {
    public let appState: AppState
    public let profile: BackupProfile

    public init(appState: AppState, profile: BackupProfile) {
        self.appState = appState
        self.profile = profile
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
                    Text(profile.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.t(.save)) {
                    appState.showProfileSettingsModal = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Tabbed Content
            ProfileRulesAndMaintenanceView(appState: appState, profile: profile)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
