# MRK-42 native Markdown insertion

This research slice adds **Insert Markdown → Bold / Italic / Inline code** to the native macOS source context menu and iOS whole-document Source edit menu. It relates to pinned MRK v2 R9/R15. These are literal source insertion helpers; complete authoring, rendering and native client acceptance remain open.

## Editing contract

Select source text and choose a command. Bold surrounds it with `**`, italic with `*`; existing Markdown is left literal rather than parsed, escaped or toggled. With an empty selection, the command inserts and selects `text` or `code` inside the markers so typing can replace the placeholder. The original selected body stays selected after insertion.

Inline code chooses a backtick delimiter longer than every backtick run in the selected body. It adds one padding space on each side when an edge backtick, or two space edges around non-space content, require it to preserve the literal body. CR/LF and whitespace-only selected bodies refuse inline code. Other commands do not rewrite line endings, normalize Unicode or convert through rich text. Arbitrary selected Markdown is not guaranteed to become a particular rendered style; this helper is not the complete CommonMark/GFM parser or a semantic formatting toggle.

Planning accepts at most 1 MiB of complete source, 64 KiB of selected UTF-8 and 1 MiB of resulting source. It validates the native UTF-16 range before slicing and refuses out-of-bounds, overflow, split-surrogate and split-CRLF ranges. Byte-exact source and range snapshots protect against stale actions, including canonically equivalent strings with different bytes. The document is never rounded to a different selection. iOS block editors keep their existing native suggested actions; the new helpers require whole-document Source mode so the source budget includes the full document. Reading content has no editing command.

## Native action and persistence

Menu actions retain an immutable plan and a weak reference to their original native text view. They recheck attachment, first responder, editability, composition, single selection, current range and exact source before replacing text. An old menu never redirects to another responder or edits a changed source/range. A native view leaving the document cannot be retained by a menu action. Disabled/unavailable plans do not invoke a replacement.

Accepted actions use native text insertion, undo grouping and the existing editor coordinator to report the final source and selection. They do not directly replace the editor model, reset its generation, rebind a destination, flush a save or retire a recovery checkpoint. Formatting is an ordinary source edit: normal autosave/recovery scheduling and baseline-conflict handling still apply. No clipboard read/write, incoming document route, external grant, URL opening, script execution, network access or asset import is added.

## Verification and open gates

The shared Mac corpus passes **113 tests**, zero failures, with Swift warnings as errors (`spikes/macos-editor/build/MRK42-shared-core-macos-20261110.log`). Ten new planner groups exercise literal selected/untouched source, placeholders, Unicode and physical line endings, code delimiters/padding, malformed Markdown, limits, invalid ranges and stale snapshots.

A further recovery-session regression follows the original failure prefix: `Re`, a failed save with an acknowledged checkpoint, then the remaining text through the same model/generation/caret, followed by another failed save. It confirms current complete-source recovery with unchanged original source/baseline. This is shared-model evidence only; it does not establish UIKit focus or OS input delivery.

All **13 focused AppKit/Transferable groups pass** (`spikes/macos-editor/build/MRK42-native-appkit-ime-setup-20261110.log`). Three new groups activate the real native menu item without showing a context menu, confirm exact native insertion and undo/redo with retained selection/focus, refuse stale selection/non-source focus/read-only/multiple-selection/marked/detached actions, and exercise an inline-code edit/undo/redo through the actual collection workspace's failed autosave and complete-source recovery checkpoint. The conflicting original file and baseline remain unchanged. All windows remain invisible and the real collection manager/root is untouched.

The first authored refusal probe timed out after its initial menu/undo group passed. It had kept deterministic non-event undo grouping enabled when synthesizing marked text. Restoring AppKit's normal event-based undo before that positive control, with the same refusal assertions and added stage diagnostics, passes. The timeout is preserved and is not treated as evidence of an app defect or a resolution of the separate iOS input issue.

The unsigned arm64 Mac app builds into the unused Verification product with warnings as errors (`spikes/macos-editor/build/MRK42-native-macos-build-20261110.log`). The iOS app and test targets pass a generic Simulator `build-for-testing` with warnings as errors (`spikes/ios-editor/build/MRK42-native-ios-build-20261110.log`), including four new UIKit refusal tests that were compiled but not run. Xcode emits existing host provisioning-profile and generic Simulator placeholder diagnostics; signing is disabled and no boot/install/launch is requested. Independent lifecycle and privacy review found no scoped blocker.

Builds use existing owned caches, two jobs and at least 20 GiB free before heavy stages. Generated projects/products, synthetic fixtures, diagnostics and passing/failed logs remain ignored locally. The visible Debug app, loopback preview, original denied-write packets and unrelated workers' resources are preserved.

The prior iOS recovery-input failure and simulator boot error 22 remain unresolved. Existing workflow logs locate the first failure at the complete-input assertion immediately after `app.typeText`, before checkpoint/recovery comparisons. Retained failure attachment/image manifests are empty, and the failed boot record retains no invocation arguments. No new evidence supports a boot-argument diagnosis or a service/runtime/device repair. No boot retry, device erase, service reset or runtime change was performed.

Authored offscreen native calls and compilation do not qualify actual OS menu selection, keyboard/IME, iOS runtime, VoiceOver, physical devices, complete Markdown rendering or performance. The existing untrusted-ingestion, network/process-isolation, provider, identity/portability and release gates remain open. Previously denied documentation-service writes remain unchanged and unposted.
