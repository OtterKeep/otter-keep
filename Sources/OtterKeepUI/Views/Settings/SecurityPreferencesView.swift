import SwiftUI
import AppKit
import OtterKeepCore

/// Preferences tab view for configuring Touch ID biometrics, action gates, and Secure Enclave hardware protection.
public struct SecurityPreferencesView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Hardware Sensor Status Banner
            hardwareStatusBanner

            // Biometric Master Toggle & Action Gates
            biometricGatesSection

            // Hardware Secure Enclave Protection
            secureEnclaveSection
        }
        .onAppear {
            appState.refreshBiometricHardwareState()
        }
    }

    // MARK: - Hardware Status Banner
    private var hardwareStatusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: hardwareStatusIcon)
                .font(.title2)
                .foregroundStyle(hardwareStatusColor)
                .frame(width: 38, height: 38)
                .background(hardwareStatusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(.biometricsTabTitle))
                    .font(.headline.bold())

                Text(hardwareStatusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle(isOn: Binding(
                get: { appState.isBiometricsEnabled },
                set: { appState.isBiometricsEnabled = $0 }
            )) {
                Text(L10n.t(.biometricsEnableMasterToggle))
                    .font(.subheadline.weight(.medium))
            }
            .toggleStyle(.switch)
            .disabled(isHardwareUnavailable)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Biometric Action Gates
    private var biometricGatesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.shield.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Text("Védett Műveletek (Action Gates)")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { appState.requireBiometricsForRestore },
                    set: { appState.requireBiometricsForRestore = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.biometricsRequireForRestore))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.biometricsRequireForRestoreDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Divider()

                Toggle(isOn: Binding(
                    get: { appState.requireBiometricsForProfileDeletion },
                    set: { appState.requireBiometricsForProfileDeletion = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.biometricsRequireForDelete))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.biometricsRequireForDeleteDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Divider()

                Toggle(isOn: Binding(
                    get: { appState.requireBiometricsForKeyReveal },
                    set: { appState.requireBiometricsForKeyReveal = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.biometricsRequireForKeyReveal))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.biometricsRequireForKeyRevealDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .disabled(!appState.isBiometricsEnabled)
            .opacity(appState.isBiometricsEnabled ? 1.0 : 0.5)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Secure Enclave Section
    private var secureEnclaveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.otterAmber)
                Text(L10n.t(.biometricsHardwareSecureEnclave))
                    .font(.headline)
            }

            Text(L10n.t(.biometricsHardwareSecureEnclaveDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle(isOn: Binding(
                get: { appState.useSecureEnclaveForKeychain },
                set: { appState.useSecureEnclaveForKeychain = $0 }
            )) {
                Text("Apple Secure Enclave Hardveres Kulcszárolás")
                    .font(.body.weight(.medium))
            }
            .toggleStyle(.switch)
            .disabled(!appState.isBiometricsEnabled)
            .opacity(appState.isBiometricsEnabled ? 1.0 : 0.5)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers
    private var hardwareStatusIcon: String {
        switch appState.biometricHardwareState {
        case .touchIDAvailable: return "touchid"
        case .passcodeOnly: return "lock.circle.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var hardwareStatusColor: Color {
        switch appState.biometricHardwareState {
        case .touchIDAvailable: return OtterTheme.statusGreen
        case .passcodeOnly: return OtterTheme.oceanicTeal
        case .unavailable: return OtterTheme.statusWarning
        }
    }

    private var hardwareStatusDescription: String {
        switch appState.biometricHardwareState {
        case .touchIDAvailable: return L10n.t(.biometricsTouchIDAvailable)
        case .passcodeOnly: return L10n.t(.biometricsTouchIDUnavailable)
        case .unavailable(let reason): return reason
        }
    }

    private var isHardwareUnavailable: Bool {
        if case .unavailable = appState.biometricHardwareState { return true }
        return false
    }
}
