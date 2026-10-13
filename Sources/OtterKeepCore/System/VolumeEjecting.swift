import Foundation

/// Abstraction over "safely unmount and eject the destination volume".
///
/// The backup pipeline must not depend on AppKit. Platform shells (GUI, CLI, daemon) inject a
/// concrete implementation, which keeps the engine runnable — and testable — without a window
/// server session.
public protocol VolumeEjecting: Sendable {
    /// Unmounts and ejects the volume that contains the given URL.
    /// - Parameter url: A location on the volume to eject.
    /// - Throws: The underlying ejection error, if the volume could not be ejected.
    func ejectVolume(at url: URL) throws
}

/// Ejector used when no platform implementation is injected; performs no filesystem work.
public struct NoopVolumeEjector: VolumeEjecting {
    /// Initializes a no-op ejector.
    public init() {}

    /// Does nothing; present so the pipeline can run without AppKit.
    public func ejectVolume(at url: URL) throws {}
}
