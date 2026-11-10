# macOS native collections and system-WKWebView research

MRK-39 adds a separate native SwiftUI/AppKit collection/source/recovery workspace through **Open collections**. It shares the iOS storage/session model and supports app-owned create/open/autosave, cross-collection Save As, inert recovery preview and separate-copy restore with close/quit guards. It does not grant WebKit access to stored documents. See [the workflow, verification and limits](../../docs/native-macos-collections-validation.md). External selected folders, full rendering and production desktop architecture remain open. The existing visible Debug app has not been rebuilt or restarted; verification uses the separate Verification product.

Standalone SwiftUI window around the existing synthetic desktop CodeMirror fixture. This is a macOS shell experiment, not a selected production architecture, Tauri integration, complete Markdown application or native iOS implementation. MRK-9 VoiceOver observation and MRK-12 integrated review remain open.

The separate native workspace can be checked without opening the visible research app:

```sh
python3 spikes/macos-editor/run-native-collection-checks.py
swift test --package-path spikes --scratch-path spikes/macos-editor/build/SharedNativePackage -Xswiftc -warnings-as-errors
```

Both commands run from the repository root. The AppKit probe uses synthetic temporary collections and a prohibited activation policy; it never calls the real app-owned workspace manager. Run serially with other builds and retain at least 20 GiB free.

MRK-39 passes **58 shared storage/session tests +5 focused AppKit groups**, with Swift warnings as errors. The separate unsigned arm64 Verification app also builds successfully. Programmatic source/undo/marked-text, late edit/receipt, recovery reuse and close-race evidence and failed harness diagnostics are documented in the linked validation record. Real keyboard/IME, VoiceOver, external providers, network isolation and release gates remain open.

The bundled fixture now includes read-only Reading mode. All 12 scoped offscreen groups pass in `build/reading-mode-native-20261110.log`, including immediate preview refresh, delivered-paste refusal and exact source/reverse selection retention. Separate browser checks pass 33/skip 1; all 87 Node groups pass. `build/reading-mode-host-20261110.log` records the unsigned warnings-as-errors build into the unused separate Verification product. The visible Debug app/tabs were preserved. The first attempt's below 20 GiB resource stop is retained; after cleanup about 47 GiB allowed sequential verification. These are scoped UI-policy checks, not OS keyboard/clipboard/VoiceOver or network-isolation acceptance. See desktop README/ADR0002 for limits.

## Native saved-source search

MRK-40 adds a collapsed **Search saved documents** panel in the selected collection. It searches saved source only, shows literal bounded previews, reports partial scans/errors and opens results through the existing guarded workflow. Query input uses its own plain native text view, with no autofocus, persisted query history or programmatic clipboard access. Active source, caret, focus and undo survive search and save-error header updates in authored offscreen checks.

**90 shared Mac tests and 8 AppKit groups pass**, including retired-query callback and real panel teardown regressions. The final unsigned Verification app builds with Swift warnings as errors. The existing visible Debug product and bundled WebKit fixture remain unchanged. See [the bounded search contract and evidence](../../docs/native-collection-search-validation.md); this is not indexed search, complete authoring, OS input/VoiceOver, external-provider or release acceptance.

## Build without launching

From the repository root, using the working Node 24 installation described in the root README:

```sh
node_modules/.bin/esbuild spikes/desktop/editor.mjs --bundle --outfile=spikes/desktop/build/bundle.js
node spikes/macos-editor/prepare-resources.mjs
xcodegen generate --spec spikes/macos-editor/project.yml
xcodebuild -project spikes/macos-editor/MarkrightMacEditorSpike.xcodeproj -scheme MarkrightMacEditorSpike -configuration Debug -destination 'platform=macOS' -derivedDataPath spikes/macos-editor/build CODE_SIGNING_ALLOWED=NO build
```

The preparation step copies only `spikes/desktop/index.html` and its generated IIFE bundle. It changes the copied script URL to a relative local classic script and injects a CSP; source desktop files remain unchanged. No dependencies are fetched and dependency versions remain pinned in the existing npm lockfile. Regenerate resources after editor changes. Generated resources, project and build output are ignored locally.

App: `spikes/macos-editor/build/Build/Products/Debug/MarkrightMacEditorSpike.app`. Building does not open the app or disturb foreground applications. Closing the bundled WebKit fixture discards its edits. Persistent documents use the explicitly opened separate native collection workspace; there is no WebKit save/open interface.

Headless navigation-policy checks, also from the repository root:

