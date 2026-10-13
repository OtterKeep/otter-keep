//
//  PreferencesModalView.swift
//  OtterKeepUI
//
//  Tabbed popup sheet for global preferences and application configuration.
//

import SwiftUI
import AppKit
import OtterKeepCore

/// Tabbed popup modal sheet for general application settings, preferences, and diagnostics.
public struct PreferencesModalView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var selectedTabBinding: Binding<PreferencesTab> {
        Binding(
            get: { appState.activePreferencesTab },
            set: { appState.activePreferencesTab = $0 }
        )
    }

    private var themeBinding: Binding<AppThemeMode> {
        Binding(
            get: { appState.currentTheme },
            set: { appState.currentTheme = $0 }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { appState.currentLanguage },
            set: { appState.currentLanguage = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.launchAtLoginEnabled },
            set: { appState.launchAtLoginEnabled = $0 }
        )
    }

    private var startMinimizedBinding: Binding<Bool> {
        Binding(
            get: { appState.startMinimized },
            set: { appState.startMinimized = $0 }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(OtterTheme.oceanicTeal)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.menuPreferences))
                        .font(.headline.bold())
                    Text("OtterKeep v\(CoreEngine.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.t(.okDone)) {
                    appState.showPreferencesModal = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Tab Picker
            Picker("", selection: selectedTabBinding) {
                ForEach(PreferencesTab.allCases) { tab in
                    Label(tab.localizedTitle, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch appState.activePreferencesTab {
                    case .general:
                        generalTabContent
                    case .finder:
                        finderTabContent
                    case .storage:
                        storageTabContent
                    case .diagnostics:
                        diagnosticsTabContent
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 520, idealHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshFinderPermissionStatus()
        }
    }

    // MARK: - 1. General Tab
    @ViewBuilder
    private var generalTabContent: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                // Language Selection
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(OtterTheme.otterAmber)
                        Text(L10n.t(.settingsLanguageSection))
                            .font(.title3.bold())
                    }

                    Text(L10n.t(.settingsLanguageDesc))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Picker("", selection: languageBinding) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .font(.body)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                // Theme Selection
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.title2)
                            .foregroundStyle(OtterTheme.otterAmber)
                        Text(L10n.t(.settingsAppearanceSection))
                            .font(.title3.bold())
                    }

                    Text(L10n.t(.settingsAppearanceDesc))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Picker("", selection: themeBinding) {
                        ForEach(AppThemeMode.allCases, id: \.self) { mode in
                            Label(mode.localizedTitle, systemImage: mode.iconName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
        }

        // Startup Section
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "power.circle.fill")
                    .font(.title2)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Text(L10n.t(.settingsStartupSection))
                    .font(.title3.bold())
            }

            Text(L10n.t(.settingsLaunchAtLoginDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle(isOn: launchAtLoginBinding) {
                Text(L10n.t(.settingsLaunchAtLoginToggle))
                    .font(.body.weight(.medium))
            }
            .toggleStyle(.switch)

            Divider()

            Toggle(isOn: startMinimizedBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.settingsStartMinimizedToggle))
                        .font(.body.weight(.medium))
                    Text(L10n.t(.settingsStartMinimizedDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 2. Finder Integration Tab
    @ViewBuilder
    private var finderTabContent: some View {
        SettingsView(appState: appState).permissionStatusHUD
        SettingsView(appState: appState).finderIntegrationSection
    }

    // MARK: - 3. Storage & DB Tab
    @ViewBuilder
    private var storageTabContent: some View {
        SettingsView(appState: appState).persistentFilesSection
    }

    // MARK: - 4. Diagnostics & Updates Tab
    @ViewBuilder
    private var diagnosticsTabContent: some View {
        SettingsView(appState: appState).debugLoggingSection
        SettingsView(appState: appState).softwareUpdatesSection
    }
}
