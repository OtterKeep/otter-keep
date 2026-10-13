import SwiftUI
import OtterKeepCore

extension RemoteDestinationEditorModalView {
    private var nameBinding: Binding<String> {
        Binding(get: { appState.destinationEditorName }, set: { appState.destinationEditorName = $0 })
    }

    private var typeIndexBinding: Binding<Int> {
        Binding(get: { appState.destinationEditorTypeIndex }, set: { appState.destinationEditorTypeIndex = $0 })
    }

    // MARK: - Section 1: Overview
    var destinationOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(.remoteDestEditorNameLabel))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                TextField(L10n.t(.remoteDestEditorNamePlaceholder), text: nameBinding)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t(.remoteDestEditorTypeLabel))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    destinationTypeTile(
                        index: 0,
                        title: "S3 Cloud",
                        subtitle: "AWS, B2, R2, MinIO",
                        icon: "icloud.and.arrow.up.fill",
                        accentColor: OtterTheme.oceanicTeal
                    )

                    destinationTypeTile(
                        index: 1,
                        title: "SMB / NAS",
                        subtitle: "Apple SMBfs, Synology",
                        icon: "server.rack",
                        accentColor: OtterTheme.otterAmber
                    )

                    destinationTypeTile(
                        index: 2,
                        title: "WebDAV",
                        subtitle: "Nextcloud, ownCloud",
                        icon: "network",
                        accentColor: OtterTheme.oceanicTeal
                    )

                    destinationTypeTile(
                        index: 3,
                        title: "SFTP / SSH",
                        subtitle: "Secure Remote Shell",
                        icon: "terminal.fill",
                        accentColor: OtterTheme.accentPurple
                    )

                    destinationTypeTile(
                        index: 4,
                        title: "Backblaze B2",
                        subtitle: "B2 Native / S3",
                        icon: "flame.fill",
                        accentColor: OtterTheme.statusError
                    )
                }
            }
        }
        .otterCard(padding: 14)
    }

    private func destinationTypeTile(
        index: Int,
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color
    ) -> some View {
        let isSelected = appState.destinationEditorTypeIndex == index

        return Button {
            withAnimation(OtterTheme.snappySpring) {
                typeIndexBinding.wrappedValue = index
            }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? accentColor : .secondary)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .secondary : .tertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? accentColor : OtterTheme.subtleBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
