import SwiftUI
import AppKit
import OtterKeepCore

/// SwiftUI presentation extensions for `AppThemeMode`.
public extension AppThemeMode {
    /// Maps the application theme mode to SwiftUI's `ColorScheme?` (`nil` resolves to macOS system appearance).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// SF Symbol icon associated with the theme mode.
    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// Localized display title for the theme picker.
    var localizedTitle: String {
        switch self {
        case .system: return L10n.t(.themeAuto)
        case .light: return L10n.t(.themeLight)
        case .dark: return L10n.t(.themeDark)
        }
    }
}

/// Color palette, styling tokens, and macOS design system constants for OtterKeep.
/// Supports seamless automatic appearance switching between light and harmonized dark palettes.
public enum OtterTheme {
    // MARK: - Dynamic Color Factory Helper
    public static func dynamicColor(
        light: (red: Double, green: Double, blue: Double, alpha: Double),
        dark: (red: Double, green: Double, blue: Double, alpha: Double)
    ) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
                return NSColor(
                    red: CGFloat(dark.red),
                    green: CGFloat(dark.green),
                    blue: CGFloat(dark.blue),
                    alpha: CGFloat(dark.alpha)
                )
            } else {
                return NSColor(
                    red: CGFloat(light.red),
                    green: CGFloat(light.green),
                    blue: CGFloat(light.blue),
                    alpha: CGFloat(light.alpha)
                )
            }
        }))
    }

    // MARK: - Primary Accent Tones
    /// Signature Otter Amber: warm, charming otter-brown in light mode, calibrated warm luminous amber in dark mode.
    public static let otterAmber = dynamicColor(
        light: (red: 0.85, green: 0.52, blue: 0.28, alpha: 1.0),
        dark: (red: 0.95, green: 0.58, blue: 0.32, alpha: 1.0)
    )
    public static let primaryAmber = otterAmber
    public static let otterOrange = otterAmber
    public static let primaryOrange = otterAmber

    // MARK: - Complementary Accent Tones
    /// Oceanic Teal tone: crisp sea-cyan in light mode, glowing readable cyan on dark surfaces.
    public static let oceanicTeal = dynamicColor(
        light: (red: 0.12, green: 0.68, blue: 0.75, alpha: 1.0),
        dark: (red: 0.22, green: 0.78, blue: 0.85, alpha: 1.0)
    )
    public static let cyberTeal = oceanicTeal

    /// Deep Sea Navy accent tone: slate navy in dark mode ensuring it does not blend into pitch black.
    public static let deepSeaNavy = dynamicColor(
        light: (red: 0.08, green: 0.12, blue: 0.22, alpha: 1.0),
        dark: (red: 0.16, green: 0.22, blue: 0.34, alpha: 1.0)
    )
    public static let deepNavy = deepSeaNavy

    /// Pebble Grey tone: subtle dividers and border accents.
    public static let pebbleGrey = dynamicColor(
        light: (red: 0.65, green: 0.68, blue: 0.72, alpha: 1.0),
        dark: (red: 0.45, green: 0.48, blue: 0.52, alpha: 1.0)
    )

    /// Accent Purple.
    public static let accentPurple = dynamicColor(
        light: (red: 0.58, green: 0.35, blue: 0.92, alpha: 1.0),
        dark: (red: 0.68, green: 0.48, blue: 0.96, alpha: 1.0)
    )

    // MARK: - Status & Telemetry
    public static let statusGreen = dynamicColor(
        light: (red: 0.18, green: 0.80, blue: 0.35, alpha: 1.0),
        dark: (red: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)
    )
    public static let statusSuccess = statusGreen

    public static let statusWarning = dynamicColor(
        light: (red: 1.00, green: 0.58, blue: 0.00, alpha: 1.0),
        dark: (red: 1.00, green: 0.65, blue: 0.22, alpha: 1.0)
    )

    public static let statusError = dynamicColor(
        light: (red: 1.00, green: 0.27, blue: 0.23, alpha: 1.0),
        dark: (red: 1.00, green: 0.42, blue: 0.42, alpha: 1.0)
    )

    public static let statusNeutral = Color.secondary

    // MARK: - Storage Breakdown Palette
    public static let storageBackups = otterAmber

    public static let storageOther = dynamicColor(
        light: (red: 0.25, green: 0.45, blue: 0.85, alpha: 1.0),
        dark: (red: 0.38, green: 0.58, blue: 0.95, alpha: 1.0)
    )

    public static let storageFree = Color.secondary.opacity(0.2)

    // MARK: - Spacing & Grid Tokens (8pt Grid System)
    public static let spacing4: CGFloat = 4
    public static let spacing6: CGFloat = 6
    public static let spacing8: CGFloat = 8
    public static let spacing12: CGFloat = 12
    public static let spacing16: CGFloat = 16
    public static let spacing20: CGFloat = 20
    public static let spacing24: CGFloat = 24
    public static let spacing32: CGFloat = 32

    // MARK: - Border & Stroke Tokens
    public static let cardBorderWidth: CGFloat = 0.5

    // MARK: - Corner Radius Tokens (Standardized macOS Golden Gate Geometry)
    public static let cardCornerRadius: CGFloat = 10
    public static let heroCornerRadius: CGFloat = 14
    public static let badgeCornerRadius: CGFloat = 5
    public static let squircleRadius: CGFloat = 10

    // MARK: - Native Materials & Colors
    public static var cardBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    public static var subtleBorder: Color {
        dynamicColor(
            light: (red: 0.0, green: 0.0, blue: 0.0, alpha: 0.07),
            dark: (red: 1.0, green: 1.0, blue: 1.0, alpha: 0.11)
        )
    }

    /// macOS Golden Gate specular top highlight color for Liquid Glass depth
    public static var specularHighlight: Color {
        dynamicColor(
            light: (red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65),
            dark: (red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16)
        )
    }

    public static var surfaceBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    public static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    public static var sectionHeaderBackground: Color {
        dynamicColor(
            light: (red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0),
            dark: (red: 0.18, green: 0.18, blue: 0.20, alpha: 1.0)
        )
    }

    // MARK: - Typography Presets
    public static let heroTitleFont = Font.system(.largeTitle, design: .rounded).bold()
    public static let sectionTitleFont = Font.system(.title3).weight(.semibold)
    public static let cardTitleFont = Font.system(.headline)
    public static let valueMonoFont = Font.system(.body, design: .monospaced).weight(.medium)
    public static let microLabelFont = Font.system(.subheadline)
    public static let captionFont = Font.system(.caption, design: .monospaced).weight(.medium)

    // MARK: - Animation Timings
    public static let standardSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    public static let snappySpring = Animation.spring(response: 0.25, dampingFraction: 0.75)
    public static let smoothEase = Animation.easeInOut(duration: 0.2)
}

