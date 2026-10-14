import SwiftUI
import AppKit
import OtterKeepStorage
import OtterKeepCore

extension ProfileRulesView {
    // MARK: - 1. Folder Overview Header
    func folderSummaryHeader(profile: BackupProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundStyle(OtterTheme.oceanicTeal)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.sourceURL.lastPathComponent)
                        .font(.subheadline.bold())
                    Image(systemName: "arrow.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(profile.destinationURL.lastPathComponent)
                        .font(.subheadline.bold())
                }

                Text(L10n.t(.rulesConfigOnDashboardNotice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.activeProfileTab = .overview
            } label: {
                Label(L10n.t(.tabOverview), systemImage: "gauge.with.needle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 2. iCloud Strategy
    func icloudStrategySection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(.icloudStrategyTitle))
                .font(.headline)

            HStack {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.icloudStrategy.localizedTitle)
                        .font(.body.weight(.medium))
                    Text(profile.icloudStrategy.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("", selection: Binding(
                    get: { profile.icloudStrategy },
                    set: { strat in
                        var updated = profile
                        updated.icloudStrategy = strat
                        appState.selectedProfile = updated
                    }
                )) {
                    ForEach(ICloudBackupStrategy.allCases, id: \.self) { strat in
                        Text(strat.localizedTitle).tag(strat)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 280)
            }
            .otterCard()
        }
    }

    // MARK: - 3. Exclusion Rules
    func exclusionRulesSection(profile: BackupProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t(.excludeRulesTitle))
                    .font(.headline)
                Spacer()
                Text("\(profile.excludePatterns.count) \(L10n.t(.activeRulesCount))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Input field for new pattern
                HStack(spacing: 8) {
                    TextField(L10n.t(.addRulePlaceholder), text: excludePatternBinding)
                        .textFieldStyle(.roundedBorder)

                    Button(L10n.t(.addRuleButton)) {
                        let trimmed = appState.newExcludePattern.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            appState.addExcludePattern(trimmed)
                            appState.newExcludePattern = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(appState.newExcludePattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Quick preset buttons
                FlowLayout(spacing: OtterTheme.spacing6) {
                    Text(L10n.t(.commonRulesLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(["node_modules", ".git", ".DS_Store", "DerivedData", "*.tmp"], id: \.self) { preset in
                        let isAdded = profile.excludePatterns.contains(preset)
                        Button {
                            if !isAdded {
                                appState.addExcludePattern(preset)
                            }
                        } label: {
                            HStack(spacing: 3) {
                                if isAdded {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                }
                                Text(preset)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isAdded)
                    }
                }

                // Technology Stack Presets
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t(.presetExclusionsTitle))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: OtterTheme.spacing6) {
                        stackPresetChip(
                            title: L10n.t(.presetExclusionNodeModules),
                            patterns: ["node_modules", ".next", ".nuxt", "dist"],
                            profile: profile
                        )
                        stackPresetChip(
                            title: L10n.t(.presetExclusionXcode),
                            patterns: ["DerivedData", ".build", "Pods"],
                            profile: profile
                        )
                        stackPresetChip(
                            title: L10n.t(.presetExclusionPython),
                            patterns: [".venv", "venv", "__pycache__", "*.pyc"],
                            profile: profile
                        )
                        stackPresetChip(
                            title: L10n.t(.presetExclusionMediaCaches),
                            patterns: ["Cache", "Caches", "Render Files"],
                            profile: profile
                        )
                    }
                }

                Divider()

                // Active exclusion tags
                if profile.excludePatterns.isEmpty {
                    Text(L10n.t(.noActiveRulesNotice))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(profile.excludePatterns, id: \.self) { pattern in
                            HStack(spacing: 5) {
                                Image(systemName: "nosign")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(pattern)
                                    .font(.caption.monospaced())
                                Button {
                                    appState.removeExcludePattern(pattern)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }

                Divider()

                // Ignore files and markers engine toggles
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { profile.enableIgnoreFiles },
                        set: { val in
                            var updated = profile
                            updated.enableIgnoreFiles = val
                            appState.selectedProfile = updated
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.enableIgnoreFilesToggle))
                                .font(.body.weight(.medium))
                            Text(L10n.t(.enableIgnoreFilesDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Toggle(isOn: Binding(
                        get: { profile.respectGitIgnore },
                        set: { val in
                            var updated = profile
                            updated.respectGitIgnore = val
                            appState.selectedProfile = updated
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t(.respectGitIgnoreToggle))
                                .font(.body)
                            Text(L10n.t(.respectGitIgnoreDesc))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.leading, 20)
                    .disabled(!profile.enableIgnoreFiles)
                    .opacity(profile.enableIgnoreFiles ? 1.0 : 0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .otterCard()
        }
    }

    private func stackPresetChip(title: String, patterns: [String], profile: BackupProfile) -> some View {
        let allAdded = patterns.allSatisfy { profile.excludePatterns.contains($0) }
        return Button {
            for p in patterns where !profile.excludePatterns.contains(p) {
                appState.addExcludePattern(p)
            }
        } label: {
            HStack(spacing: 4) {
                if allAdded {
                    Image(systemName: "checkmark")
                        .font(.caption2)
                }
                Text(title)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(allAdded)
    }

}
