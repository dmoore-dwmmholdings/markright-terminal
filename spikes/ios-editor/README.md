# MRK-9 native interaction spike

SwiftUI previews plus a native UITextView for the selected source line/fixture block. It runs only on a dedicated simulator; no real documents, sync, disk persistence, scripts, signing account or physical devices are involved.

## Native reading mode

Reading mode replaces the tappable edit rows with static native text and hides editing actions. Exit reading returns to the preview/editing screen. Entry commits whole-document source and rebuilds fixture groups; both entry and exit invalidate prior editor generations. Composition blocks mode changes, and stale callbacks cannot overwrite source or composition state during or after reading. The model also refuses direct editing helpers while reading. These are UI/model controls, not an untrusted-code security boundary.

Both edit previews and reading text remove attributed link targets, preserving readable text/emphasis without adding URL-opening behavior. Code/table rows remain source-like; the renderer and grouping are still partial. Cross-mode undo/selection restoration is not implemented or claimed. The action bar preserves button identity while switching to a vertical layout at larger Dynamic Type sizes, and has an opaque system background. Static reading rows use natural text height. Up to 128 rows and 65,536 UTF-16 units stay mounted during reading; larger documents retain lazy rendering. These bounds change mounting only, never document content. No audit category or reported issue is suppressed.

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

Grouping is a small fixture-level experiment, NOT CommonMark/GFM or the Markright grammar. Ordinary inline preview uses Foundation AttributedString; code/table previews currently remain source-like. IDs/groups are not reparsed after structural edits. There is no complete authoring toolbar, cross-block selection/undo, file collection, large-document UI performance proof, VoiceOver session, real IME keyboard proof, iPad/physical device validation or app-release acceptance. No claim of full Liquid Glass/accessibility conformance follows from system controls. MRK-9 stays open.

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

The `--static-calculator` launch flag loads only the authored bundled `calculator-static.md`. Its frozen table and inert script source remain readable while execution is unavailable, with explicit freshness/trust disclaimers. This is fixture-level readability, not snapshot/import/export or distribution acceptance.

Current isolated destination: `Markright-MRK28-iOS27-20261109`, `B41A0866-71EA-45B5-94DB-C1634AEC0F5B`, iPhone Duo/iOS 27.2. The runtime was already installed; no download, physical device or other project's simulator was used. Targeted result `build/MRK28-native-declarative-ios27-20261109.xcresult`: **7 native decoder tests + 1 static-readability UI test pass**. The prior full editor/audit counts above are historical and were not rerun for this targeted change. Current policy evidence and remaining gates are in `docs/adr-0005-ios-declarative-fallback.md`.

Reproduce with the existing xcodebuild command and explicit destination, adding `-only-testing:MarkrightEditorSpikeTests/DeclarativeDecoderTests` and `-only-testing:MarkrightEditorSpikeUITests/EditorInteractionTests/testStaticCalculatorResultRemainsReadableWithoutExecution`. Regenerate the project from `project.yml` first so both trusted fixtures are bundled.
