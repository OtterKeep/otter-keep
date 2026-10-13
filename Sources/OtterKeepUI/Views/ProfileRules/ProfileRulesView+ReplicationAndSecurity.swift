import SwiftUI
import AppKit
import OtterKeepStorage
import OtterKeepCore

extension ProfileRulesView {
    // MARK: - 6. 3-2-1 Backup Copy Job & Remote Targets
    func backupCopyJobSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.t(.rule321Title), systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(.headline)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Spacer()
                Text(L10n.t(.rule321Desc))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                // Master Copy Job Toggle
                Toggle(isOn: Binding(
                    get: { profile.copyJobConfig.isEnabled },
                    set: { enabled in
                        var updated = profile
                        updated.copyJobConfig.isEnabled = enabled
                        if enabled && updated.copyJobConfig.destinations.isEmpty {
                            // Provide default Cloud and NAS destinations
                            let defaultS3 = RemoteDestination(
                                name: "AWS S3 / Backblaze Cloud",
                                type: .s3(S3Configuration(endpoint: "https://s3.eu-central-1.amazonaws.com", bucket: "otterkeep-offsite", region: "eu-central-1", pathPrefix: "backups")),
                                isClientEncryptionEnabled: true
                            )
                            updated.copyJobConfig.destinations.append(defaultS3)
                        }
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.copyJobMasterToggleTitle))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.copyJobMasterToggleDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                if profile.copyJobConfig.isEnabled {
                    Divider()

                    // Trigger Selection
                    HStack {
                        Text(L10n.t(.copyJobTriggerLabel))
                            .font(.body)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { profile.copyJobConfig.trigger },
                            set: { val in
                                var updated = profile
                                updated.copyJobConfig.trigger = val
                                appState.selectedProfile = updated
                            }
                        )) {
                            ForEach(CopyJobTrigger.allCases, id: \.self) { trg in
                                Text(trg.localizedTitle).tag(trg)
                            }
                        }
                        .frame(width: 220)
                    }

