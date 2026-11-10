# Native collection and editing validation

Native SwiftUI collection browsing and native UITextView source/preview/reading editing. The app-owned collection validation is tracked by MRK-36, bounded recovery by MRK-37 and Save As by MRK-38; editor interaction research remains MRK-9. Automated runs use synthetic documents on the dedicated simulator, with no sync, script execution, signing account or physical devices.

The default launch now creates and reopens app-owned collection folders and UTF-8 documents with autosave. See [the storage contract and limitations](../../docs/native-collections-validation.md). External folders, full identity, crash-before-checkpoint recovery and production MRK-18 acceptance remain gated. Use `--editor-fixture` for the historical sample editor, including with `--static-calculator` or `--large-document`.

MRK-39 extracts `EditorModel` unchanged into a Foundation/Observation source shared with the separate native macOS collection workspace. Its storage/lifecycle corpus also runs through `spikes/Package.swift` on macOS. At the MRK-39 checkpoint, the iOS native/model/decoder shard passed 91 tests with zero failures/skips/result-bundle runtime warnings. Its workflow shard had 10 UI passes and one recovery-input failure; a full attempt remained unfinalized. Isolated diagnostic runs were blocked first by process exhaustion and then by unexplained boot error22 despite device/runtime availability. The stricter recovery harness now fails before termination unless exact source/current-checkpoint prerequisites hold, retains input diagnostics, and adds typing across the error-header transition without refocusing. It compiles with warnings-as-errors; its selected runtime cases have not run. Current UI acceptance remains open; the prior MRK-38 114-pass checkpoint below is historical evidence. See [the shared-core and desktop evidence](../../docs/native-macos-collections-validation.md).

## Link, image-reference and code-block checkpoint

MRK-43 adds **Link**, **Image reference** and **Code block** to the existing Source edit menu. Link/image templates select the destination placeholder for ordinary typing and retain simple selected label/alt text. They resolve no URL and import no image. Code blocks preserve selected bytes and physical endings with a sufficiently long backtick fence and only needed surrounding separator lines.

The iOS app and test targets compile with warnings as errors (`build/MRK43-native-ios-build-20261110.log`), including one parameterized UIKit refusal regression for the three commands. No new iOS runtime case ran. Shared Mac tests pass 123/0 and all 14 authored AppKit/Transferable groups pass; actual OS input/menu, the recorded native TextKit undo diagnostic, recovery-input/boot error 22 and full reference/asset/rendering acceptance remain open. See [the contract and evidence](../../docs/native-markdown-structure-validation.md).

## Native Markdown insertion checkpoint

MRK-42 adds **Insert Markdown → Bold / Italic / Inline code** to the native whole-document Source edit menu. Commands preserve literal selected text, select inserted bodies/placeholders, use native insertion/undo and refuse stale or composing views. Block editors retain their existing native suggested actions. These are source helpers, with no rich-text conversion or complete rendering claim.

The iOS app and test targets compile with warnings as errors (`build/MRK42-native-ios-build-20261110.log`), including four focused UIKit refusal tests. They have not run on iOS. Shared Mac tests pass 113/0 and all 13 authored AppKit/Transferable groups pass. The recovery continuation regression confirms shared state only; simulator boot error 22 and original iOS input acceptance remain open. See [the contract and evidence](../../docs/native-markdown-insertion-validation.md).

## Source-copy export checkpoint

MRK-41 adds **Export source copy** for the current in-memory source, including unsaved edits. A bounded immutable UTF-8 snapshot goes to the OS user-selected destination; editing remains in the original document, with its baseline, dirty state and recovery checkpoint unchanged. Assets/includes remain source references. Pending requests guard close and Save As; stale callbacks cannot complete a newer request.

The iOS app and test targets compile with warnings as errors at `build/MRK41-native-ios-build-20261110.log`, without booting or launching a simulator. All 102 shared Mac tests and 10 authored AppKit/Transferable groups pass. Actual OS export/provider interaction, iOS runtime and the existing recovery-input and boot error 22 gates remain open. See [the contract and evidence](../../docs/native-source-copy-export-validation.md).

## Saved-source search checkpoint

MRK-40 adds an explicit **Search saved documents** panel for the selected app-owned collection. It scans saved source, never unsaved editor text or recovery journals, with bounded literal previews, cancellation and visible limits/errors. Opening a result uses the existing fresh-open workflow; no old match range is applied. Query controls disable prose transformations and retire callbacks before teardown.

