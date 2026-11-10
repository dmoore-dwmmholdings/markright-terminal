# MRK-36 app-owned native collection validation

This is a bounded native iOS research slice related to MRK-R6, R7 and R15, pinned to MRK specification v2. MRK-18 production collections and MRK-12 integration remain gated. It does not establish general storage or client acceptance.

## Usable path

The native app now starts with a collection/document browser. New collection creates an ordinary folder inside the app's Documents/MarkrightCollections directory. New document creates an ordinary UTF-8 `.mrk` file, then opens the native preview/source/reading editor. Lists can switch collections and reopen documents. No account or sync service is involved. There is no external-folder picker or import in this slice.

Edits debounce for 300 ms into one save pump per session. A receipt advances the baseline even if newer edits arrive during a write; those newer edits are saved next. Composition defers saving and closing. Close waits for the pump and refuses dismissal on unsaved text, errors or uncertain durability. Errors retain the model and expose Retry save. A divergent file is refused without overwriting its bytes. There is not yet a save-copy or conflict-resolution UI; retain the open editor when a conflict occurs.

The app uses one storage actor shared across its windows. Separate sessions opening the same revision cannot silently overwrite each other's divergent app writes: the later stale baseline conflicts. Byte comparisons before replacement also detect observed external divergence, but are not an atomic cross-process compare-and-swap. Uncooperative external-write races and external file coordination remain open.

## File boundary

The trusted container parent is canonicalized before appending the private root leaf. POSIX directory descriptors traverse with `O_DIRECTORY|O_NOFOLLOW`; collection/document symlinks and multiply linked documents are refused. Reads verify regular file type and remain bounded even if size changes. File names are validated rather than rewritten: visible single components, no separators/control characters or Windows-reserved names, at most 255 UTF-8 bytes, case/canonical-Unicode collision refusal. Supported document suffixes are `.md` and `.mrk`.

Limits are 64 collections, 512 documents per collection and 1 MiB of document UTF-8. Limits, invalid UTF-8 and unexpected entries produce explicit errors rather than truncated results. BOM, mixed LF/CRLF/CR, combining characters and all other valid UTF-8 source bytes remain authoritative. This is not a portable manifest or stable cross-platform identity implementation.

Writes use a new exclusive temporary inode, exact bytes and file `fsync`. Creation publishes with no-clobber `linkat`; saves compare baseline bytes and atomically replace with `renameat`. The directory is then synchronized. A post-commit durability failure returns the new baseline plus a visible warning, blocking close until an explicit successful retry. A failed pre-commit operation leaves the old document and in-memory edits intact. Only the operation's own temporary name is removed on ordinary completion/failure.

Crash-left temporary entries are preserved and produce an explicit error; there is no recovery journal or repair UI yet. This fail-closed behavior can block a collection until recovery is implemented. No disk-full/power-loss/filesystem fault campaign or crash durability guarantee is inferred from synthetic save errors or ordinary fsync success. Scene-phase flushing is best effort; there is no background-time assertion and no guarantee for a kill before an acknowledged save. Acknowledged-save termination/relaunch is tested separately.

## Validation

Final full result `spikes/ios-editor/build/MRK36-native-collections-verified-20261110.xcresult`: **50 native/model/decoder + 16 UI tests pass** (66 total), zero failures/skips/runtime warnings, with Swift warnings treated as errors. Includes seven new session tests, ten storage tests, create/edit/reopen/relaunch, injected failure retention, six unfiltered light/dark collection/workspace audits across two test methods, and all prior editor audits/OCR/large-document/static-calculator checks. The result summary is `build/MRK36-native-collections-verified-summary-20261110.json`; the reopened-document screenshot is `build/MRK36-reopened-document-attachments-20261110/13DB4898-6558-44DF-820F-88E0BA82843D.png` under the iOS spike. Visual inspection confirmed the saved title, exact literal source and on-device saved status after relaunch. The screenshot contains a partially visible keyboard; it does not establish settled keyboard/layout behavior.

The first full run passed 64 tests and failed the new collection accessibility method. Its attachments identified low-contrast headers/row/Close text and a partially unsupported Dynamic Type row. Headers/actions now use primary contrast, Close/Retry have 44-point minimum height, and short collections stay mounted through relayout. More than 128 listed collections/documents use lazy mounting; no content is truncated and large-list accessibility remains unqualified. The selected checkmark is decorative; the collection button exposes its Selected accessibility value. No audit category or issue is suppressed. The targeted corrected run passed 10 storage + 3 UI tests before the final dark coverage/full run. Original failed bundles, detailed diagnostics and screenshots remain under `build/MRK36-*20261110*`.

The simulator was restored to Shutdown; about 164.3 GiB remained free after verification. No cleanup was performed. The dedicated owned simulator is iPhone Duo/iOS 27.2, B41A0866-71EA-45B5-94DB-C1634AEC0F5B; no physical device, runtime download, other project's simulator, signing, deployment or external infrastructure is used.

Native tests exercise exact UTF-8, bounds, names/collisions, no-follow paths, divergent/concurrent writes, save coalescing, composition, failures and committed durability receipts. UI tests exercise create/edit/close/reopen/acknowledged-save relaunch, retained edits on injected failure and unfiltered list/workspace accessibility audits. These are not VoiceOver, real keyboard IME, physical iPhone/iPad, complete Markdown, security isolation, external provider, recovery or release acceptance. Existing MRK-9/12 and ingestion/device/release gates remain open.

## Launch and reproduce

Normal launch shows collections. `--editor-fixture` selects the previous bundled synthetic editor; combine it with `--dark-mode`, `--large-document` or `--static-calculator` for those checks. Tests use `--library-test-root <UUID>` to select a fresh app-owned test leaf; the argument never accepts an arbitrary path. `--fail-library-save` only affects that UUID-scoped test route and injects a pre-commit save error. It is not a disk-full test.

Generate from `spikes/ios-editor/project.yml`; run scheme MarkrightEditorSpike on the exact owned simulator UUID, with the existing derivedDataPath and code signing disabled. Check at least 20 GiB free before each build stage, avoid concurrent large builds and restore the simulator's original Shutdown state. Keep failed result bundles and logs. Commits stay local while Dawson and the parent resolve repository authorization; do not create a remote destination implicitly.
