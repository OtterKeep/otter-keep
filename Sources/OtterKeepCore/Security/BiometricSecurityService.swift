import Foundation
import LocalAuthentication
import os

/// Errors that can occur during biometric or passcode authentication.
public enum BiometricAuthError: Error, Sendable, LocalizedError, Equatable {
    case biometricsNotAvailable
    case userCancelled
    case authenticationFailed(String)
    case passcodeNotSet
    case operationRestricted

    public var errorDescription: String? {
        switch self {
        case .biometricsNotAvailable:
            return "Touch ID or biometric authentication is not available on this Mac."
        case .userCancelled:
            return "Authentication was cancelled by the user."
        case .authenticationFailed(let msg):
            return "Authentication failed: \(msg)"
        case .passcodeNotSet:
            return "Device passcode is not configured in macOS System Settings."
        case .operationRestricted:
            return "Biometric authentication is restricted by system security policies."
        }
    }
}

/// Hardware capability state for biometric authentication.
public enum BiometricHardwareState: Sendable, Equatable {
    case touchIDAvailable
    case passcodeOnly
    case unavailable(reason: String)
}

/// Service managing Touch ID, Apple Watch, and macOS system passcode verification.
public final class BiometricSecurityService: @unchecked Sendable {
    public static let shared = BiometricSecurityService()

    private let logger = Logger(subsystem: "com.otterkeep", category: "Biometrics")

    /// Test hook to simulate authentication outcomes in automated test environments or CI runners.
    public var testAuthenticationHandler: (@Sendable (String) -> Result<Void, BiometricAuthError>)? = nil

    public init() {}

    /// Checks the current biometric hardware capability of the running Mac.
    public func evaluateHardwareState() -> BiometricHardwareState {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return .touchIDAvailable
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .passcodeOnly
        } else {
            let msg = error?.localizedDescription ?? "Hardware authentication unavailable"
            return .unavailable(reason: msg)
        }
    }

    /// Authenticates the current user using Touch ID (or Apple Watch / system password fallback).
    /// - Parameter reason: Clear explanation displayed in the macOS authentication sheet.
    /// - Returns: Success if verified, or typed `BiometricAuthError` on failure or cancellation.
    public func authenticate(reason: String) async -> Result<Void, BiometricAuthError> {
        if let handler = testAuthenticationHandler {
            return handler(reason)
        }

        let context = LAContext()
        context.localizedCancelTitle = L10n.t(.cancel)

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            logger.warning("Device owner authentication cannot be evaluated: \(error?.localizedDescription ?? "Unknown error")")
            return .failure(.biometricsNotAvailable)
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, authError in
                if success {
                    continuation.resume(returning: .success(()))
                } else if let laError = authError as? LAError {
                    switch laError.code {
                    case .userCancel, .appCancel, .systemCancel:
                        continuation.resume(returning: .failure(.userCancelled))
                    case .passcodeNotSet:
                        continuation.resume(returning: .failure(.passcodeNotSet))
                    default:
                        continuation.resume(returning: .failure(.authenticationFailed(laError.localizedDescription)))
                    }
                } else {
                    continuation.resume(returning: .failure(.authenticationFailed(authError?.localizedDescription ?? "Unknown failure")))
                }
            }
        }
    }
}
