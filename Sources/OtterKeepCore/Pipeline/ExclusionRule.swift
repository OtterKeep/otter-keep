import Foundation

/// Pattern matching rule for filtering and excluding specific files or directories from backups.
///
/// Shared by the backup scanner and the continuous-mode filesystem watcher so both apply the
/// exact same exclusion semantics.
public struct ExclusionRule: Sendable, Equatable {
    /// Supported rule matching strategies.
    public enum RuleType: Sendable, Equatable {
        /// Exact filename or path match.
        case exact(String)
        /// Prefix pattern match (e.g. `temp*`).
        case prefix(String)
        /// Suffix/extension pattern match (e.g. `*.log`).
        case suffix(String)
        /// Substring containment match (e.g. `*cache*`).
        case contains(String)
    }

    /// Raw input pattern string.
    public let pattern: String
    /// Categorized rule type.
    public let ruleType: RuleType

    /// Initializes an `ExclusionRule` by parsing wildcard characters in the pattern.
    /// - Parameter pattern: Pattern string (e.g. `*.tmp`, `node_modules`, `.DS_Store`).
    public init(pattern: String) {
        self.pattern = pattern
        if pattern.hasPrefix("*") && !pattern.dropFirst().contains("*") {
            self.ruleType = .suffix(String(pattern.dropFirst()))
        } else if pattern.hasSuffix("*") && !pattern.dropLast().contains("*") {
            self.ruleType = .prefix(String(pattern.dropLast()))
        } else if pattern.hasPrefix("*") && pattern.hasSuffix("*") {
            let inner = String(pattern.dropFirst().dropLast())
            self.ruleType = .contains(inner)
        } else {
            self.ruleType = .exact(pattern)
        }
    }

    /// Evaluates whether a filename or relative path matches this exclusion rule.
    /// - Parameters:
    ///   - name: The item's last path component.
    ///   - relativePath: The relative path from the root directory.
    /// - Returns: True if the item should be excluded.
    public func matches(name: String, relativePath: String) -> Bool {
        switch ruleType {
        case .exact(let p):
            return name == p || relativePath == p
        case .prefix(let p):
            return name.hasPrefix(p) || relativePath.hasPrefix(p)
        case .suffix(let p):
            return name.hasSuffix(p) || relativePath.hasSuffix(p)
        case .contains(let p):
            return name.contains(p) || relativePath.contains(p)
        }
    }

    /// Evaluates whether an absolute filesystem path matches this exclusion rule.
    ///
    /// Used by the continuous-mode watcher, which only sees absolute event paths. Matching is
    /// anchored on the last path component so a rule can never accidentally match a parent
    /// directory segment; only `contains` rules also inspect the full path, which is what makes
    /// patterns such as `*cache*` exclude nested directories.
    /// - Parameter path: Absolute path reported by the filesystem event stream.
    /// - Returns: True if the path should be excluded.
    public func matches(absolutePath path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        switch ruleType {
        case .exact(let p):
            return name == p
        case .prefix(let p):
            return name.hasPrefix(p)
        case .suffix(let p):
            return name.hasSuffix(p)
        case .contains(let p):
            return name.contains(p) || path.contains(p)
        }
    }
}
