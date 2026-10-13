import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// AppKit-backed ``FinderSettingsOpening`` implementation used by the platform shells (GUI).
///
/// This file is the only place where Finder integration touches AppKit, keeping
/// ``FinderPermissionManager`` free of platform UI frameworks.
public struct SystemFinderSettingsOpener: FinderSettingsOpening {
    /// Initializes the system settings opener.
    public init() {}

    /// Opens the given System Settings deep link through `NSWorkspace`.
    /// - Parameter url: System Settings deep link.
    /// - Returns: `true` when macOS accepted the request.
    public func openSettingsURL(_ url: URL) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }
}
