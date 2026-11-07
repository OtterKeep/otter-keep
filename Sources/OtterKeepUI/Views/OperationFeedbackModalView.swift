import SwiftUI
import AppKit
import OtterKeepCore

/// Modern macOS modal dialog presenting visual operation feedback with Ottie the mascot.
public struct OperationFeedbackModalView: View {
    public let feedback: OperationFeedback
    public let onDismiss: () -> Void
    public let onViewDetails: (() -> Void)?
    public let onViewLogs: (() -> Void)?

    public init(
        feedback: OperationFeedback,
        onDismiss: @escaping () -> Void,
        onViewDetails: (() -> Void)? = nil,
        onViewLogs: (() -> Void)? = nil
    ) {
        self.feedback = feedback
        self.onDismiss = onDismiss
        self.onViewDetails = onViewDetails
        self.onViewLogs = onViewLogs
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Scrollable body: a long diagnostic reason can never push the footer off screen.
            ScrollView {
                VStack(spacing: 0) {
                    // Hero Character Presentation
                    VStack(spacing: OtterTheme.spacing12) {
                        OttieFeedbackMascotView(
                            state: feedback.type == .success ? .success : .failure,
                            size: 150
                        )
                        .padding(.top, OtterTheme.spacing16)

                        Text(feedback.title)
                            .font(OtterTheme.heroTitleFont)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(feedback.type == .success ? OtterTheme.statusGreen : OtterTheme.statusError)
                            .padding(.horizontal, OtterTheme.spacing16)

                        Text(feedback.message)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, OtterTheme.spacing24)
                    }

                    // Detailed Telemetry or Diagnostic Advice Card
                    VStack(spacing: OtterTheme.spacing12) {
                        if feedback.type == .success, let summary = feedback.summary {
                            successSummaryCard(summary: summary)
                        } else if feedback.type == .success, let restoreSummary = feedback.restoreSummary {
                            restoreSummaryCard(summary: restoreSummary)
                        } else {
                            if let guarantee = feedback.guaranteeText, !guarantee.isEmpty {
                                guaranteeCard(text: guarantee)
                            }
                            if let reason = feedback.detailedReason, !reason.isEmpty {
                                failureAdviceCard(reason: reason)
                            }
                        }
                    }
                    .padding(.horizontal, OtterTheme.spacing24)
                    .padding(.top, OtterTheme.spacing16)
                    .padding(.bottom, OtterTheme.spacing16)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            // Footer Action Buttons
            HStack(spacing: OtterTheme.spacing12) {
                if feedback.type == .success && onViewDetails != nil {
                    Button {
                        onDismiss()
                        onViewDetails?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                            Text(L10n.t(.feedbackViewDetails))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                } else if feedback.type == .failure && onViewLogs != nil {
                    Button {
                        onDismiss()
                        onViewLogs?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text(L10n.t(.feedbackViewLogs))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()

                if let recovery = feedback.recoveryAction {
                    Button {
                        perform(recovery)
                    } label: {
                        Text(recovery.label)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Button {
                    onDismiss()
                } label: {
                    Text(L10n.t(.okDone))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(feedback.type == .success ? OtterTheme.statusGreen : OtterTheme.otterAmber)
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
            .padding(.horizontal, OtterTheme.spacing20)
            .padding(.vertical, OtterTheme.spacing12)
            .background(OtterTheme.sectionHeaderBackground)
        }
        .frame(
            minWidth: 440, idealWidth: 480, maxWidth: 620,
            minHeight: 380, idealHeight: 460, maxHeight: 720
        )
        .background(OtterTheme.windowBackground)
    }

    // MARK: - Success Summary Card
    private func successSummaryCard(summary: BackupSessionSummary) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                statColumn(
                    title: L10n.t(.telemetryCopied),
                    value: ByteCountFormatter.string(fromByteCount: summary.copiedBytes, countStyle: .file),
                    icon: "arrow.down.doc.fill",
                    color: OtterTheme.statusGreen
                )

                statColumn(
                    title: L10n.t(.telemetryCloned),
                    value: ByteCountFormatter.string(fromByteCount: summary.clonedBytes, countStyle: .file),
                    icon: "link.badge.plus",
                    color: OtterTheme.oceanicTeal
                )

                statColumn(
                    title: L10n.t(.inspectorDuration),
                    value: String(format: "%.1fs", summary.durationSeconds),
                    icon: "clock.fill",
                    color: .secondary
                )
            }
            .padding(.vertical, 8)
        }
        .otterCard(padding: OtterTheme.spacing12)
    }

    // MARK: - Restore Summary Card
    private func restoreSummaryCard(summary: RestoreSessionSummary) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                statColumn(
                    title: L10n.t(.snapshotFilesCount),
                    value: "\(summary.restoredFiles)",
                    icon: "doc.on.doc.fill",
                    color: OtterTheme.statusGreen
                )

                statColumn(
                    title: L10n.t(.fileSizeLabel),
                    value: ByteCountFormatter.string(fromByteCount: summary.restoredBytes, countStyle: .file),
                    icon: "arrow.down.circle.fill",
                    color: OtterTheme.oceanicTeal
                )

                statColumn(
                    title: L10n.t(.inspectorDuration),
                    value: String(format: "%.1fs", summary.durationSeconds),
                    icon: "clock.fill",
                    color: .secondary
                )
            }
            .padding(.vertical, 8)
        }
        .otterCard(padding: OtterTheme.spacing12)
    }

    private func statColumn(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sanctuary Guarantee Card
    private func guaranteeCard(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title3)
                .foregroundStyle(OtterTheme.statusGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(.feedbackGuaranteeTitle))
                    .font(.callout.weight(.semibold))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .otterCard(padding: OtterTheme.spacing12)
    }

    /// Runs the restorative pathway attached to a failure, then closes the modal.
    private func perform(_ recovery: RecoveryAction) {
        switch recovery.kind {
        case .openFullDiskAccess:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
            onDismiss()
        case .viewLogs:
            onDismiss()
            onViewLogs?()
        }
    }

    // MARK: - Failure Advice & Reassurance Card
    private func failureAdviceCard(reason: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(OtterTheme.otterAmber)

            VStack(alignment: .leading, spacing: 4) {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .otterCard(padding: OtterTheme.spacing12)
    }
}
