import Foundation

// Only the bundled top-level fixture (and its fragment) can navigate. Resource
// requests are separately restricted by the fixture's CSP and read-access root.
struct BundledNavigationPolicy {
    let pageURL: URL

    func permits(_ url: URL?, mainFrame: Bool, download: Bool = false) -> Bool {
        guard mainFrame, !download, let url, url.isFileURL,
              url.host == nil || url.host == "", url.query == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        components.fragment = nil
        return components.url?.standardizedFileURL == pageURL.standardizedFileURL
    }
}