                    // Network Policy
                    HStack {
                        Text(L10n.t(.copyJobNetworkPolicyLabel))
                            .font(.body)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { profile.copyJobConfig.networkPolicy },
                            set: { val in
                                var updated = profile
                                updated.copyJobConfig.networkPolicy = val
                                appState.selectedProfile = updated
                            }
                        )) {
                            ForEach(CopyJobNetworkPolicy.allCases, id: \.self) { pol in
                                Text(pol.localizedTitle).tag(pol)
                            }
                        }
                        .frame(width: 220)
                    }

                    // Smart Bandwidth Throttling
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.smartThrottlingTitle))
                                .font(.body)
                            Text(L10n.t(.smartThrottlingDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { profile.copyJobConfig.maxBandwidthBytesPerSec },
                            set: { val in
                                var updated = profile
                                updated.copyJobConfig.maxBandwidthBytesPerSec = val
                                appState.selectedProfile = updated
                            }
                        )) {
                            Text(L10n.t(.copyJobThrottlingUnlimited)).tag(Int64(0))
                            Text(L10n.t(.copyJobThrottlingGentle)).tag(Int64(2 * 1024 * 1024))
                            Text(L10n.t(.copyJobThrottlingRecommended)).tag(Int64(5 * 1024 * 1024))
                            Text(L10n.t(.copyJobThrottlingFast)).tag(Int64(10 * 1024 * 1024))
                            Text(L10n.t(.copyJobThrottlingHigh)).tag(Int64(25 * 1024 * 1024))
                        }
                        .frame(width: 180)
                    }

                    // Parallel Multi-Destination Replication Toggle
                    Toggle(isOn: Binding(
                        get: { profile.isParallelMultiDestinationEnabled },
                        set: { val in
                            var updated = profile
                            updated.isParallelMultiDestinationEnabled = val
                            appState.selectedProfile = updated
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundStyle(OtterTheme.oceanicTeal)
                                Text(L10n.t(.parallelMultiDestTitle))
                                    .font(.body.weight(.medium))
                            }
                            Text(L10n.t(.parallelMultiDestDescription))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Remote Destinations List Header with Add Button
                    HStack {
                        Text(L10n.t(.remoteDestinationsTitle))
                            .font(.subheadline.bold())
                        Spacer()
                        Button {
                            appState.openDestinationEditor(destination: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text(L10n.t(.addRemoteDestinationButton))
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(OtterTheme.otterAmber)
                        .controlSize(.small)
                    }

                    if profile.copyJobConfig.destinations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "cloud.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(L10n.t(.noRemoteDestinationsNotice))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L10n.t(.addRemoteDestinationPrompt)) {
                                appState.openDestinationEditor(destination: nil)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(profile.copyJobConfig.destinations) { dest in
                            HStack(spacing: 12) {
                                Image(systemName: {
                                    switch dest.type {
                                    case .s3: return "icloud.fill"
                                    case .backblazeB2: return "flame.fill"
                                    case .smb: return "server.rack"
                                    case .webdav: return "network"
                                    case .sftp: return "terminal.fill"
                                    }
                                }())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                                .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(dest.name)
                                            .font(.body.weight(.medium))
                                            .lineLimit(1)
                                        if dest.isClientEncryptionEnabled {
                                            HStack(spacing: 3) {
                                                Image(systemName: "lock.fill")
                                                Text("AES-256")
                                            }
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(OtterTheme.oceanicTeal.opacity(0.15), in: Capsule())
                                            .foregroundStyle(OtterTheme.oceanicTeal)
                                        }
                                        if dest.archivePackagingEnabled {
                                            HStack(spacing: 3) {
                                                Image(systemName: "archivebox.fill")
                                                Text("TAR.ZST (L\(dest.archiveCompressionLevel))")
                                            }
                                            .font(.caption2.bold().monospacedDigit())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(OtterTheme.otterAmber.opacity(0.15), in: Capsule())
                                            .foregroundStyle(OtterTheme.otterAmber)
                                        }
                                    }

                                    Text({ () -> String in
                                        switch dest.type {
                                        case .s3(let cfg): return "S3: \(cfg.endpoint) [\(cfg.bucket)]"
                                        case .backblazeB2(let cfg): return "B2: \(cfg.bucketName) (\(cfg.region))"
                                        case .smb(let cfg): return "SMB: \(cfg.shareURL)"
                                        case .webdav(let cfg): return "WebDAV: \(cfg.serverURL)\(cfg.destinationPath)"
                                        case .sftp(let cfg): return "SFTP: \(cfg.host):\(cfg.port)\(cfg.remotePath)"
                                        }
                                    }())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 6) {
                                    Button {
                                        appState.openDestinationEditor(destination: dest)
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(L10n.t(.editRemoteDestination))

                                    Button {
                                        appState.deleteDestinationEditor(destinationId: dest.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(OtterTheme.statusError)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help(L10n.t(.deleteRemoteDestination))

                                    Toggle("", isOn: Binding(
                                        get: { dest.isEnabled },
                                        set: { enabled in
                                            var updated = profile
                                            if let idx = updated.copyJobConfig.destinations.firstIndex(where: { $0.id == dest.id }) {
                                                updated.copyJobConfig.destinations[idx].isEnabled = enabled
                                                appState.selectedProfile = updated
                                            }
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .labelsHidden()
                                    .fixedSize()
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                            .otterCard(padding: 10, cornerRadius: 8)
                        }
                    }
                }
            }
            .otterCard()
        }
    }

    // MARK: - 9. Ransomware & Rate-of-Change Anomaly Guard
    func ransomwareGuardSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(OtterTheme.statusWarning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.ransomwareSectionTitle))
                        .font(.headline)
                    Text(L10n.t(.ransomwareSectionDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { profile.enableRateOfChangeGuard },
                    set: { val in
                        var updated = profile
                        updated.enableRateOfChangeGuard = val
                        appState.selectedProfile = updated
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .fixedSize()
            }

            if profile.enableRateOfChangeGuard {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    // Percent threshold
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.ransomwareMaxChangePercentLabel))
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: L10n.t(.ransomwareThresholdPercentFormat), profile.maxChangeThresholdPercent))
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }
                        Slider(
                            value: Binding(
                                get: { profile.maxChangeThresholdPercent },
                                set: { val in
                                    var updated = profile
                                    updated.maxChangeThresholdPercent = val
                                    appState.selectedProfile = updated
                                }
                            ),
                            in: 5...100,
                            step: 5
                        )
                    }

                    // Deleted threshold
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.ransomwareMaxDeletedCountLabel))
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: L10n.t(.ransomwareThresholdCountFormat), profile.maxDeletedThresholdCount))
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(profile.maxDeletedThresholdCount) },
                                set: { val in
                                    var updated = profile
                                    updated.maxDeletedThresholdCount = Int(val)
                                    appState.selectedProfile = updated
                                }
                            ),
                            in: 10...5000,
                            step: 10
                        )
                    }

                    Divider()

                    // Known extensions
                    Toggle(L10n.t(.ransomwareDetectExtensionsToggle), isOn: Binding(
                        get: { profile.detectKnownRansomwareExtensions },
                        set: { val in
                            var updated = profile
                            updated.detectKnownRansomwareExtensions = val
                            appState.selectedProfile = updated
                        }
                    ))
                    .font(.subheadline)

                    // Abort on anomaly
                    Toggle(isOn: Binding(
                        get: { profile.abortOnAnomaly },
                        set: { val in
                            var updated = profile
                            updated.abortOnAnomaly = val
                            appState.selectedProfile = updated
                        }
                    )) {
                        HStack {
                            Text(L10n.t(.ransomwareAbortToggle))
                                .font(.subheadline)
                            if profile.abortOnAnomaly {
                                Text(L10n.t(.ransomwareAutoPauseBadge))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(OtterTheme.otterAmber.opacity(0.14), in: Capsule())
                                    .foregroundStyle(OtterTheme.otterAmber)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .otterCard()
    }

}
