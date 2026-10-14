import SwiftUI
import AppKit
import OtterKeepCore
import OtterKeepUI
#if canImport(Sparkle)
import Sparkle

/// In-app software update controller bridging the official Sparkle 2.x framework.
final class SparkleUpdaterBridge: NSObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdaterBridge()
    private var updaterController: SPUStandardUpdaterController?

    func setup() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
#endif

/// Shared application context holding the central `@Observable` AppState.
@MainActor
final class AppContext {
    static let shared = AppContext()
    let appState = AppState()
    private init() {}
}

/// Application delegate handling single-instance lifecycle events, application dock icon, and cleanup.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the native mascot dock icon for OtterKeep
        if let icon = OtterKeepLogoView.createApplicationDockIcon() {
            NSApp.applicationIconImage = icon
        }

        #if canImport(Sparkle)
        SparkleUpdaterBridge.shared.setup()
        AppContext.shared.appState.onCheckForUpdatesNative = {
            SparkleUpdaterBridge.shared.checkForUpdates()
        }
        #endif

        // Register macOS Services provider for universal right-click context menu integration
        NSApp.servicesProvider = self

        // Request authorization for proactive backup and restore notifications
        Task {
            _ = await NotificationDeliveryService.shared.requestAuthorization()
        }

        // Parse launch arguments for direct file-history requests on initial launch
        let args = CommandLine.arguments
        for i in 0..<args.count {
            if args[i] == "--restore-file" || args[i] == "--file-history" || args[i] == "-f" {
                if i + 1 < args.count {
                    let path = args[i + 1]
                    Task { @MainActor in
                        WindowManager.showAndFocusMainWindow()
                        AppContext.shared.appState.openVersionHistory(for: URL(fileURLWithPath: path))
                    }
                }
            }
        }

        // Automatically check for software updates in the background if enabled
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if AppContext.shared.appState.automaticallyChecksForUpdates {
                AppContext.shared.appState.checkForSoftwareUpdates(silent: true)
            }
        }
    }

    // MARK: - macOS Services Context Menu Handler

    @objc func openVersionHistoryService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if let types = pboard.types, types.contains(.fileURL),
           let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = urls.first {
            Task { @MainActor in
                WindowManager.showAndFocusMainWindow()
                AppContext.shared.appState.openVersionHistory(for: firstURL)
            }
            return
        }

        if let filenames = pboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String], let first = filenames.first {
            let fileURL = URL(fileURLWithPath: first)
            Task { @MainActor in
                WindowManager.showAndFocusMainWindow()
                AppContext.shared.appState.openVersionHistory(for: fileURL)
            }
            return
        }

        if let str = pboard.string(forType: .string) {
            let fileURL = URL(fileURLWithPath: str)
            Task { @MainActor in
                WindowManager.showAndFocusMainWindow()
                AppContext.shared.appState.openVersionHistory(for: fileURL)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            WindowManager.showAndFocusMainWindow()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "otterkeep" && url.host == "restore-versions" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let pathItem = components.queryItems?.first(where: { $0.name == "path" })?.value {
                    let fileURL = URL(fileURLWithPath: pathItem)
                    Task { @MainActor in
                        WindowManager.showAndFocusMainWindow()
                        AppContext.shared.appState.openVersionHistory(for: fileURL)
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        SingleInstanceManager.shared.stopServer()
    }
}

/// Main application entry point providing the single SwiftUI window scene and MenuBar companion.
struct OtterKeepApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let appState = AppContext.shared.appState

    var body: some Scene {
        Window("OtterKeep", id: "main") {
            MainWindowView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            OtterKeepMenuCommands(appState: appState)
        }

        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            OtterKeepMenuBarIconView(isRunning: appState.isBackupRunning || appState.isPhotosBackupRunning)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Single-Instance Pre-Flight Execution

// 1. Check if a primary GUI instance is already running
if SingleInstanceManager.shared.checkAndForward(arguments: CommandLine.arguments) {
    print("🦦 OtterKeep GUI is already running. Request forwarded to active instance.")
    exit(0)
}

// 2. Start the Unix Domain Socket IPC listener for future secondary launches and Finder integration
SingleInstanceManager.shared.startServer { message in
    Task { @MainActor in
        WindowManager.showAndFocusMainWindow()

        switch message.action {
        case .activate:
            break
        case .openVersionHistory:
            if let path = message.filePath {
                AppContext.shared.appState.openVersionHistory(for: URL(fileURLWithPath: path))
            }
        }
    }
}

// 3. Launch the native SwiftUI application
OtterKeepApplication.main()

