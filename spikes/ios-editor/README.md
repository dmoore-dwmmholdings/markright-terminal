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
