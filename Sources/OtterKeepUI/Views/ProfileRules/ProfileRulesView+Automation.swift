import SwiftUI
import AppKit
import OtterKeepStorage
import OtterKeepCore

extension ProfileRulesView {
    // MARK: - 4. Backup Schedule
    func scheduleSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.scheduleAndRetentionHeader))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                // Schedule toggle
                Toggle(isOn: Binding(
                    get: { profile.schedule.isEnabled },
                    set: { enabled in
                        var updated = profile
                        updated.schedule.isEnabled = enabled
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.scheduleEnableToggle))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.scheduleCardSubtitle))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                if profile.schedule.isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()

                        HStack(spacing: 8) {
                            Text(L10n.t(.scheduleFrequencyLabel))
                                .font(.body)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { profile.schedule.frequency },
                                set: { freq in
                                    var updated = profile
                                    updated.schedule.frequency = freq
                                    appState.selectedProfile = updated
                                }
                            )) {
                                ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                                    Text(freq.localizedTitle).tag(freq)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        // Detailed controls for selected frequency
                        switch profile.schedule.frequency {
                        case .hourly:
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                Text(L10n.t(.scheduleHourlyDesc))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)

                        case .daily:
                            HStack {
                                Text(L10n.t(.scheduleHourLabel))
                                    .font(.body)
                                Spacer()
                                HStack(spacing: 8) {
                                    Picker("", selection: Binding(
                                        get: { profile.schedule.hour },
                                        set: { h in
                                            var updated = profile
                                            updated.schedule.hour = h
                                            appState.selectedProfile = updated
                                        }
                                    )) {
                                        ForEach(0..<24, id: \.self) { h in
                                            Text(String(format: "%02d:00", h)).tag(h)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 90)

                                    Picker("", selection: Binding(
                                        get: { profile.schedule.minute },
                                        set: { m in
                                            var updated = profile
                                            updated.schedule.minute = m
                                            appState.selectedProfile = updated
                                        }
                                    )) {
                                        ForEach([0, 15, 30, 45], id: \.self) { m in
                                            Text(String(format: ":%02d", m)).tag(m)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 75)
                                }
                            }

                        case .weekly:
                            HStack {
                                Text(L10n.t(.scheduleDayLabel))
                                    .font(.body)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { profile.schedule.weekday },
                                    set: { w in
                                        var updated = profile
                                        updated.schedule.weekday = w
                                        appState.selectedProfile = updated
                                    }
                                )) {
                                    Text(L10n.t(.monday)).tag(2)
                                    Text(L10n.t(.tuesday)).tag(3)
                                    Text(L10n.t(.wednesday)).tag(4)
                                    Text(L10n.t(.thursday)).tag(5)
                                    Text(L10n.t(.friday)).tag(6)
                                    Text(L10n.t(.saturday)).tag(7)
                                    Text(L10n.t(.sunday)).tag(1)
                                }
                                .labelsHidden()
                                .frame(width: 120)

                                Picker("", selection: Binding(
                                    get: { profile.schedule.hour },
                                    set: { h in
                                        var updated = profile
                                        updated.schedule.hour = h
                                        appState.selectedProfile = updated
                                    }
                                )) {
                                    ForEach(0..<24, id: \.self) { h in
                                        Text(String(format: "%02d:00", h)).tag(h)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 90)
                            }

                        case .intervalMinutes:
                            HStack {
                                Text(L10n.t(.scheduleIntervalLabel))
                                    .font(.body)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { profile.schedule.intervalMinutes },
                                    set: { val in
                                        var updated = profile
                                        updated.schedule.intervalMinutes = val
                                        appState.selectedProfile = updated
                                    }
                                )) {
                                    Text(L10n.t(.interval15m)).tag(15)
                                    Text(L10n.t(.interval30m)).tag(30)
                                    Text(L10n.t(.interval1h)).tag(60)
                                    Text(L10n.t(.interval2h)).tag(120)
                                    Text(L10n.t(.interval4h)).tag(240)
                                    Text(L10n.t(.interval8h)).tag(480)
                                }
                                .frame(width: 140)
                            }
                        }

                        // Catch-up missed backups toggle
                        Toggle(isOn: Binding(
                            get: { profile.schedule.catchUpIfMissed },
                            set: { val in
                                var updated = profile
                                updated.schedule.catchUpIfMissed = val
                                appState.selectedProfile = updated
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t(.scheduleCatchUpToggle))
                                    .font(.body)
                                Text(L10n.t(.scheduleCatchUpDesc))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .otterCard()
        }
    }

    // MARK: - WORM Immutability & Scrub Section
    func immutabilityAndScrubSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(OtterTheme.accentPurple)
                Text(L10n.t(.wormLockTitle))
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 14) {
                // WORM Immutability Lock (uchg / schg)
                Toggle(isOn: Binding(
                    get: { profile.isImmutabilityLockEnabled },
                    set: { enabled in
                        var updated = profile
                        updated.isImmutabilityLockEnabled = enabled
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(L10n.t(.wormLockTitle))
                                .font(.body.weight(.medium))
                        }
                        Text(L10n.t(.wormLockDescription))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                if profile.isImmutabilityLockEnabled {
                    HStack {
                        Text(L10n.t(.wormLockDurationDays))
                            .font(.body)
                        Spacer()
                        Stepper(value: Binding(
                            get: { profile.immutabilityLockDays },
                            set: { val in
                                var updated = profile
                                updated.immutabilityLockDays = max(1, val)
                                appState.selectedProfile = updated
                            }
                        ), in: 1...365) {
                            Text("\(profile.immutabilityLockDays) nap")
                                .monospacedDigit()
                        }
                    }
                    .padding(.leading, 24)
                }

                Divider()

                // Manual Integrity Scrub button
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(OtterTheme.statusGreen)
                            Text(L10n.t(.verifySnapshotIntegrityTitle))
                                .font(.body.weight(.medium))
                        }
                        Text(L10n.t(.verifySnapshotIntegrityDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appState.performManualScrub(profile: profile)
                    } label: {
                        HStack(spacing: 6) {
                            if appState.isDataScrubInProgress {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.circle.fill")
                            }
                            Text(L10n.t(.verifySnapshotIntegrityButton))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OtterTheme.oceanicTeal)
                    .controlSize(.regular)
                    .disabled(appState.isDataScrubInProgress)
                }
            }
            .otterCard()
        }
    }

    // MARK: - 5. External Drive Automation
    func externalDriveSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.timemachine")
                    .foregroundStyle(OtterTheme.otterAmber)
                Text(L10n.t(.driveAutomationHeader))
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { profile.backupOnVolumeMount },
                    set: { val in
                        var updated = profile
                        updated.backupOnVolumeMount = val
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.backupOnVolumeMountToggle))
                            .font(.body.weight(.medium))
                        Text(L10n.t(.backupOnVolumeMountDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(isOn: Binding(
                    get: { profile.autoEjectOnCompletion },
                    set: { val in
                        var updated = profile
                        updated.autoEjectOnCompletion = val
                        appState.selectedProfile = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(.autoEjectOnCompletionToggle))
                            .font(.body)
                        Text(L10n.t(.autoEjectOnCompletionDesc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.leading, 20)
                .disabled(!profile.backupOnVolumeMount)
                .opacity(profile.backupOnVolumeMount ? 1.0 : 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .otterCard()
        }
    }


}