The iOS app and test targets compile with Swift warnings as errors using a generic Simulator destination (`build/MRK40-native-ios-build-20261110.log`). **No iOS runtime case ran for this slice.** Shared Mac90 and AppKit8 passes establish their scoped platforms only; simulator boot error22 and the prior iOS recovery-input failure remain open. See [the full contract and evidence](../../docs/native-collection-search-validation.md).

## Native Save As checkpoint

MRK-38 adds Save as a new document into another existing app-owned collection. It preserves source/file type/caret, refuses collisions and rebinds future saves only after a committed copy receipt. Newer edits save to that new baseline. Failed/cancelled naming resumes the original autosave on dismissal; prior in-flight receipts remain valid. The copy operation does not overwrite the original. Linked files/includes are not copied or rewritten.

Full `build/MRK38-native-save-as-verified-20261110.xcresult`: **91 native/model/decoder +23 UI tests pass** (114 total), zero failures/skips/runtime warnings, Swift warnings-as-errors. Adds sixteen session groups, four store/focus groups and four UI methods for actual divergent originals, exact UTF-8, collisions, concurrent writes, direct caret resumption, new-destination relaunch and unfiltered light/dark naming audits. Initial name-field clipping was fixed with a vertically expanding field; a cancelled-failure autosave gap was fixed and regression-tested. Corrected targeted 24/0 and final 114/0 evidence are preserved. Independent lifecycle and publication review cleared the scoped work.

[Save As contract and evidence](../../docs/native-save-as-validation.md) records exact ordering and limits. Owned simulator Shutdown, about 154.4 GiB free; preview and prior evidence preserved. External folders, relative reference/asset relocation, complete identity/authoring, real keyboard/VoiceOver/physical-device/security/release and production MRK-18/12 acceptance remain open.

## Historical app-owned recovery checkpoint

MRK-37 adds a confirmed exact-source checkpoint before each document save, explicit close with a current recovery copy, a relaunch recovery inbox and inert native preview. Restoration always creates a separate non-clobbering file; original `.md`/`.mrk` suffixes are preserved. Only a matching checkpoint is retired after a confirmed save. Receipt-aware cleanup retries and newer-edit/composition guards prevent stale recovery claims.

Full `build/MRK37-native-recovery-verified-20261110.xcresult`: **71 native/model/decoder +19 UI tests pass** (90 total), zero failures/skips/runtime warnings, Swift warnings-as-errors. Includes twelve storage and nine session groups, acknowledged-checkpoint termination/new-copy recovery with unchanged original, four unfiltered light/dark inbox/preview audits, and every prior regression. Initial clipped-caption audit failures, corrected targeted24/0 and final90/0 evidence are retained. Independent lifecycle/storage review cleared; actual filesystem-failure injection is not qualified.

[Recovery contract and evidence](../../docs/native-recovery-validation.md) covers checksummed bounded envelopes, exact-token retirement, pending/malformed preservation, 32-stage/544-entry collection bounds and interrupted publication links. Simulator restored Shutdown; about150.5 GiB free. This does not establish power-loss/disk-full, crash-before-checkpoint, external providers/writers, VoiceOver/physical-device/security/release or full MRK-18/12 acceptance. Public source publication is separately authorized and reviewed.

## Historical app-owned collection checkpoint

MRK-36 adds a native collection/document browser, ordinary UTF-8 file creation/opening and debounced autosave. One app-wide actor refuses unsafe paths/collisions and divergent baseline writes; one session pump retains in-flight receipts and newer edits. Close waits for a confirmed save, with composition/error/durability gates and retained source on failure. File contents remain authoritative; no imported code runs.

Full `build/MRK36-native-collections-verified-20261110.xcresult`: **50 native/model/decoder + 16 UI tests pass**, zero failures/skips/runtime warnings, Swift warnings as errors. Includes create/edit/close/reopen/acknowledged-save relaunch, injected failure retention, ten storage and seven session tests, six unfiltered light/dark browser/workspace audit invocations, plus every prior editor test. The original audit failure and successful targeted rerun are retained. See [the detailed contract and evidence](../../docs/native-collections-validation.md).

