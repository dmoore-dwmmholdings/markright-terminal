# MRK-9 macOS system-WKWebView research host

Standalone SwiftUI window around the existing synthetic desktop CodeMirror fixture. This is a macOS shell experiment, not a selected production architecture, Tauri integration, complete Markdown application or native iOS implementation. MRK-9 VoiceOver observation and MRK-12 integrated review remain open.

## Build without launching

From the repository root, using the working Node 24 installation described in the root README:

```sh
node_modules/.bin/esbuild spikes/desktop/editor.mjs --bundle --outfile=spikes/desktop/build/bundle.js
node spikes/macos-editor/prepare-resources.mjs
xcodegen generate --spec spikes/macos-editor/project.yml
xcodebuild -project spikes/macos-editor/MarkrightMacEditorSpike.xcodeproj -scheme MarkrightMacEditorSpike -configuration Debug -destination 'platform=macOS' -derivedDataPath spikes/macos-editor/build CODE_SIGNING_ALLOWED=NO build
```

The preparation step copies only `spikes/desktop/index.html` and its generated IIFE bundle. It changes the copied script URL to a relative local classic script and injects a CSP; source desktop files remain unchanged. No dependencies are fetched and dependency versions remain pinned in the existing npm lockfile. Regenerate resources after editor changes. Generated resources, project and build output are ignored locally.

App: `spikes/macos-editor/build/Build/Products/Debug/MarkrightMacEditorSpike.app`. Building does not open the app or disturb foreground applications. Closing the native window discards edits; the host has no save/export/open-file interface.

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

**Observed limitation:** cancelling a native-initiated external navigation opened one speculative TCP connection to the trap, while sending no HTTP request and retaining source. The script-initiated attempt made no extra connection/request in this run. Navigation cancellation is therefore **not network isolation**. The harness reports both counts and does not claim zero network activity for navigation. CSP's separate fetch-denial probe made zero additional trap connections. OS/process network isolation remains a security gate.

Passing log: `build/integration-final-20261109.log`. Earlier failed assertions/diagnostics remain under `build/integration-*-20261109.log`, including the original zero-TCP assertion and invisible-helper-window finding. These checks use authored host probes and synthetic source, never document script execution. They do not test actual downloads, OS keyboard/clipboard/IME, VoiceOver, latency, or full sandbox/security acceptance.

## Verified checkpoint

The unsigned arm64 app builds on macOS 26.6.2 with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. Fourteen pure Foundation navigation-policy checks pass. A native-window observation confirms the app loads its bundled fixture in system WKWebView, including the editor's formatted inactive text; the window was raised and a fresh screenshot verified. This is an actual local `.app` window, separate from the loopback browser preview. The configured macOS 14 deployment target is experimental, not tested minimum-OS acceptance.

The shared-controller refactor also builds with warnings as errors into `build/Build/Products/Verification/MarkrightMacEditorSpike.app`, keeping the existing Debug product/window untouched. Regenerate the Xcode project after adding source files. The integration and verification builds reuse owned resources; the build directory most recently measured 290 MiB, compared with an earlier 199 MiB checkpoint.

No interactive OS typing/undo, native accessibility/VoiceOver, OS IME or latency acceptance is claimed from the load observation or programmatic offscreen probes. The app is deliberately labeled research and temporary edits. Generated products, failed/passing probe logs and build logs are retained for inspection; regenerable unused module/SDK-stat caches may be removed independently without deleting the app or evidence.

## Deliberate boundary

- Nonpersistent `WKWebsiteDataStore`; no accounts, disk document persistence or sync.
- Only the exact bundled `index.html` top-level navigation, plus fragment changes, is allowed. New windows, subframe navigations, downloads and JavaScript dialogs are refused.
- `loadFileURL` grants WebKit read access only to the generated Editor resource directory. No user-document grants or native message handlers are registered.
- CSP denies default/network connections, images, fonts, media, frames, workers, objects, forms and base URLs. Only the local bundled script and necessary inline editor styles are allowed. Document HTML/script-looking text remains inert source in the existing editor.
- Native status and toolbar label the experiment and temporary edits. This build uses no signing credentials, entitlements, production services or embedded credentials.

These restrictions are authored controls, not a completed security review or an OS sandbox claim for an unsigned host. Bundled loading, a visible native window and the scoped offscreen behaviors above have evidence; speculative navigation connections, broader adversarial network/download behavior, keyboard/IME, clipboard/drop/multiple selection, VoiceOver and input-to-paint latency remain gates. Existing headless browser tests do not prove full native acceptance. The desktop test harness remains present in the bundled code; it exposes no native bridge and is not a production API.
