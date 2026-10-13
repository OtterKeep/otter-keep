//
//  SystemLogsModalView.swift
//  OtterKeepUI
//
//  Dedicated modal sheet window for diagnostic system logs, log level filtering,
//  text search, and export.
//

import SwiftUI
import AppKit
import OtterKeepCore

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

                Button(L10n.t(.okDone)) {
                    appState.showSystemLogsModal = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Main Logs View
            DiagnosticLogView(appState: appState)
        }
        .frame(minWidth: 780, idealWidth: 840, minHeight: 520, idealHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
