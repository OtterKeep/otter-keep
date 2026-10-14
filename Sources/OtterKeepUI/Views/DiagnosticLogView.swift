import SwiftUI
import UniformTypeIdentifiers
import OtterKeepCore

public struct DiagnosticLogView: View {
    public let appState: AppState

    private var selectedLevelBinding: Binding<LogEntry.LogLevel?> {
        Binding(get: { appState.selectedLogLevel }, set: { appState.selectedLogLevel = $0 })
    }

    private var filterQueryBinding: Binding<String> {
        Binding(get: { appState.logFilterQuery }, set: { appState.logFilterQuery = $0 })
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar / filter bar
            HStack {
                Picker("", selection: selectedLevelBinding) {
                    Text(L10n.t(.logAllLevels)).tag(LogEntry.LogLevel?.none)
                    ForEach(LogEntry.LogLevel.allCases, id: \.self) { lvl in
                        Text(lvl.rawValue).tag(LogEntry.LogLevel?.some(lvl))
                    }
                }
                .frame(width: 160)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(L10n.t(.logSearchPlaceholder), text: filterQueryBinding)
                        .textFieldStyle(.plain)
                        .font(.body)
                    if !appState.logFilterQuery.isEmpty {
                        Button { appState.logFilterQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

                if appState.isDebugFileLoggingEnabled, let logURL = (appState.currentDebugLogFileURL ?? LogManager.shared.currentDebugLogFileURL) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(OtterTheme.statusGreen)
                                .frame(width: 7, height: 7)
                            Text(".log")
                                .font(.caption.bold())
                                .foregroundStyle(OtterTheme.statusGreen)
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OtterTheme.statusGreen.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(logURL.path(percentEncoded: false))
                }

                Spacer()

                Button {
                    appState.refreshLogs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                }
                .help(L10n.t(.refreshStatus))

                Button(role: .destructive) {
                    appState.clearLogs()
                } label: {
                    Label(L10n.t(.clearLogsButton), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(L10n.t(.exportLogsButton)) {
                    exportLogs()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    exportSupportBundle()
                } label: {
                    Label(LocalizationManager.shared.effectiveLanguage == .hungarian ? "Támogatási csomag..." : "Support Bundle...", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding()
            .background(.background.secondary)

            Divider()

            // Log entries list
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    L10n.t(.logEmptyTitle),
                    systemImage: "list.bullet.rectangle",
                    description: Text(L10n.t(.logEmptyDesc))
                        .font(.body)
                )
            } else {
                List(filteredEntries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Text(Self.dateFormatter.string(from: entry.timestamp))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 105, alignment: .leading)

                        Text(entry.level.rawValue)
                            .font(.system(.body, design: .monospaced).bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(levelColor(entry.level).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(levelColor(entry.level))
                            .frame(width: 75)

                        Text("[\(entry.category)]")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Text(entry.message)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            appState.refreshLogs()
        }
    }

    private var filteredEntries: [LogEntry] {
        appState.logEntries.filter { entry in
            let matchesLevel = (appState.selectedLogLevel == nil) || (entry.level == appState.selectedLogLevel)
            let matchesQuery = appState.logFilterQuery.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(appState.logFilterQuery) ||
                entry.category.localizedCaseInsensitiveContains(appState.logFilterQuery)
            return matchesLevel && matchesQuery
        }
    }

    private func levelColor(_ level: LogEntry.LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "OtterKeep_Logs_\(ISO8601DateFormatter().string(from: Date())).txt"
        if panel.runModal() == .OK, let url = panel.url {
            appState.exportLogs(to: url)
        }
    }

    private func exportSupportBundle() {
        let panel = NSSavePanel()
        if let zipType = UTType(filenameExtension: "zip") {
            panel.allowedContentTypes = [zipType]
        }
        panel.nameFieldStringValue = "OtterKeep-Diagnostics-\(Int(Date().timeIntervalSince1970)).zip"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    _ = try await SanctuarySupportBundleExporter.shared.exportSupportBundle(to: url)
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    LogManager.shared.log("Failed to export support bundle: \(error.localizedDescription)", level: .error, category: "SupportBundle")
                }
            }
        }
    }
}
