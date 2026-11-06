//
//  BiometricSecurityTests.swift
//  OtterKeepIntegrationTests
//
//  Tests for LocalAuthentication Biometric Security Service, Secure Enclave Keychain,
//  and action gates.
//

import Foundation
import Testing
import OtterKeepDomain
import OtterKeepCore

@MainActor
@Suite(.serialized)
struct BiometricSecurityTests {
    @Test func testBiometricHardwareStateEvaluation() throws {
        let service = BiometricSecurityService.shared
        let state = service.evaluateHardwareState()
        // Hardware state should be either touchIDAvailable, passcodeOnly, or unavailable on CI/headless
        switch state {
        case .touchIDAvailable, .passcodeOnly, .unavailable:
            try assertTrue(true)
        }
    }

    @Test func testBiometricAuthenticationSuccessSimulation() async throws {
        let service = BiometricSecurityService.shared
        service.testAuthenticationHandler = { reason in
            return .success(())
        }
        defer { service.testAuthenticationHandler = nil }

        let result = await service.authenticate(reason: "Testing Touch ID auth")
        switch result {
        case .success:
            try assertTrue(true)
        case .failure(let error):
            try assertTrue(false, "Simulated authentication should succeed: \(error)")
        }
    }

    @Test func testBiometricAuthenticationFailureSimulation() async throws {
        let service = BiometricSecurityService.shared
        service.testAuthenticationHandler = { reason in
            return .failure(.userCancelled)
        }
        defer { service.testAuthenticationHandler = nil }

        let result = await service.authenticate(reason: "Testing Touch ID failure")
        switch result {
        case .success:
            try assertTrue(false, "Should not succeed when handler returns failure")
        case .failure(let error):
            try assertEqual(error, .userCancelled)
        }
    }

    @Test func testAppSettingsBiometricProperties() throws {
        var settings = AppSettings()
        try assertTrue(!settings.isBiometricsEnabled, "Default biometrics enabled should be false")
        try assertTrue(settings.requireBiometricsForRestore, "Action gates default to true when biometrics master switch is turned on")
        try assertTrue(settings.requireBiometricsForProfileDeletion)
        try assertTrue(settings.requireBiometricsForKeyReveal)
        try assertTrue(!settings.useSecureEnclaveForKeychain)

        settings.isBiometricsEnabled = true
        settings.requireBiometricsForRestore = false
        settings.requireBiometricsForProfileDeletion = false
        settings.requireBiometricsForKeyReveal = false
        settings.useSecureEnclaveForKeychain = true

        try assertTrue(settings.isBiometricsEnabled)
        try assertTrue(!settings.requireBiometricsForRestore)
        try assertTrue(!settings.requireBiometricsForProfileDeletion)
        try assertTrue(!settings.requireBiometricsForKeyReveal)
        try assertTrue(settings.useSecureEnclaveForKeychain)
    }

    @Test func testKeychainPassphraseRoundtrip() throws {
        let profileId = UUID()
        let passphrase = "Ollie-Keychain-Test-Key-1234"

        try KeychainManager.savePassphrase(passphrase, for: profileId, requireSecureEnclave: false)
        let retrieved = KeychainManager.getPassphrase(for: profileId)
        try assertEqual(retrieved, passphrase, "Passphrase from Keychain must match saved value")

        KeychainManager.deletePassphrase(for: profileId)
        let afterDelete = KeychainManager.getPassphrase(for: profileId)
        try assertTrue(afterDelete == nil, "Passphrase should be deleted from Keychain")
    }
}
