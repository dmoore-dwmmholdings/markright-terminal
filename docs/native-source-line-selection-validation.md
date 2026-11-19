# MRK-52 native source-line selection

This feature is ported from the spike branch `spike/native-source-line-selection` (`f7fc1b8`, `0a1668f`) onto `main`. Only the source-line selection parts are kept. The spike's MRK-47/48/49/51 outline, selection-find and heading-quote parts are not included. The small selection-only navigation plan (`SourceNavigationPlan`) and the AppKit save gate that the feature needs are ported with it.

## Behavior

The native whole-document context menu adds **Select source lines**. It expands the current caret or selection to the complete physical rows it touches, including their original CR, LF or CRLF endings.

- A nonempty selection that ends exactly at the start of a later row does not include that row.
- The destination excludes the initial BOM, even when the original selection included it. Internal BOMs stay literal.
- A caret at EOF without a trailing ending selects the final nonempty row.
- An empty EOF row after a trailing ending has no action. An interior blank row selects its ending.
- An already-expanded selection has no action.

The feature selects literal physical rows. It does not parse Markdown blocks, insert or replace source, resolve references, access files, providers or the clipboard, use the network or run scripts.

Source is limited to 1 MiB UTF-8 before the native string bridge or range arithmetic. The original UTF-16 endpoints must pass the existing surrogate and CRLF validation. The plan keeps the exact original source and selection. Execution checks again that the editor is attached, focused and editable, has one selection and no marked text, and still has the captured source and selection.

The action only moves the native selection and reports it through the existing selection reporter. It does not change the source, the text undo stack, the editor generation or focus.

## AppKit save gate

On `main`, the AppKit whole-document workspace scheduled a save on every editor report, including a selection-only report. That rewrote the recovery checkpoint when only the selection moved. The workspace now schedules a save only when the source revision or the composing state changes. The iOS editor already used this rule (`onChange(of: sourceRevision)`).

## Verification (MRK-52 branch)

| Check | Result |
| :- | :- |
| Shared `swift test` (warnings as errors) | Pass, 171 tests (11 new source-line tests) |
| AppKit native checks | Pass, 18 groups (new source-line group: menu and root validation, exact selection, focus and typing undo/redo kept, stale/read-only/non-source/multiple/marked/detached refusals, clean and conflicted workspace files and recovery checkpoint unchanged after 650 ms) |
| Node tests | Pass, 89 |
| Playwright (default config) | Pass, 33 passed, 1 skipped |
| Unsigned macOS app build | Pass |
| Unsigned iOS build-for-testing | Pass |
| iOS simulator runtime tests | See the PR description |

## Open gates

Attached UIKit runtime behavior, actual OS menus, keyboard and IME input, VoiceOver, physical devices and release acceptance remain open.
