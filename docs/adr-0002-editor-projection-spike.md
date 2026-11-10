# ADR 0002: active-line projection feasibility

Status: MRK-9 in progress, not UI acceptance.

## Native selection continuity — November 10, 2026

The native prototype stores per-block UTF-16 selection extents and document bookmarks tied to exact source revisions. Mode transitions map valid local/document ranges without joining the whole document on selection-only callbacks; whole-source regrouping invalidates block IDs. Invalid/overflow, surrogate and CRLF-interior ranges are cleared rather than clamped, without discarding accepted source edits. Canonical Unicode equality cannot stand in for byte identity. Stale source/composition/selection callbacks are rejected together before mutation. Editor generation IDs isolate coordinators; restored ranges are installed before delegates, and one-shot window attachment focus makes them usable without another tap. Ordinary updates do not rewrite native selection or marked text.

An independent review found that a missing/invalid local bookmark could be promoted to a different global position through the fallback getter. Mapping now requires an explicitly stored valid bookmark; regression coverage also verifies stale block-range rejection. Nine new native groups cover source coordinates, canonical-equivalent edits, source revisions, cross-block/EOF mapping, invalid ranges, actual UIKit replacement/marked text and a 1 MB document bookmark. Two new UI flows type at restored carets without tapping the editor.

Full result: **33 native/model/decoder + 12 UI tests pass**, zero failures/skips, Swift warnings as errors (`spikes/ios-editor/build/MRK9-native-selection-full-20261110.xcresult`). Includes all four unfiltered preview/reading audits, rendered-caption OCR and the existing 1 MB interaction smoke. The sole owned iPhone Duo/iOS 27.2 simulator was restored to Shutdown. No runtime download, physical device, credentials, infrastructure or deployment was used. Commits remain local while the repository destination is resolved.

This preserves selection extent, not direction/affinity, prior viewport, cross-mode undo or cross-launch state. Exact comparison/validation costs can scale with source length; no p95 performance, large-document screen-reader, real IME/VoiceOver, current iPad/physical-device, full parser/renderer, isolation/ingestion/security or release acceptance is claimed. MRK-9/12 and the existing gates remain open.

## Native Swift reading mode — November 10, 2026

The iOS prototype now has explicit reading mode with static native text and no edit-row actions. Entry commits/regroups whole-source edits and invalidates old callbacks; exit invalidates again and returns to preview/editing. Composition blocks transitions. Generation checks reject stale source/composition callbacks before mutation, including repeated reading entry. Exact BOM/mixed-ending source remains authoritative. Links are removed from attributed previews so reading text adds no URL-opening capability. This remains partial fixture rendering. At that reading-mode checkpoint, native cross-mode undo/selection restoration was not implemented; the selection follow-up above adds range bookmarks.

Actual audit findings drove natural text sizing, stable action identity in the adaptive footer and bounded retention of short reading documents during Dynamic Type relayout. At most 128 blocks and 65,536 UTF-16 units remain mounted; larger documents retain lazy rendering, with no truncation or source rewrite. A four-case native budget test checks both limits. These are resource/interaction experiment choices, not frozen production budgets or proof of large-document screen-reader behavior.

Final owned iPhone Duo/iOS 27.2 run passes **24 native/model/decoder tests and 10 UI tests**, zero failures/skips, with Swift warnings as errors: `spikes/ios-editor/build/MRK9-native-reading-verified-20261110.xcresult`. All four full light/dark preview/reading accessibility audits pass, plus direct block/whole-source transitions, stale callbacks, exact source re-entry and an extended 1 MB edit → read → edit smoke. Independent review found no semantic blocker. No actual VoiceOver, real keyboard IME, current iPad/physical-device or latency acceptance follows.

Visual QA found a missing button caption that accessibility metadata alone did not catch. A mode-specific button identity corrected the rendering, and the final transition test verifies the visible caption with on-device Vision OCR of its synthetic screenshot. No upload or document analysis service is used. Action orientation currently follows Dynamic Type size; narrow windows/localization remain unverified.

Original failed audits/test assertions and diagnostics are preserved. Same-device unchanged `c094525` dark-preview baseline passed; the new findings were treated as regressions. A leading-whitespace presentation assertion was corrected while retaining exact raw-source checks. Audit diagnostic handlers return false for every issue, preserving all categories/failures. The sole owned simulator was restored to Shutdown. No runtime download, signing credential, Firebase, deployment, physical device or other worker artifact was used; the desktop preview/Debug window was preserved. Source security/ingestion, isolation, VoiceOver, device/distribution/release and MRK-9/12 gates remain open. The separate GitHub destination investigation is in `github-destination.md`; no remote was guessed or repository created.

