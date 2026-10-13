//
//  AssertionFramework.swift
//  OtterKeepIntegrationTests
//
//  Throwing assertion helpers carried over from the legacy OtterKeepTestRunner harness.
//

import Foundation

// MARK: - Assertion Framework

public struct TestFailure: Error, CustomStringConvertible {
    public let message: String
    public let file: String
    public let line: Int

    public init(message: String, file: String = #file, line: Int = #line) {
        self.message = message
        self.file = file
        self.line = line
    }

    public var description: String {
        "\(URL(fileURLWithPath: file).lastPathComponent):\(line): \(message)"
    }
}

public func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard condition() else {
        throw TestFailure(message: "Assertion failed: expected true, got false. \(message)", file: file, line: line)
    }
}

public func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard !condition() else {
        throw TestFailure(message: "Assertion failed: expected false, got true. \(message)", file: file, line: line)
    }
}

public func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a == b else {
        throw TestFailure(message: "Assertion failed: '\(a)' != '\(b)'. \(message)", file: file, line: line)
    }
}

public func assertNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard a != b else {
        throw TestFailure(message: "Assertion failed: values are unexpectedly equal ('\(a)'). \(message)", file: file, line: line)
    }
}

public func assertNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard value == nil else {
        throw TestFailure(message: "Assertion failed: expected nil, got '\(value!)'. \(message)", file: file, line: line)
    }
}

public func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws {
    guard value != nil else {
        throw TestFailure(message: "Assertion failed: expected non-nil value. \(message)", file: file, line: line)
    }
}

/// Unwraps an optional or throws a `TestFailure`, returning the unwrapped value.
public func require<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) throws -> T {
    guard let value else {
        throw TestFailure(message: "Assertion failed: expected non-nil value. \(message)", file: file, line: line)
    }
    return value
}
