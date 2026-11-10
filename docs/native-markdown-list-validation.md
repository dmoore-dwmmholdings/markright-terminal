# MRK-44 native Markdown list insertion

This research slice adds **Bulleted list**, **Numbered list** and **Task list** to **Insert Markdown** on native macOS and iOS whole-document Source editors. It relates to pinned MRK v2 R9/R15 and uses the existing literal-source/native-undo path. Full authoring and semantic Markdown rendering remain separate gates.

## Source workflow

Select complete physical lines to prepend `- `, sequential `1. `/`2. ` markers, or unchecked `- [ ] ` task markers. Nonblank rows receive markers; blank and whitespace-only rows retain their exact bytes. Numbering counts nonblank rows and restarts at one for each command. A trailing physical ending does not create a phantom final item. The resulting list content is selected, with an absolute leading BOM left outside that selection and before the first marker.

At a physical-line-start caret, an existing nonblank line receives only its marker and the caret stays after it. On an empty or whitespace-only row, a selected `item` placeholder is inserted after the marker, leaving existing spaces and line endings unchanged. A caret immediately after an absolute leading BOM is allowed; a caret before it is refused so the BOM stays first.

Partial-line nonempty selections are refused rather than expanded to unselected text. A valid range begins at a physical line start (including just after a leading BOM) and ends before or after a complete physical ending, or at EOF. Selected whitespace-only input is refused as a no-op. These helpers do not parse existing Markdown, toggle markers, infer nesting, continue an outside numbering sequence, normalize indentation, implement automatic Return behavior or create interactive checkboxes. Existing markers remain literal text and may receive another prefix. No separator lines are inserted to isolate surrounding Markdown context.

The existing strict UTF-16 range checks protect surrogate and CRLF boundaries. Complete source/result remain bounded to 1 MiB and selected UTF-8 to 64 KiB; selected work is additionally limited to 256 physical rows, including blank rows. BOM, NFD/emoji, row text, CRLF/CR/LF and outside source bytes remain literal. iOS block editors retain their existing suggested actions; the new commands require whole-document Source mode.

## Native lifecycle and acceptance

The platform menu implementations are unchanged. Immutable plans keep the original replacement range and stale-source/selection snapshot; weak native-view captures and attachment/focus/editability/composition/single-selection checks still apply. Accepted commands use native insertion, arbitrary valid final selections, native undo grouping and existing coordinator reports. They do not change the active session identity/generation, save destination/baseline, autosave/recovery authority or close authorization. A list command is an ordinary unsaved source edit.

No clipboard access, file/URL resolution, external grant, asset import, network capability, script execution or incoming document route is added. Original source and recovery handling retain their existing conflicts and limits.

## Verification

The shared Mac corpus passes **134 tests**, zero failures, with Swift warnings as errors (`spikes/macos-editor/build/MRK44-shared-core-macos-20261110.log`). Eleven new list groups cover complete/partial row boundaries, surrogate/CRLF validation through the shared factory, BOM positioning, mixed endings, blank rows, numbering through two digits, 256/257-row bounds, source/selection/result byte limits, caret/placeholder rules, exact stale snapshots and inert script-shaped text. Earlier source, session, recovery and insertion tests remain included.

All **15 focused AppKit/Transferable groups pass** (`spikes/macos-editor/build/MRK44-native-appkit-20261110.log`). The new group invokes each real native menu target invisibly and checks exact BOM/NFD/emoji/physical endings, preserved blank rows, numbering/task markers, transformed-content selection, native undo/redo, an existing-line marker-only caret and separately undoable typing over an empty-line placeholder. A partial-line menu action is explicitly disabled. Earlier actual-workspace autosave-conflict/recovery and stale-action groups remain included. The known TextKit diagnostic is still emitted during the prior Link undo/redo sequence; source assertions pass and no fix is claimed.

The first shared-test preflight found another lane compiling and stopped before any Markright compile or log was started. Lightweight review continued; a later read-only capacity check showed the competing job had ended before verification resumed. Heavy stages remain serial, reuse owned caches, check at least 20 GiB free and use two build jobs. No unrelated resources or visible app windows are changed.

The unsigned arm64 Mac app builds in the unused Verification product with warnings as errors (`spikes/macos-editor/build/MRK44-native-macos-build-20261110.log`). The iOS app and test targets pass a generic Simulator `build-for-testing` with warnings as errors (`spikes/ios-editor/build/MRK44-native-ios-build-20261110.log`). One new parameterized UIKit refusal test for all three valid list plans compiled but did not run. Existing host provisioning-profile/generic Simulator placeholder diagnostics are preserved; signing is disabled and no boot, install or app launch is requested. Independent lifecycle and privacy review found no scoped blocker. Generated products, synthetic fixtures and logs remain ignored locally; the visible Debug app and existing preview are preserved.

The TextKit nil-content-manager diagnostic during authored Link undo/redo from MRK-43 remains unresolved; adding list commands does not claim a fix. Simulator boot error 22 and the original iOS recovery-input failure remain open without new runtime evidence. Actual OS menu/keyboard/IME/undo, iOS runtime, VoiceOver, physical devices, complete rendering, ingestion/isolation, provider and release acceptance remain gated. Previously denied documentation writes remain preserved without retries or alternate publication.
