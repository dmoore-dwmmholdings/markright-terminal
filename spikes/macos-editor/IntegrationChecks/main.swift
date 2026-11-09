import AppKit
import Foundation
import Network
import WebKit

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// Test-only HTTP trap. It binds only loopback, returns inert text, and retains
// counts rather than request contents. No window or production listener exists.
private final class LoopbackTrap: @unchecked Sendable {
    private let lock = NSLock()
    private let listener: NWListener
    private var readyPort: UInt16?
    private var failure: String?
    private var dataReceives = 0
    private var connections = 0

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.lock.lock()
            switch state {
            case .ready: self.readyPort = self.listener.port?.rawValue
            case .failed(let error): self.failure = String(describing: error)
            default: break
            }
            self.lock.unlock()
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.lock.lock(); self.connections += 1; self.lock.unlock()
            connection.start(queue: .global(qos: .utility))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, _, _ in
                if let self, data?.isEmpty == false {
                    self.lock.lock(); self.dataReceives += 1; self.lock.unlock()
                }
                let response = "HTTP/1.1 200 OK\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\nAccess-Control-Allow-Private-Network: true\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: DispatchQueue(label: "markright.integration.loopback"))
    }

    var port: UInt16? { lock.lock(); defer { lock.unlock() }; return readyPort }
    var error: String? { lock.lock(); defer { lock.unlock() }; return failure }
    var counts: [Int] { lock.lock(); defer { lock.unlock() }; return [connections, dataReceives] }
    func stop() { listener.cancel() }
}

// Diagnostic comparator only: the old raw WKWebView entrypoint plus the same
// pure navigation allowlist. Never used by the actual research app.
@MainActor private final class RawNavigationControl: NSObject, WKNavigationDelegate {
    let view: WKWebView
    private let page: URL
    private let policy: BundledNavigationPolicy
    private(set) var loaded = false
    private(set) var blocked = 0

    init(page: URL) {
        self.page = page
        self.policy = BundledNavigationPolicy(pageURL: page)
        self.view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 760),
                              configuration: BundledEditorController.makeConfiguration())
        super.init()
        view.navigationDelegate = self
    }
    func load() { view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent()) }
    func stop() { view.stopLoading(); view.navigationDelegate = nil }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let allowed = policy.permits(action.request.url, mainFrame: action.targetFrame?.isMainFrame == true,
                                     download: action.shouldPerformDownload)
        if !allowed { blocked += 1 }
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
}

@MainActor private func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw CheckFailure(message) }
}

@MainActor private func waitUntil(_ message: String, timeout: TimeInterval = 12,
                                 _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else { throw CheckFailure("Timed out: " + message) }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

@MainActor private func javascript(_ view: WKWebView, _ body: String,
                                  _ arguments: [String: Any] = [:]) async throws -> String {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
        view.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
            switch result {
            case .success(let value):
                if let value = value as? String { continuation.resume(returning: value) }
                else { continuation.resume(throwing: CheckFailure("Expected a string result from authored probe")) }
            case .failure(let error): continuation.resume(throwing: error)
            }
        }
    }
}

@MainActor private func loadedController(_ page: URL) async throws -> BundledEditorController {
    let controller = BundledEditorController(pageURL: page)
    controller.webView.frame = NSRect(x: 0, y: 0, width: 1024, height: 760)
    controller.load()
    do {
        try await waitUntil("bundled page navigation") { controller.loaded }
        let ready = try await javascript(controller.webView, "return typeof window.spike === 'object' ? 'ready' : 'missing';")
        try require(ready == "ready", "Bundled editor did not initialize")
        return controller
    } catch { controller.stop(); throw error }
}

