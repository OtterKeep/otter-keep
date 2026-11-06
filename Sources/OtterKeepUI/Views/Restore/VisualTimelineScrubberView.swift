import SwiftUI
import OtterKeepDomain
import OtterKeepCore

/// Interactive spatial timeline scrubber allowing fluid scrubbing and step navigation across snapshots.
public struct VisualTimelineScrubberView: View {
    @Bindable var appState: AppState

    /// Horizontal inset that keeps the thumb and edge dots fully inside the track.
    private static let trackInset: CGFloat = 8

    public init(appState: AppState) {
        self.appState = appState
    }

    private var snapshots: [SnapshotRecord] {
        appState.snapshots
    }

    private var currentIndex: Int {
        guard let selectedId = appState.selectedSnapshotId,
              let idx = snapshots.firstIndex(where: { $0.id == selectedId }) else {
            return 0
        }
        return idx
    }

    public var body: some View {
        if snapshots.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                // Header with current timestamp & quick stepping buttons
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .foregroundStyle(Color.accentColor)
                        Text(L10n.t(.timelineScrubberTitle))
                            .font(.subheadline.weight(.semibold))
                    }

                    Spacer()

                    if currentIndex < snapshots.count {
                        let currentSnap = snapshots[currentIndex]
                        HStack(spacing: 8) {
                            Text(currentSnap.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundStyle(.primary)

                            if currentSnap.backupType == "full" {
                                Text(L10n.t(.backupTypeFull))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.18), in: Capsule())
                                    .foregroundStyle(Color.blue)
                            }

                            if currentSnap.isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.purple)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Button {
                            step(by: 1)  // Older
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentIndex >= snapshots.count - 1)
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(L10n.t(.previousSnapshotButton))

                        Button {
                            step(by: -1)  // Newer
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentIndex <= 0)
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(L10n.t(.nextSnapshotButton))
                    }
                }

                // Interactive Scrubber Track
                GeometryReader { geometry in
                    let trackWidth = geometry.size.width
                    let inset = Self.trackInset
                    let usableWidth = max(trackWidth - inset * 2, 1)
                    ZStack(alignment: .leading) {
                        // Background track line
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)

                        // Snapshot tick marks / status dots
                        if snapshots.count > 1 {
                            ForEach(0..<snapshots.count, id: \.self) { idx in
                                let position = inset + CGFloat(idx) / CGFloat(snapshots.count - 1) * usableWidth
                                Circle()
                                    .fill(dotColor(for: snapshots[idx], isSelected: idx == currentIndex))
                                    .frame(width: idx == currentIndex ? 10 : 6, height: idx == currentIndex ? 10 : 6)
                                    .position(x: position, y: 8)
                                    .allowsHitTesting(false)
                            }
                        }

                        // Active scrubber thumb
                        if snapshots.count > 1 {
                            let thumbX = inset + CGFloat(currentIndex) / CGFloat(snapshots.count - 1) * usableWidth
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 16, height: 16)
                                .shadow(radius: 2)
                                .position(x: thumbX, y: 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectSnapshot(
                                    at: Self.snapshotIndex(forX: value.location.x, trackWidth: trackWidth, count: snapshots.count),
                                    reloadFiles: false
                                )
                            }
                            .onEnded { value in
                                selectSnapshot(
                                    at: Self.snapshotIndex(forX: value.location.x, trackWidth: trackWidth, count: snapshots.count),
                                    reloadFiles: true
                                )
                            }
                    )
                }
                .frame(height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
    }

    /// Maps a horizontal drag position onto a snapshot index.
    ///
    /// The track is inset on both sides so the thumb never clips at the edges; positions outside the
    /// usable range clamp to the first/last snapshot instead of producing an out-of-bounds index.
    static func snapshotIndex(forX x: CGFloat, trackWidth: CGFloat, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let usableWidth = max(trackWidth - trackInset * 2, 1)
        let fraction = max(0, min(1, (x - trackInset) / usableWidth))
        return Int((fraction * CGFloat(count - 1)).rounded())
    }

    private func dotColor(for snap: SnapshotRecord, isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        }
        if snap.isLocked {
            return Color.purple
        }
        if snap.backupType == "full" {
            return Color.blue
        }
        return Color.secondary.opacity(0.6)
    }

    private func step(by delta: Int) {
        let newIdx = max(0, min(snapshots.count - 1, currentIndex + delta))
        selectSnapshot(at: newIdx)
    }

    private func selectSnapshot(at index: Int, reloadFiles: Bool = true) {
        guard index >= 0 && index < snapshots.count else { return }
        let snap = snapshots[index]
        if appState.selectedSnapshotId != snap.id {
            appState.selectedSnapshotId = snap.id
            if reloadFiles {
                appState.loadFilesForSelectedSnapshot(force: true)
            }
        }
    }
}
