import SwiftUI
import OtterKeepCore

extension RemoteDestinationEditorModalView {
    private var s3EndpointBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3Endpoint }, set: { appState.destinationEditorS3Endpoint = $0 })
    }

    private var s3BucketBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3Bucket }, set: { appState.destinationEditorS3Bucket = $0 })
    }

    private var s3RegionBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3Region }, set: { appState.destinationEditorS3Region = $0 })
    }

    private var s3AccessKeyBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3AccessKeyId }, set: { appState.destinationEditorS3AccessKeyId = $0 })
    }

    private var s3SecretAccessKeyBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3SecretAccessKey }, set: { appState.destinationEditorS3SecretAccessKey = $0 })
    }

    private var s3PrefixBinding: Binding<String> {
        Binding(get: { appState.destinationEditorS3PathPrefix }, set: { appState.destinationEditorS3PathPrefix = $0 })
    }

    private var s3ForcePathStyleBinding: Binding<Bool> {
        Binding(get: { appState.destinationEditorS3ForcePathStyle }, set: { appState.destinationEditorS3ForcePathStyle = $0 })
    }

    // MARK: - Section 2: S3 Configuration
    var s3ConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t(.remoteDestEditorS3SettingsTitle), systemImage: "cloud.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Spacer()
                Text(L10n.t(.protocolBadgeS3))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Quick Presets
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.remoteDestEditorPresetsLabel))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    presetButton(title: "AWS S3", icon: "cube.fill") {
                        appState.destinationEditorS3Endpoint = "https://s3.amazonaws.com"
                        appState.destinationEditorS3Region = "eu-central-1"
                        appState.destinationEditorS3ForcePathStyle = false
                    }

                    presetButton(title: "Backblaze B2", icon: "flame.fill") {
                        appState.destinationEditorS3Endpoint = "https://s3.us-west-004.backblazeb2.com"
                        appState.destinationEditorS3Region = "us-west-004"
                        appState.destinationEditorS3ForcePathStyle = true
                    }

                    presetButton(title: "Cloudflare R2", icon: "bolt.fill") {
                        appState.destinationEditorS3Endpoint = "https://<account-id>.r2.cloudflarestorage.com"
                        appState.destinationEditorS3Region = "auto"
                        appState.destinationEditorS3ForcePathStyle = true
                    }

                    presetButton(title: "MinIO", icon: "server.rack") {
                        appState.destinationEditorS3Endpoint = "http://127.0.0.1:9000"
                        appState.destinationEditorS3Region = "us-east-1"
                        appState.destinationEditorS3ForcePathStyle = true
                    }
                }
            }

            Divider()

            // Endpoint & Bucket
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorEndpointLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorEndpointPlaceholder), text: s3EndpointBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorBucketLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorBucketPlaceholder), text: s3BucketBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Region & Path Prefix
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorRegionLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorRegionPlaceholder), text: s3RegionBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorPrefixLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorPrefixPlaceholder), text: s3PrefixBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Access Key & Secret Access Key
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(.remoteDestEditorAccessKeyLabel))
                        .font(.caption2.bold())
                    TextField(L10n.t(.remoteDestEditorAccessKeyPlaceholder), text: s3AccessKeyBinding)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.t(.remoteDestEditorSecretKeyLabel))
                            .font(.caption2.bold())
                        Spacer()
                        Image(systemName: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    SecureField(L10n.t(.remoteDestEditorSecretKeyPlaceholder), text: s3SecretAccessKeyBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Text(L10n.t(.remoteDestEditorForcePathStyle))
                    .font(.caption)
                Spacer()
                Toggle("", isOn: s3ForcePathStyleBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .otterCard(padding: 14)
    }

    private func presetButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Section 2.5: Backblaze B2 Configuration
    var b2ConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.t(.destTypeBackblazeB2), systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(OtterTheme.statusError)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.b2KeyId))
                    .font(.caption.bold())
                TextField("004abc...", text: Binding(get: { appState.destinationEditorB2KeyId }, set: { appState.destinationEditorB2KeyId = $0 }))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.b2ApplicationKey))
                    .font(.caption.bold())
                SecureField("K004...", text: Binding(get: { appState.destinationEditorB2AppKey }, set: { appState.destinationEditorB2AppKey = $0 }))
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t(.b2BucketName))
                        .font(.caption.bold())
                    TextField("my-backup-bucket", text: Binding(get: { appState.destinationEditorB2BucketName }, set: { appState.destinationEditorB2BucketName = $0 }))
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t(.b2Region))
                        .font(.caption.bold())
                    TextField("us-west-004", text: Binding(get: { appState.destinationEditorB2Region }, set: { appState.destinationEditorB2Region = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.b2CustomEndpoint))
                    .font(.caption.bold())
                TextField("s3.us-west-004.backblazeb2.com (optional)", text: Binding(get: { appState.destinationEditorB2CustomEndpoint }, set: { appState.destinationEditorB2CustomEndpoint = $0 }))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.pathPrefixLabel))
                    .font(.caption.bold())
                TextField("otterkeep", text: Binding(get: { appState.destinationEditorB2PathPrefix }, set: { appState.destinationEditorB2PathPrefix = $0 }))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .otterCard(padding: 14)
    }
}
