# MRK-41 native source-copy export

This research slice adds **Export source copy** to the native macOS and iOS editors. It relates to pinned MRK v2 R5/R6/R14/R15. It exports the current raw source, including unsaved edits, through the operating system's user-selected destination. Editing continues in the original document. Full static export, flattened includes, asset bundles and complete production clients remain separate acceptance gates.

## Snapshot and destination contract

The button captures one immutable UTF-8 snapshot on the main actor. Source, block and reading modes preserve the exact original BOM, Unicode normalization, punctuation and physical LF/CRLF/CR separators. Empty source is valid. The original filename's bytes and case are retained as the suggested filename; invalid basenames, path separators, controls and unsupported suffixes are refused. Only `.md` and `.mrk` source are supported.

Encoding stops at the first byte beyond an 8 MiB ceiling. Block mode encodes individual source/separator chunks without joining an oversized document. This export ceiling does not increase the collection store's existing 1 MiB reopen limit. Later edits do not change a pending snapshot. Active marked text and a pending Save As destination change refuse a snapshot; an ordinary in-flight or scheduled save can continue independently.

The export-only CoreTransferable adapter has two conditional DataRepresentations, one for Markdown and one for Markright source. It returns only the snapshot bytes. Deployment-compatible type declarations describe the established Markdown identifier and the app's Markright source identifier; they add no document-open route or incoming data representation. The SwiftUI exporter API supports the existing macOS 14 and iOS 26 minima. No destination URL, bookmark or directory grant is retained in the export model.

The OS handles destination selection, provider interaction and any overwrite confirmation. This path does not use the collection store's atomic-save or baseline-conflict protocol. A completion reports export of the captured copy; it does not establish provider durability or save the active document's latest revision. A failed completion leaves the destination unconfirmed and asks the user to check it before retrying. There is no automatic retry.

Relative links, assets and includes remain literal source references. No associated file is read, copied or rewritten. No HTML rendering, script execution, network capability, import route or cloud service is added. This is not the gated MRK-17 portable static export/bundle implementation.

## Lifecycle and original document

Only one request can be pending. Each request has a unique token; stale or duplicate success, error and cancellation callbacks leave newer state untouched. Explicit cancellation and platform cancellation errors have their own outcome. Escaping callbacks capture immutable request data and the reference model, discard the returned URL and never access a disappearing presenter's SwiftUI state.

Export never flushes, marks the original saved, changes its destination/baseline, retires a recovery checkpoint or authorizes closing dirty source. It neither suspends autosave nor resets the editor generation, selection or native undo history. Pending requests block workspace navigation, Save As and close. The Mac window and app-quit delegates refuse a pending export synchronously, before scheduling close work, and retain their final current-state checks.

## Verification

The shared Mac corpus passes **102 tests**, zero failures, with Swift warnings as errors: `spikes/macos-editor/build/MRK41-shared-core-macos-20261110.log`. Twelve new groups cover exact bytes and bounds, composition/destination guards, immutable snapshots, stale/cancel/error callbacks, session lifetime, ordinary save concurrency and preservation of conflicted dirty recovery state.

All **ten focused AppKit/Transferable groups pass** in `spikes/macos-editor/build/MRK41-native-appkit-final-20261110.log`. The two new groups serialize the real conditional Transferable representations to data and files beneath a fresh synthetic temporary destination, reject importing and unrelated types, and retain the real native source view/caret/focus/undo and conflicting original/recovery checkpoint across export outcomes. The actual production workspace is hosted invisibly with OS exporter presentation explicitly disabled. A pending request is also detached and cancelled. The real app-quit delegate is exercised using an isolated workspace manager and inert reply: pending export is refused without queued work, and an idle request receives its deferred safe reply while a duplicate is refused. No real application termination is requested. Transferable introspection in this probe requires macOS 15.2; product export APIs retain the older deployment minimum.

The unsigned arm64 Mac app builds with warnings as errors in the unused Verification product (`spikes/macos-editor/build/MRK41-native-macos-build-final-20261110.log`). The iOS app and test targets also pass a two-job warnings-as-errors `build-for-testing` against the installed Simulator SDK without booting (`spikes/ios-editor/build/MRK41-native-ios-build-20261110.log`). Both generated app plists declare source types without adding incoming document routes. Xcode emitted host provisioning-profile diagnostics with signing disabled, and a generic Simulator placeholder diagnostic on the iOS build; neither build failed and no signing operation was requested.

The first compile caught the SDK's OS-27-only Markdown convenience constant; the adapter now declares the established type identifier for older systems. The unchanged retention assertions then caught a queued native close acting after export completion and refreshing the recovery token. Final lifecycle review identified the analogous app-quit path. Both delegates now refuse that request immediately, and the regression completes export before yielding to expose any delayed work. Original failed compile/probe logs and passing evidence are preserved locally. Independent lifecycle and publication review found no scoped blocker.

Generated products, temporary fixtures, logs and simulator diagnostics remain ignored. Verification uses owned caches, at least 20 GiB free before heavy work and two build jobs; the visible Debug app remains untouched.

## Remaining acceptance

The OS save panel, provider cancellation/overwrite/failure behavior and focus restoration after actual modal dismissal have not been exercised. The synthetic serialization and invisible host checks establish their narrower behavior only. No iOS runtime validation has run for this slice. The existing recovery-input failure and simulator boot error 22 remain open.

Read-only simulator diagnosis found the owned device available and Shutdown, its image Ready and supported, and consistent GUI/console/developer selection. The default runtime-build mapping differs from the owned runtime build; this observation does not prove the boot cause or justify a repair. No boot retry, service reset, runtime replacement or device erase was performed.

Native keyboard/IME, VoiceOver, physical devices, untrusted ingestion, external folders, network/process isolation, full authoring/rendering, identity/portability and release acceptance remain gated. No accessibility or isolation acceptance is claimed.