// MARK: - View Modifiers for Modern macOS UI (macOS Golden Gate)

public struct OtterCardModifier: ViewModifier {
    public let padding: CGFloat
    public let cornerRadius: CGFloat

    public init(padding: CGFloat = 14, cornerRadius: CGFloat = OtterTheme.cardCornerRadius) {
        self.padding = padding
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(OtterTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: OtterTheme.specularHighlight, location: 0.0),
                                .init(color: OtterTheme.subtleBorder, location: 0.25),
                                .init(color: OtterTheme.subtleBorder, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: Color.black.opacity(0.025), radius: 3, x: 0, y: 1)
    }
}

public struct OtterHeroCardModifier: ViewModifier {
    public let padding: CGFloat

    public init(padding: CGFloat = 18) {
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: OtterTheme.heroCornerRadius, style: .continuous)
                    .fill(OtterTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OtterTheme.heroCornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: OtterTheme.specularHighlight, location: 0.0),
                                .init(color: OtterTheme.subtleBorder, location: 0.2),
                                .init(color: OtterTheme.subtleBorder, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

public extension View {
    /// Applies the refined macOS Golden Gate card styling with specular highlight.
    func otterCard(padding: CGFloat = 14, cornerRadius: CGFloat = OtterTheme.cardCornerRadius) -> some View {
        modifier(OtterCardModifier(padding: padding, cornerRadius: cornerRadius))
    }

    /// Applies the prominent macOS Golden Gate hero card styling with subtle depth.
    func otterHeroCard(padding: CGFloat = 18) -> some View {
        modifier(OtterHeroCardModifier(padding: padding))
    }
}
