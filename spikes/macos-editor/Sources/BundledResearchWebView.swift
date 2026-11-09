import Foundation
import WebKit

// A narrow host-side preflight for the native load(URLRequest) entry point.
// Delegate cancellation happens later and may permit speculative connections.
// This does not cover other native loading APIs or establish network isolation.
@MainActor final class BundledResearchWebView: WKWebView {
    private let nativeRequestPolicy: BundledNavigationPolicy
    private let teardownDelegate = StoppedResearchDelegate()
    private var stopped = false
    var onRejectedNativeRequest: (() -> Void)?

    init(pageURL: URL, configuration: WKWebViewConfiguration) {
        nativeRequestPolicy = BundledNavigationPolicy(pageURL: pageURL)
        super.init(frame: .zero, configuration: configuration)
    }

    @available(*, unavailable, message: "Use the programmatic bundled-page initializer")
    required init?(coder: NSCoder) { return nil }

    override func load(_ request: URLRequest) -> WKNavigation? {
        guard !stopped else { return nil }
        guard nativeRequestPolicy.permits(request.url, mainFrame: true) else {
            onRejectedNativeRequest?()
            return nil
        }
        return super.load(request)
    }

    // WKWebView delegates are weak. Keep the refusal delegate on the view itself
    // so delayed page callbacks stay guarded even after its controller dies.
    // This does not terminate JavaScript or cover every native loading API.
    func stopForTeardown() {
        stopped = true
        onRejectedNativeRequest = nil
        navigationDelegate = teardownDelegate
        uiDelegate = teardownDelegate
        stopLoading()
    }
}

@MainActor private final class StoppedResearchDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        completionHandler(nil)
    }
}