Short collection lists keep at most 128 listed entries mounted through Dynamic Type changes; larger lists remain lazy without truncation. The owned iPhone Duo/iOS 27.2 simulator is Shutdown, approximately 164.3 GiB free after the run. External folders, crash recovery/save-copy, cross-process coordination, full identity, VoiceOver/real IME, physical devices and production/security/release acceptance remain open. MRK-18/12 stay gated; this slice does not close MRK-R6/R7/R15.

## Caret and selection continuity

Block and whole-document editors now resume their saved UTF-16 selection extent when reopened after preview/reading mode. A valid active-block range maps into Source; a contained document selection can map back into that block after regrouping. Cross-block document selections remain document-only. New editor sessions restore before installing their delegate and focus once on window attachment, so typing resumes at the saved caret without another tap.

`SourceSelection` rejects out-of-bounds/overflow, surrogate-pair and CRLF-interior endpoints rather than rounding them. Invalid bookmarks are cleared while accepted text edits remain. Document bookmarks belong to exact source revisions; canonical-equivalent Unicode is not byte-identical. Unrelated block edits retain valid local bookmarks but invalidate global coordinates; whole-source regrouping clears old block IDs. Stale source/composition/range callbacks are rejected atomically by generation. Routine view updates preserve native selection/marked text, and authoritative text replacements use byte identity while suppressing delegate feedback.

Result `build/MRK9-native-selection-full-20261110.xcresult`: **33 native/model/decoder + 12 UI tests pass**, zero failures/skips, with Swift warnings as errors. Nine new native groups cover validation, mapping, Unicode/revisions, stale/invalid ranges, actual UITextView replacement/marked text and a 1 MB model bookmark. Two UI flows type at restored block/document carets without tapping the editor. All four unfiltered light/dark preview/reading audits, rendered-caption OCR and the earlier 1 MB interaction smoke also pass. The owned iPhone Duo/iOS 27.2 simulator was restored to Shutdown; no other destination or runtime download was used.

Only selection extent is retained: selection direction/affinity, prior scroll position, cross-mode undo, cross-launch selection persistence, real IME/VoiceOver, current iPad/physical devices and p95 paint remain open. Byte comparisons/range validation can scale with source length; this is not a production performance qualification. Research commit IDs and publication provenance are described in docs/publication-review.md.

## Native reading mode

Reading mode replaces the tappable edit rows with static native text and hides editing actions. Exit reading returns to the preview/editing screen. Entry commits whole-document source and rebuilds fixture groups; both entry and exit invalidate prior editor generations. Composition blocks mode changes, and stale callbacks cannot overwrite source or composition state during or after reading. The model also refuses direct editing helpers while reading. These are UI/model controls, not an untrusted-code security boundary.

Both edit previews and reading text remove attributed link targets, preserving readable text/emphasis without adding URL-opening behavior. Code/table rows remain source-like; the renderer and grouping are still partial. Cross-mode undo, selection direction and viewport restoration remain unimplemented or unverified; range bookmarks are described above. The action bar preserves button identity while switching to a vertical layout at larger Dynamic Type sizes, and has an opaque system background. Static reading rows use natural text height. Up to 128 rows and 65,536 UTF-16 units stay mounted during reading; larger documents retain lazy rendering. These bounds change mounting only, never document content. No audit category or reported issue is suppressed.

Native and UI regressions cover BOM/mixed-ending source, composition, repeated mode entry, stale callbacks, direct block/source-editor transitions, static reading rows and full light/dark preview/reading audits. Simulator evidence remains distinct from VoiceOver, real keyboard IME, iPad/physical devices, complete rendering, persistence, security and release acceptance.

Final result `build/MRK9-native-reading-verified-20261110.xcresult`: **24 native/model/decoder tests + 10 UI tests pass**, zero failures/skips, with Swift warnings as errors. All four `.all` light/dark preview/reading audits pass. The 1 MB smoke now includes edit → read → edit with exact first-block source retained; this is not a latency budget or large-document screen-reader proof. Only the existing owned iPhone Duo/iOS 27.2 simulator was used and restored to Shutdown; current iPad/physical-device suites were not run.

The action bar's orientation currently follows Dynamic Type size. Narrow split views, smaller phone widths and localization remain unverified alongside the broader device gates.

Visual inspection also caught a missing mode-button caption despite functional/audit passes. Mode-specific button identity corrected it; the final transition test uses on-device Vision OCR of the synthetic screenshot to require a visibly rendered “Exit reading” caption, independently of accessibility metadata. No image or document is uploaded. Earlier empty-caption screenshots remain as evidence.

