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
        if let svg = try? String(contentsOf: fileURL) {
            let html = """
            <!doctype html>
            <html>
              <head>
                <meta charset="utf-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1" />
                <style>
                  html, body { margin: 0; width: 100%; height: 100%; background: transparent; }
                  .wrap { width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; }
                  svg { width: 100% !important; height: 100% !important; }
                </style>
              </head>
              <body>
                <div class="wrap">
                  \(svg)
                </div>
              </body>
            </html>
            """
            nsView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
        } else {
            nsView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {}
}
