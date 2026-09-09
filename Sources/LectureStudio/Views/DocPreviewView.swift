import SwiftUI
import AppKit
import PDFKit
import Quartz
import StudioCore

/// Preview for everything that is not a Marp deck.
struct DocPreviewView: View {
    @Environment(StudioStore.self) private var store
    var path: String
    var kind: FileKind

    var url: URL? { try? store.repo?.resolve(path) }

    var body: some View {
        switch kind {
        case .md, .text:
            WebViewHost(webView: store.preview.webView)
        case .pdf:
            if let url { PDFKitView(url: url) } else { missing }
        case .image:
            if let url, let img = NSImage(contentsOf: url) {
                ScrollView([.horizontal, .vertical]) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(16) }
                    .background(Color(nsColor: .windowBackgroundColor))
            } else { missing }
        case .docx, .xlsx, .pptx, .other:
            if let url { QuickLookView(url: url) } else { missing }
        case .deck:
            WebViewHost(webView: store.preview.webView)
        }
    }

    var missing: some View {
        EmptyBlock(icon: "questionmark.folder", title: "No preview for this file", description: path) {
            if let url { Button("Open in its app") { NSWorkspace.shared.open(url) } }
        }
    }
}

struct PDFKitView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(url: url)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}

/// Word, Excel, PowerPoint and anything else Quick Look can draw.
struct QuickLookView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.autostarts = true
        v.previewItem = url as QLPreviewItem
        return v
    }
    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? URL) != url { v.previewItem = url as QLPreviewItem }
    }
}
