import SwiftUI
import AppKit
import OtterKeepCore

/// Redesigned 3-workspace tab view separating Rules & Exclusions, Automation & Schedule,
/// and Maintenance & Storage into a clean, calm, user-friendly macOS interface.
public struct ProfileRulesAndMaintenanceView: View {
    public let appState: AppState
    public let profile: BackupProfile

    public init(appState: AppState, profile: BackupProfile) {
        self.appState = appState
        self.profile = profile
    }

    private var selectedSubTabBinding: Binding<ProfileMaintenanceSubTab> {
        Binding(
            get: { appState.activeMaintenanceSubTab },
            set: { appState.activeMaintenanceSubTab = $0 }
        )
    }

    private var maxSnapshotsToKeepBinding: Binding<Int> {
        Binding(
            get: { appState.maxSnapshotsToKeep },
            set: { val in
                appState.maxSnapshotsToKeep = val
                var updated = profile
                updated.pruningPolicy.maxSnapshotsToKeep = val
                appState.selectedProfile = updated
            }
        )
    }

    private var showConfirmPruneBinding: Binding<Bool> {
        Binding(get: { appState.showConfirmPrune }, set: { appState.showConfirmPrune = $0 })
    }

    private var showConfirmRebuildBinding: Binding<Bool> {
        Binding(get: { appState.showConfirmRebuild }, set: { appState.showConfirmRebuild = $0 })
    }

    private var rulesView: ProfileRulesView {
        ProfileRulesView(appState: appState)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Modern Segmented Workspace Picker
            Picker("", selection: selectedSubTabBinding) {
                ForEach(ProfileMaintenanceSubTab.allCases) { tab in
                    Label(tab.localizedTitle, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let isLocked = appState.isBackupRunning(for: profile.id)

                    if isLocked {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield.fill")
                                .font(.title3)
                                .foregroundStyle(OtterTheme.otterAmber)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t(.profileLockedBannerTitle))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(OtterTheme.otterAmber)
                                Text(L10n.t(.profileLockedBannerMessage))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .otterCard(padding: OtterTheme.spacing12)
                    }

                    Group {
                        switch appState.activeMaintenanceSubTab {
                        case .rules:
                            rulesContent
                        case .automation:
                            automationContent
                        case .maintenance:
                            maintenanceContent
                        }
                    }
                    .disabled(isLocked)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            L10n.t(.maintenancePruneConfirmTitle),
            isPresented: showConfirmPruneBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.t(.maintenancePruneConfirmAction), role: .destructive) {
                appState.pruneOldSnapshots(maxKeep: appState.maxSnapshotsToKeep)
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        } message: {
            Text(L10n.t(.maintenancePruneConfirmMessage))
        }
        .confirmationDialog(
            L10n.t(.maintenanceRebuildConfirmTitle),
            isPresented: showConfirmRebuildBinding,
            titleVisibility: .visible
        ) {
            Button(L10n.t(.maintenanceRebuildConfirmAction)) {
                appState.disasterRebuildCatalog()
            }
            Button(L10n.t(.cancel), role: .cancel) {}
        } message: {
            Text(L10n.t(.maintenanceRebuildConfirmMessage))
        }
        .sheet(isPresented: Binding(
            get: { appState.showRemoteDestinationEditorSheet },
            set: { appState.showRemoteDestinationEditorSheet = $0 }
        )) {
            RemoteDestinationEditorModalView(appState: appState)
        }
    }

    // MARK: - 1. Rules & Exclusions Tab Content
    @ViewBuilder
    private var rulesContent: some View {
        rulesView.folderSummaryHeader(profile: profile)
        rulesView.exclusionRulesSection(profile: profile)
        rulesView.localEncryptionSection(profile: profile)
        rulesView.icloudStrategySection(profile: profile)
        WiFiProtectionCardView(appState: appState, profile: profile)
        rulesView.ransomwareGuardSection(profile: profile)
        rulesView.canaryTrapSection(profile: profile)
    }

    // MARK: - 2. Automation & Schedule Tab Content
    @ViewBuilder
    private var automationContent: some View {
        rulesView.scheduleSection(profile: profile)
        rulesView.powerGovernorSection(profile: profile)
        rulesView.externalDriveSection(profile: profile)
        rulesView.backupCopyJobSection(profile: profile)
        WebhookSettingsCardView(appState: appState, profile: profile)
    }

    // MARK: - 3. Maintenance & Storage Tab Content
    @ViewBuilder
    private var maintenanceContent: some View {
        // Unified Retention Policy Card
        unifiedRetentionSection

        // WORM Immutability & Background Scrub
        rulesView.immutabilityAndScrubSection(profile: profile)

        // Disaster Recovery
        catalogRecoverySection

        // Profile Technical Metadata & UUID
        profileMetadataSection
    }

    // MARK: - Unified Retention Card
    private var unifiedRetentionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "scissors")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.otterAmber)
                Text(L10n.t(.maintenanceConsolidationTitle))
                    .font(.headline)
            }

            Text(L10n.t(.maintenanceConsolidationDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            // Auto-pruning toggle
            Toggle(isOn: Binding(
                get: { profile.pruningPolicy.isAutoPruningEnabled },
                set: { enabled in
                    var updated = profile
                    updated.pruningPolicy.isAutoPruningEnabled = enabled
                    appState.selectedProfile = updated
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.autoPruningToggleTitle))
                        .font(.body.weight(.medium))
                    Text(L10n.t(.autoPruningToggleDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Text(L10n.t(.maintenanceKeepSnapshotsLabel))
                    .font(.body.weight(.medium))

                Stepper(L10n.format(.unitCountFormat, appState.maxSnapshotsToKeep), value: maxSnapshotsToKeepBinding, in: 1...100)
                    .font(.body)
                    .frame(width: 140)

                Spacer()

                Button(L10n.t(.maintenancePruneButton)) {
                    appState.showConfirmPrune = true
                }
                .buttonStyle(.borderedProminent)
                .tint(OtterTheme.otterAmber)
                .disabled(appState.snapshots.count <= appState.maxSnapshotsToKeep)
            }
        }
        .otterCard(padding: 16)
    }

    // MARK: - Disaster Recovery Card
    private var catalogRecoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.cyberTeal)
                Text(L10n.t(.maintenanceRecoveryTitle))
                    .font(.headline)
            }

            Text(L10n.t(.maintenanceRecoveryDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L10n.t(.maintenanceRebuildButton)) {
                    appState.showConfirmRebuild = true
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .otterCard(padding: 16)
    }

    // MARK: - Profile Metadata & Identifiers Card
    private var profileMetadataSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder")
                    .font(.title3)
                    .foregroundStyle(OtterTheme.otterAmber)
                Text(L10n.t(.profileMetadataSectionTitle))
                    .font(.headline)
            }

            Text(L10n.t(.profileMetadataSectionDesc))
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.uuidLabel))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.id.uuidString)
                            .font(.callout.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(profile.id.uuidString, forType: .string)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text(L10n.t(.settingsCopyUUID))
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.sourceFolderTitle))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.sourceURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.destinationFolderTitle))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.destinationURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
        .otterCard(padding: 16)
    }
}
