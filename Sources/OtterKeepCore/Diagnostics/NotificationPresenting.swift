import Foundation

/// Abstraction over the AppKit-dependent parts of user-notification delivery.
///
/// ``NotificationDeliveryService`` must not depend on AppKit. The platform implementation lives in
/// a single AppKit-isolated adapter (``SystemNotificationPresenter``), so notifications and the
/// diagnostics engine stay usable from a headless process that has no window server session.
public protocol NotificationPresenting: Sendable {
    /// Returns a PNG icon file URL suitable as a notification attachment, if the platform can supply one.
    func notificationAttachmentIconURL() -> URL?

    /// Presents a notification outside `UNUserNotificationCenter`, used when the process has no bundle identifier.
    /// - Parameters:
    ///   - title: Notification title.
    ///   - body: Notification body.
    func deliverFallbackNotification(title: String, body: String)

    /// Indicates whether the application is foreground-active with a visible main window.
    func isApplicationForegroundActive() -> Bool

    /// Brings the application and its main window to the front.
    func activateApplication()
}
