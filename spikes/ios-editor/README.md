# MRK-9 native interaction spike

SwiftUI previews plus a native UITextView for the selected source line/fixture block. It runs only on a dedicated simulator; no real documents, sync, disk persistence, scripts, signing account or physical devices are involved.

## Reproduce

Generate with `xcodegen generate --spec spikes/ios-editor/project.yml`. Build/test the generated project and scheme `MarkrightEditorSpike`, with a dedicated simulator UUID and `-derivedDataPath spikes/ios-editor/build -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO`. Never target `booted` or a physical device implicitly. Coordinate simulator ownership before running. Do not open Simulator.app for headless runs.

Current isolated destination: Markright-MRK9-20261108, `1C3FCA53-C143-4C4C-B353-298B1711744C`, iPhone 17 Pro/iOS 26.5. Other projects' simulators and attached physical devices were left untouched; that worker confirmed no conflict.

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
