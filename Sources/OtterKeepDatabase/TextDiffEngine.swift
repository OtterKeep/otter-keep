import Foundation
import OtterKeepDomain

/// High-performance text and binary difference engine computing aligned side-by-side diffs.
public struct TextDiffEngine: Sendable {

    /// Maximum file size supported for in-memory line-by-line diffing (10 MB).
    public static let maxDiffableFileSize: Int64 = 10 * 1024 * 1024

    public init() {}

    /// Compares two text strings line-by-line and returns aligned side-by-side diff rows.
    /// - Parameters:
    ///   - left: Base text content.
    ///   - right: Target text content.
    ///   - relativePath: File relative path for context.
    /// - Returns: A `FileComparisonResult` with aligned lines and change statistics.
    public func diff(left: String, right: String, relativePath: String = "") -> FileComparisonResult {
        let leftLines = left.components(separatedBy: "\n")
        let rightLines = right.components(separatedBy: "\n")

        let aligned = computeLCSAlignment(leftLines: leftLines, rightLines: rightLines)

        var addedCount = 0
        var deletedCount = 0
        var modifiedCount = 0

        for row in aligned {
            switch row.type {
            case .added: addedCount += 1
            case .deleted: deletedCount += 1
            case .modified: modifiedCount += 1
            case .unchanged: break
            }
        }

        return FileComparisonResult(
            relativePath: relativePath,
            isBinary: false,
            leftSize: Int64(left.utf8.count),
            rightSize: Int64(right.utf8.count),
            rows: aligned,
            addedLinesCount: addedCount,
            deletedLinesCount: deletedCount,
            modifiedLinesCount: modifiedCount
        )
    }

    /// Compares two files on disk by path or URL, inspecting binary signatures and generating diffs.
    /// - Parameters:
    ///   - leftURL: Base file URL (optional, nil if file was newly added).
    ///   - rightURL: Target file URL (optional, nil if file was deleted).
    ///   - relativePath: Display relative path.
    /// - Returns: A complete `FileComparisonResult`.
    public func diffFiles(
        leftURL: URL?,
        rightURL: URL?,
        relativePath: String
    ) throws -> FileComparisonResult {
        let leftData: Data? = leftURL.flatMap { try? Data(contentsOf: $0) }
        let rightData: Data? = rightURL.flatMap { try? Data(contentsOf: $0) }

        let leftSize = Int64(leftData?.count ?? 0)
        let rightSize = Int64(rightData?.count ?? 0)

        let isLeftBinary = leftData.map(Self.isBinaryData) ?? false
        let isRightBinary = rightData.map(Self.isBinaryData) ?? false
        let isBinary = isLeftBinary || isRightBinary

        let leftMtime = leftURL.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let rightMtime = rightURL.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

        if isBinary {
            return FileComparisonResult(
                relativePath: relativePath,
                isBinary: true,
                leftSize: leftSize,
                rightSize: rightSize,
                leftSHA256: nil,
                rightSHA256: nil,
                leftMtime: leftMtime,
                rightMtime: rightMtime,
                rows: [],
                addedLinesCount: 0,
                deletedLinesCount: 0,
                modifiedLinesCount: 0
            )
        }

        let leftText = leftData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let rightText = rightData.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        let result = diff(left: leftText, right: rightText, relativePath: relativePath)
        return FileComparisonResult(
            relativePath: relativePath,
            isBinary: false,
            leftSize: leftSize,
            rightSize: rightSize,
            leftSHA256: nil,
            rightSHA256: nil,
            leftMtime: leftMtime,
            rightMtime: rightMtime,
            rows: result.rows,
            addedLinesCount: result.addedLinesCount,
            deletedLinesCount: result.deletedLinesCount,
            modifiedLinesCount: result.modifiedLinesCount
        )
    }

    /// Evaluates whether raw data represents binary content by scanning for null bytes (0x00).
    public static func isBinaryData(_ data: Data) -> Bool {
        let inspectLimit = min(data.count, 8192)
        guard inspectLimit > 0 else { return false }
        for byte in data.prefix(inspectLimit) {
            if byte == 0 { return true }
        }
        return false
    }

    /// Computes Longest Common Subsequence (LCS) matrix to align lines side-by-side.
    private func computeLCSAlignment(leftLines: [String], rightLines: [String]) -> [SideBySideDiffLine] {
        // Optimization for identical or empty inputs
        if leftLines == rightLines {
            return leftLines.enumerated().map { index, text in
                SideBySideDiffLine(
                    id: index,
                    leftLineNumber: index + 1,
                    leftText: text,
                    rightLineNumber: index + 1,
                    rightText: text,
                    type: .unchanged
                )
            }
        }

        // Limit LCS table size for performance
        let maxLines = 1500
        let truncatedLeft = Array(leftLines.prefix(maxLines))
        let truncatedRight = Array(rightLines.prefix(maxLines))

        let tN = truncatedLeft.count
        let tM = truncatedRight.count

        var dp = Array(repeating: Array(repeating: 0, count: tM + 1), count: tN + 1)

        for i in 1...tN {
            for j in 1...tM {
                if truncatedLeft[i - 1] == truncatedRight[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var rows: [SideBySideDiffLine] = []
        var i = tN
        var j = tM
        var rowId = 0

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && truncatedLeft[i - 1] == truncatedRight[j - 1] {
                rows.append(SideBySideDiffLine(
                    id: rowId,
                    leftLineNumber: i,
                    leftText: truncatedLeft[i - 1],
                    rightLineNumber: j,
                    rightText: truncatedRight[j - 1],
                    type: .unchanged
                ))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                rows.append(SideBySideDiffLine(
                    id: rowId,
                    leftLineNumber: nil,
                    leftText: nil,
                    rightLineNumber: j,
                    rightText: truncatedRight[j - 1],
                    type: .added
                ))
                j -= 1
            } else if i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j]) {
                rows.append(SideBySideDiffLine(
                    id: rowId,
                    leftLineNumber: i,
                    leftText: truncatedLeft[i - 1],
                    rightLineNumber: nil,
                    rightText: nil,
                    type: .deleted
                ))
                i -= 1
            }
            rowId += 1
        }

        rows.reverse()

        // Re-assign consecutive IDs 0..<count
        return rows.enumerated().map { index, row in
            SideBySideDiffLine(
                id: index,
                leftLineNumber: row.leftLineNumber,
                leftText: row.leftText,
                rightLineNumber: row.rightLineNumber,
                rightText: row.rightText,
                type: row.type
            )
        }
    }
}
