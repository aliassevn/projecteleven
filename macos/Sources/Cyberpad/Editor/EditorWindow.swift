import AppKit
import WebKit

/// De editor (shared/editor) in een eigen venster op de Mac. Laadt via 127.0.0.1 met een geheim token in de #hash,
/// zodat het token nooit in een HTTP-verzoek of logbestand belandt.
final class EditorWindow: NSObject, WKUIDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    static let shared = EditorWindow()
    private var window: NSWindow?
    private var web: WKWebView?

    func show(token: String) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "cyberpad")
        cfg.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = self
        web.navigationDelegate = self
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Cyberpad — Layout bewerken"
        w.minSize = NSSize(width: 900, height: 600)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = web
        w.center()
        window = w
        self.web = web
        web.load(URLRequest(url: URL(string: "http://127.0.0.1:\(Server.port)/editor/#mac=\(token)")!))
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // Venster dicht → alles opruimen (volgende keer vers laden).
    func windowWillClose(_ notification: Notification) {
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "cyberpad")
        web = nil
        window = nil
    }

    // Alleen de editor zelf laden; links naar buiten openen in de browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.host == "127.0.0.1", url.port == Int(Server.port), url.path.hasPrefix("/editor") {
            decisionHandler(.allow)
        } else {
            if let url = action.request.url, ["http", "https"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }

    // MARK: Dialogen voor alert/confirm en bestand kiezen (importeren)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Annuleer")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.allowedContentTypes = []
        p.begin { completionHandler($0 == .OK ? p.urls : nil) }
    }

    // MARK: Exporteren: de editor stuurt de inhoud, de Mac vraagt waar hij moet komen.

    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], body["type"] as? String == "export",
              let text = body["data"] as? String else { return }
        let p = NSSavePanel()
        p.nameFieldStringValue = (body["name"] as? String) ?? "layout.cyberpad"
        p.canCreateDirectories = true
        guard let window else { return }
        p.beginSheetModal(for: window) { r in
            guard r == .OK, let url = p.url else { return }
            do { try Data(text.utf8).write(to: url, options: .atomic) } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}
