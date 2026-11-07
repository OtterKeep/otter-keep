//
//  InfoTooltipView.swift
//  OtterKeepUI
//
//  Compact, unobtrusive contextual information icon with native macOS hover tooltip.
//

import SwiftUI

/// Compact contextual info icon that reveals detailed explanatory guidance on mouse hover or accessibility inspection.
public struct InfoTooltipView: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.8))
            .help(text)
            .accessibilityLabel(text)
    }
}