Initial runs exposed contrast, clipping and Dynamic Type findings, plus a test that incorrectly expected Markdown presentation to retain leading whitespace. Raw source was already preserved exactly. The unchanged `c094525` baseline passed its same-device dark audit. Corrections retained natural reading-text sizing, stable action identity across layout changes and bounded mounting of short reading documents during Dynamic Type relayout. The diagnostic audit handler always returns false for every issue; none is ignored. Original failed bundles, baseline, diagnostics and screenshots remain under `build/MRK9-*reading*20261110*`; successful summary/screenshot exports are `MRK9-native-reading-verified-summary-20261110.json` and `native-reading-verified-attachments-20261110`.

## Reproduce

Generate with `xcodegen generate --spec spikes/ios-editor/project.yml`. Build/test the generated project and scheme `MarkrightEditorSpike`, with a dedicated simulator UUID and `-derivedDataPath spikes/ios-editor/build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`. Never target `booted` or a physical device implicitly. Coordinate simulator ownership before running. Do not open Simulator.app for headless runs.

Historical isolated destination: Markright-MRK9-20261108, `1C3FCA53-C143-4C4C-B353-298B1711744C`, iPhone 17 Pro/iOS 26.5. That device/runtime was no longer installed after later cleanup. The current dedicated MRK-28 destination is recorded below; never substitute another project's device. Other projects' simulators and attached physical devices were not targeted.

## Verified evidence

Xcode 27.2/iOS Simulator SDK build succeeded. Three native model tests and one XCUITest pass. The UI test activates an ordinary preview line, checks raw Markdown, types literal straight quotes/double hyphens, returns to preview, reopens and asserts identical edited source with an unchanged neighbor, then activates the entire fenced-code block. Prose keyboard transformations are disabled in raw-source editing. Test result: `build/MRK9-source-preservation.xcresult` (ignored generated artifact).

The model tests cover fixture source round-trip, block grouping, edits preserving adjacent source, and a simulated composing-state guard. They are not real IME tests. Independent source review identified keyboard transformation and missing persistence-assertion gaps; both were fixed and the simulator suite rerun.

## Explicit limitations

Grouping is a small fixture-level experiment, NOT CommonMark/GFM or the Markright grammar. Ordinary inline preview uses Foundation AttributedString; code/table previews currently remain source-like. IDs/groups are not reparsed after structural edits. There is no complete authoring toolbar, cross-block selection/undo, full external-folder collection workflow, large-document UI performance proof, VoiceOver session, real IME keyboard proof, iPad/physical device validation or app-release acceptance. No claim of full Liquid Glass/accessibility conformance follows from system controls. MRK-9 stays open.

## Extended phone and tablet checks

Both dedicated iPhone 17 Pro and iPad Pro 11-inch (M5) iOS 26.5 simulators now pass four native model/UIKit tests plus two XCUITests. iPad destination: `51320233-D655-4A16-9FE2-B60C7FB87E67`. A native `setMarkedText`/`unmarkText` probe verifies the coordinator observes marked ranges and defers preview until commit; this is still not a real international keyboard session. The additional UI smoke launches a 1,000,000-byte fixture with lazy rows, types into the first block and verifies source survives preview/reactivation. It proves that scenario does not hang, not a p95 input-to-paint budget or full-document scroll performance. Results: `build/MRK9-iPhone-large-ime.xcresult` and `build/MRK9-iPad-large-ime.xcresult`. Both dedicated simulators are shut down after testing and retained for reuse; no existing destination was altered.

A later phone run (`build/MRK9-teardown.xcresult`) passes five native tests plus two UI tests. The additional test places marked text at an explicit insertion offset, verifies exact `sにource` bytes, and exercises the UIViewRepresentable teardown path. Teardown/end-edit now commits visible marked text and clears the composition guard. This reduces the lazy-view lifecycle risk; an actual keyboard composition while scrolling away/returning remains untested. The iPad's last completed run predates this final teardown addition.

## Automated accessibility corrections

The initial `.all` accessibility audit found undersized empty-line hit targets, insufficient caption/button contrast, and a Dynamic Type limitation in the toolbar action. Failure evidence is retained in `build/MRK9-accessibility.xcresult` and `build/MRK9-accessibility-fixed.xcresult`. The prototype now provides 44-point minimum preview targets, primary caption contrast, and a body-font bottom action with a high-contrast bronze tint. No audit category is filtered or suppressed.

