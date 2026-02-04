import SwiftUI
import WebKit

struct SVGWebView: NSViewRepresentable {
    var fileURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let v = WKWebView()
        v.setValue(false, forKey: "drawsBackground")
        v.navigationDelegate = context.coordinator
        return v
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let fileURL else {
            nsView.loadHTMLString("", baseURL: nil)
            return
        }
        nsView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {}
}

