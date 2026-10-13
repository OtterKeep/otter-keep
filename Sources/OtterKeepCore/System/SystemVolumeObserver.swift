import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// AppKit-backed ``VolumeObserving`` implementation used by the platform shells (GUI, CLI, daemon).
///
/// This file is the only place where volume mount/unmount observation touches AppKit, keeping
/// ``VolumeMonitor`` free of platform UI frameworks.
public final class SystemVolumeObserver: VolumeObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?

    /// Initializes the system observer.
    public init() {}

    /// Registers `NSWorkspace` mount and unmount observers delivering on the main queue.
    /// - Parameters:
    ///   - onMount: Called with the mounted volume URL, or `nil` when the URL is unavailable.
    ///   - onUnmount: Called with the unmounted volume URL, or `nil` when the URL is unavailable.
    public func startObserving(
        onMount: @escaping @Sendable (URL?) -> Void,
        onUnmount: @escaping @Sendable (URL?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard mountObserver == nil, unmountObserver == nil else { return }

        #if canImport(AppKit)
        let center = NSWorkspace.shared.notificationCenter
        mountObserver = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { notif in
            onMount(notif.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)
        }
        unmountObserver = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { notif in
            onUnmount(notif.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)
        }
        #endif
    }

    /// Removes the registered `NSWorkspace` observers.
    public func stopObserving() {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(AppKit)
        let center = NSWorkspace.shared.notificationCenter
        if let observer = mountObserver {
            center.removeObserver(observer)
        }
        if let observer = unmountObserver {
            center.removeObserver(observer)
        }
        #endif
        mountObserver = nil
        unmountObserver = nil
    }
}
