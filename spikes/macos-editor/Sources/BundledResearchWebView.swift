import Foundation
import WebKit

// A narrow host-side preflight for the native load(URLRequest) entry point.
// Delegate cancellation happens later and may permit speculative connections.
// This does not cover other native loading APIs or establish network isolation.
@MainActor final class BundledResearchWebView: WKWebView {
    private let nativeRequestPolicy: BundledNavigationPolicy
    var onRejectedNativeRequest: (() -> Void)?

    init(pageURL: URL, configuration: WKWebViewConfiguration) {
        nativeRequestPolicy = BundledNavigationPolicy(pageURL: pageURL)
        super.init(frame: .zero, configuration: configuration)
    }

    @available(*, unavailable, message: "Use the programmatic bundled-page initializer")
    required init?(coder: NSCoder) { return nil }

    override func load(_ request: URLRequest) -> WKNavigation? {
        guard nativeRequestPolicy.permits(request.url, mainFrame: true) else {
            onRejectedNativeRequest?()
            return nil
        }
        return super.load(request)
    }
}