```sh
mkdir -p spikes/macos-editor/build
swiftc -module-cache-path spikes/macos-editor/build/PolicyModuleCache spikes/macos-editor/Sources/BundledNavigationPolicy.swift spikes/macos-editor/Tests/main.swift -o spikes/macos-editor/build/check-navigation-policy
spikes/macos-editor/build/check-navigation-policy
```

These checks validate the pure URL allowlist, not actual WebKit network behavior or native UI acceptance.

## Offscreen system-WebKit integration checks

From the repository root with the working Node installation:

```sh
node spikes/macos-editor/run-integration-checks.mjs
```

The runner rebuilds the editor with the pinned local esbuild through the current Node executable, prepares strict production resources, and compiles a background test app with Swift 6 warnings as errors. It reuses `build/IntegrationModuleCache`, checks for at least 20 GiB free before build stages and again before launching, and caps the test process at 45 seconds. No dependency/runtime download, simulator, visible window or user document is involved. The visible research app is not restarted or changed.

`BundledEditorController` is shared by the real app and this harness, so navigation/UI delegate behavior is not duplicated in a test stand-in. The loopback trap binds only 127.0.0.1 and counts connections/data rather than retaining requests. A positive control proves WebKit can fetch its inert response; only that test control permits loopback in CSP. It lives under `build/IntegrationControl`, outside production resources and app packaging.

Eight scoped checks pass on the current Mac: bundled editor/nonpersistent state, delivered-string mixed-ending paste, inert document markup (including a deferred recheck), actual CSP connection denial, native/script navigation cancellation with source retained, scripted popup/subframe denial, native alert/confirm/prompt suppression and one-shot teardown. The positive WebKit fetch is included in the eight groups. The harness remains inactive and shows no visible windows; WebKit does create an invisible `TUINSWindow` helper.

**Observed limitation at the first checkpoint:** cancelling a raw native-initiated navigation opened one speculative TCP connection to the trap, while no application/request bytes were observed and source was retained. The script-initiated attempt made no extra connection in that run. Navigation cancellation is therefore **not network isolation**. The follow-up below hardens one native entrypoint without changing that conclusion. The trap's second counter counts nonempty receives, not parsed HTTP requests; all network findings are bounded probe observations.

Passing log: `build/integration-final-20261109.log`. Earlier failed assertions/diagnostics remain under `build/integration-*-20261109.log`, including the original zero-TCP assertion and invisible-helper-window finding. These checks use authored host probes and synthetic source, never document script execution. They do not test actual downloads, OS keyboard/clipboard/IME, VoiceOver, latency, or full sandbox/security acceptance.

## Narrow native-request preflight follow-up

`BundledResearchWebView` now overrides only `load(URLRequest)`. It applies the unchanged fixed bundled-page policy **before** calling WebKit and synchronously returns nil for a disallowed request. The real controller uses that subclass and records host-only rejection diagnostics. It adds no guest/native bridge or general navigation capability. Initial bundled `loadFileURL` behavior is unchanged.

Nine scoped offscreen groups pass in `build/native-request-preflight-20261109.log`. The covered request returned nil, incremented its rejection counter synchronously, preserved source and produced zero additional trap TCP/data observations. In the same run a separate raw WKWebView with the same cancellation policy opened one TCP connection, with no application/request bytes observed and no source replacement. That comparator count is logged, not required to remain exactly one. Script navigation made no extra connection in the observed run, also not a process-isolation invariant. The positive WebKit fetch and other existing checks remain in place.

This hardens the demonstrated native `load(URLRequest)` route; **it does not fix or establish OS/process network isolation**. Other native loaders remain outside demonstrated coverage: `load(URL)` (SDK availability macOS/iOS 27, not executable on this macOS 26 host), `loadFileURL`, `loadFileRequest`, HTML/data/simulated-request loaders, native download start/resume, reload/back-forward and interaction-state restoration. Installed `WKWebView.h` explicitly notes simulated-request content may load subresources. These are trusted-host APIs, not reachable through current inert document source, and are not a guest sandbox boundary.

Swift warnings-as-errors app verification passes in the existing separate Verification product. The visible Debug app is not restarted or rebuilt. Current native-request evidence remains separate from actual downloads, OS input/clipboard/IME, VoiceOver, latency and complete security/release acceptance.

## Verified checkpoint

### Bundled whole-document source control

The latest bundled desktop fixture has an explicit Source mode toggle. Eleven scoped groups pass in `build/desktop-source-mode-native-final-20261109.log`, including authored DOM clicks that reveal all syntax and preserve exact BOM/mixed-ending source plus reverse selection through both transitions. Keyboard/focus/undo and composition guards have separate headless browser evidence (29 passes/1 explicit WebKit CDP skip); the offscreen native probe is not OS keyboard input. `build/desktop-source-mode-host-final-20261109.log` records a successful warnings-as-errors build into the unused Verification product. The existing visible Debug app was not updated/restarted. Source mode continues parsing; it is not a read-only reading mode, full renderer or performance acceptance. All isolation/VoiceOver/ingestion/device/release gates remain.

