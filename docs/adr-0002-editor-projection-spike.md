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

### Native iOS simulator interaction evidence

A separate SwiftUI/UITextView interaction spike now builds and runs headlessly on its own iPhone 17 Pro/iOS 26.5 simulator, coordinated with other workers. Three model tests and one XCUITest pass. The UI test verifies active source/preview transitions, literal punctuation preservation through Done/reactivation, unchanged neighboring source and a full fenced-block source editor. An independent source review caught default keyboard transformations and a weak edit-survival assertion; both were corrected and tests rerun.

This is stronger than the earlier macOS storage probe but remains fixture-level. Code/table previews are still source-like; grouping is not the shared parser, structure changes are not reparsed, and cross-block selection/undo, actual IME/VoiceOver, 1 MB input-to-paint, iPad and physical device acceptance remain open. See `spikes/ios-editor/README.md`. No physical devices, user documents or production services were touched.

### Large-document and native marked-text smoke

The isolated phone and iPad simulators each pass four native tests plus two UI tests. Added a real UIKit marked-range/coordinator probe (not real keyboard IME) and a 1,000,000-byte lazy-row fixture that can enter editing, type, preview and re-enter without losing the source. This is an interaction smoke, not measured p95 paint latency; broad accessibility, cross-block undo/selection and full Markdown grouping/rendering remain gates. Both dedicated simulators were shut down after use.

Review identified a lazy-view teardown risk for composing text. Explicit teardown/end-edit handling now commits visible marked text and clears the guard. A phone native test exercises that path with exact expected source; five native plus two UI tests pass on phone. Real keyboard composition while scrolling away/returning remains a separate gate, and the iPad run predates the final teardown addition.

### Desktop editor candidate evidence

A local CodeMirror/Lezer candidate now passes fifteen headless Chromium/WebKit checks on this Mac, with one Chromium-specific composition probe explicitly skipped on WebKit. Tests exercise source-preserving preview decoration, literal punctuation, enclosing code/table source editing, inert HTML-shaped text, cross-block undo and a 1 MB edit smoke. Prose keyboard transformations are disabled. No browser window, website publication or desktop shell was launched.

This favors a source-native editor candidate over treating rich-text output as the authoritative document, but it does not freeze CodeMirror/Tauri. Rendering is partial, primary-selection-only, and separate from the tentative native Comrak core. Physical Windows/Linux, real webview shell integration, screen readers/OS IME and p95 input-to-paint remain gates. Browser test durations are not latency acceptance.

Desktop review reproduced a caret-at-atomic-block-end defect in both engines. Boundary regressions now cover fences/tables at EOF and following empty lines; two-sided node resolution fixes the gap without broadening the subsequent empty line. Fifteen browser checks pass; the WebKit CDP composition case remains explicitly skipped.

### Automated accessibility findings and corrections

Native `.all` preview-screen audits initially failed on touch target size, caption/button contrast and toolbar Dynamic Type. Each was fixed rather than filtered: minimum 44-point preview targets, primary caption contrast, and a body-font bottom action with high-contrast tint. The full phone and tablet suites now each pass five native plus four UI tests, including both light and dark audits. Actual VoiceOver navigation, active-editor auditing and real keyboard composition/scroll-away remain explicit downstream validation needs. The line-button prototype's larger touch spacing is also a UX tradeoff to resolve in the integrated editor, not a frozen final layout.

## Shell/core comparison and research recommendation

| Option | Fit | Tradeoff and decision |
| --- | --- | --- |
| Tauri + CodeMirror desktop, Rust core | Existing Rust parser candidates, source-authoritative web editor, narrow capability bridge | Recommended for the next desktop implementation experiment, not selected/frozen until MRK-12. System webview differences require Windows WebView2/Linux WebKitGTK acceptance. Current Chromium/WebKit tests on Mac do not prove those shells. |
| Electron + CodeMirror | Consistent bundled Chromium and mature worker process tooling | Valid fallback if system-webview parity or packaging fails. Larger bundled runtime/update surface; strict sandbox/context isolation still required. No footprint claims are measured in this spike. |
| Fully native per-desktop-platform editor | Native accessibility/input conventions | Reject as first shared desktop path: three editor integrations multiply source-map/IME/undo work. Could revisit for evidenced platform failures, not preference alone. |
| SwiftUI + UITextView/TextKit iOS, narrow Rust bridge | Native iOS UI/Liquid Glass direction, demonstrated source edits and marked-text callbacks | Carry forward as native candidate. Fixture grouping is not a production Markdown renderer; bridge/structural reparsing and real VoiceOver remain unresolved. Do not replace with desktop web wrapper. |

Shared core recommendation: prototype Comrak through a narrow versioned Rust API for parser/source coordinates, with JS reference fixtures as compatibility oracle rather than two independently evolving language definitions. Keep filesystem grants, key storage, renderer and UI services outside parsing. Rust proof is a command-line comparison, not an already integrated Swift/Tauri bridge. FFI must handle cancellation, UTF-8 ownership/lifetime and error bounds without throwing across ABI boundaries.

## Consolidated editor source contract

- The original source is authoritative. Preview is a projection of an immutable revision, not a source reconstruction. Parse results carry revision identity; discard stale results after edits.
- UI positions are zero-based UTF-16 half-open ranges. Reject surrogate-splitting selections; convert native UTF-8 positions explicitly and treat missing ranges as unmappable rather than guessing.
- Activate the current line except when source belongs to an atomic fence/table, where the enclosing block is active. Exact end-of-block and next-line-start ownership must be distinct (desktop boundary regression now covers both).
- Map decorations through edits while composing; do not replace active marked text or change smart punctuation. Commit/unmark deliberately at teardown. Actual input-method navigation remains separate from programmatic marked-text probes.
- Edits, undo and selection operate on source first. Preview changes cannot enter undo history as text mutations. Source export/save retains original BOM/line-ending policy, including untouched neighbors.
- Background/incremental parsing plus cached range indexes is required for large documents. Measured 1 MB parse time of approximately1–4 seconds rules out whole-document synchronous keystroke parsing. Indexed lookup p95 approximately0.012 ms is a model lookup, NOT end-to-end input latency. No p95 paint target has passed.

Latest evidence: desktop15 passing browser tests/1explicit WebKit CDP-IME skip; both native phone/tablet5 native+4 UI passes, including all automated accessibility audit types in light/dark preview. An actual attended VoiceOver experiment is outstanding and keeps MRK-9 open. The plan in `mrk9-attended-voiceover-plan.md` defines stop/restore rules and observations. Further native cross-block selection/undo, real keyboard composition/scroll-away, full Markdown semantics and performance remain recorded limitations. MRK-12 must evaluate these findings before freezing contracts; downstream MRK-20/21/26/27/33 still own complete product/platform acceptance.
