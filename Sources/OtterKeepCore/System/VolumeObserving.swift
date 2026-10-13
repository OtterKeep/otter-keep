import Foundation

/// Abstraction over "observe macOS volume mount and unmount events".
///
/// ``VolumeMonitor`` must not depend on AppKit. The platform implementation lives in a single
/// AppKit-isolated adapter (``SystemVolumeObserver``), so a headless caller can inject
/// ``NoopVolumeObserver`` instead and keep the engine runnable without a window server session.
public protocol VolumeObserving: Sendable {
    /// Starts delivering volume mount and unmount events.
    /// - Parameters:
    ///   - onMount: Called with the mounted volume URL, or `nil` when the URL is unavailable.
    ///   - onUnmount: Called with the unmounted volume URL, or `nil` when the URL is unavailable.
    func startObserving(
        onMount: @escaping @Sendable (URL?) -> Void,
        onUnmount: @escaping @Sendable (URL?) -> Void
    )

    /// Stops delivering events; safe to call multiple times.
    func stopObserving()
}

/// Observer used when no platform implementation is injected; never reports events.
public struct NoopVolumeObserver: VolumeObserving {
    /// Initializes a no-op observer.
    public init() {}

    /// Does nothing; present so the monitor can run without AppKit.
    public func startObserving(
        onMount: @escaping @Sendable (URL?) -> Void,
        onUnmount: @escaping @Sendable (URL?) -> Void
    ) {}

    /// Does nothing; present so the monitor can run without AppKit.
    public func stopObserving() {}
}
