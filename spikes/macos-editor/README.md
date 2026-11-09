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

## Verified checkpoint

The unsigned arm64 app builds on macOS 26.6.2 with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. Fourteen pure Foundation navigation-policy checks pass. A native-window observation confirms the app loads its bundled fixture in system WKWebView, including the editor's formatted inactive text; the window was raised and a fresh screenshot verified. This is an actual local `.app` window, separate from the loopback browser preview. The configured macOS 14 deployment target is experimental, not tested minimum-OS acceptance.

No interactive typing/undo, actual denial-path/network probe, native accessibility/VoiceOver, OS IME or latency acceptance is claimed from the load observation. The app is deliberately labeled research and temporary edits. Generated products and build logs are retained for inspection; regenerable unused module/SDK-stat caches may be removed independently without deleting the app.

## Deliberate boundary

- Nonpersistent `WKWebsiteDataStore`; no accounts, disk document persistence or sync.
- Only the exact bundled `index.html` top-level navigation, plus fragment changes, is allowed. New windows, subframe navigations, downloads and JavaScript dialogs are refused.
- `loadFileURL` grants WebKit read access only to the generated Editor resource directory. No user-document grants or native message handlers are registered.
- CSP denies default/network connections, images, fonts, media, frames, workers, objects, forms and base URLs. Only the local bundled script and necessary inline editor styles are allowed. Document HTML/script-looking text remains inert source in the existing editor.
- Native status and toolbar label the experiment and temporary edits. This build uses no signing credentials, entitlements, production services or embedded credentials.

These restrictions are authored controls, not a completed security review or an OS sandbox claim for an unsigned host. Bundled resource loading and a visible native window were observed; adversarial CSP/network/navigation behavior, keyboard/IME, clipboard/drop/multiple selection, VoiceOver and exact input-to-paint latency still require actual system-WKWebView checks. Existing headless browser tests do not prove those results. The desktop test harness remains present in the bundled code; it exposes no native bridge and is not a production API.
