import Foundation
import WebKit

// Shared by the native research window and offscreen WebKit checks. All
// diagnostics remain host-side; no native message handlers are registered.
@MainActor final class BundledEditorController: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private(set) var loaded = false
    private(set) var blockedNavigations = 0
    private(set) var nativeRequestRejections = 0
    private(set) var blockedWindows = 0
    private(set) var suppressedDialogs = 0

    private let pageURL: URL
    private let policy: BundledNavigationPolicy
    private var onStatus: ((String) -> Void)?
    private var stopped = false

    init(pageURL: URL, onStatus: @escaping (String) -> Void = { _ in }) {
        self.pageURL = pageURL
        self.policy = BundledNavigationPolicy(pageURL: pageURL)
        self.onStatus = onStatus
        let view = BundledResearchWebView(pageURL: pageURL, configuration: BundledEditorController.makeConfiguration())
        self.webView = view
        super.init()
        view.onRejectedNativeRequest = { [weak self] in
            guard let self, !self.stopped else { return }
            self.nativeRequestRejections += 1
            self.blockedNavigations += 1
            self.onStatus?("Rejected native navigation before WebKit; only the bundled research fixture is permitted.")
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.setAccessibilityLabel("Markright synthetic research editor")
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // Only the pinned bundled editor runs. Document text stays inert source.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = WKUserContentController()
        return configuration
    }

    func load() {
        guard !stopped else { return }
        loaded = false
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
    }

    // Controllers are one-shot after teardown. Late callbacks cannot change the
    // visible screen's status or revive its loaded state after this point.
    func stop() {
        stopped = true
        loaded = false
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onStatus = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard !stopped else { decisionHandler(.cancel); return }
        let allowed = policy.permits(action.request.url, mainFrame: action.targetFrame?.isMainFrame == true,
                                     download: action.shouldPerformDownload)
        if !allowed {
            blockedNavigations += 1
            onStatus?("Blocked navigation or download; only the bundled research fixture is permitted.")
        }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        guard !stopped else { decisionHandler(.cancel); return }
        let allowed = response.canShowMIMEType && policy.permits(response.response.url, mainFrame: response.isForMainFrame)
        if !allowed { blockedNavigations += 1 }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !stopped else { return }
        loaded = true
        onStatus?("Bundled fixture loaded in system WKWebView. Edits are temporary; accessibility acceptance remains open.")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !stopped else { return }
        onStatus?("Research fixture failed to load (error \((error as NSError).code)). No documents were opened.")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !stopped else { return }
        onStatus?("Research fixture could not load (error \((error as NSError).code)). No documents were opened.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !stopped else { return }
        loaded = false
        onStatus?("The research web content process stopped. Relaunching resets the synthetic fixture.")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !stopped else { return nil }
        blockedWindows += 1
        onStatus?("Blocked a new window request from the research fixture.")
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        if !stopped { suppressedDialogs += 1 }
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        if !stopped { suppressedDialogs += 1 }
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        if !stopped { suppressedDialogs += 1 }
        completionHandler(nil)
    }
}
