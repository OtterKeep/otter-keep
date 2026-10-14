import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// AppKit-backed ``NotificationPresenting`` implementation used by the platform shells (GUI, daemon).
///
/// This file is the only place where notification delivery touches AppKit (icon rendering, the
/// `osascript` fallback and application activation), keeping ``NotificationDeliveryService`` free
/// of platform UI frameworks.
public struct SystemNotificationPresenter: NotificationPresenting {
    /// Initializes the system presenter.
    public init() {}

    /// Resolves (and caches) a PNG rendering of the application icon for notification attachments.
    /// - Returns: The PNG file URL, or `nil` when no icon could be rendered.
    public func notificationAttachmentIconURL() -> URL? {
        #if canImport(AppKit)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OtterKeep_NotifIcon", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let targetPNG = tempDir.appendingPathComponent("AppIcon.png")

        if FileManager.default.fileExists(atPath: targetPNG.path) {
            return targetPNG
        }

        var sourceImage = NSImage(named: NSImage.applicationIconName)

        if sourceImage == nil {
            let candidatePaths = [
                Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                Bundle.main.url(forResource: "OttieSuccess", withExtension: "png"),
                Bundle.main.resourceURL?.appendingPathComponent("AppIcon.icns"),
                Bundle.main.resourceURL?.appendingPathComponent("OtterKeep_OtterKeepUI.bundle/Contents/Resources/AppIcon.icns"),
                URL(fileURLWithPath: "/Applications/OtterKeep.app/Contents/Resources/AppIcon.icns"),
                URL(fileURLWithPath: "/Applications/OtterKeep.app/Contents/Resources/OtterKeep_OtterKeepUI.bundle/Contents/Resources/AppIcon.icns")
            ]
            for candidate in candidatePaths.compactMap({ $0 }) {
                if FileManager.default.fileExists(atPath: candidate.path), let img = NSImage(contentsOf: candidate) {
                    sourceImage = img
                    break
                }
            }
        }

        if let img = sourceImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let pngData = rep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: targetPNG, options: .atomic)
            return targetPNG
        }
        #endif

        return nil
    }

    /// Displays a notification through `osascript`.
    /// - Parameters:
    ///   - title: Notification title.
    ///   - body: Notification body.
    public func deliverFallbackNotification(title: String, body: String) {
        #if canImport(AppKit)
        let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName.lowercased().contains("test")
            || ProcessInfo.processInfo.arguments.contains(where: { $0.lowercased().contains("test") })
            || NSClassFromString("XCTest") != nil
        if isTesting {
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let safeBody = body.replacingOccurrences(of: "\"", with: "\\\"")
            let safeTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let fallbackScript = "display notification \"\(safeBody)\" with title \"\(safeTitle)\""
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", fallbackScript]
            try? proc.run()
        }
        #endif
    }

    /// Reports whether the application is active with a visible main window.
    /// - Returns: `true` when the app is foreground-active with a visible main window.
    public func isApplicationForegroundActive() -> Bool {
        #if canImport(AppKit)
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                NSApp.isActive && (NSApp.mainWindow?.isVisible == true)
            }
        }
        #endif
        return false
    }

    /// Activates the application and brings its main window to the front on the main queue.
    public func activateApplication() {
        #if canImport(AppKit)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) ?? NSApp.mainWindow {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
        #endif
    }
}