## Desktop reading-mode follow-up — November 10, 2026

The reading-mode experiment adds read-only all-line partial preview. Compartment reconfiguration retains exact-source metadata, directional selection and history, remembering the prior live/source editing mode. EditorState.readOnly, EditorView.editable and ordinary transaction rejection work together; custom paste refuses early. Trusted host state replacement/filter bypass remains possible, so this is UI policy, not isolation or permission for document code. Both controls retain compositionStarted guards. Explicit refresh handles reuse of the same preview plugin across live/reading transitions.

After the first attempt stopped below the 20 GiB resource threshold before bundling/browser launch, safe cleanup restored about 47 GiB. Sequential verification now passes all 87 Node groups, 33 browser checks (one existing explicit WebKit CDP-composition skip) and 12 scoped offscreen system-WebKit groups. The reading checks cover immediate preview refresh, exact mixed endings/reverse selection, focused keyboard/paste/history refusal, remembered source mode and composition. Native probes use authored DOM clicks/delivered paste, not OS keyboard/clipboard input. Independent review found no blocker.

Logs are `spikes/macos-editor/build/reading-mode-node-final-20261110.log`, `reading-mode-browser-20261110.log`, `reading-mode-native-20261110.log` and `reading-mode-host-20261110.log`. The original resource-stop log and previous results remain. The unsigned separate Verification app builds with Swift warnings as errors; visible Debug app/tabs were not rebuilt/reloaded. Own Mac build storage is about 304 MiB, desktop build about 1 MiB. No simulator/download/cleanup or other worker artifact was used by verification.

The same-run raw WebKit navigation comparator still observed one speculative TCP connection and no additional application bytes; guarded request and teardown probes observed zero additional TCP in that run. These bounded observations do not establish network/process isolation. Real OSIME/VoiceOver, complete renderer/latency, ingestion/security/physical/device/distribution/release and MRK-9/12 gates remain open. No production requirement is accepted by this checkpoint.

## BOM-prefixed reference projection correction — November 10, 2026

The reference AST's coordinates previously ignored the first source BOM. This truncated closed fences and returned an empty range for an unclosed fence's EOF caret; even an emoji's mapped end could split a surrogate pair. `analyze` now maps the parser's BOM-relative positions into exact original-source UTF-16 coordinates before projection/ownership/extraction. The root retains origin zero; first-line columns and all end offsets include the BOM. Only one BOM is semantically ignored, matching the pinned dependency.

New document/projection regressions first failed and now pass across LF/CRLF/CR, including first-line file cards and inert nested constructs. All 37 targeted and 84 full-suite Node test groups pass; evidence and implementation detail are in ADR0001. Independent review found no blocker. A separate in-memory adapter review passed 16,000 raw edits with full undo/redo histories and 328,786 source/editor round trips without a new defect; these are additional review probes, not committed test groups or security acceptance. No desktop/native bundle, browser, simulator or app build ran at 19 GiB free. Existing builds/previews and all MRK-9/12, network-isolation, VoiceOver, ingestion, physical/device/distribution/release gates remain unchanged.

## Desktop whole-document source mode — November 9, 2026

The desktop research editor now has an explicit Source mode control. A CodeMirror compartment removes/reinstalls only preview decorations without rebuilding state, preserving raw-source separator metadata, reverse selection and edit history. Keyboard activation returns focus to the editor. This is an editing mode; a read-only reading mode and complete renderer remain absent. Parsing continues, so no performance fallback or latency claim follows.

Independent review identified a transition gap before the first composition edit: `view.composing` is false in that phase. A new synthetic compositionstart/selection-update/forced-click regression failed in both browser engines before all toggle/control/projection guards switched to `compositionStarted`. Final evidence is 29 browser passes/1 existing WebKit CDP-composition skip (`spikes/macos-editor/build/desktop-source-mode-browser-final-20261109.log`) and11 scoped offscreen system-WebKit groups (`desktop-source-mode-native-final-20261109.log`), including exact mixed-ending source and directional selection through both modes. Browser checks also prove undo/redo and keyboard focus survive transitions. Failed log/error contexts are retained separately from final results.

