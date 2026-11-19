# MRK-50 native task-marker source candidate

This feature is ported from the spike branch `spike/native-task-marker-state` (`6339b80`) onto `main`. Only the task-marker parts are kept. The spike's MRK-47/48/49 outline, selection-find and heading-quote parts are not included. It is a literal source-editing feature, separate from the production authoring and parser work.

The native whole-document context menu adds **Toggle task markers**. Put the caret anywhere on one physical row, or select whole physical rows. An accepted task prefix has zero to three ASCII spaces, `-`, `+` or `*`, one ASCII space, `[ ]`, `[x]` or `[X]`, then an ASCII space/tab or end of row. Selected blank ASCII-space/tab rows stay unchanged. Any other selected row refuses the entire edit. At least one accepted marker is required. If any is unchecked, unchecked markers become lowercase `x` and existing `x`/`X` bytes stay unchanged; if all are checked, they become spaces.

This command edits explicitly selected literal source. It does not determine whether Markdown surrounding that row makes it a rendered task: a matching source row inside a fence can still be explicitly edited. It does not add a rendered checkbox, parse surrounding context, execute code, access a reference/URL/file/provider, read clipboard contents, or use network capability. Unsupported syntax leaves the action disabled.

Source is limited to 1 MiB UTF-8, the actual replacement to 64 KiB UTF-8 and a batch to 256 physical rows. The caret's replacement range expands to its row body, excluding the ending. A selected batch uses exactly the selected whole-row range, including endings/BOM when selected. Leading BOM, body Unicode and every other byte remain unchanged. Strict UTF-16/surrogate/CRLF boundary validation applies. Carets at the start of a new physical row belong to that new row; an EOF caret after a final ending has no task row.

The captured original selection is checked separately from the replacement range. All existing insertion plans default that capture to their original range. Exact-byte source and selection checks refuse retained actions after either changes. Task mutations keep the original caret/selection offsets, use the existing native text/report path and name a separate undo action. AppKit uses its explicit replacement-range input API; UIKit temporarily selects the expanded range before native insertion, then restores the captured selection.

## Exact undo and redo

A task-marker plan sets `restoresSelectionOnUndo`. The editor registers one selection step before the native insertion and one after it, in the same undo group. Undo restores the exact original source bytes and the original selection (caret or whole rows). Redo restores the toggled bytes and the selection after the edit. Each step registers its mirror, so repeated undo/redo cycles stay exact. If the insertion is refused, the selection steps are removed. Other insertion plans keep their earlier undo behavior.

## Verification (MRK-50 branch)

| Check | Result |
| :- | :- |
| Shared `swift test` (warnings as errors) | Pass, 160 tests |
| AppKit native checks | Pass, 17 groups (task-marker group includes 3 exact undo/redo cycles, batch undo, later-row partial batch undo) |
| Node tests | Pass, 89 |
| Playwright (default config) | Pass, 33 passed, 1 skipped |
| Unsigned macOS app build | Pass |
| Unsigned iOS build-for-testing | Pass |
| iOS simulator runtime tests | Not run: the simulator run stayed idle with no test output and was stopped after 10 minutes |

The spike's AppKit stale-caret check split a combining sequence and failed. It now places the stale caret on a grapheme boundary.

## Open gates

UIKit attached runtime behavior (including `testAttachedTaskUndoRedoRestoresExactBytesAndCaret`), attended VoiceOver, actual OS menus, keyboard and IME input, physical devices and release acceptance remain open.
