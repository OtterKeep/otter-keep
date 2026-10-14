import SwiftUI
import OtterKeepCore

/// Visual pipeline diagram showing the source directory flowing into the APFS CoW Engine and into the destination volume.
public struct BackupPipelineView: View {
    public let sourceURL: URL
    public let destinationURL: URL
    public let cowMode: CoWMode
    public let isActive: Bool
    public var onSelectSource: (() -> Void)?
    public var onRevealSource: (() -> Void)?
    public var onSelectDestination: (() -> Void)?
    public var onRevealDestination: (() -> Void)?

    public init(
        sourceURL: URL,
        destinationURL: URL,
        cowMode: CoWMode,
        isActive: Bool,
        onSelectSource: (() -> Void)? = nil,
        onRevealSource: (() -> Void)? = nil,
        onSelectDestination: (() -> Void)? = nil,
        onRevealDestination: (() -> Void)? = nil
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.cowMode = cowMode
        self.isActive = isActive
        self.onSelectSource = onSelectSource
        self.onRevealSource = onRevealSource
        self.onSelectDestination = onSelectDestination
        self.onRevealDestination = onRevealDestination
    }

    public var body: some View {
        HStack(spacing: 0) {
            // 1. Source Node
            pipelineNode(
                icon: "folder.fill",
                iconColor: .blue,
                title: L10n.t(.pipelineSourceLabel),
                subtitle: sourceURL.lastPathComponent,
                detail: sourceURL.path(percentEncoded: false),
                onChange: onSelectSource,
                onReveal: onRevealSource
            )

            // Flow Connector 1
            flowConnector

            // 2. Darwin APFS Engine Node
            pipelineEngineNode

            // Flow Connector 2
            flowConnector

            // 3. Destination Node
            pipelineNode(
                icon: "externaldrive.fill",
                iconColor: OtterTheme.cyberTeal,
                title: L10n.t(.pipelineTargetLabel),
                subtitle: destinationURL.lastPathComponent,
                detail: destinationURL.path(percentEncoded: false),
                alignment: .trailing,
                onChange: onSelectDestination,
                onReveal: onRevealDestination
            )
        }
        .padding(14)
        .background(OtterTheme.cardBackground, in: RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OtterTheme.cardCornerRadius, style: .continuous)
                .stroke(OtterTheme.subtleBorder, lineWidth: 0.5)
        )
    }

    private func pipelineNode(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        detail: String,
        alignment: HorizontalAlignment = .leading,
        onChange: (() -> Void)? = nil,
        onReveal: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack(spacing: 6) {
                if alignment == .trailing {
                    Text(title)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(iconColor)
                } else {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundStyle(iconColor)

                    Text(title)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

            Text(subtitle.isEmpty ? "/" : subtitle)
                .font(.subheadline.bold())
                .lineLimit(1)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .help(detail)

            Text(detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
                .help(detail)

            if onChange != nil || onReveal != nil {
                nodeActionButtons(alignment: alignment, onChange: onChange, onReveal: onReveal)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    @ViewBuilder
    private func nodeActionButtons(
        alignment: HorizontalAlignment,
        onChange: (() -> Void)?,
        onReveal: (() -> Void)?
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                actionButtons(onChange: onChange, onReveal: onReveal)
            }
            VStack(alignment: alignment, spacing: 4) {
                actionButtons(onChange: onChange, onReveal: onReveal)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func actionButtons(
        onChange: (() -> Void)?,
        onReveal: (() -> Void)?
    ) -> some View {
        if let onChange = onChange {
            Button {
                onChange()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder.badge.gearshape")
                    Text(L10n.t(.changeFolderButton))
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(isActive)
        }

        if let onReveal = onReveal {
            Button {
                onReveal()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.forward.app")
                    Text(L10n.t(.revealInFinderButton))
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    private var pipelineEngineNode: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(OtterTheme.otterAmber.opacity(0.12))
                    .frame(width: 32, height: 32)

                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(OtterTheme.otterAmber)
                    .symbolEffect(.pulse, isActive: isActive)
            }

            Text(L10n.t(.apfsCowBadge))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.primary)

            Text(cowMode == .intraVolumeCoW ? "clonefile(2)" : "Snapshot-CoW")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 90)
    }

    private var flowConnector: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { _ in
                Circle()
                    .fill(isActive ? OtterTheme.otterAmber : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: 3)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isActive ? OtterTheme.otterAmber : Color.secondary.opacity(0.4))
        }
        .padding(.horizontal, 6)
    }
}
