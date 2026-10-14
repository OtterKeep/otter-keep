import SwiftUI
import OtterKeepCore

/// Apple-style multi-segment storage capacity gauge bar showing backups, system/other files, and free space.
public struct StorageGaugeBar: View {
    public let totalBytes: Int64
    public let backupBytes: Int64
    public let freeBytes: Int64
    public let title: String
    public let subtitle: String?

    public init(
        totalBytes: Int64,
        backupBytes: Int64,
        freeBytes: Int64,
        title: String,
        subtitle: String? = nil
    ) {
        self.totalBytes = max(totalBytes, 1)
        self.backupBytes = max(min(backupBytes, totalBytes), 0)
        self.freeBytes = max(min(freeBytes, totalBytes), 0)
        self.title = title
        self.subtitle = subtitle
    }

    private var otherBytes: Int64 {
        max(totalBytes - backupBytes - freeBytes, 0)
    }

    private var backupRatio: CGFloat {
        CGFloat(backupBytes) / CGFloat(totalBytes)
    }

    private var otherRatio: CGFloat {
        CGFloat(otherBytes) / CGFloat(totalBytes)
    }

    private var freeRatio: CGFloat {
        CGFloat(freeBytes) / CGFloat(totalBytes)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Title & Total Capacity
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
            }

            // Segmented Storage Bar
            GeometryReader { geo in
                let width = geo.size.width
                HStack(spacing: 2) {
                    // Backup Bytes Segment
                    if backupRatio > 0.005 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(OtterTheme.storageBackups)
                            .frame(width: max(width * backupRatio - 2, 4))
                    }

                    // Other System Files Segment
                    if otherRatio > 0.005 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(OtterTheme.storageOther)
                            .frame(width: max(width * otherRatio - 2, 4))
                    }

                    // Free Disk Space Segment
                    if freeRatio > 0.005 {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: max(width * freeRatio - 2, 4))
                    }
                }
            }
            .frame(height: 8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            // Legend Row
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    legendContent
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        legendItem(color: OtterTheme.storageBackups, label: L10n.t(.storageBackupsLabel), bytes: backupBytes)
                        legendItem(color: OtterTheme.storageOther, label: L10n.t(.storageOtherLabel), bytes: otherBytes)
                    }
                    legendItem(color: Color.secondary.opacity(0.5), label: L10n.t(.storageFreeLabel), bytes: freeBytes)
                }
                VStack(alignment: .leading, spacing: 4) {
                    legendContent
                }
            }
        }
    }

    @ViewBuilder
    private var legendContent: some View {
        legendItem(
            color: OtterTheme.storageBackups,
            label: L10n.t(.storageBackupsLabel),
            bytes: backupBytes
        )

        legendItem(
            color: OtterTheme.storageOther,
            label: L10n.t(.storageOtherLabel),
            bytes: otherBytes
        )

        legendItem(
            color: Color.secondary.opacity(0.5),
            label: L10n.t(.storageFreeLabel),
            bytes: freeBytes
        )
    }

    private func legendItem(color: Color, label: String, bytes: Int64) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}
