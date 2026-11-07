import SwiftUI
import AppKit

/// Mascot logo presentation view for OtterKeep featuring modern macOS squircle styling.
public struct OtterKeepLogoView: View {
    public let size: CGFloat
    public let withGlow: Bool
    public let withBorder: Bool

    public init(size: CGFloat = 44, withGlow: Bool = true, withBorder: Bool = true) {
        self.size = size
        self.withGlow = withGlow
        self.withBorder = withBorder
    }

    public var body: some View {
        ZStack {
            if withGlow {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(OtterTheme.oceanicTeal.opacity(0.25))
                    .blur(radius: size * 0.15)
                    .frame(width: size * 1.05, height: size * 1.05)
            }

            if let nsImage = resolvedLogoImage() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        OtterTheme.oceanicTeal.opacity(withBorder ? 0.6 : 0),
                                        OtterTheme.otterAmber.opacity(withBorder ? 0.4 : 0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: withBorder ? max(1, size * 0.03) : 0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: size * 0.08, x: 0, y: size * 0.04)
            } else {
                fallbackMascotView
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackMascotView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [OtterTheme.otterAmber, OtterTheme.deepSeaNavy],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: size * 0.02) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(OtterTheme.oceanicTeal)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedLogoImage() -> NSImage? {
        Self.resolveLogoImage()
    }

    /// Resolves the raw OtterKeep mascot logo image from bundle resources or local fallback paths.
    public static func resolveLogoImage() -> NSImage? {
        resolveResourceImage(named: "OtterKeepLogo", ext: "jpg")
    }

    /// Resolves the OttieSuccess transparent illustration from bundle resources or local fallback paths.
    public static func resolveSuccessImage() -> NSImage? {
        resolveResourceImage(named: "OttieSuccess", ext: "png")
    }

    /// Resolves the OttieFailure transparent illustration from bundle resources or local fallback paths.
    public static func resolveFailureImage() -> NSImage? {
        resolveResourceImage(named: "OttieFailure", ext: "png")
    }

    /// Resolves the OttieSanctuarySafe transparent mascot illustration.
    public static func resolveSanctuarySafeImage() -> NSImage? {
        resolveResourceImage(named: "OttieSanctuarySafe", ext: "png") ?? resolveSuccessImage()
    }

    /// Resolves the OttieSanctuaryWarning transparent mascot illustration.
    public static func resolveSanctuaryWarningImage() -> NSImage? {
        resolveResourceImage(named: "OttieSanctuaryWarning", ext: "png") ?? resolveLogoImage()
    }

    /// Resolves the OttieSanctuaryDanger transparent mascot illustration.
    public static func resolveSanctuaryDangerImage() -> NSImage? {
        resolveResourceImage(named: "OttieSanctuaryDanger", ext: "png") ?? resolveFailureImage()
    }

    /// Universal resource resolver supporting SPM module bundle, main bundle, nested bundles and development filesystem.
    public static func resolveResourceImage(named name: String, ext: String) -> NSImage? {
        // 0. Primary: SPM module bundle
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: ext),
           let img = NSImage(contentsOf: url) {
            return img
        }
        #endif

        // 1. Search in main application bundle resources
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let img = NSImage(contentsOf: url) {
            return img
        }

        // 2. Search in SPM resource bundle candidates safely without triggering fatalError
        let bundleName = "OtterKeep_OtterKeepUI"
        var candidateURLs: [URL] = []
        if let resURL = Bundle.main.resourceURL {
            candidateURLs.append(resURL.appendingPathComponent("\(bundleName).bundle"))
        }
        candidateURLs.append(Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle"))
        candidateURLs.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName).bundle"))
        candidateURLs.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("\(bundleName).bundle"))
        if let envPath = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            candidateURLs.append(URL(fileURLWithPath: envPath).appendingPathComponent("\(bundleName).bundle"))
            candidateURLs.append(URL(fileURLWithPath: envPath))
        }

        for bundleURL in candidateURLs {
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: name, withExtension: ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }

        // 3. Search in loaded framework/module bundles
        for bundle in Bundle.allBundles where bundle.bundlePath.contains("OtterKeep") {
            if let url = bundle.url(forResource: name, withExtension: ext),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }

        // 4. Source tree filesystem fallbacks (compile-time source path and working directory)
        let sourceRelativeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Components
            .deletingLastPathComponent() // OtterKeepUI
            .appendingPathComponent("Resources/\(name).\(ext)")
        if FileManager.default.fileExists(atPath: sourceRelativeURL.path),
           let img = NSImage(contentsOf: sourceRelativeURL) {
            return img
        }

        let devRelativePath = "Sources/OtterKeepUI/Resources/\(name).\(ext)"
        if FileManager.default.fileExists(atPath: devRelativePath),
           let img = NSImage(contentsOfFile: devRelativePath) {
            return img
        }

        return nil
    }

    /// Creates a 512x512 rounded macOS squircle dock icon using the OtterKeep mascot logo.
    @MainActor
    public static func createApplicationDockIcon() -> NSImage? {
        guard let baseImage = resolveLogoImage() else { return nil }
        let iconSize = NSSize(width: 512, height: 512)
        let outputImage = NSImage(size: iconSize)
        outputImage.lockFocus()

        let rect = NSRect(origin: .zero, size: iconSize)
        let cornerRadius = iconSize.width * 0.2237 // macOS standard app icon continuous corner radius ratio
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        baseImage.draw(in: rect, from: NSRect(origin: .zero, size: baseImage.size), operation: .sourceOver, fraction: 1.0)

        outputImage.unlockFocus()
        return outputImage
    }
}

