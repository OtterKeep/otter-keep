import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// AppKit-backed ``VolumeEjecting`` implementation used by the platform shells (GUI, CLI, daemon).
///
/// This file is the only place where volume ejection touches AppKit, keeping the backup pipeline
/// free of platform UI frameworks.
public struct SystemVolumeEjector: VolumeEjecting {
    /// Initializes the system ejector.
    public init() {}

    /// Unmounts and ejects the volume containing `url` through `NSWorkspace`.
    /// - Parameter url: A location on the volume to eject.
    /// - Throws: `NSWorkspace` errors when the volume cannot be ejected.
    public func ejectVolume(at url: URL) throws {
        #if canImport(AppKit)
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        #endif
    }
}
