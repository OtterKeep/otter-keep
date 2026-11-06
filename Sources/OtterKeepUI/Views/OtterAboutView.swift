//
//  OtterAboutView.swift
//  OtterKeepUI
//
//  Created for OtterKeep 1.1.0 (Build 1100).
//  Copyright © 2026 OtterKeep. All rights reserved.
//

import SwiftUI
import AppKit
import OtterKeepCore

/// Brand-new modern macOS Sequoia About (Névjegy) view celebrating the OtterKeep lore, architecture, and craftsmanship.
public struct OtterAboutView: View {
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?

    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private func closeAction() {
        if let onClose = onClose {
            onClose()
        } else {
            dismiss()
            AboutWindowController.shared.close()
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerView
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            VStack(spacing: 14) {
                // 1. Mascot Logo with Glowing Dual Ring
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(OtterTheme.oceanicTeal.opacity(0.18))
                            .frame(width: 96, height: 96)
                            .blur(radius: 10)

                        Circle()
                            .fill(OtterTheme.otterAmber.opacity(0.14))
                            .frame(width: 86, height: 86)
                            .blur(radius: 6)

                        OtterKeepLogoView(size: 76, withGlow: true, withBorder: true)
                    }

                    VStack(spacing: 4) {
                        Text("OtterKeep")
                            .font(.title.bold()).fontDesign(.rounded)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Text(L10n.format(.aboutVersionBuildFormat, CoreEngine.version, CoreEngine.buildNumber))
                                .font(.caption.weight(.bold).monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(OtterTheme.oceanicTeal.opacity(0.15), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(OtterTheme.oceanicTeal.opacity(0.35), lineWidth: 1)
                                )
                                .foregroundStyle(OtterTheme.oceanicTeal)
                        }
                    }
                }

                // 2. Slogans
                VStack(spacing: 3) {
                    Text(L10n.t(.aboutTaglineEnglish))
                        .font(.subheadline.weight(.semibold)).fontDesign(.serif).italic()
                        .foregroundStyle(OtterTheme.otterAmber)

                    Text(L10n.t(.aboutTaglineHungarian))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 3. Brand Lore Quote Card
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OtterTheme.otterAmber)
                        .frame(width: 3)

                    Text(L10n.t(.aboutLoreStory))
                        .font(.caption)
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(OtterTheme.subtleBorder, lineWidth: 0.5)
                )