### Retained-view teardown follow-up

The old teardown removed weak delegates while leaving the loaded page alive. An authored delayed navigation after `stop()` reached the loopback trap and committed its response: TCP/nonempty-receive deltas `[1, 1]` in `build/teardown-before-session-20261109.log`. The old stale-callback assertion passed despite this gap.

`BundledResearchWebView` now owns a deny-all navigation/UI delegate, installs it before `stopLoading()`, clears the host callback, and permanently refuses covered native `load(URLRequest)` calls after teardown, including the otherwise allowed fixture. The delegate survives controller release without retaining the controller. This does **not** terminate JavaScript.

Ten scoped groups pass in `build/teardown-source-final-20261109.log`. The new regression retains the view after releasing its controller, arms an authored delayed navigation after teardown, verifies the attempt actually ran, and checks exact source/URL retention, suppressed dialogs, no stale status callback and no additional trap application bytes. Repeated stop and covered fixture/external native loads are checked. Teardown TCP delta was zero in this run; it remains a diagnostic, not an isolation invariant. Independent review found no blocking issue. Other native loaders/download/history APIs, already-started work, speculative connections and OS/process isolation remain open.

The separate unused Verification app builds successfully with Swift warnings as errors (`build/teardown-host-session-verification-20261109.log`); the visible Debug product was preserved. Fourteen pure policy checks still pass. Reused Mac build storage is now about 306 MiB, versus 291 MiB before this checkpoint, with 23 GiB shared free space at verification.

The initial sandbox probe aborted during AppKit registration before checks ran; the initial app verification hit SwiftUI macro sandbox restrictions. Session runs are recorded separately. A warnings-as-errors compiler diagnostic in the first regression draft was corrected before the passing run; failed logs remain preserved. No visible window, VoiceOver, simulator, user document or production service was used by these checks.

The unsigned arm64 app builds on macOS 26.6.2 with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. Fourteen pure Foundation navigation-policy checks pass. A native-window observation confirms the app loads its bundled fixture in system WKWebView, including the editor's formatted inactive text; the window was raised and a fresh screenshot verified. This is an actual local `.app` window, separate from the loopback browser preview. The configured macOS 14 deployment target is experimental, not tested minimum-OS acceptance.

The shared-controller refactor also builds with warnings as errors into `build/Build/Products/Verification/MarkrightMacEditorSpike.app`, keeping the existing Debug product/window untouched. Regenerate the Xcode project after adding source files. The integration and verification builds reuse owned resources; the build directory most recently measured 290 MiB, compared with an earlier 199 MiB checkpoint.

No interactive OS typing/undo, native accessibility/VoiceOver, OS IME or latency acceptance is claimed from the load observation or programmatic offscreen probes. The app is deliberately labeled research and temporary edits. Generated products, failed/passing probe logs and build logs are retained for inspection; regenerable unused module/SDK-stat caches may be removed independently without deleting the app or evidence.

## Deliberate boundary

- Nonpersistent `WKWebsiteDataStore`; the WebKit fixture has no accounts, disk document persistence or sync. The separate native workspace uses the shared app-owned collection store with no WebKit bridge.
- The navigation allowlist permits only the exact bundled `index.html` plus fragment changes. Delegates refuse new windows, subframe/download-marked navigations and JavaScript dialogs.
- The native request preflight covers only `load(URLRequest)`; delegate checks reject download-marked navigations, but separate native loader/download/history APIs are not demonstrated isolated.
- `loadFileURL` grants WebKit read access only to the generated Editor resource directory. No user-document grants or native message handlers are registered.
- CSP denies default/network connections, images, fonts, media, frames, workers, objects, forms and base URLs. Only the local bundled script and necessary inline editor styles are allowed. Document HTML/script-looking text remains inert source in the existing editor.
- Native status and toolbar label the experiment and temporary edits. This build uses no signing credentials, entitlements, production services or embedded credentials.

These restrictions are authored controls, not a completed security review or an OS sandbox claim for an unsigned host. Bundled loading, a visible native window and the scoped offscreen behaviors above have evidence; speculative navigation connections, broader adversarial network/download behavior, keyboard/IME, clipboard/drop/multiple selection, VoiceOver and input-to-paint latency remain gates. Existing headless browser tests do not prove full native acceptance. The desktop test harness remains present in the bundled code; it exposes no native bridge and is not a production API.