/// Presentation view for Ottie mascot illustrations in operation feedback modals.
public struct OttieFeedbackMascotView: View {
    public enum MascotState {
        case success
        case failure
    }

    public let state: MascotState
    public let size: CGFloat

    public init(state: MascotState, size: CGFloat = 160) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
            } else {
                fallbackView
            }
        }
    }

    private var resolvedImage: NSImage? {
        switch state {
        case .success:
            return OtterKeepLogoView.resolveSuccessImage()
        case .failure:
            return OtterKeepLogoView.resolveFailureImage()
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(state == .success ? OtterTheme.statusGreen.opacity(0.15) : OtterTheme.statusError.opacity(0.15))
                .frame(width: size * 0.85, height: size * 0.85)

            Image(systemName: state == .success ? "hand.thumbsup.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(state == .success ? OtterTheme.statusGreen : OtterTheme.statusError)
        }
        .frame(width: size, height: size)
    }
}

/// Dynamic emotional state for Ottie in the Sanctuary Hero Card based on backup and storage health.
public enum SanctuaryMascotMood: Sendable, Equatable {
    case safe
    case warning
    case danger
}

/// Presentation view for Ottie mascot illustrations in the Overview Sanctuary Hero Card.
public struct OttieSanctuaryMascotView: View {
    public let mood: SanctuaryMascotMood
    public let size: CGFloat

    public init(mood: SanctuaryMascotMood, size: CGFloat = 110) {
        self.mood = mood
        self.size = size
    }

    public var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .shadow(color: glowColor.opacity(0.20), radius: 8, x: 0, y: 4)
            } else {
                fallbackView
            }
        }
    }

    private var resolvedImage: NSImage? {
        switch mood {
        case .safe:
            return OtterKeepLogoView.resolveSanctuarySafeImage()
        case .warning:
            return OtterKeepLogoView.resolveSanctuaryWarningImage()
        case .danger:
            return OtterKeepLogoView.resolveSanctuaryDangerImage()
        }
    }

    private var glowColor: Color {
        switch mood {
        case .safe: return OtterTheme.oceanicTeal
        case .warning: return OtterTheme.otterAmber
        case .danger: return OtterTheme.statusError
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(glowColor.opacity(0.12))
                .frame(width: size * 0.85, height: size * 0.85)

            Image(systemName: iconName)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(glowColor)
        }
        .frame(width: size, height: size)
    }

    private var iconName: String {
        switch mood {
        case .safe: return "shield.lefthalf.filled.badge.checkmark"
        case .warning: return "exclamationmark.shield"
        case .danger: return "shield.fill"
        }
    }
}

