import Foundation

/// Abstract platform port for requesting external volume ejection.
public protocol VolumeEjectingPort: Sendable {
    func ejectVolume(at url: URL) async throws
}

/// Abstract platform port for observing hardware volume mount/unmount events.
public protocol VolumeObservingPort: Sendable {
    func startObserving(onChange: @escaping @Sendable (URL, Bool) -> Void)
    func stopObserving()
}

/// Abstract platform port for acquiring and releasing sleep-prevention assertions.
public protocol PowerManagementPort: Sendable {
    func beginPowerAssertion(reason: String) -> Any
    func endPowerAssertion(_ token: Any)
}

/// Abstract platform port for dispatching system notifications.
public protocol NotificationDispatchPort: Sendable {
    func notifySuccess(title: String, message: String)
    func notifyWarning(title: String, message: String)
    func notifyFailure(title: String, message: String)
}