@MainActor private func runChecks() async throws {
    guard CommandLine.arguments.count == 3 else { throw CheckFailure("Pass production and test-control fixture paths") }
    let page = URL(fileURLWithPath: CommandLine.arguments[1]), controlPage = URL(fileURLWithPath: CommandLine.arguments[2])
    try require(FileManager.default.fileExists(atPath: page.path), "Prepared production fixture missing")
    try require(FileManager.default.fileExists(atPath: controlPage.path), "Prepared test control missing")
    try require(NSApplication.shared.windows.isEmpty, "Offscreen checks must not create application windows")
    let trap = try LoopbackTrap()
    defer { trap.stop() }
    try await waitUntil("loopback trap startup") { trap.port != nil || trap.error != nil }
    if let error = trap.error { throw CheckFailure("Loopback trap failed: " + error) }
    guard let port = trap.port else { throw CheckFailure("Loopback port missing") }
    let target = "http://127.0.0.1:\(port)/synthetic-probe"

    // Positive control differs only by allowing loopback connections in its CSP.
    // It is generated under build/, never bundled into the user-facing app.
    let control = try await loadedController(controlPage)
    defer { control.stop() }
    let connected = try await javascript(control.webView, "return await (await fetch(url)).text();", ["url": target])
    try require(connected == "ok" && trap.counts[1] >= 1, "WebKit loopback positive control failed")
    control.stop()
    let baseline = trap.counts
    print("PASS loopback WebKit positive control")

    let controller = try await loadedController(page)
    defer { controller.stop() }
    let view = controller.webView
    try require(!view.configuration.websiteDataStore.isPersistent, "Research store must be nonpersistent")
    let initial = try await javascript(view, "return window.spike.source();")
    try require(initial.hasPrefix("# Markright Terminal"), "Unexpected bundled source")
    print("PASS shared controller, bundled editor and nonpersistent store")

    let source = "\u{FEFF}first\r\nreplace\rafter\n", insert = "A\rB\n😀"
    let pasted = try await javascript(view, """
        window.spike.setSource(source);
        const from = source.indexOf('replace');
        window.spike.select(from, from + 'replace'.length);
        const data = new DataTransfer(); data.setData('text/plain', insert);
        document.querySelector('.cm-content').dispatchEvent(new ClipboardEvent('paste', {clipboardData:data, bubbles:true, cancelable:true}));
        return window.spike.source();
        """, ["source": source, "insert": insert])
    try require(pasted == "\u{FEFF}first\r\nA\rB\n😀\rafter\n", "System WebKit changed delivered source separators")
    print("PASS programmatic delivered-string paste and mixed source endings")

    let inert = "<img src='\(target)' onerror='window.injected=1'>\n\n<script>window.injected=1</script>"
    let literal = try await javascript(view, """
        window.spike.setSource(source);
        return JSON.stringify({source:window.spike.source(), injected:typeof window.injected,
            activeElements:document.querySelectorAll('.cm-content img, .cm-content script').length});
        """, ["source": inert])
    let literalData = try JSONSerialization.jsonObject(with: Data(literal.utf8)) as? [String: Any]
    try require(literalData?["source"] as? String == inert && literalData?["injected"] as? String == "undefined" && literalData?["activeElements"] as? Int == 0,
                "HTML/script-shaped document source became active")
    print("PASS inert markup-shaped document source")

    let fetched = try await javascript(view, "try { await fetch(url); return 'connected'; } catch { return 'blocked'; }", ["url": target])
    try await Task.sleep(nanoseconds: 250_000_000)
    try require(fetched == "blocked" && trap.counts == baseline, "Production CSP allowed a loopback connection")
    let settledInert = try await javascript(view, "return window.spike.source() === source && typeof window.injected === 'undefined' && document.querySelectorAll('.cm-content img, .cm-content script').length === 0 ? 'inert' : 'active';", ["source": inert])
    try require(settledInert == "inert", "Deferred rendering activated document markup")
    print("PASS actual CSP connection denial, with zero additional trap connections")

    let nativeRejectedBefore = controller.nativeRequestRejections
    let navigation = view.load(URLRequest(url: URL(string: target)!))
    try require(navigation == nil && controller.nativeRequestRejections == nativeRejectedBefore + 1,
                "External native URLRequest reached WebKit instead of synchronous preflight rejection")
    let retained = try await javascript(view, "return window.spike.source();")
    try await Task.sleep(nanoseconds: 250_000_000)
    try require(retained == inert && trap.counts == baseline, "Guarded native URLRequest changed source or opened a connection")
    let guestBaseline = trap.counts, guestBlockedBefore = controller.blockedNavigations
    _ = try await javascript(view, "setTimeout(() => window.location.assign(url), 0); return 'scheduled';", ["url": target])
    try await waitUntil("script-initiated navigation cancellation") { controller.blockedNavigations > guestBlockedBefore }
    try await Task.sleep(nanoseconds: 250_000_000)
    let guestRetained = try await javascript(view, "return window.spike.source();")
    try require(guestRetained == inert && trap.counts[1] == baseline[1], "Script navigation replaced source or sent an HTTP request")
    print("PASS covered native URLRequest preflight: synchronous refusal, zero additional TCP/data observed; script navigation cancelled with source retained")
    print("OBSERVATION: script navigation TCP delta=\(trap.counts[0] - guestBaseline[0]); zero script TCP is not a process-isolation invariant.")

    let raw = RawNavigationControl(page: page)
    defer { raw.stop() }
    raw.load()
    try await waitUntil("raw WebKit diagnostic control") { raw.loaded }
    let rawSource = try await javascript(raw.view, "return window.spike.source();")
    let rawBaseline = trap.counts
    raw.view.load(URLRequest(url: URL(string: target)!))
    try await waitUntil("raw native navigation cancellation") { raw.blocked > 0 }
    try await Task.sleep(nanoseconds: 250_000_000)
    let rawRetained = try await javascript(raw.view, "return window.spike.source();")
    try require(rawRetained == rawSource && trap.counts[1] == rawBaseline[1],
                "Raw navigation diagnostic committed or sent an HTTP request")
    print("PASS raw navigation cancellation comparator: source retained, no HTTP/application bytes observed")
    print("LIMITATION: raw native TCP delta=\(trap.counts[0] - rawBaseline[0]); the request-only guard is NOT OS/process network isolation or coverage of other loaders/download APIs.")
    raw.stop()
    let postNavigation = trap.counts

    let popup = try await javascript(view, "return window.open(url) === null ? 'blocked' : 'opened';", ["url": target])
    let frame = try await javascript(view, """
        const frame = document.createElement('iframe'); frame.id='synthetic-blocked-frame'; frame.src=url;
        document.body.appendChild(frame); return 'requested';
        """, ["url": target])
    try await Task.sleep(nanoseconds: 250_000_000)
    print("Popup/frame diagnostic: popup=\(popup), frame=\(frame), before=\(postNavigation), after=\(trap.counts), blockedWindows=\(controller.blockedWindows), ownWindows=\(NSApplication.shared.windows.map { String(describing: type(of: $0)) + ":visible=" + String($0.isVisible) })")
    try require(popup == "blocked" && frame == "requested" && trap.counts == postNavigation && NSApplication.shared.windows.allSatisfy { !$0.isVisible },
                "Popup/frame probe created a visible window or network connection")
    print("PASS scripted popup/subframe denial without visible native windows")

    let dialogBaseline = controller.suppressedDialogs
    let dialogs = try await javascript(view, "alert('synthetic'); return JSON.stringify([confirm('synthetic'), prompt('synthetic')]);")
    try require(dialogs == "[false,null]" && controller.suppressedDialogs == dialogBaseline + 3,
                "Native dialog delegates did not suppress the authored probes")
    try require(!NSApplication.shared.isActive && NSApplication.shared.windows.allSatisfy { !$0.isVisible },
                "Offscreen checks activated the app or showed a native window")
    controller.stop()
    controller.webView(view, didFinish: nil)
    try require(!controller.loaded && view.navigationDelegate != nil && view.navigationDelegate !== controller && view.uiDelegate != nil,
                "Stopped controller accepted a stale navigation callback")
    print("PASS native dialog suppression and one-shot teardown")

    var teardownStatusCalls = 0
    var retiring: BundledEditorController? = BundledEditorController(pageURL: page, onStatus: { _ in teardownStatusCalls += 1 })
    weak let releasedController = retiring
    let retiredView = retiring!.webView
    retiredView.frame = NSRect(x: 0, y: 0, width: 1024, height: 760)
    retiring!.load()
    try await waitUntil("teardown fixture") { retiring?.loaded == true }
    let retiringSource = try await javascript(retiredView, "return window.spike.source();")
    _ = try await javascript(retiredView, """
        window.teardownArmed = false; window.teardownAttempted = false;
        function attempt() {
            if (!window.teardownArmed) { setTimeout(attempt, 20); return; }
            window.teardownAttempted = true; window.location.assign(url);
        }
        setTimeout(attempt, 20); return 'scheduled';
        """, ["url": target])
    let teardownBaseline = trap.counts, statusBaseline = teardownStatusCalls
    retiring!.stop()
    retiring!.stop() // Idempotence must not drop the view-owned refusal delegates.
    retiring!.load() // A stopped controller cannot restart itself.
    retiring = nil
    try require(releasedController == nil, "Teardown view retained its controller")
    try require(retiredView.load(URLRequest(url: page)) == nil && retiredView.load(URLRequest(url: URL(string: target)!)) == nil,
                "Stopped view accepted a covered native request")
    let retiredDialogs = try await javascript(retiredView, "alert('retired'); window.teardownArmed = true; return JSON.stringify([confirm('retired'), prompt('retired')]);")
    // Wait in the page's own timer queue so the earlier authored attempt ran.
    let retiredState = try await javascript(retiredView, "await new Promise(resolve => setTimeout(resolve, 250)); return window.teardownAttempted ? window.location.href : 'not-attempted';")
    let retiredSource = try await javascript(retiredView, "return window.spike.source();")
    try require(retiredDialogs == "[false,null]" && retiredState == page.absoluteString && retiredSource == retiringSource,
                "Retained stopped page navigated or failed to suppress dialogs")
    try require(trap.counts[1] == teardownBaseline[1] && teardownStatusCalls == statusBaseline,
                "Stopped page sent request bytes or emitted a stale status callback")
    try require(retiredView.navigationDelegate != nil && retiredView.uiDelegate != nil && !NSApplication.shared.isActive && NSApplication.shared.windows.allSatisfy { !$0.isVisible },
                "Teardown lost refusal delegates or showed native UI")
    print("PASS retained-view teardown after controller release: delayed script navigation refused, dialogs suppressed, covered native loads rejected, no stale status or additional application bytes")
    print("OBSERVATION: teardown TCP delta=\(trap.counts[0] - teardownBaseline[0]); JavaScript remains alive and process/network isolation is not established.")
    print("Passed 10 scoped offscreen system-WKWebView integration checks. No OS keyboard/clipboard, VoiceOver, latency or full network/security acceptance claimed.")
}

@main private enum IntegrationChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do { try await runChecks(); exit(0) }
            catch {
                FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
                exit(1)
            }
        }
        app.run()
    }
}
