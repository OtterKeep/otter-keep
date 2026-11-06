import SwiftUI
import OtterKeepCore

/// Card component configuring Wi-Fi SSID allow/disallow filtering and mobile hotspot metering safeguards.
public struct WiFiProtectionCardView: View {
    public let appState: AppState
    public let profile: BackupProfile

    public init(appState: AppState, profile: BackupProfile) {
        self.appState = appState
        self.profile = profile
    }

    private var currentSSID: String? {
        appState.currentWiFiSSID
    }

    private func updateProfile(_ block: (inout BackupProfile) -> Void) {
        var copy = profile
        block(&copy)
        appState.selectedProfile = copy
        appState.saveProfiles()
    }

    private var allowedSSIDBinding: Binding<String> {
        Binding(
            get: { appState.newAllowedWiFiSSID },
            set: { appState.newAllowedWiFiSSID = $0 }
        )
    }

    private var disallowedSSIDBinding: Binding<String> {
        Binding(
            get: { appState.newDisallowedWiFiSSID },
            set: { appState.newDisallowedWiFiSSID = $0 }
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: OtterTheme.spacing16) {
            // Header
            HStack(spacing: OtterTheme.spacing8) {
                Image(systemName: "wifi.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.oceanicTeal)

                Text(L10n.t(.wifiSectionTitle))
                    .font(.headline)

                Spacer()

                // Current Wi-Fi Indicator
                HStack(spacing: OtterTheme.spacing4) {
                    Image(systemName: "wifi")
                        .font(.caption2)
                    Text(currentSSID ?? L10n.t(.wifiNoActiveNetwork))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160)
                }
                .padding(.horizontal, OtterTheme.spacing8)
                .padding(.vertical, OtterTheme.spacing4)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .foregroundStyle(.secondary)
            }

            Text(L10n.t(.wifiSectionDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            // 1. Metered / Hotspot Guard Toggle
            Toggle(isOn: Binding(
                get: { profile.copyJobConfig.pauseOnMeteredNetwork },
                set: { val in
                    updateProfile { $0.copyJobConfig.pauseOnMeteredNetwork = val }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.wifiPauseOnMeteredToggle))
                        .font(.body.weight(.medium))
                    Text(L10n.t(.wifiPauseOnMeteredDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Divider()

            // 2. Allowed SSIDs
            VStack(alignment: .leading, spacing: OtterTheme.spacing8) {
                HStack {
                    Text(L10n.t(.wifiAllowedSSIDsLabel))
                        .font(.subheadline.bold())

                    Spacer()

                    if let curr = currentSSID, !profile.copyJobConfig.allowedWiFiSSIDs.contains(curr) {
                        Button {
                            updateProfile { $0.copyJobConfig.allowedWiFiSSIDs.append(curr) }
                        } label: {
                            Label(L10n.t(.wifiAddCurrentButton), systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if profile.copyJobConfig.allowedWiFiSSIDs.isEmpty {
                    Text(L10n.t(.wifiAllNetworksAllowed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: OtterTheme.spacing8) {
                        ForEach(profile.copyJobConfig.allowedWiFiSSIDs, id: \.self) { ssid in
                            ssidTag(name: ssid, isAllowed: true) {
                                updateProfile { p in
                                    p.copyJobConfig.allowedWiFiSSIDs.removeAll(where: { $0 == ssid })
                                }
                            }
                        }
                    }
                }

                // Add Allowed Input
                HStack(spacing: OtterTheme.spacing8) {
                    TextField(L10n.t(.wifiAllowedPlaceholder), text: allowedSSIDBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .onSubmit {
                            addAllowedSSID()
                        }

                    Button(L10n.t(.addRuleButton)) {
                        addAllowedSSID()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.newAllowedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Divider()

            // 3. Disallowed SSIDs
            VStack(alignment: .leading, spacing: OtterTheme.spacing8) {
                Text(L10n.t(.wifiDisallowedSSIDsLabel))
                    .font(.subheadline.bold())

                if !profile.copyJobConfig.disallowedWiFiSSIDs.isEmpty {
                    FlowLayout(spacing: OtterTheme.spacing8) {
                        ForEach(profile.copyJobConfig.disallowedWiFiSSIDs, id: \.self) { ssid in
                            ssidTag(name: ssid, isAllowed: false) {
                                updateProfile { p in
                                    p.copyJobConfig.disallowedWiFiSSIDs.removeAll(where: { $0 == ssid })
                                }
                            }
                        }
                    }
                }

                // Add Disallowed Input
                HStack(spacing: OtterTheme.spacing8) {
                    TextField(L10n.t(.wifiDisallowedPlaceholder), text: disallowedSSIDBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .onSubmit {
                            addDisallowedSSID()
                        }

                    Button(L10n.t(.addRuleButton)) {
                        addDisallowedSSID()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.newDisallowedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .otterCard()
    }

    private func addAllowedSSID() {
        let trimmed = appState.newAllowedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !profile.copyJobConfig.allowedWiFiSSIDs.contains(trimmed) {
            updateProfile { $0.copyJobConfig.allowedWiFiSSIDs.append(trimmed) }
        }
        appState.newAllowedWiFiSSID = ""
    }

    private func addDisallowedSSID() {
        let trimmed = appState.newDisallowedWiFiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !profile.copyJobConfig.disallowedWiFiSSIDs.contains(trimmed) {
            updateProfile { $0.copyJobConfig.disallowedWiFiSSIDs.append(trimmed) }
        }
        appState.newDisallowedWiFiSSID = ""
    }

    private func ssidTag(name: String, isAllowed: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isAllowed ? "checkmark.circle.fill" : "nosign")
                .font(.caption2)
                .foregroundStyle(isAllowed ? OtterTheme.statusGreen : OtterTheme.statusError)

            Text(name)
                .font(.caption.weight(.medium))

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OtterTheme.spacing8)
        .padding(.vertical, OtterTheme.spacing4)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(
            Capsule()
                .stroke(isAllowed ? OtterTheme.statusGreen.opacity(0.3) : OtterTheme.statusError.opacity(0.3), lineWidth: OtterTheme.cardBorderWidth)
        )
    }
}
