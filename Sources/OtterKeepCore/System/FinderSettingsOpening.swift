import Foundation

/// Abstraction over "open a macOS System Settings pane".
///
/// ``FinderPermissionManager`` must not depend on AppKit. The platform implementation lives in a
/// single AppKit-isolated adapter (``SystemFinderSettingsOpener``), so the permission checks
/// themselves stay usable from a headless process that has no window server session.
public protocol FinderSettingsOpening: Sendable {
    /// Asks macOS to open the given `x-apple.systempreferences:` deep link.
    /// - Parameter url: System Settings deep link.
    /// - Returns: `true` when macOS accepted the request.
    func openSettingsURL(_ url: URL) -> Bool
}
