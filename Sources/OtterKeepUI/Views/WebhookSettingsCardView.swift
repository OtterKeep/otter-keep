import SwiftUI
import OtterKeepCore

/// Card component allowing configuration and testing of remote webhooks (Slack, Discord, Pushover, HTTP POST).
public struct WebhookSettingsCardView: View {
    public let appState: AppState
    public let profile: BackupProfile

    public init(appState: AppState, profile: BackupProfile) {
        self.appState = appState
        self.profile = profile
    }

    private func updateProfile(_ block: (inout BackupProfile) -> Void) {
        var copy = profile
        block(&copy)
        appState.selectedProfile = copy
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: OtterTheme.spacing16) {
            // Header with Master Switch
            HStack(spacing: OtterTheme.spacing8) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.otterAmber)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.webhookSectionTitle))
                        .font(.headline)
                    Text(L10n.t(.webhookSectionDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { profile.webhookConfig.isEnabled },
                    set: { val in
                        updateProfile { $0.webhookConfig.isEnabled = val }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
            }

            if profile.webhookConfig.isEnabled {
                Divider()

                VStack(alignment: .leading, spacing: OtterTheme.spacing16) {
                    // Service Type Picker
                    HStack {
                        Text(L10n.t(.webhookServiceTypeLabel))
                            .font(.body)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { profile.webhookConfig.serviceType },
                            set: { val in
                                updateProfile { $0.webhookConfig.serviceType = val }
                            }
                        )) {
                            ForEach(WebhookServiceType.allCases, id: \.self) { svc in
                                Label(svc.displayName, systemImage: svc.iconName).tag(svc)
                            }
                        }
                        .frame(width: 240)
                    }

                    // Webhook URL
                    VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                        Text(L10n.t(.webhookUrlLabel))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(L10n.t(.webhookUrlPlaceholder), text: Binding(
                            get: { profile.webhookConfig.url },
                            set: { val in
                                updateProfile { $0.webhookConfig.url = val }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                    }

                    // Optional Auth Token / Pushover Token
                    if profile.webhookConfig.serviceType == .pushover || profile.webhookConfig.serviceType == .genericJson {
                        VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                            Text(L10n.t(.webhookTokenLabel))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            SecureField(L10n.t(.webhookTokenPlaceholder), text: Binding(
                                get: { profile.webhookConfig.authToken ?? "" },
                                set: { val in
                                    updateProfile { $0.webhookConfig.authToken = val.isEmpty ? nil : val }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                        }
                    }

                    // Target User or Channel Override
                    if profile.webhookConfig.serviceType == .pushover || profile.webhookConfig.serviceType == .slack {
                        VStack(alignment: .leading, spacing: OtterTheme.spacing4) {
                            Text(L10n.t(.webhookTargetLabel))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField(L10n.t(.webhookTargetPlaceholder), text: Binding(
                                get: { profile.webhookConfig.targetUserOrChannel ?? "" },
                                set: { val in
                                    updateProfile { $0.webhookConfig.targetUserOrChannel = val.isEmpty ? nil : val }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                        }
                    }

                    // Event Filter Toggles
                    FlowLayout(spacing: OtterTheme.spacing16) {
                        Toggle(L10n.t(.webhookNotifyOnSuccess), isOn: Binding(
                            get: { profile.webhookConfig.notifyOnSuccess },
                            set: { val in updateProfile { $0.webhookConfig.notifyOnSuccess = val } }
                        ))
                        .toggleStyle(.checkbox)

                        Toggle(L10n.t(.webhookNotifyOnWarning), isOn: Binding(
                            get: { profile.webhookConfig.notifyOnWarning },
                            set: { val in updateProfile { $0.webhookConfig.notifyOnWarning = val } }
                        ))
                        .toggleStyle(.checkbox)

                        Toggle(L10n.t(.webhookNotifyOnFailure), isOn: Binding(
                            get: { profile.webhookConfig.notifyOnFailure },
                            set: { val in updateProfile { $0.webhookConfig.notifyOnFailure = val } }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    .font(.callout)

                    Divider()

                    // Test Webhook Action
                    HStack(spacing: OtterTheme.spacing12) {
                        Button {
                            appState.testWebhook(config: profile.webhookConfig)
                        } label: {
                            if appState.webhookTestingStatus.isTesting {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(L10n.t(.details))
                                }
                            } else {
                                Label(L10n.t(.webhookTestButton), systemImage: "paperplane.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(profile.webhookConfig.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.webhookTestingStatus.isTesting)

                        if let msg = appState.webhookTestingStatus.message {
                            HStack(spacing: 6) {
                                Image(systemName: appState.webhookTestingStatus.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(appState.webhookTestingStatus.isSuccess ? OtterTheme.statusGreen : OtterTheme.statusError)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(appState.webhookTestingStatus.isSuccess ? OtterTheme.statusGreen : OtterTheme.statusError)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(.top, OtterTheme.spacing4)
            }
        }
        .otterCard()
    }
}
