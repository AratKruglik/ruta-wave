import AppKit
import PlayerEngine
import SwiftUI
import WebKit

struct PlayerHost: NSViewRepresentable {
    let engine: PlayerEngine

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        container.alphaValue = 0
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let webView = engine.webView
        if container.subviews.first === webView { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let webView else { return }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
