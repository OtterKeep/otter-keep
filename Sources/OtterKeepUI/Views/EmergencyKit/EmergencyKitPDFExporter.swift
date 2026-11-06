import SwiftUI
import AppKit
import UniformTypeIdentifiers
import OtterKeepDomain
import OtterKeepCore

/// Service rendering the `EmergencyKitDocumentView` into a printable A4 PDF file and presenting the native macOS save dialog.
@MainActor
public enum EmergencyKitPDFExporter {

    /// Renders the Emergency Kit document to PDF binary data.
    /// - Parameter metadata: Profile emergency metadata.
    /// - Returns: PDF Data if rendering succeeded, nil otherwise.
    public static func renderPDFData(metadata: EmergencyKitMetadata) -> Data? {
        let docView = EmergencyKitDocumentView(metadata: metadata)
        let renderer = ImageRenderer(content: docView)
        renderer.proposedSize = ProposedViewSize(width: 595, height: 842)

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData) else { return nil }

        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        renderer.render { size, renderInContext in
            pdfContext.beginPage(mediaBox: &mediaBox)
            renderInContext(pdfContext)
            pdfContext.endPage()
        }
        pdfContext.closePDF()

        return mutableData as Data
    }

    /// Prompts the user with an `NSSavePanel` and writes the generated Emergency Kit PDF to disk.
    /// - Parameters:
    ///   - metadata: Profile emergency metadata.
    ///   - parentWindow: Host window for modal attachment.
    ///   - completion: Callback invoked with the chosen file URL or nil if cancelled.
    public static func exportPDF(
        metadata: EmergencyKitMetadata,
        parentWindow: NSWindow? = nil,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        guard let pdfData = renderPDFData(metadata: metadata) else {
            completion(nil)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        panel.title = L10n.t(.emergencyKitTitle)
        panel.prompt = L10n.t(.save)

        let sanitizedName = metadata.profileName.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "OtterKeep-Emergency-Kit-\(sanitizedName).pdf"

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let targetURL = panel.url else {
                completion(nil)
                return
            }

            do {
                try pdfData.write(to: targetURL, options: .atomic)
                LogManager.shared.log("Emergency Recovery Kit PDF exported successfully to: \(targetURL.path)", level: .info, category: "Security")
                completion(targetURL)
            } catch {
                LogManager.shared.log("Failed to write Emergency Kit PDF: \(error.localizedDescription)", level: .error, category: "Security")
                completion(nil)
            }
        }

        if let win = parentWindow {
            panel.beginSheetModal(for: win, completionHandler: handler)
        } else {
            let response = panel.runModal()
            handler(response)
        }
    }
}
