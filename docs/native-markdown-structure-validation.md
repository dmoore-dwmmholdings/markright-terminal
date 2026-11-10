# MRK-43 native link, image-reference and code-block insertion

This research slice extends **Insert Markdown** with **Link**, **Image reference** and **Code block** on native macOS and iOS whole-document Source editors. It builds on the MRK-42 source-menu/native-undo path and relates to pinned MRK v2 R9/R15. It does not accept full authoring, asset management, syntax highlighting or Markdown rendering.

## User workflow and source contract

Choose **Link** or **Image reference** with a simple label/alt-text selection. The helper inserts `[label](destination)` or `![alt text](destination)` and selects `destination` so ordinary typing replaces that placeholder. An empty selection supplies `link text` or `alt text`. It preserves selected label bytes and the surrounding source. Labels containing controls, square brackets, backslashes or only whitespace are refused rather than parsed or escaped. Existing Markdown inside an accepted label stays literal source; a particular rendered appearance is not guaranteed.

These are reference templates. They do not choose, import, inspect or copy an image, establish an external grant, validate/resolve a destination or open a URL. The placeholder must be replaced and the final label/alt text reviewed by the author. Relative references remain relative. The complete file/link picker, image-asset workflow and actionable reference validation remain separate work.

Choose **Code block** to fence selected literal source, including multiline text and existing backticks. An empty selection supplies selected `code`. The fence has at least three backticks and is longer than every selected backtick run. The body is preserved byte for byte, including trailing physical line endings and whitespace. No inline-code padding is added to a block.

New separator lines use the first physical CRLF, CR or LF in the document, or LF when none exists. An opening separator is added only when the insertion starts inside a physical line. The closing fence reuses a selected body's trailing ending when present; otherwise one is inserted. A following untouched newline supplies the closing-line boundary, or one separator is inserted before a non-newline suffix. Existing prefix/suffix bytes are never rewritten. Surrounding Markdown syntax is not parsed, so this remains a literal source helper rather than a semantic block transformation.

The existing 1 MiB complete-source/result and 64 KiB selection budgets, strict UTF-16 boundary validation and exact stale-source/range checks apply. BOM/NFD/emoji and mixed physical endings remain literal source. Invalid ranges, split surrogate/CRLF boundaries and oversized work are refused. iOS block editors keep their existing native suggested actions; these helpers require whole-document Source mode.

## Native lifecycle

The existing generic native menu path presents the new commands without a new dialog. Actions retain weak native-view references and immutable plans, recheck attached/focused/editable/unmarked/single-selection state and exact input, insert through the native text system, and select the plan's destination or body. Native undo grouping and final coordinator reporting remain unchanged. The active session identity/generation, autosave/recovery and baseline-conflict protocol retain their existing authority; inserting a reference or fence does not acknowledge a save.

No rich-text conversion, clipboard access, script execution, URL opening, image loading, network capability, external folder grant or incoming document route is added. Fenced source is never automatically executed. The native UI code itself is unchanged for this slice; both platforms enumerate the shared command list.

## Verification and remaining gates

The shared Mac corpus passes **123 tests**, zero failures, with Swift warnings as errors (`spikes/macos-editor/build/MRK43-shared-core-macos-20261110.log`). Ten new groups cover link/image placeholders and exact destination selection, rejected labels, literal neighbors, caret positions, first-document and mixed physical endings, trailing endings/whitespace, bounded backtick fences, script-shaped source, shared limits and stale plans. Earlier inline-command and recovery regressions remain included.

All **14 focused AppKit/Transferable groups pass** (`spikes/macos-editor/build/MRK43-native-appkit-teardown-20261110.log`). The new group invokes real native menu targets without showing a context menu, checks exact BOM/NFD/emoji/CRLF/CR source, selected destination/body, ordinary typing over a destination placeholder, and separate native undo of typing and insertion followed by insertion redo. It does not read source files, resolve a reference, access a pasteboard or activate an application. Earlier actual-workspace conflict/recovery and stale-action groups remain included.

The initial native run passed but emitted `NSTextLayoutManagerBreakOnNilContentManager`. A second passing run added command stages and retired only private-host callbacks, responder and undo state after assertions. The diagnostic remains during the Link insertion undo/redo sequence, before cleanup; the source/report/selection assertions still pass. Neither the diagnostic's cause nor a production fix is established, and the original and staged logs are preserved. Actual native OS undo/input acceptance remains open.

The unsigned arm64 Mac app builds in the unused Verification product with warnings as errors (`spikes/macos-editor/build/MRK43-native-macos-build-20261110.log`). The iOS app and test targets pass a two-job generic Simulator `build-for-testing` with warnings as errors (`spikes/ios-editor/build/MRK43-native-ios-build-20261110.log`). One added UIKit refusal method covers all three new valid plans in detached/out-of-scope states; it compiled but did not run. Existing host provisioning-profile and generic Simulator placeholder diagnostics are retained, with signing disabled and no boot, install or launch requested. Independent lifecycle and privacy review found no scoped blocker.

Heavy stages are serial, reuse owned caches, require at least 20 GiB free and use two build jobs. Generated projects/products, synthetic fixtures and passing/diagnostic logs stay ignored. The visible Debug app and existing preview are preserved.

No new owned-device runtime or recovery-test evidence is available since MRK-42. The latest generic build metadata does not supply boot arguments, a current boot error trace or per-keystroke recovery evidence. Simulator boot error 22 remains unexplained; a repair or blind boot retry is unsupported. Existing exact-input/current-checkpoint and no-refocus continuation probes remain the next useful diagnostics when runtime execution is available. No simulator/device/service/runtime mutation was performed.

Actual OS menu/keyboard/IME, iOS runtime, VoiceOver, physical devices, full authoring/rendering, reference/asset/provider handling, untrusted ingestion, network/process isolation and release acceptance remain open. Denied documentation-service drafts and packets remain preserved without retries or alternate publication.
