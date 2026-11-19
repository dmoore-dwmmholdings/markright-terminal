# MRK-47 native source outline

This feature is ported from the spike branch `spike/native-heading-navigation` (`b02cf51`, `7ccb7b8`) onto `main`. Only the MRK-47 heading-navigation parts are kept. The spike's own navigation plan and AppKit save gate are not ported again: `main` already has `SourceNavigationPlan`, its native apply path and the selection-only save gate from MRK-52 (PR #3). Heading navigation reuses them. The MRK-51 outline label bounds work is not included.

## Behavior

The native whole-document source editor gains a **Document outline** submenu, in the macOS contextual menu and the iOS text edit menu. Each entry shows the heading level, the physical line number and a literal title. Choosing an entry selects and scrolls to that heading row in the same editor.

The shared scanner (`SourceOutline`) accepts at most 64 KiB of UTF-8 source and 128 headings. It recognizes top-level ATX rows: one to six `#` marks, zero to three leading spaces, then a space, tab or end of row.

- Ranges are global UTF-16 offsets into the exact source. Physical line numbers keep LF, CRLF and CR distinct. An initial BOM stays in the source but is outside every heading range.
- Fenced bodies (backtick or tilde, same character, at least the opening length, whitespace-only closing tail) are skipped, including an unclosed fence through EOF.
- A backtick fence with a backtick in its info string, or any `<` outside fenced code, disables the whole report with an explicit message. This also refuses plain text that contains `<`. No HTML or full Markdown parser is claimed.
- Above 64 KiB, above 128 headings, or with no headings, the menu shows one disabled explanatory item, never partial results.
- Labels are literal. Control characters and Unicode line or paragraph separators become spaces. Labels longer than 80 characters end in a visible ellipsis. Empty headings show `(empty heading)`. Setext and nested container headings are out of scope.

Each entry carries a `SourceNavigationPlan` captured against the exact source and selection. Execution goes through the existing `applySourceNavigation`, which checks again that the editor is attached, focused and editable, has one selection and no marked text, and still has the captured source and selection. On iOS the capability is limited to the whole-document source field (`allowsSourceNavigation`, renamed from MRK-52's `allowsSourceLineSelection`, which now covers both selection-only actions).

The action only moves the native selection and reports it. It does not insert text, change the undo stack, the editor generation or focus, render Markdown, resolve URLs, or access files, storage, the network, providers, scripts or the clipboard.

## Verification (MRK-47 branch)

| Check | Result |
| :- | :- |
| Shared `swift test` (warnings as errors) | Pass, 181 tests (10 new outline tests) |
| AppKit native checks | Pass, 19 groups (new outline group: literal menu titles, fenced heading excluded, exact heading selection, focus and typing undo/redo kept, stale source/caret, read-only, non-source, multiple-selection, marked-text and detached refusals; clean and conflicted workspace bytes, modification dates and recovery checkpoint unchanged after 650 ms) |
| Node tests | Pass, 89 |
| Playwright (default config) | Pass, 33 passed, 1 skipped |
| Unsigned macOS app build | Pass |
| Unsigned iOS build-for-testing | Pass |
| iOS simulator runtime tests | Not run: the focused run on a dedicated iOS 26.5 simulator stayed idle with no test output and was stopped after 10 minutes |

## Open gates

Attached UIKit runtime behavior, actual OS menus, keyboard and IME input, VoiceOver, physical devices, full ATX/CommonMark/Setext outline semantics and release acceptance remain open.
