import SwiftUI
import AppKit
import OtterKeepCore

/// Modal sheet for creating a new backup profile with customizable source and destination directories, intelligent presets, and rule toggles.
public struct NewProfileModalView: View {
    public let appState: AppState

    @FocusState private var isNameFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
    }

    private var profileNameBinding: Binding<String> {
        Binding(
            get: { appState.newProfileName },
            set: { appState.updateNewProfileName($0) }
        )
    }

    private var volumeEval: VolumeEvaluationResult {
        VolumeCapabilityEvaluator.evaluate(
            sourceURL: appState.newProfileSourceURL,
            destinationURL: appState.newProfileDestinationURL
        )
    }

    private var isFolderPairValid: Bool {
        appState.validateFolderPair(
            sourceURL: appState.newProfileSourceURL,
            destinationURL: appState.newProfileDestinationURL
        )
    }

    private var canCreate: Bool {
        !appState.newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isFolderPairValid
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Pinned Header
            headerView
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            // Scrollable Form Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    presetsView
                    nameInputView
                    sourceFolderView
                    destinationFolderView
                    executionModeView
                    advancedOptionsView
                    validationErrorView
                }
                .padding(20)
            }

            Divider()

            // Pinned Action Buttons Footer
            footerActionsView
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
        }
        .frame(width: 580, height: 600)
        .onAppear {
            if appState.newProfileName.isEmpty && appState.selectedPresetTag == nil {
                appState.resetNewProfileDraft()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isNameFocused = true
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(OtterTheme.otterAmber)
                .frame(width: 36, height: 36)
                .background(OtterTheme.otterAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(.newProfileSheetTitle))
                    .font(.headline.bold())
                Text(L10n.t(.newProfileSheetPrompt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.showNewProfileSheet = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var presetsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t(.profilePresetsSection))
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                presetCard(
                    tag: "developer",
                    title: L10n.t(.presetDeveloper),
                    subtitle: L10n.t(.presetDeveloperDesc),
                    icon: "curlybraces",
                    action: { appState.applyDeveloperPreset() }
                )

                presetCard(
                    tag: "documents",
                    title: L10n.t(.presetDocuments),
                    subtitle: L10n.t(.presetDocumentsDesc),
                    icon: "doc.text.fill",
                    action: { appState.applyDocumentsPreset() }
                )

                presetCard(
                    tag: "creative",
                    title: L10n.t(.presetCreative),
                    subtitle: L10n.t(.presetCreativeDesc),
                    icon: "photo.stack.fill",
                    action: { appState.applyCreativePreset() }
                )
            }
        }
    }

    private var nameInputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t(.profilesMenuTitle))
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            TextField(L10n.t(.newProfileNamePlaceholder), text: profileNameBinding)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
        }
    }

    private var sourceFolderView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.t(.sourceFolderTitle), systemImage: "folder.fill")
                    .font(.caption.bold())
                    .foregroundStyle(OtterTheme.cyberTeal)
                Spacer()
                Text(L10n.t(.newProfileSourceDesc))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(OtterTheme.cyberTeal)
                    .font(.title3)

                Text(appState.newProfileSourceURL.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    appState.pickDirectory(
                        title: L10n.t(.selectSourceFolder),
                        prompt: L10n.t(.selectFolderConfirm),
                        initialURL: appState.newProfileSourceURL,
                        canCreateDirectories: false
                    ) { chosenURL in
                        appState.newProfileSourceURL = chosenURL
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                        Text(L10n.t(.browseButton))
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var destinationFolderView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.t(.destinationFolderTitle), systemImage: "internaldrive.fill")
                    .font(.caption.bold())
                    .foregroundStyle(OtterTheme.otterAmber)
                Spacer()
                Text(L10n.t(.newProfileDestinationDesc))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                Image(systemName: "internaldrive.fill")
                .foregroundStyle(OtterTheme.otterAmber)
                .font(.title3)

                Text(appState.newProfileDestinationURL.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button {
                    appState.pickDirectory(
                        title: L10n.t(.selectDestinationFolder),
                        prompt: L10n.t(.selectFolderConfirm),
                        initialURL: appState.newProfileDestinationURL,
                        canCreateDirectories: true
                    ) { chosenURL in
                        appState.newProfileDestinationURL = chosenURL
                        appState.newProfileIsDestinationCustomized = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.badge.plus")
                        Text(L10n.t(.browseButton))
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            // Storage Volume CoW Capability Badge
            HStack(spacing: 6) {
                Image(systemName: volumeEval.isTargetAPFS ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(volumeEval.isTargetAPFS ? OtterTheme.statusGreen : OtterTheme.statusWarning)
                    .font(.caption)
                Text(L10n.t(volumeEval.cowMode.descriptionKey))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private var executionModeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n.t(.executionModeScheduled) + " / " + L10n.t(.executionModeContinuous), systemImage: "clock.arrow.2.circlepath")
                    .font(.caption.bold())
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Spacer()
                Picker("", selection: Binding(
                    get: { appState.newProfileIsContinuous },
                    set: { appState.newProfileIsContinuous = $0 }
                )) {
                    Text(L10n.t(.executionModeScheduled)).tag(false)
                    Text(L10n.t(.executionModeContinuous)).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            if appState.newProfileIsContinuous {
                HStack(spacing: 8) {
                    Text(L10n.t(.continuousDebounceLabel) + ":")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(appState.newProfileDebouncingSeconds) },
                            set: { appState.newProfileDebouncingSeconds = Int($0) }
                        ),
                        in: 5...300,
                        step: 5
                    )
                    Text("\(appState.newProfileDebouncingSeconds)s")
                        .font(.caption.monospacedDigit().bold())
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var advancedOptionsView: some View {
        HStack(alignment: .top, spacing: 14) {
            // 1. Ignore rules group
            VStack(alignment: .leading, spacing: 6) {
                Label(".otterkeepignore", systemImage: "eye.slash.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { appState.newProfileEnableIgnoreFiles },
                    set: { appState.newProfileEnableIgnoreFiles = $0 }
                )) {
                    Text(L10n.t(.enableIgnoreFilesToggle))
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { appState.newProfileRespectGitIgnore },
                    set: { appState.newProfileRespectGitIgnore = $0 }
                )) {
                    Text(L10n.t(.respectGitIgnoreToggle))
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .disabled(!appState.newProfileEnableIgnoreFiles)
                .opacity(appState.newProfileEnableIgnoreFiles ? 1.0 : 0.5)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            // 2. Drive Automation group
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t(.backupOnVolumeMountTitle), systemImage: "externaldrive.badge.timemachine")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { appState.newProfileBackupOnVolumeMount },
                    set: { appState.newProfileBackupOnVolumeMount = $0 }
                )) {
                    Text(L10n.t(.backupOnVolumeMountToggle))
                        .font(.caption)
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: Binding(
                    get: { appState.newProfileAutoEjectOnCompletion },
                    set: { appState.newProfileAutoEjectOnCompletion = $0 }
                )) {
                    Text(L10n.t(.autoEjectOnCompletionToggle))
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .disabled(!appState.newProfileBackupOnVolumeMount)
                .opacity(appState.newProfileBackupOnVolumeMount ? 1.0 : 0.5)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var validationErrorView: some View {
        if !isFolderPairValid {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(OtterTheme.statusError)
                    .font(.caption)
                Text(L10n.t(.invalidFolderSelectionMessage))
                    .font(.caption)
                    .foregroundStyle(OtterTheme.statusError)
            }
            .padding(.horizontal, 4)
        }
    }

    private var footerActionsView: some View {
        HStack {
            Button(L10n.t(.cancel)) {
                appState.showNewProfileSheet = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(L10n.t(.create)) {
                performCreate()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreate)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func presetCard(tag: String, title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        let isSelected = appState.selectedPresetTag == tag
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? OtterTheme.primaryOrange : OtterTheme.cyberTeal)
                    Text(title)
                        .font(.callout.weight(isSelected ? .bold : .medium))
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(OtterTheme.primaryOrange)
                    }
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? OtterTheme.primaryOrange : OtterTheme.subtleBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func performCreate() {
        guard canCreate else { return }
        appState.createProfileFromDraft()
        appState.showNewProfileSheet = false
    }
}
