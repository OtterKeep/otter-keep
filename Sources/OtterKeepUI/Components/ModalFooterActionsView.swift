//
//  ModalFooterActionsView.swift
//  OtterKeepUI
//
//  Standardized macOS modal sheet footer action bar adhering to Apple Human Interface Guidelines.
//

import OtterKeepCore
import SwiftUI

/// Standardized pinned footer action bar for macOS modal sheets and dialogs.
/// Follows Apple HIG: optional auxiliary actions on the leading edge, and grouped
/// dismissive / primary action buttons on the trailing edge.
public struct ModalFooterActionsView<Auxiliary: View>: View {
    public let cancelTitle: String
    public let primaryTitle: String
    public let isPrimaryDisabled: Bool
    public let isPrimaryDestructive: Bool
    public let primaryTint: Color?
    public let onCancel: (() -> Void)?
    public let onPrimary: () -> Void
    public let auxiliary: Auxiliary

    public init(
        cancelTitle: String = L10n.t(.cancel),
        primaryTitle: String = L10n.t(.save),
        isPrimaryDisabled: Bool = false,
        isPrimaryDestructive: Bool = false,
        primaryTint: Color? = nil,
        onCancel: (() -> Void)? = nil,
        onPrimary: @escaping () -> Void,
        @ViewBuilder auxiliary: () -> Auxiliary
    ) {
        self.cancelTitle = cancelTitle
        self.primaryTitle = primaryTitle
        self.isPrimaryDisabled = isPrimaryDisabled
        self.isPrimaryDestructive = isPrimaryDestructive
        self.primaryTint = primaryTint
        self.onCancel = onCancel
        self.onPrimary = onPrimary
        self.auxiliary = auxiliary()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                // Leading Auxiliary Content
                auxiliary

                Spacer()

                // Trailing Grouped Action Buttons
                if let onCancel = onCancel {
                    Button(cancelTitle) {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .keyboardShortcut(.cancelAction)
                }

                Button(role: isPrimaryDestructive ? .destructive : nil) {
                    onPrimary()
                } label: {
                    Text(primaryTitle)
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryTint ?? (isPrimaryDestructive ? OtterTheme.statusError : OtterTheme.otterAmber))
                .controlSize(.regular)
                .disabled(isPrimaryDisabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
    }
}

extension ModalFooterActionsView where Auxiliary == EmptyView {
    public init(
        cancelTitle: String = L10n.t(.cancel),
        primaryTitle: String = L10n.t(.save),
        isPrimaryDisabled: Bool = false,
        isPrimaryDestructive: Bool = false,
        primaryTint: Color? = nil,
        onCancel: (() -> Void)? = nil,
        onPrimary: @escaping () -> Void
    ) {
        self.init(
            cancelTitle: cancelTitle,
            primaryTitle: primaryTitle,
            isPrimaryDisabled: isPrimaryDisabled,
            isPrimaryDestructive: isPrimaryDestructive,
            primaryTint: primaryTint,
            onCancel: onCancel,
            onPrimary: onPrimary,
            auxiliary: { EmptyView() }
        )
    }
}
