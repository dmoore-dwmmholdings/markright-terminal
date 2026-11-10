# MRK-39 native macOS collections and recovery

This bounded research slice extends the app-owned MRK-36/37/38 storage workflow to macOS against pinned MRK v2 R6/R7/R14/R15. It does not select the production desktop architecture or accept MRK-26, MRK-18, MRK-12 or MRK-9.

## Native workspace

The research app's **Open collections** command opens a separate SwiftUI/AppKit workspace. The existing bundled WebKit fixture keeps its temporary source and receives no filesystem or message bridge. Opening the native workspace creates an app-owned `MarkrightCollectionsResearch` directory beneath the OS Application Support parent. Nothing resolves or opens that store at app launch. The trusted OS parent is resolved physically before appending the app-owned leaf; collection/root traversal still refuses symlinks and arbitrary hard links.

Collections support explicit creation, document listing/opening, plain `NSTextView` source editing, autosave, Save As into another existing collection, and recovery preview/restore into a new file. Source bytes, BOM and mixed line endings use the shared storage core. Smart punctuation, spelling correction, automatic links/data detection and rich text are disabled. The native workspace does not yet offer the iOS partial preview/reading controls, a complete Markdown renderer, external folder selection or provider grants. Linked assets/includes are not copied or rewritten.

`EditorModel` was extracted unchanged from the iOS view file into a Foundation/Observation source. Both apps compile the same model, selection validation, collection store, checkpoint format and document-session lifecycle. A standalone Swift package runs the existing storage/session corpus on macOS without UIKit.

## Session and recovery boundaries

Collection changes, open, create and restore flush the current session before storage work and recheck it after awaited I/O. A late edit or marked-text composition keeps that session open. Committed creation/restore receipts remain separately available even when adoption is deferred; listing or cleanup failures do not offer to publish the same copy again. Reopening the current file retains a newer saved source/caret rather than replacing it with an earlier read.

Native window close and application quit flush accepted source, refuse active composition/operations, and recheck current close eligibility immediately before final authorization. A failed save can close only after explicit confirmation that an acknowledged checkpoint covers the current revision. That choice detaches the validated session without retiring its draft, allowing the same workspace to reopen and restore a separate copy even while the original remains conflicted. Cancelling or acknowledging a stale revision keeps the window open. A hidden window still participates in quit preparation.

These checkpoints are acknowledged-save recovery, not a claim that every keystroke survives a crash. Debounce, interruption before checkpoint acknowledgement, actual power loss, disk exhaustion, permission loss and filesystem synchronization faults retain their existing qualification limits.

## Verification

The shared macOS storage/session corpus passes **58 tests**, zero failures, Swift warnings as errors. Evidence: `spikes/macos-editor/build/MRK39-shared-core-macos-fixed-20261110.log`. The first run's failures are preserved separately: Foundation shortened the temporary-directory alias to a symlink that the store correctly refused. Test fixtures now physically resolve only the trusted OS temporary parent; the store’s nofollow checks were not weakened.

Run that corpus from the repository root:

```sh
swift test --package-path spikes --scratch-path spikes/macos-editor/build/SharedNativePackage -Xswiftc -warnings-as-errors
```

The focused native AppKit probe builds and directly runs a separate invisible test app:

```sh
python3 spikes/macos-editor/run-native-collection-checks.py
```

It uses an application activation policy of prohibited, never opens the real workspace manager, and creates only uniquely named synthetic fixtures under the physically resolved temporary parent. Compile and runtime each have a 90-second bound. It checks headroom before both stages and caps the executable size. No network, dependency download, user collection or foreground window is involved.

The unsigned arm64 macOS app builds with Swift warnings as errors in the separate unused Verification product: `spikes/macos-editor/build/MRK39-native-macos-build-final-20261110.log`. The initial build's AppKit property spelling diagnostic is preserved; the corrected source uses the installed SDK's `smartInsertDeleteEnabled` property. The bundled editor resource hash is unchanged. The existing visible Debug app was not rebuilt, restarted or updated, and no real app-owned workspace was opened during verification.

All **five focused native AppKit groups pass** in `spikes/macos-editor/build/MRK39-native-appkit-final-20261110.log`. They cover the actual hosted source view's nonzero layout, literal bytes and policies, programmatic insertion/undo, UTF-16 caret, one-shot focus, marked-text preservation and read-only recovery label; model creation/edit/Save As; conflicting-original recovery close/reuse/new-copy restore; late edits across actor-held storage work with committed receipt retention; and invisible native window close/quit guards. The last group injects a composing edit immediately before the real delegate consumes its close authorization, checks refusal, then commits and verifies the current bytes before actual closure.

Two initial probe timeouts remain preserved. Diagnostics located the first group's programmatic marked-text call after the probe had deliberately resigned focus and changed undo grouping. Restoring the source first responder and normal automatic grouping before composition corrected the harness, without changing production source. The passing check still uses authored calls, not an OS keyboard/input-method session. Independent lifecycle and harness review cleared the post-I/O and close freshness fixes. The final run also checks that no link attribute exists anywhere in the recovery preview.

The current iOS native/model/decoder shard passes **91 tests**, zero failures/skips/result-bundle runtime warnings: `spikes/ios-editor/build/MRK39-ios-native-shard-20261110.xcresult` and the adjacent summary JSON. It reuses the current warnings-as-errors build. The initial full-suite attempt reached its 20-minute bound without finalizing a result; its logs and incomplete bundle remain preserved. A graceful interrupt did not finish finalization before the hard timeout. That incomplete run is not counted as a pass. A completed current workflow shard, `MRK39-ios-workflow-shard-20261110.xcresult`, has **10 UI passes and one failure**, zero skips/result-bundle runtime warnings. The failing recovery-relaunch method observed incomplete typed source before a missing current-checkpoint acknowledgement; it then continued termination despite those failed prerequisites. Later restore comparisons are cascading failures, not evidence proving storage rollback. The complete current UI regression remains open.

The isolated recovery-input rerun could not boot the simulator: CoreSimulator reported 3,869 user processes against a 4,000 limit with a 300-process reserve. No tests ran in that attempt, and the owned simulator remains Shutdown. This resource blocker and the unresolved input/checkpoint failure do not change the native storage/core results, and they prevent claiming current iOS UI or recovery-interaction acceptance.

Generated projects, products, test fixtures and diagnostics stay ignored locally. All build/probe stages require at least 20 GiB free and reuse owned resources.

Real keyboard/IME, VoiceOver, physical iOS devices, external providers, complete parser/assets/identity, network/process isolation and security/release acceptance remain open. Programmatic offscreen AppKit checks do not establish attended interaction or accessibility acceptance.
