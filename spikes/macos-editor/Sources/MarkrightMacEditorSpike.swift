import SwiftUI
import WebKit

@main struct MarkrightMacEditorSpikeApp: App {
    var body: some Scene {
        Window("Markright macOS research", id: "markright-research") {
            ResearchEditorScreen()
        }
        .defaultSize(width: 1024, height: 760)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct ResearchEditorScreen: View {
    @State private var status = "Loading the bundled synthetic fixture…"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Research host · Temporary edits")
                    .font(.headline)
                Text("Synthetic fixture only. No file saving, collections, accounts or sync. Closing the window discards edits.")
                    .font(.callout)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("research-status")
            }
            .padding()
            Divider()
            BundledEditorView(status: $status)
        }
        .frame(minWidth: 760, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("MRK-9 experiment · Not a production app")
                    .font(.caption)
            }
        }
    }
}

struct BundledEditorView: NSViewRepresentable {
    @Binding var status: String

    func makeCoordinator() -> Coordinator { Coordinator(status: $status) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // The pinned, bundled editor runs. Document text is always inert source.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // No message handlers, user scripts, native API or filesystem bridge.
        configuration.userContentController = WKUserContentController()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        view.setAccessibilityLabel("Markright synthetic research editor")
        guard let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Editor") else {
            context.coordinator.status.wrappedValue = "Bundled fixture missing. Run prepare-resources.mjs and rebuild."
            return view
        }
        context.coordinator.policy = BundledNavigationPolicy(pageURL: page)
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.status = $status
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var status: Binding<String>
        var policy: BundledNavigationPolicy?

        init(status: Binding<String>) { self.status = status }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let allowed = policy?.permits(action.request.url, mainFrame: action.targetFrame?.isMainFrame == true,
                                          download: action.shouldPerformDownload) == true
            if !allowed { status.wrappedValue = "Blocked navigation or download; only the bundled research fixture is permitted." }
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
            let allowed = response.canShowMIMEType && policy?.permits(response.response.url, mainFrame: response.isForMainFrame) == true
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            status.wrappedValue = "Bundled fixture loaded in system WKWebView. Edits are temporary; accessibility acceptance remains open."
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            status.wrappedValue = "Research fixture failed to load (error \((error as NSError).code)). No documents were opened."
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            status.wrappedValue = "Research fixture could not load (error \((error as NSError).code)). No documents were opened."
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            status.wrappedValue = "The research web content process stopped. Relaunching resets the synthetic fixture."
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            status.wrappedValue = "Blocked a new window request from the research fixture."
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) { completionHandler() }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) { completionHandler(false) }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) { completionHandler(nil) }
    }
}
