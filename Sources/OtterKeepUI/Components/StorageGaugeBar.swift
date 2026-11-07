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

    /// Gap between gauge segments, in points.
    private static let segmentSpacing: CGFloat = 2

    /// Minimum visible width of a segment, in points.
    private static let minimumSegmentWidth: CGFloat = 3

    struct GaugeSegment: Equatable {
        let width: CGFloat
        let color: Color
    }

    /// Distributes the available track width across the visible segments.
    ///
    /// Segment widths are derived from the track width minus the inter-segment gaps, so the row can
    /// never overflow the track. Segments below the visibility threshold are dropped and their
    /// share is redistributed, which keeps the bar flush with the track at every width.
    func segmentWidths(for trackWidth: CGFloat) -> [GaugeSegment] {
        let candidates: [(ratio: CGFloat, color: Color)] = [
            (backupRatio, OtterTheme.storageBackups),
            (otherRatio, OtterTheme.storageOther),
            (freeRatio, Color.primary.opacity(0.08)),
        ]
        let visible = candidates.filter { $0.ratio > 0.005 }
        guard !visible.isEmpty, trackWidth > 0 else { return [] }

        let totalGap = Self.segmentSpacing * CGFloat(visible.count - 1)
        let usableWidth = max(trackWidth - totalGap, 0)
        let totalRatio = visible.reduce(CGFloat.zero) { $0 + $1.ratio }
        guard totalRatio > 0 else { return [] }

        var widths = visible.map { max(usableWidth * ($0.ratio / totalRatio), Self.minimumSegmentWidth) }
        let overflow = widths.reduce(CGFloat.zero, +) - usableWidth
        if overflow > 0, let widest = widths.indices.max(by: { widths[$0] < widths[$1] }) {
            widths[widest] = max(widths[widest] - overflow, Self.minimumSegmentWidth)
        }

        return zip(visible, widths).map { GaugeSegment(width: $1, color: $0.color) }
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
                let segments = segmentWidths(for: geo.size.width)
                HStack(spacing: Self.segmentSpacing) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(segment.color)
                            .frame(width: segment.width)
                    }
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