The final bundled assets build into the unused separate unsigned Verification app with Swift warnings as errors (`desktop-source-mode-host-final-20261109.log`). Existing visible Debug app/preview tabs were preserved; preview reload exposes the control but discards temporary edits. This evidence does not prove OS IME/clipboard, VoiceOver/accessibility acceptance, all desktop shells, persistence, read-only reading mode, native iOS changes or network isolation. MRK-9/12 and security/ingestion/physical/device/distribution/release gates remain open. No simulator/download or other workers' artifacts were used.

## Retained system-WebKit view teardown — November 9, 2026

A delayed authored navigation reproduced a lifecycle gap: the old `stop()` cleared delegates while leaving its loaded page alive, allowing a retained view to reach the loopback trap and commit a response after teardown (TCP/nonempty-receive delta `[1, 1]`, `spikes/macos-editor/build/teardown-before-session-20261109.log`). The previous stale-`didFinish` check alone did not cover this.

The research WebView now strongly owns a stopped-state refusal delegate, installs it before stopping loading, and refuses all covered native `load(URLRequest)` calls after stop. Controller callbacks are cleared/guarded; releasing the controller leaves the sentinel intact without a retain cycle. JavaScript is still alive: this is navigation/dialog lifecycle hardening, not process termination or network isolation.

Ten scoped offscreen groups pass (`build/teardown-source-final-20261109.log`), including an armed delayed attempt after controller release, exact source/URL retention, no additional application bytes, inert dialogs, repeated stop and rejected covered native loads. Observed teardown TCP delta zero is not a universal guarantee. Independent review found no blocking issue. Uncovered loaders/download/history APIs, already-started operations, speculative connections, VoiceOver, untrusted ingestion, physical/distribution and release acceptance remain open. Failed sandbox/compilation diagnostics and the before-fix evidence are retained; the visible Debug app and preview remain untouched.

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

Earlier evidence: desktop 15 passing browser tests/1 explicit WebKit CDP-IME skip; both native phone/tablet 5 native+4 UI passes, including all automated accessibility audit types in light/dark preview. The subsequent approved Mac VoiceOver attempt in `mrk9-attended-voiceover-plan.md` could not capture reliable announcements or focus evidence; the prior setting was restored. An attended listener or reliable output capture, plus a separate native iOS VoiceOver check, remain outstanding and keep MRK-9 open. Further native cross-block selection/undo, real keyboard composition/scroll-away, full Markdown semantics and performance remain recorded limitations. MRK-12 must evaluate these findings before freezing contracts; downstream MRK-20/21/26/27/33 still own complete product/platform acceptance.

## Empty EOF fence ownership and source-fidelity audit — November 9, 2026

