# ADR 0002: active-line projection feasibility

Status: MRK-9 in progress, not UI acceptance.

The first prototype separates authoritative source, AST, selection, and preview projection. Ordinary lines reveal source; touched fenced code/table blocks reveal their entire syntax. Nonempty selection ending at a line boundary does not consume the next line. Coordinates are UTF-16 half-open and reject surrogate splits. During marked-text composition the projection is deferred rather than rebuilding widgets or rewriting source. This is a model contract, not tested platform IME handling.

A headless Swift 6.4.2/AppKit TextKit storage probe preserves four Unicode/CRLF cases under presentation attributes and UTF-16 insertions, including combining marks and multi-scalar emoji. No application window was opened. This does NOT prove native iOS TextKit, Liquid Glass, selection, undo, VoiceOver, or actual composition behavior.

## Measurements

Mac, Node v24.15.0, 1,000,000-byte synthetic Markdown document, one local run:

- Full reference parse: 1085.22 ms.
- Reusing AST for 100 projection selections: median 8.23 ms, p95 9.62 ms.

Reproduce with `node scripts/measure-editor.mjs`. These are headless model times, not end-to-end typing latency or robust benchmark distributions. The full parse is far too slow to run synchronously on each keystroke. Incremental/background parsing, indexed block lookup, cancellation, and a source-only fallback are required before adoption. The current planner traverses the AST on every call; this is explicitly a baseline, not the intended production algorithm.

## Framework tradeoffs and remaining gates

Tauri plus shared Rust core remains provisional: it permits native parsing, but introduces Swift FFI and web/native selection parity work. Native SwiftUI with TextKit remains the iOS requirement; a web wrapper does not satisfy it. Compare desktop editor engines using real active-line decorations and widget invalidation before freezing one. Preserve source-only mode as a reliable escape hatch.

Required next evidence: actual desktop/native iOS selection and multi-line edits, IME composition, undo, copy/paste, VoiceOver focus/order, 1 MB interaction traces, malformed nested tables/fences, and native byte-to-UTF16 mapping. No MRK-R8/R14/R15/R21 acceptance is complete from these headless tests.

### Indexed follow-up

The reusable `createProjection` now builds line and atomic-block indexes once per source/AST snapshot. Selection lookup binary-searches those indexes instead of walking every AST node. A later 1 MB run under shared-machine load measured full parse 3947.92 ms, index construction 98.93 ms, selection p50 0.00129 ms and p95 0.01229 ms. The different parse timings demonstrate machine/load sensitivity, not a parse regression benchmark. Source edits require a new matching source/AST snapshot; never use a stale projection for mutated source. Parsing/index construction still belongs off the interactive path. These figures still exclude actual UI rendering.
