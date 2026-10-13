import SwiftUI
import AppKit
import OtterKeepCore

extension RemoteDestinationEditorModalView {
    private var smbShareURLBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbShareURL }, set: { appState.destinationEditorSmbShareURL = $0 })
    }

    private var smbMountPathBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbMountPath }, set: { appState.destinationEditorSmbMountPath = $0 })
    }

    private var smbUsernameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbUsername }, set: { appState.destinationEditorSmbUsername = $0 })
    }

    private var smbPasswordBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSmbPassword }, set: { appState.destinationEditorSmbPassword = $0 })
    }

    private var webdavURLBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVURL }, set: { appState.destinationEditorWebDAVURL = $0 })
    }

    private var webdavPathBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVPath }, set: { appState.destinationEditorWebDAVPath = $0 })
    }

    private var webdavUsernameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVUsername }, set: { appState.destinationEditorWebDAVUsername = $0 })
    }

    private var webdavPasswordBinding: Binding<String> {
        Binding(get: { appState.destinationEditorWebDAVPassword }, set: { appState.destinationEditorWebDAVPassword = $0 })
    }

    private var sftpHostBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPHost }, set: { appState.destinationEditorSFTPHost = $0 })
    }

    private var sftpPortBinding: Binding<Int> {
        Binding(get: { appState.destinationEditorSFTPPort }, set: { appState.destinationEditorSFTPPort = $0 })
    }

    private var sftpUsernameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPUsername }, set: { appState.destinationEditorSFTPUsername = $0 })
    }

    private var sftpPasswordOrKeyBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPPasswordOrKey }, set: { appState.destinationEditorSFTPPasswordOrKey = $0 })
    }

    private var sftpPathBinding: Binding<String> {
        Binding(get: { appState.destinationEditorSFTPPath }, set: { appState.destinationEditorSFTPPath = $0 })
    }

    private var sftpAuthModeBinding: Binding<Int> {
        Binding(get: { appState.destinationEditorSFTPAuthModeIndex }, set: { appState.destinationEditorSFTPAuthModeIndex = $0 })
    }

    // MARK: - Section 2: SMB Configuration
    var smbConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorSMBSettingsTitle), systemImage: "server.rack")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.otterAmber)
                Spacer()
                Text(L10n.t(.protocolBadgeSMB))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSMBShareLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSMBSharePlaceholder), text: smbShareURLBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSMBSubfolderLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSMBSubfolderPlaceholder), text: smbMountPathBinding)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorSMBUsernameLabel))
                            .font(.caption2.bold())
                        TextField(L10n.t(.remoteDestEditorSMBUsernamePlaceholder), text: smbUsernameBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.remoteDestEditorSMBPasswordLabel))
                                .font(.caption2.bold())
                            Spacer()
                            Image(systemName: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        SecureField(L10n.t(.remoteDestEditorSMBPasswordPlaceholder), text: smbPasswordBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Section 2: WebDAV Configuration
    var webdavConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorWebDAVSettingsTitle), systemImage: "network")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Spacer()
                Text(L10n.t(.protocolBadgeWebDAV))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorWebDAVURLLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorWebDAVURLPlaceholder), text: webdavURLBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorWebDAVPathLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorWebDAVPathPlaceholder), text: webdavPathBinding)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorWebDAVUsernameLabel))
                            .font(.caption2.bold())
                        TextField(L10n.t(.remoteDestEditorWebDAVUsernamePlaceholder), text: webdavUsernameBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.remoteDestEditorWebDAVPasswordLabel))
                                .font(.caption2.bold())
                            Spacer()
                            Image(systemName: "key.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        SecureField(L10n.t(.remoteDestEditorWebDAVPasswordPlaceholder), text: webdavPasswordBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }

    // MARK: - Section 2: SFTP Configuration
    var sftpConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorSFTPSettingsTitle), systemImage: "terminal.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.accentPurple)
                Spacer()
                Text(L10n.t(.protocolBadgeSFTP))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorSFTPHostLabel))
                            .font(.caption2.bold())
                        TextField(L10n.t(.remoteDestEditorSFTPHostPlaceholder), text: sftpHostBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(.remoteDestEditorSFTPPortLabel))
                            .font(.caption2.bold())
                        TextField("22", value: sftpPortBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .monospacedDigit()
                            .frame(width: 80)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSFTPPathLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSFTPPathPlaceholder), text: sftpPathBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorSFTPUsernameLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorSFTPUsernamePlaceholder), text: sftpUsernameBinding)
                        .textFieldStyle(.roundedBorder)
                }

                // SFTP Auth Mode Picker & Fields
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t(.remoteDestEditorSFTPAuthMethodLabel))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    Picker("", selection: sftpAuthModeBinding) {
                        Text(L10n.t(.remoteDestEditorSFTPAuthPassword)).tag(0)
                        Text(L10n.t(.remoteDestEditorSFTPAuthKey)).tag(1)
                    }
                    .pickerStyle(.segmented)

                    if appState.destinationEditorSFTPAuthModeIndex == 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L10n.t(.remoteDestEditorSFTPPasswordLabel))
                                    .font(.caption2.bold())
                                Spacer()
                                Image(systemName: "key.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            SecureField(L10n.t(.remoteDestEditorSFTPPasswordPlaceholder), text: sftpPasswordOrKeyBinding)
                                .textFieldStyle(.roundedBorder)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L10n.t(.remoteDestEditorSFTPAuthKey))
                                    .font(.caption2.bold())
                                Spacer()
                                Image(systemName: "doc.text.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                TextField("~/.ssh/id_ed25519", text: sftpPasswordOrKeyBinding)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.t(.remoteDestEditorSFTPBrowseKeyButton)) {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.showsHiddenFiles = true
                                    panel.message = L10n.t(.remoteDestEditorSFTPSelectKeyTitle)
                                    if panel.runModal() == .OK, let url = panel.url {
                                        appState.destinationEditorSFTPPasswordOrKey = url.path
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .otterCard(padding: 14)
    }
}
