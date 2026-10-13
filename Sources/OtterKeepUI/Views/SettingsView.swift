import SwiftUI
import AppKit
import OtterKeepCore

public struct SettingsView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Permission Status HUD
                permissionStatusHUD

                // Top Preferences: 1. Nyelvválasztó, 2. Témaválasztó (középen), 3. Rendszerindítás
                Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        // 1. Language Selection Section
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

                        // 2. Appearance & Theme Selection Card (Középen a Nyelv és Indítás között)
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

                        // 3. Launch at Login & Start Minimized Section
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

                            Spacer(minLength: 4)

                            Toggle(isOn: launchAtLoginBinding) {
                                Text(L10n.t(.settingsLaunchAtLoginToggle))
                                    .font(.body.weight(.medium))
                            }
                            .toggleStyle(.switch)

                            Divider()
                                .padding(.vertical, 2)

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                // 4. Persistent Files & Storage Section
                persistentFilesSection

                // 5. Debug Logging & Diagnostics Section (.log)
                debugLoggingSection

                // 6. Finder Integration Section (Global Toggle)
                finderIntegrationSection

                // 7. Software Updates Section (Sparkle 2.0 / Appcast)
                softwareUpdatesSection
            }
            .padding(24)
        }
        .onAppear {
            appState.refreshFinderPermissionStatus()
        }
    }
}
