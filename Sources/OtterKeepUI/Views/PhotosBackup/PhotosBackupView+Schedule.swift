import SwiftUI
import Photos
import UniformTypeIdentifiers
import OtterKeepCore
import OtterKeepDatabase

extension PhotosBackupView {
    // MARK: - Schedule Section
    var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.scheduleCardTitle))
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { appState.photosConfig.schedule.isEnabled },
                    set: {
                        appState.photosConfig.schedule.isEnabled = $0
                        appState.savePhotosConfig()
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

                if appState.photosConfig.schedule.isEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()

                        HStack(spacing: 8) {
                            Text(L10n.t(.scheduleFrequencyLabel))
                                .font(.body)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { appState.photosConfig.schedule.frequency },
                                set: {
                                    appState.photosConfig.schedule.frequency = $0
                                    appState.savePhotosConfig()
                                }
                            )) {
                                ForEach(ScheduleFrequency.allCases, id: \.self) { freq in
                                    Text(freq.localizedTitle).tag(freq)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        // Detailed frequency controls
                        switch appState.photosConfig.schedule.frequency {
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
                                        get: { appState.photosConfig.schedule.hour },
                                        set: {
                                            appState.photosConfig.schedule.hour = $0
                                            appState.savePhotosConfig()
                                        }
                                    )) {
                                        ForEach(0..<24, id: \.self) { h in
                                            Text(String(format: "%02d:00", h)).tag(h)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 90)

                                    Picker("", selection: Binding(
                                        get: { appState.photosConfig.schedule.minute },
                                        set: {
                                            appState.photosConfig.schedule.minute = $0
                                            appState.savePhotosConfig()
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
                                    get: { appState.photosConfig.schedule.weekday },
                                    set: {
                                        appState.photosConfig.schedule.weekday = $0
                                        appState.savePhotosConfig()
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
                                    get: { appState.photosConfig.schedule.hour },
                                    set: {
                                        appState.photosConfig.schedule.hour = $0
                                        appState.savePhotosConfig()
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
                                    get: { appState.photosConfig.schedule.intervalMinutes },
                                    set: {
                                        appState.photosConfig.schedule.intervalMinutes = $0
                                        appState.savePhotosConfig()
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
                            get: { appState.photosConfig.schedule.catchUpIfMissed },
                            set: {
                                appState.photosConfig.schedule.catchUpIfMissed = $0
                                appState.savePhotosConfig()
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
            .padding(14)
            .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius)
                    .stroke(OtterTheme.subtleBorder, lineWidth: 1)
            )
        }
    }
}
