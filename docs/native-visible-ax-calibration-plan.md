# MRK-46 visible accessibility calibration

## Purpose and current status

The hidden-host preview probe paints readable SwiftUI text but cannot read its expected semantic metadata, even for a plain-text control. The original native suite still fails that required observation. A separate opt-in visible calibration fixture is now authored to compare the observation path using the existing `MacSourceEditor` and `SourcePreviewPanel` components.

**The fixture is uncompiled and unrun.** Python syntax/help and source review do not establish that it builds, opens, exposes metadata, retains input or works with assistive technology. No visible result, accessible name/order, contrast, keyboard behavior or VoiceOver result is claimed. This helper is separate from the app and the invisible test runner; production source, the failing assertions and prior evidence are unchanged.

## Synthetic surface

The entry point accepts only `--show-synthetic-window` or `--help`. Other arguments exit before application creation. The visible mode creates a regular 1080×760 native window titled **Markright Synthetic Accessibility Calibration**, with a minimum size of 900×600. It contains a plain SwiftUI text control, a native source field, an optional existing partial preview, composition status and close/quit controls.

Initial source is fixed and below 1 KiB: inactive bold/link-label text, an active literal source selection, decomposed Unicode, emoji, mixed physical endings and inert HTML/image/code/table source. Edits remain in memory. There is no collection workspace, document input, open/save dialog, source persistence, automatic input, screenshot capture, URL navigation, script execution or accessibility-setting change. The partial preview keeps its existing literal fallbacks, bounds and cleared link targets. The editable native source field keeps its existing menu and undo implementation.

The source field stays in the unconditional first position of a stable split container. The optional preview uses a minimum width of 260 points. This layout is a source-level intention pending visible observation; it does not establish workspace or iOS editor retention. Closing the window or quitting terminates only this diagnostic app and discards its edits.

Expected identifiers are `calibration-heading`, `calibration-plain-text`, `calibration-preview-toggle`, `calibration-composition-status`, `calibration-source-editor`, `calibration-close`, `live-preview-panel` and `live-preview-status`. The native source label is **Synthetic Markdown source**; the plain control reads **Synthetic SwiftUI calibration text**. These are declarations, not observed AX results. SwiftUI may expose a representable wrapper differently from its native text field; record the actual tree and native label rather than treating every declared identifier as a guaranteed node.

## Separate build and launch

Run from the repository root only after coordinating a quiet slot with other host workers. The launcher requires at least 20 GiB free, one-minute load below 32 and a readable process inventory without known competing native/compiler jobs. It does not reserve the host or detect every possible workload; these checks supplement peer coordination. A refused check creates no compiler or app process and leaves other jobs untouched.

Build only:

```sh
python3 spikes/macos-editor/run-ax-calibration.py --build-only
```

This compiles eight allowlisted source files with Swift 6, warnings as errors, two jobs and a 90-second compiler allowance. It reuses the existing native-check module cache, downloads nothing and does not modify the Xcode project, sign, install, launch or publish the app. A timeout cancels only the compiler process group started by this invocation. Each attempt has a fresh owned output directory and compile log; failed attempts and prior builds are retained. Unknown output ownership and symlink components are refused. No stale lock is removed automatically.

Launch only after explicitly coordinating foreground ownership and an observer:

```sh
python3 spikes/macos-editor/run-ax-calibration.py --run-visible --foreground-coordinated
```

This never compiles. It requires an owned build whose source hashes, launcher hash, architecture, binary hash and app metadata still match. Source changes require a separate rebuild in an available slot. The acknowledgement flag records the caller's coordination; it does not obtain permission, inspect other workers' reservations or prove a window was observed. Directly running the binary also requires its explicit synthetic-window flag; do not use that route to bypass coordination or failed launcher admission.

Outputs remain under ignored `spikes/.build/macos-ax-calibration/`; the existing native-check module cache is reused. Every build has immutable `build.json`, `compile.log` and its unsigned app. `current.json` selects a successful build atomically. Launches append fresh runtime logs and report only the owned PID/log path. Startup JSON contains the PID, title, declared identifiers and the ordinary `window.isVisible` property; that property is not a visual or AX observation. Neither helper logs edited source deliberately. Compiler or framework diagnostics may still appear in local logs; review them before external sharing. These ownership/hash checks protect against accidental reuse; they are not an untrusted-filesystem or process-isolation boundary.

`--help` and invalid argument combinations stop before process inventory, output creation, compilation and launch. No automatic launch, global preference, login item or other worker process is changed.

## Source-only verification

The Python AST parse, real `--help` path and `git diff --check` pass. Nine lightweight launcher regression groups also pass:

```sh
python3 spikes/macos-editor/check-ax-calibration-launcher.py
```

These checks use fake compiler/process/launch/signal operations and synthetic temporary files. They exercise early CLI refusal, build/launch separation, disk/load/process-inventory refusal, unknown/symlink output ownership, overlapping operation locks, stale build/app metadata, the exact synthetic launch flag and source changes during a mock compile. Compiler-result cases preserve diagnostics and send no signal after a completed job; mocked timeout/interrupt cases check the new process-group boundary and bounded graceful/forced waits. They do not inventory the real host, compile Swift, launch an application or establish the behavior of real compiler timeout cancellation. An initial ad-hoc check correctly hit the symlink guard at macOS's `/var` temporary-directory alias; the test fixtures now use the resolved temporary root, without relaxing launcher checks.

A follow-up regression reproduced a cancellation race: if the owned group exited after its graceful wait expired but before the forced signal, `ProcessLookupError` replaced the original timeout. The launcher now tolerates that already-exited group, reaps its leader and retains the original cancellation. The new case failed before the fix and passes afterward. All process and signal operations in this regression are mocked; no real group was stopped.

Independent source review found no blocking issue and approved the checkpoint with runtime verification still required. The four source-level accessibility passes found native system styles and textual state feedback, native labeled controls, no custom motion and a missing heading trait that is now added. The activation call uses the public macOS 14 API recommended by the installed SDK. Actual contrast/layout, keyboard/focus/IME and AX/spoken behavior remain unmeasured.

## Observation and unchanged gates

Once a safe slot exists, first compile without launch and inspect the retained log. Separately launch with a coordinated observer and verify the actual titled window, plain control, native source label and preview metadata through an approved observation path. Keep screenshots, metadata and spoken output as distinct kinds of evidence. Use synthetic text only. Test actual toggle/input/focus/undo/composition behavior in that owned window without assuming model or startup-property values establish it. Check minimum-size clipping, system appearance/contrast and keyboard reachability when the window can be observed; those remain unverified in this source-only slice.

The fixture has no collection list or Open marker, recovery lifecycle, export provider or iOS surface. Success here can calibrate an observation path; it cannot pass the original workspace assertions or replace their retention coverage. Failure here does not identify a product defect without further evidence.

Follow [the attended VoiceOver plan](mrk9-attended-voiceover-plan.md) before any VoiceOver experiment. An attended listener or reliable spoken-output observation is still required, and native iOS VoiceOver remains a separate check. This helper never enables VoiceOver. Network/process isolation, ingestion, external folders/providers, physical devices, full Markdown rendering, native input and release gates remain open. No main merge or publication follows from adding or building this diagnostic.