Both phone and tablet now pass the same five native tests and four UI tests, including light/dark preview audits. Latest bundles: `build/MRK9-accessibility-light-dark.xcresult` and `build/MRK9-iPad-accessibility-light-dark.xcresult`. These automated preview-screen audits do not establish actual VoiceOver navigation, active-editor accessibility, a real international keyboard session, or release acceptance. The per-line button approach also adds touch-target spacing; it is an interaction experiment, not a final dense-document layout decision. Both dedicated simulators are shut down after the runs.

## Physical line-ending follow-up

Swift Character-based LF splitting failed to group CRLF and CR fixtures even though their initial bytes often round-tripped. The model now scans physical LF/CRLF/CR scalar boundaries and stores each block's original `separatorAfter`, preserving internal atomic-block endings and untouched neighbors. Four added tests cover consistent grouping, mixed endings/BOM/Unicode, empty EOF and an actual UITextView atomic-block replacement through its coordinator.

Dedicated phone run `build/MRK9-source-endings-20261109.xcresult`: **9 native model/UIKit tests pass**, zero failures. This run selected native tests only; the earlier four UI/audit checks were not rerun, and iPad/physical-device/real keyboard/VoiceOver acceptance remains separate. Grouping is still a fixture experiment and structural edits do not reparse it. No files or services are accessed.

## Whole-document source fallback

The bottom Source action opens the entire authoritative document in a scrolling native UITextView. Done commits that source and rebuilds the fixture groups, allowing structural edits outside the limited per-block projection. Composition guards prevent switching modes mid-composition. Editor-generation checks reject old block/document callbacks before they can overwrite source or alter the new session's composing state. Undo history across mode switches is not implemented or claimed.

Independent review reproduced stale-callback overwrites and cleared the generation checks after regression coverage. The first new Source action in the navigation bar failed Dynamic Type audits; it moved into the scalable bottom action area, without suppressing any audit category. Failure evidence remains `build/MRK9-whole-source-phone-20261109.xcresult`.

Both dedicated phone and iPad now pass **12 native tests and 5 UI tests**, including exact literal source insertion/Done/re-entry and full light/dark preview accessibility audits. Results: `build/MRK9-whole-source-phone-fixed-20261109.xcresult` and `build/MRK9-whole-source-ipad-20261109.xcresult`. These are simulator/fixture checks, not VoiceOver or full client acceptance. Active-editor accessibility, real OS IME, cross-block selection/undo interaction, 1 MB whole-source latency, full Markdown semantics and file persistence remain gates.

## MRK-28 native declarative fallback

`DeclarativeDecoder.swift` is a pure typed Swift bit-field kernel with exact UInt64/signed results and bounded literal table output. It has test-only callers; no document JSON parser, interpreter, automatic execution or calculator UI bridge is added. `fixtures/bitfields-0.1.json` supplies 49 shared trusted vectors. Foundation JSONDecoder is used only to load that authored test corpus, not untrusted document data.

The `--editor-fixture --static-calculator` launch flags loads only the authored bundled `calculator-static.md`. Its frozen table and inert script source remain readable while execution is unavailable, with explicit freshness/trust disclaimers. This is fixture-level readability, not snapshot/import/export or distribution acceptance.

Current isolated destination: `Markright-MRK28-iOS27-20261109`, `B41A0866-71EA-45B5-94DB-C1634AEC0F5B`, iPhone Duo/iOS 27.2. The runtime was already installed; no download, physical device or other project's simulator was used. Targeted result `build/MRK28-native-declarative-ios27-20261109.xcresult`: **7 native decoder tests + 1 static-readability UI test pass**. The prior full editor/audit counts above are historical and were not rerun for this targeted change. Current policy evidence and remaining gates are in `docs/adr-0005-ios-declarative-fallback.md`.

Reproduce with the existing xcodebuild command and explicit destination, adding `-only-testing:MarkrightEditorSpikeTests/DeclarativeDecoderTests` and `-only-testing:MarkrightEditorSpikeUITests/EditorInteractionTests/testStaticCalculatorResultRemainsReadableWithoutExecution`. Regenerate the project from `project.yml` first so both trusted fixtures are bundled.
