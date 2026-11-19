# MRK-46 native companion preview

Ported onto main after MRK-50, MRK-52, MRK-47 and MRK-51. The Mac source callback keeps main's selection-only save gate (a selection-only report does not schedule an autosave); the preview sits beside the source editor in a stable split container. The preview is research, not a complete inline editor, renderer or parser freeze. It relates to pinned MRK v2 R8/R15.


## Intended workflow and boundaries

Enable **Live preview** to view current in-memory text beside the Mac source editor or below the iOS source field. Inactive supported rows receive Foundation inline styling; active units and recognized backtick/table units remain literal source. Mac document rows also identify the currently open file. The source editor remains the authority: preview has no source binding, edit callback, navigation action, selectable text, Link/Image view, file access, URL resolution, script execution or network capability.

The projection reuses the existing fixture-level EditorModel grouping rather than a complete Markdown parser. It retains each unit's original source/separator and global UTF-16 range. Carets belong to the unit owning that position, including left-owned separators and the final EOF unit; nonempty selections use half-open intersections. Strict range checks reject surrogate/CRLF interior endpoints without changing source or selection.

Processing accepts at most 64 KiB of source and displays at most 256 fixture units. Inline parsing is limited to 4,096 UTF-16 units per row. Oversized, invalid-selection and composition states show an explicit unavailable/paused message with no partial truncation. Active, atomic, long and marker-bearing HTML/image/directive rows remain literal. Row-level unsupported markup is not a full context parser. An unrecognized tilde/indented-backtick fence-like unit keeps the entire report literal and explains the fallback, avoiding styled text inside a possible code body. Attributed link targets are cleared on all paths.

Mac source remains the unconditional first child of a stable split container, using the existing session/generation identity and callback. iOS source mode uses a retained VStack, with its existing fixed-height source editor and a separate fixed-height preview. This avoids relying on lazy-row identity to retain the editor when scrolled out of view. These are implementation guarantees to verify; no iOS runtime retention or cross-mode undo acceptance is claimed.

## Evidence on this branch

| Check | Result |
| :- | :- |
| Shared `swift test` (warnings as errors) | Pass, 195 tests (14 new projection tests) |
| Native AppKit runner (`run-native-collection-checks.py`) | Pass, 20 required groups, including preview data retention |
| Rendered preview observation (hidden-host semantic AX) | Not passed: open gate, reported by the runner |
| Node `npm test` | Pass, 89 tests |
| Playwright desktop (`spikes/desktop/playwright.config.mjs`) | Pass, 33 passed, 1 existing WebKit skip |
| Unsigned macOS app build (warnings as errors) | Pass |
| Unsigned iOS generic Simulator `build-for-testing` (warnings as errors) | Pass, compile only |
| iOS Simulator runtime | Not run |

The preview data-retention group verifies actual pane attachment and detachment, the original source view and scroll containers, caret, focus and undo-manager retention, native insert/undo/redo, marked-text retention and composition pause, unchanged settled disk bytes and the current conflicting recovery checkpoint after 650 ms, Save As, and a document switch with a fresh native source and projection.

## Rendered observation is an open gate

A hidden NSHostingView exposes no SwiftUI semantic accessibility, even for a plain SwiftUI control in the same probe, so the runner cannot observe the rendered panel text, literal rows or the Open marker. On the spike branch, white-composited raster captures were reviewed by eye and showed the expected styled and literal rows; that is diagnostic, not acceptance. The default runner prints `OPEN GATE (not passed)` for this group and continues. `--require-rendered-observation` makes it a hard failure. `--preview-snapshots` writes synthetic offscreen captures to a fresh ignored folder.

The separate visible-AX calibration experiment (`spike/mrk46-visible-ax-calibration`) is not part of this branch.

## Open gates

Real window rendering, theme and contrast, VoiceOver and spoken order, controller-host and OS keyboard/IME input, the iOS Simulator runtime, physical devices, ingestion, isolation, providers, security and release remain open. Existing TextKit, simulator boot and recovery-input blockers are unchanged.
