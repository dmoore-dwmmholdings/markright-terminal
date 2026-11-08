# MRK-9 desktop editor interaction spike

Local CodeMirror 6/Lezer Markdown candidate. This is not a Tauri application, full Markdown renderer or selected production framework. No document scripts execute; source is shown as text, never injected as HTML. It does not implement Markright file resolution/includes or use the native parser yet.

Build: `node_modules/.bin/esbuild spikes/desktop/editor.mjs --bundle --outfile=spikes/desktop/build/bundle.js`.
Test: `node_modules/.bin/playwright test -c spikes/desktop/playwright.config.mjs`.

The test server binds only 127.0.0.1:18790, serves two known assets, has no filesystem/browser API endpoint and stops with Playwright. All browser runs are headless; nothing is published. Browser binaries come from official Playwright downloads matching the pinned package; use `playwright install chromium --only-shell` and `playwright install webkit` when absent.

Fifteen browser checks pass across Chromium and WebKit on this Mac. The one CDP composition probe is skipped on WebKit, explicitly not claimed as platform IME evidence. Tests cover inactive formatting/source fidelity, literal punctuation, whole code/table source units, inert HTML/script-shaped text, cross-block replacement with exact undo, a 1 MB edit smoke and Chromium composition text commit.

The initial preview decorates headings/emphasis/strikethrough and hides selected syntax markers outside the active line/block without rewriting source. Links/images/tables and all Markright extensions do not have complete renderers. Active preview follows the primary selection; multiple-cursor behavior remains a gate. Background parse-tree changes trigger decoration refresh. Composition maps existing decorations instead of rebuilding them until commit, but real OS keyboard IME/accessibility testing remains required.

These browser durations are test-runtime smoke measurements, NOT p95 input-to-paint evidence. Headless engines on macOS do not prove Windows/Linux shell behavior, actual WKWebView/WebView2 integration, filesystem access, packaging, screen-reader use, native startup or framework acceptance. The editor and native Swift prototype use different temporary parse/grouping approaches; a shared semantic/source-map contract still needs integration.

Independent source review identified exact-end caret ownership as a gap. The added fence/table-at-EOF regression initially failed in both engines; two-sided syntax resolution now reveals the full block while leaving a following empty line separate. All fifteen browser checks pass, with the one explicit WebKit composition skip retained.