                // 4. Architecture & Feature Badges (2x2 Grid)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    architectureBadge(
                        icon: "bolt.shield.fill",
                        color: OtterTheme.oceanicTeal,
                        title: L10n.t(.aboutBadgeApfsTitle),
                        subtitle: L10n.t(.aboutBadgeApfsSubtitle)
                    )
                    architectureBadge(
                        icon: "swift",
                        color: .orange,
                        title: L10n.t(.aboutBadgeSwiftTitle),
                        subtitle: L10n.t(.aboutBadgeSwiftSubtitle)
                    )
                    architectureBadge(
                        icon: "internaldrive.fill",
                        color: OtterTheme.otterAmber,
                        title: L10n.t(.aboutBadgeLocalTitle),
                        subtitle: L10n.t(.aboutBadgeLocalSubtitle)
                    )
                    architectureBadge(
                        icon: "hand.raised.slash.fill",
                        color: OtterTheme.statusGreen,
                        title: L10n.t(.aboutBadgeTelemetryTitle),
                        subtitle: L10n.t(.aboutBadgeTelemetrySubtitle)
                    )
                }

                // 4.5. Subsystem Component Versions
                VStack(spacing: 6) {
                    HStack {
                        Text(L10n.t(.aboutSubsystemComponentsTitle))
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        componentVersionChip(name: "Storage", version: CoreEngine.storageVersion, icon: "internaldrive")
                        componentVersionChip(name: "Database", version: CoreEngine.databaseVersion, icon: "cylinder.split.1x2")
                        componentVersionChip(name: "Core", version: CoreEngine.coreVersion, icon: "cpu")
                        componentVersionChip(name: "UI", version: CoreEngine.uiVersion, icon: "macwindow")
                        componentVersionChip(name: "CLI", version: CoreEngine.cliVersion, icon: "terminal")
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(OtterTheme.subtleBorder, lineWidth: 0.5)
                )

                // 5. Interactive Resource Links

                HStack(spacing: 8) {
                    LinkButton(title: L10n.t(.aboutLinkWebsite), icon: "globe", url: "https://otterkeep.app")
                    LinkButton(
                        title: L10n.t(.aboutLinkGitHub), icon: "chevron.left.forwardslash.chevron.right",
                        url: "https://github.com/OtterKeep/otter-keep")
                    LinkButton(title: L10n.t(.aboutLinkReleases), icon: "tag.fill", url: "https://github.com/OtterKeep/otter-keep/releases")
                    LinkButton(
                        title: L10n.t(.aboutLinkLicense), icon: "doc.text.fill",
                        url: "https://github.com/OtterKeep/otter-keep/blob/main/LICENSE")
                }
                .padding(.top, 2)

                // 6. Credits & Copyright Footnote
                VStack(spacing: 2) {
                    Text(L10n.t(.aboutCraftedBy))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)

                    Text(L10n.t(.aboutCopyrightNotice))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
        }
        .frame(width: 480)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: OtterTheme.heroCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
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
        .clipShape(RoundedRectangle(cornerRadius: OtterTheme.heroCornerRadius, style: .continuous))
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(OtterTheme.oceanicTeal)
                .frame(width: 32, height: 32)
                .background(OtterTheme.oceanicTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(.aboutWindowTitle))
                    .font(.headline.bold())
                Text(L10n.format(.aboutVersionBuildFormat, CoreEngine.version, CoreEngine.buildNumber))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                closeAction()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.t(.cancel))
        }
    }

    private func architectureBadge(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(OtterTheme.subtleBorder, lineWidth: 0.5)
        )
    }

    private func componentVersionChip(name: String, version: String, icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(OtterTheme.oceanicTeal)
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text("v\(version)")
                .font(.caption2.bold().monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 5))
    }
}


private struct LinkButton: View {
    let title: String
    let icon: String
    let url: String

    var body: some View {
        Button {
            if let linkURL = URL(string: url) {
                NSWorkspace.shared.open(linkURL)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.medium))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Dedicated macOS NSWindowController presenting the About window as a clean floating modal panel without OS traffic lights.
@MainActor
public final class AboutWindowController: NSObject {
    public static let shared = AboutWindowController()
    private var window: NSWindow?

    public func show() {
        // Find parent window to center upon
        let parentWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: {
            $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain
        })

        if let window = window, window.isVisible {
            if let parent = parentWindow {
                let parentFrame = parent.frame
                let originX = parentFrame.origin.x + (parentFrame.width - window.frame.width) / 2
                let originY = parentFrame.origin.y + (parentFrame.height - window.frame.height) / 2
                window.setFrameOrigin(NSPoint(x: originX, y: originY))
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = OtterAboutView(onClose: { [weak self] in
            self?.close()
        })
        let hostingController = NSHostingController(rootView: aboutView)

        // Calculate dynamic height fitting the content exactly
        let fittingSize = hostingController.view.fittingSize
        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = fittingSize.height > 0 ? fittingSize.height : 520

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "About OtterKeep"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating

        // Hide standard OS window controls (traffic lights) so only the in-app close button is shown
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = hostingController
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.isReleasedWhenClosed = false

        if let parent = parentWindow {
            let parentFrame = parent.frame
            let originX = parentFrame.origin.x + (parentFrame.width - panelWidth) / 2
            let originY = parentFrame.origin.y + (parentFrame.height - panelHeight) / 2
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        } else {
            panel.center()
        }

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}