Independent model review reproduced an unclosed-fence boundary defect: with source `` ```js\nx\n ``, a caret on the final empty line revealed an empty range instead of the enclosing fence. The same regression failed in both desktop browser engines before correction. The indexed model now retains an EOF-owned code start from the matching reference AST; the desktop candidate checks the Lezer fence's closing-marker ownership. Closed fences, tables and indented code still leave a following empty line separate. Container regressions distinguish the unmarked empty line outside a quote from an EOF-owned fence in a list. Independent source review found no blocking issue in these scoped fixes.

Current checkpoint: 70 Node tests and 17 desktop browser checks pass, with the existing WebKit CDP composition test explicitly skipped. Model fixtures cover LF, CRLF and CR. No native code changed or native UI suite was rerun in this checkpoint; the prior native evidence above remains historical.

At checkpoint b137de4, the desktop source-fidelity claim was limited to LF fixtures. A direct dependency probe confirms `EditorState.create({doc: 'a\r\nb\rc\n'}).doc.toString()` yields `a\nb\nc\n`: that harness normalized line endings on load, so its offsets did not map directly to original CRLF bytes. The browser prototype must not write imported document bytes without a tested adapter. A production adapter must preserve original per-line separators (including mixed endings), map editor offsets to the immutable source revision, and verify edits, paste and undo without changing untouched bytes. Setting one global line separator alone does not preserve mixed endings. The follow-up below records subsequent progress; MRK-12/20 integration remains separate from a format change.

## Source-buffer follow-up — November 9, 2026

The LF-only limitation above is now addressed for tested desktop source-buffer paths, not complete file-editor acceptance. `spikes/desktop/source-buffer.mjs` stores each original physical separator independently of normalized CodeMirror text. Offset conversion retains BOM/Unicode and rejects CRLF/surrogate interiors. Raw delivered text insertions carry exact separator effects, and history inversion restores deleted and changed separators. A canonicalizing transaction filter handles edits that join CR and LF into one physical CRLF, including metadata-only changes to an otherwise identical editor document. Ordinary keyboard newlines use the first original separator (LF when the initial source has none). Fixture reload creates fresh matching state/history.

Current Node suite: **79 pass**. Desktop Chromium/WebKit: **23 pass, 1 existing WebKit CDP composition skip**. Browser regressions cover mixed-ending load, native typing/undo, original-source selection/block offsets, delivered-string paste replacement/undo/redo and CR+LF joining. Nine adapter test groups additionally cover grouped histories, simultaneous edits, 200 deterministic authoritative source splices and a 150,000-newline stress case. Independent in-memory review added 10,000 grouped randomized edits and 11,227 offset checks without a blocking finding. These extra probes are review evidence, not committed test groups or a production security proof.

Native model review found Swift Character-based LF splitting did not separate CRLF or CR fixtures, leaving them as one ungrouped block. Scalar-based physical line splitting and exact per-block boundary storage now preserve the same grouping and untouched boundaries across LF/CRLF/CR. Nine actual native model/UIKit tests pass on the dedicated phone simulator, including a mixed-ending atomic UITextView edit through its coordinator with exact UTF-8 source and unchanged BOM/Unicode neighbors. Result: `spikes/ios-editor/build/MRK9-source-endings-20261109.xcresult`. No native UI suite, iPad or physical-device run was performed in this follow-up; prior UI/audit results remain historical.

Source saving remains unimplemented. Native structural reparsing, copy/drop/multiple-selection semantics, OS clipboard normalization, real keyboard IME and complete shared-parser integration remain explicit gates. Desktop metadata work is O(line count) per edit; no p95 input-to-paint acceptance follows. Tests now use loopback port 18791 independently of the visible synthetic preview on 18790. MRK-9 and the MRK-12 freeze remain open for reliable desktop/native VoiceOver observations and integrated review. No runtime, file grant, sync, credential or production security gate changed.

## Native whole-document source fallback

The native prototype now has an explicit complete-document UITextView mode, separate from fixture block previews. Its source remains authoritative while editing; Done rebuilds fixture groups from exact source. It can express structural/cross-block edits without relying on the incomplete preview grouping. This is not a CommonMark reparser or cross-mode undo implementation. Full-source 1 MB input/paint performance has not been measured.

Independent review reproduced a late-callback defect: an old editor could overwrite a newer source session, or clear its composing state after block IDs were reused. Captured editor generations now guard both source and composition updates atomically, with regressions covering document re-entry and regrouped blocks. Review cleared the scoped fix. Mode changes remain blocked while composing.

The first Source control in the navigation bar failed Dynamic Type audits in light/dark preview. Moving it to the body-font bottom action area corrected the findings without filtering audits. Both dedicated phone and tablet now pass **12 native tests plus 5 UI tests**, including the whole-source literal-insertion/Done/re-entry flow and full light/dark preview audits. Bundles: `MRK9-whole-source-phone-fixed-20261109.xcresult` and `MRK9-whole-source-ipad-20261109.xcresult` under `spikes/ios-editor/build`; the initial failed phone bundle is retained. Active-editor/VoiceOver/real IME, native undo/selection flows and complete product/platform acceptance remain gates. No physical device or production service was used.

## Standalone macOS system-webview host

`spikes/macos-editor` provides an actual unsigned macOS `.app` for the existing synthetic CodeMirror fixture. SwiftUI hosts system WKWebView with a nonpersistent data store, a bundled-page navigation allowlist, no new windows/downloads/dialogs/native message bridge, a restricted bundled resource read root and an authored restrictive CSP. No document-open/save interface or user filesystem grant exists. Fourteen pure Foundation policy checks cover exact bundled-page/fragment allowance and other URL/frame/download rejection.

The arm64 host builds on macOS 26.6.2 with Swift warnings treated as errors. A fresh native-window observation verifies the bundled editor loaded and rendered its formatted inactive text; the window was raised and visibly confirmed. Product: `spikes/macos-editor/build/Build/Products/Debug/MarkrightMacEditorSpike.app`. This establishes scoped system-WKWebView resource loading, not Tauri integration, Windows/Linux packaging, interactive input acceptance or a production framework freeze. Native iOS remains the separate SwiftUI/UITextView target.

No security assurance follows merely from declared restrictions or URL-policy unit tests. Actual hostile navigation/network checks, OS sandboxing/signing, input/clipboard/IME, VoiceOver and p95 paint remain gates. The app is visibly labeled research/temporary edits; no collections, disk saves, account, sync or script execution is added. MRK-9 and MRK-12 remain open. Generated projects/resources/builds are ignored, while reproducible preparation/build instructions and policy checks are committed.

## Offscreen system-WebKit follow-up

The production app and the new offscreen harness now use the same `BundledEditorController` configuration/delegates. Swift 6 warnings-as-errors compilation and a separate `Verification` app build pass, leaving the visible Debug app product/state untouched. The runner rebuilds the pinned local editor first, enforces 20 GiB free before build stages/launch, reuses owned caches and limits its runtime process to 45 seconds. Its relaxed CSP positive control lives only under the ignored build directory, never in app resources.

Eight scoped integration groups pass on this Mac: a real WebKit fetch positive control, strict bundled editor/nonpersistent store, programmatic mixed-ending paste, immediate/deferred inert markup checks, actual CSP fetch denial, native/script navigation cancellation retaining source, popup/subframe denial, and native dialog suppression/teardown. CSP fetch denial produced no additional trap connections. No visible test window or app activation occurred; WebKit's invisible `TUINSWindow` helper is recorded rather than mistaken for user-facing UI.

An important residual was observed: a native-initiated external navigation opened one speculative TCP connection before cancellation, but sent no HTTP request and retained the original source. A script-initiated navigation opened none in the same run. Therefore navigation policy cancellation must not be presented as network isolation. The first zero-TCP assertion failed; diagnostics separate accepted connections from application requests, and the final checks assert the narrower cancellation/source-retention/no-HTTP behavior while explicitly reporting TCP counts. OS/process network isolation and broader hostile download/network testing remain MRK-23/26 gates, not a solved property.

Passing evidence: `spikes/macos-editor/build/integration-final-20261109.log`; prior failed navigation/popup diagnostic logs are retained. This is authored host-probe evidence, not executing imported scripts. Actual download requests, OS keyboard/clipboard/IME, VoiceOver, performance and full security/client acceptance remain open. There is no change to the untrusted-ingestion, physical-device or release gates, and MRK-9/12 stay open.

## Scoped native request hardening and comparison

The research host now uses a `BundledResearchWebView` subclass with a synchronous allowlist check on the specific native `load(URLRequest)` entrypoint. Disallowed requests return nil before `super.load`, with a weak host-only counter/status callback. No general navigation API, guest bridge, signing permission or untrusted document ingestion is introduced. The fixed bundled `loadFileURL` path remains unchanged.

Nine scoped checks pass in `build/native-request-preflight-20261109.log`. The covered native request is synchronously refused, source remains unchanged, and no additional trap TCP/data was observed. A same-run raw WKWebView/cancellation comparator still opened one TCP connection with no observed application bytes or source replacement. Raw/script connection counts are diagnostics rather than promised constants. The trap records accepted connections/nonempty receive callbacks, not parsed HTTP requests; this does not provide an unbounded no-network guarantee. Independent review cleared the narrow implementation and probe claims.

This is one-entrypoint hardening, **not a network isolation fix**. Installed public SDK headers expose other loaders and capabilities outside demonstrated coverage: native `load(URL)` (macOS/iOS 27; current host is macOS 26), file/read-access, HTML/data/simulated requests, native download start/resume, reload/back-forward and interaction-state restoration. Simulated content can load subresources; nonpersistent storage and navigation delegates do not establish an OS/process boundary. These APIs are trusted-host interfaces, not currently reachable from inert document source. MRK-23/26 retain broader capability/network/download review; no blocked issue is advanced by this research evidence.

The app wiring builds with Swift warnings as errors into the reused nonvisible Verification product after a 20 GiB headroom/unused-product check. The visible Debug app remains untouched; all prior failed/passing logs, products and other workers' artifacts are preserved. VoiceOver, OS input/IME, ingestion, physical-device and release gates remain open, with no new download or simulator use.
