import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepDomain

/// Modal dialog providing side-by-side visual file comparison between two backup snapshots.
public struct SideBySideDiffModalView: View {
    public let appState: AppState

    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if appState.isLoadingSideBySideDiff {
                loadingView
            } else if let comparison = appState.activeSideBySideDiffComparison {
                if comparison.isBinary {
                    binaryFileNoticeView
                } else if comparison.addedLinesCount == 0 && comparison.deletedLinesCount == 0 && comparison.modifiedLinesCount == 0 {
                    identicalNoticeView
                } else {
                    diffContentView(comparison)
                }
            } else {
                emptyStateView
            }

            Divider()
            footerBar
        }
        .frame(minWidth: 960, idealWidth: 1200, maxWidth: .infinity, minHeight: 600, idealHeight: 800, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.split.2x1")
                .font(.title2)
                .foregroundStyle(OtterTheme.oceanicTeal)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.activeSideBySideDiffItem?.fileName ?? L10n.t(.diffSideBySideTitle))
                    .font(.headline)
                    .lineLimit(1)
                if let path = appState.activeSideBySideDiffItem?.relativePath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let comp = appState.activeSideBySideDiffComparison, !comp.isBinary {
                HStack(spacing: 10) {
                    Text(L10n.format(.diffLinesAddedFormat, comp.addedLinesCount))
                        .font(.caption.bold())
                        .foregroundStyle(OtterTheme.statusGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(OtterTheme.statusGreen.opacity(0.12))
                        .clipShape(Capsule())

                    Text(L10n.format(.diffLinesRemovedFormat, comp.deletedLinesCount))
                        .font(.caption.bold())
                        .foregroundStyle(OtterTheme.statusError)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(OtterTheme.statusError.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Button(L10n.t(.cancel)) {
                appState.showSideBySideDiffModal = false
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Column Labels

    private func columnHeaders(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack {
                Text(L10n.t(.diffSideBySideSnapshotA))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                if let mtime = appState.activeSideBySideDiffComparison?.leftMtime {
                    Text("(\(Self.dateFormatter.string(from: mtime)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let size = appState.activeSideBySideDiffComparison?.leftSize {
                    Text(formatBytes(size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: columnWidth, height: 36)
            .background(Color(NSColor.controlBackgroundColor))

            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1, height: 20)

            HStack {
                Text(L10n.t(.diffSideBySideSnapshotB))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                if let mtime = appState.activeSideBySideDiffComparison?.rightMtime {
                    Text("(\(Self.dateFormatter.string(from: mtime)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if let size = appState.activeSideBySideDiffComparison?.rightSize {
                    Text(formatBytes(size))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: columnWidth, height: 36)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(height: 36)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Diff Content View

    private func diffContentView(_ comparison: FileComparisonResult) -> some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let columnWidth = max(420, (totalWidth - 1) / 2)

            VStack(spacing: 0) {
                columnHeaders(columnWidth: columnWidth)
                    .frame(height: 36)

                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(spacing: 0) {
                        ForEach(comparison.rows) { line in
                            diffRow(line, columnWidth: columnWidth)
                            Divider()
                        }
                    }
                    .frame(minWidth: totalWidth, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func diffRow(_ line: SideBySideDiffLine, columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Left (Base / Original)
            HStack(alignment: .top, spacing: 8) {
                Text(line.leftLineNumber.map { "\($0)" } ?? "")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Text(line.leftText ?? " ")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(line.type == .deleted ? OtterTheme.statusError : .primary)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .frame(width: columnWidth, alignment: .leading)
            .background(leftBackgroundColor(for: line.type))

            Divider()

            // Right (Target / Modified)
            HStack(alignment: .top, spacing: 8) {
                Text(line.rightLineNumber.map { "\($0)" } ?? "")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Text(line.rightText ?? " ")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(line.type == .added ? OtterTheme.statusGreen : (line.type == .modified ? OtterTheme.otterAmber : .primary))
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .frame(width: columnWidth, alignment: .leading)
            .background(rightBackgroundColor(for: line.type))
        }
    }

    private func leftBackgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .deleted:
            return OtterTheme.statusError.opacity(0.15)
        case .modified:
            return OtterTheme.otterAmber.opacity(0.12)
        default:
            return Color.clear
        }
    }

    private func rightBackgroundColor(for type: DiffLineType) -> Color {
        switch type {
        case .added:
            return OtterTheme.statusGreen.opacity(0.15)
        case .modified:
            return OtterTheme.otterAmber.opacity(0.12)
        default:
            return Color.clear
        }
    }

    // MARK: - State Notices

    private var binaryFileNoticeView: some View {
        ContentUnavailableView(
            L10n.t(.diffBinaryFileNotice),
            systemImage: "doc.zipper",
            description: Text(appState.activeSideBySideDiffItem?.relativePath ?? "")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identicalNoticeView: some View {
        ContentUnavailableView(
            L10n.t(.diffIdenticalFiles),
            systemImage: "checkmark.seal.fill",
            description: Text(appState.activeSideBySideDiffItem?.relativePath ?? "")
        )
        .foregroundStyle(OtterTheme.statusGreen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(L10n.t(.details))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            L10n.t(.diffNoChanges),
            systemImage: "doc.text.magnifyingglass"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Spacer()
            Button(L10n.t(.aboutCloseButton)) {
                appState.showSideBySideDiffModal = false
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(OtterTheme.oceanicTeal)
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
