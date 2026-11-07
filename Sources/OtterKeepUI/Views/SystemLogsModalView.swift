//
//  SystemLogsModalView.swift
//  OtterKeepUI
//
//  Dedicated modal sheet window for diagnostic system logs, log level filtering,
//  text search, and export.
//

import AppKit
import OtterKeepCore
import SwiftUI

/// Dedicated modal sheet presenting live system logs and diagnostics.
public struct SystemLogsModalView: View {
    public let appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(OtterTheme.accentPurple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(.menuSystemLogs))
                        .font(.headline.bold())
                    Text(L10n.t(.logsSubtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.showSystemLogsModal = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(.closeButton))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Main Logs View
            DiagnosticLogView(appState: appState)

            // Pinned Footer
            ModalFooterActionsView(
                primaryTitle: L10n.t(.okDone),
                onCancel: nil,
                onPrimary: {
                    appState.showSystemLogsModal = false
                }
            )
        }
        .frame(minWidth: 780, idealWidth: 840, minHeight: 520, idealHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
