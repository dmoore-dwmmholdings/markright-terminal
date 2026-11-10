# MRK-45 native table source authoring

This research slice adds **Table** to **Insert Markdown** on native macOS and iOS whole-document Source editors. It creates a source starter or converts an explicitly selected tab-separated grid. It relates to pinned MRK v2 R9/R15; full table editing, alignment controls, semantic rendering and complete authoring remain open.

## Source workflow

At a truly empty physical-row caret, **Table** inserts two header columns, a delimiter row and a data row, selecting `Value 1` for ordinary typing. Added lines use the first document CRLF, CR or LF, with LF fallback. No final line ending is added; an existing suffix ending remains untouched. A caret after an absolute leading BOM is supported, while a caret before that BOM or on a nonempty/whitespace-only row is refused.

Select complete physical rows containing a rectangular tab-separated grid to convert it into pipe-table source. The first row supplies headers; the helper inserts one delimiter row after it using that header's original ending. Every original row retains its original ending, including mixed CRLF/CR/LF and an optional trailing ending. A terminal ending does not create a phantom row. Existing tabs become cell separators and pipe-table syntax is added; accepted cell text is not trimmed, normalized, parsed or escaped. Outside bytes and an absolute leading BOM retain their positions.

The selection moves to the first data cell. An empty first cell receives a zero-length caret, so typing can fill it without replacing table syntax. Selected work must contain 2–16 columns and 2–64 physical rows, with equal column counts. Some empty cells are allowed; entirely whitespace/empty grids, ragged rows, partial-line selections and cells containing pipes, backslashes or controls are refused. These limits describe a source-conversion subset, not arbitrary TSV import or complete Markdown table parsing. Surrounding Markdown context is not isolated or interpreted.

The helper independently validates UTF-16 ranges before slicing and enforces the existing 1 MiB complete-source/result and 64 KiB selection bounds. Source snapshots and replacement ranges remain unchanged in the native plan, with exact stale-source/selection, weak-view, attachment/focus/editability/composition/single-selection and whole-document scope guards. Native insertion/undo and the existing final coordinator report apply the source edit without rebinding, resetting generation or acknowledging a save/recovery checkpoint.

No clipboard is read: the grid must already be selected source. No file importer, URL resolution, asset/provider grant, network capability, script execution or incoming document route is added. Cell markup remains literal source; no rendered-value round trip is claimed.

## Verification

The shared Mac corpus passes **144 tests**, zero failures, with Swift warnings as errors (`spikes/macos-editor/build/MRK45-shared-core-macos-20261110.log`). Ten new table groups cover empty-row starters, first-data-cell selection including empty cells, direct forged-range refusal, whole-row and BOM handling, minimum/maximum/ragged dimensions, unsupported cells, exact byte/output limits, mixed row/header endings, stale snapshots and inert script-shaped source.

All **16 focused AppKit/Transferable groups pass** (`spikes/macos-editor/build/MRK45-native-appkit-20261110.log`). The new group invokes the real Table menu target for starter, selected TSV and empty-first-cell cases, checks exact BOM/NFD/emoji/cell/ending/outside bytes, types into the first cell, separately undoes typing and insertion, and redoes insertion. Windows remain invisible, no OS menu is shown and the real collection root is untouched. The sibling-container refusal fixture passes its original focus/stale/marked/multiple-selection/detached assertions. The earlier Link/TextKit diagnostic persists in the same sequence; no production resolution is claimed.

The unsigned arm64 Mac app builds in the unused Verification product with warnings as errors (`spikes/macos-editor/build/MRK45-native-macos-build-20261110.log`). The iOS app and test targets pass a generic Simulator `build-for-testing` with warnings as errors (`spikes/ios-editor/build/MRK45-native-ios-build-20261110.log`). One new UIKit refusal method covers valid selected-grid/starter plans in detached/out-of-scope views; it compiled but did not run. Existing host provisioning-profile/generic Simulator placeholder diagnostics are retained; signing is disabled and no simulator boot/install/launch is requested. Independent lifecycle/privacy review found no scoped blocker.

Verification uses owned caches and serial stages, with two build jobs and at least 20 GiB free checked before heavy work. The debugger investigation runs separately from builds. Generated projects/products, synthetic fixtures and logs remain ignored locally; the visible Debug app, preview and other workers' artifacts are preserved.

## TextKit and simulator investigation

A single bounded LLDB run used the already-built private MRK-44 probe, with user initialization files disabled and ASLR retained. It attached to no existing application and changed no OS security settings. The named TextKit diagnostic breakpoint resolved in UIFoundation but did not stop execution despite the diagnostic appearing. The fixture completed its 15 groups and exited zero; the subsequent backtrace command failed because no process was stopped. LLDB exited one, no stack was captured, and no owned fixture process remained. The ignored record is `spikes/macos-editor/build/MRK45-textkit-owned-lldb-20261110.log`.

That run also reported a concrete unsupported fixture hierarchy: a private AppKit focus sentinel was inserted inside `NSHostingView`. The refusal fixture now places the sentinel and hosting view as siblings in a common AppKit container, matching SwiftUI's diagnostic guidance. Assertions are unchanged and production UI is untouched. This corrects a test setup problem; it does not establish the cause or a fix for the separate TextKit nil-content-manager diagnostic. Event grouping disabled with balanced undo groups is supported by the installed Foundation header and is not by itself a demonstrated fault.

No new simulator/recovery runtime evidence exists since MRK-44. Generic builds provide no owned boot trace or input-phase result. Boot error 22 and the original UIKit recovery-input failure remain unexplained, and no boot retry, device/runtime/service reset or unsupported repair was performed.

Actual OS menus/keyboard/IME/undo, iOS runtime, VoiceOver, physical devices, full grid/rendering behavior, untrusted ingestion, isolation, providers and release acceptance remain gated. Held documentation-service drafts remain preserved without retries or alternate publication.
