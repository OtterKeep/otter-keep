import SwiftUI
import AppKit
import OtterKeepDomain
import OtterKeepCore

/// A calm, reassuring four-step onboarding wizard introducing the user to their digital sanctuary.
public struct SanctuaryOnboardingModalView: View {
    public let appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    private var currentStep: Int {
        appState.maintenanceSettings.onboardingCurrentStep
    }

    private var profileNameBinding: Binding<String> {
        Binding(
            get: {
                if appState.maintenanceSettings.onboardingProfileName.isEmpty {
                    return L10n.t(.defaultProfileName)
                }
                return appState.maintenanceSettings.onboardingProfileName
            },
            set: { appState.maintenanceSettings.onboardingProfileName = $0 }
        )
    }

    private var continuousModeBinding: Binding<Bool> {
        Binding(
            get: { appState.maintenanceSettings.onboardingIsContinuousMode },
            set: { appState.maintenanceSettings.onboardingIsContinuousMode = $0 }
        )
    }

    private var canaryTrapsBinding: Binding<Bool> {
        Binding(
            get: { appState.maintenanceSettings.onboardingEnableCanaryTraps },
            set: { appState.maintenanceSettings.onboardingEnableCanaryTraps = $0 }
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with Stepper Indicator
            headerView

            Divider()

            // Step Content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case 0:
                        welcomeStep
                    case 1:
                        fdaPermissionStep
                    case 2:
                        profileSetupStep
                    case 3:
                        protectionModeStep
                    default:
                        EmptyView()
                    }
                }
                .padding(28)
            }

            Divider()

            // Bottom Navigation Actions
            footerView
        }
        .frame(width: 580, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            checkPermissions()
        }
    }

    // MARK: - Header & Step Indicator

    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(L10n.t(.onboardingWelcomeTitle))
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            // Step dots
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Step 0: Welcome & Philosophy

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 90, height: 90)

                Image(systemName: "heart.shield.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 10)

            Text(L10n.t(.welcomeSanctuaryTitle))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(L10n.t(.welcomeSanctuarySubtitle))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 12) {
                featureBullet(
                    icon: "sparkles",
                    title: "APFS Copy-on-Write",
                    subtitle: "Zero-duplicate instantaneous snapshots without taking extra storage."
                )
                featureBullet(
                    icon: "lock.shield",
                    title: "Private & Local First",
                    subtitle: "Your data stays entirely under your control on your trusted drives."
                )
                featureBullet(
                    icon: "leaf.fill",
                    title: "Gentle on Battery & Hardware",
                    subtitle: "Smart power throttling keeps your Mac cool and silent."
                )
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Step 1: Full Disk Access (FDA)

    private var fdaPermissionStep: some View {
        let hasFDA = appState.maintenanceSettings.onboardingHasFDAPermission
        return VStack(spacing: 20) {
            Image(systemName: hasFDA ? "checkmark.seal.fill" : "lock.open.trianglebadge.exclamationmark.fill")
                .font(.system(size: 48))
                .foregroundStyle(hasFDA ? Color.green : Color.orange)
                .padding(.top, 10)

            Text(L10n.t(.onboardingStepFDA))
                .font(.title2.weight(.bold))

            Text("OtterKeep requires Full Disk Access to safely back up protected user directories like Documents, Desktop, and Mail without permission errors.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(hasFDA ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(hasFDA ? L10n.t(.permissionFDAGranted) : L10n.t(.permissionFDAMissing))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())

                Button {
                    openSystemSettingsFDA()
                } label: {
                    Label(L10n.t(.permissionOpenSettings), systemImage: "arrow.up.forward.app")
                }
                .controlSize(.regular)

                Button {
                    checkPermissions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Recheck Full Disk Access")
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Step 2: First Profile Setup

    private var profileSetupStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.onboardingStepProfile))
                    .font(.title2.weight(.bold))
                Text("Select the primary folders you wish to safeguard.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                // Profile Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile Name")
                        .font(.headline)
                    TextField("Name", text: profileNameBinding)
                        .textFieldStyle(.roundedBorder)
                }

                // Source Folder
                VStack(alignment: .leading, spacing: 6) {
                    Text("Source Directory (What to back up)")
                        .font(.headline)
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.accentColor)
                        Text(appState.maintenanceSettings.onboardingSourceURL.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(.subheadline, design: .monospaced))
                        Spacer()
                        Button("Choose...") {
                            chooseFolder { appState.maintenanceSettings.onboardingSourceURL = $0 }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Destination Folder
                VStack(alignment: .leading, spacing: 6) {
                    Text("Destination Directory (Where to store snapshots)")
                        .font(.headline)
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(Color.accentColor)
                        Text(appState.maintenanceSettings.onboardingDestinationURL.path(percentEncoded: false))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.system(.subheadline, design: .monospaced))
                        Spacer()
                        Button("Choose...") {
                            chooseFolder { appState.maintenanceSettings.onboardingDestinationURL = $0 }
                        }
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Step 3: Protection Mode & Schedule

    private var protectionModeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.onboardingStepSchedule))
                    .font(.title2.weight(.bold))
                Text("Configure real-time monitoring and anti-ransomware traps.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                // Execution mode
                Toggle(isOn: continuousModeBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t(.executionModeContinuous))
                            .font(.headline)
                        Text(L10n.t(.continuousDebounceDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Canary trap toggle
                Toggle(isOn: canaryTrapsBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t(.enableCanaryTrapsLabel))
                            .font(.headline)
                        Text(L10n.t(.enableCanaryTrapsDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Footer Actions

    private var footerView: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation {
                        appState.maintenanceSettings.onboardingCurrentStep -= 1
                    }
                }
                .controlSize(.regular)
            }

            Button(L10n.t(.onboardingSkip)) {
                dismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.leading, 8)

            Spacer()

            if currentStep < 3 {
                Button(L10n.t(.onboardingContinue)) {
                    withAnimation {
                        appState.maintenanceSettings.onboardingCurrentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Button(L10n.t(.onboardingFinish)) {
                    finishAndCreateProfile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Helpers

    private func featureBullet(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkPermissions() {
        let testPath = ("~/Library/Mail" as NSString).expandingTildeInPath
        appState.maintenanceSettings.onboardingHasFDAPermission = FileManager.default.isReadableFile(atPath: testPath)
    }

    private func openSystemSettingsFDA() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func chooseFolder(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    private func finishAndCreateProfile() {
        let isCont = appState.maintenanceSettings.onboardingIsContinuousMode
        let execMode: BackupExecutionMode = isCont ? .continuous(debouncingSeconds: 30) : .scheduled(BackupSchedule(isEnabled: true, frequency: .daily, hour: 18))
        let name = appState.maintenanceSettings.onboardingProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = name.isEmpty ? L10n.t(.defaultProfileName) : name
        let src = appState.maintenanceSettings.onboardingSourceURL
        let dst = appState.maintenanceSettings.onboardingDestinationURL

        let profile = BackupProfile(
            name: resolvedName,
            sourceURL: src,
            destinationURL: dst,
            executionMode: execMode,
            enableCanaryTraps: appState.maintenanceSettings.onboardingEnableCanaryTraps
        )

        appState.profiles.append(profile)
        appState.saveProfiles()
        appState.selectedProfileId = profile.id
        appState.activeNavigation = .profile(profile.id)

        // Stamp zero-config profile metadata
        DriveProfileMetadata.write(for: profile, to: dst)

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        appState.showOnboardingModal = false
        dismiss()
    }
}
