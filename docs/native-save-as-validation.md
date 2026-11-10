# MRK-38 native Save As validation

This bounded app-owned native editing slice extends MRK-36/37 against pinned MRK v2 requirements R6/R7/R15. It does not start or accept gated production MRK-18/MRK-12 or introduce external-folder grants.

## User workflow

Save as opens a native naming sheet with existing app-owned collections and a new filename. It creates a separate file and continues editing that destination, preserving the original `.md`/`.mrk` suffix. Existing destination names, including case/Unicode equivalents, are refused without overwriting. Cancel or failed creation leaves the current document and source open. Dismissing the naming sheet resumes normal autosave on whichever destination remains active.

The operation copies document source only. Linked assets and includes are not copied or rewritten; relative references may resolve differently in another collection. Full reference/asset and portable-identity handling remain gated. Already completed or in-flight autosaves to the original file remain valid; Save As does not undo prior editing. The creation operation itself never replaces the original.

The editor model, exact source and selection extent survive destination change. After sheet dismissal, a fresh native editor generation restores the saved range and keyboard focus while rejecting callbacks from the prior view. Composition and reading mode block inappropriate focus changes; direction/affinity, cross-mode undo and complete real-keyboard behavior remain unqualified.

## Receipt and recovery ordering

A destination change cancels the pending debounce, waits for an active autosave receipt and prevents another old-destination pump iteration. Composition is checked again after that wait. A confirmed recovery checkpoint covers the captured source before creating the new document through the existing non-clobber storage API.

Only a committed creation receipt rebinds the session. Its source revision becomes the saved revision, so edits arriving during creation remain dirty and subsequently save to the new file using its receipt baseline. Concurrent destination changes are refused; flush joins an active destination operation before saving the newest source. A warning still represents a committed copy: its baseline is retained, while uncertain durability keeps the recovery checkpoint and close gate. Cleanup failure cannot erase a committed receipt and remains explicitly retryable.

Failed copy attempts retain their recovery snapshot when available and keep the naming sheet open for another choice. Cancel/swipe dismissal resumes the original destination's autosave without needing another edit or manual flush. This lifecycle boundary is tested separately from successful-copy debounce. Destination errors remain distinct from original-file save errors.

## Validation and limits

Native interleaving tests cover in-flight old saves, changes during creation, concurrent copy/flush, stale recovery acknowledgements, composition, warnings and cleanup failures. Actual-store tests verify an observed divergent original can be saved to another collection, future writes reach only the copy, collision/path refusal retain source, and BOM/mixed-ending bytes reopen exactly. UI checks cover two collections, literal source, direct caret resumption without another editor tap, original/copy divergence, relaunch, collision/cancel, and unfiltered light/dark naming-sheet audits.

Final `spikes/ios-editor/build/MRK38-native-save-as-verified-20261110.xcresult`: **91 native/model/decoder +23 UI tests pass** (114 total), zero failures/skips/runtime warnings, Swift warnings-as-errors. New coverage comprises sixteen session groups, four store/focus groups and four UI methods, alongside all prior collection/recovery/editor checks. Initial targeted 21/2 audit failures identified the single-line name field clipping at large text sizes; a vertically expanding field corrected it. The corrected targeted 24/0 run and final 114/0 retain all audit categories. Independent lifecycle review also identified missing autosave resumption after cancelled failed copies; the dismissal hook and no-edit/no-flush regression corrected it.

Summary: `build/MRK38-native-save-as-verified-summary-20261110.json` under the iOS spike. Reopened-copy screenshot: `build/MRK38-save-as-reopened-attachments-20261110/58162861-B533-4211-B831-858CCC7C737C.png`; visual inspection confirmed the copied title, saved status and literal source with subsequent new-destination edits. The original and relaunch assertions are in the UI result. Original failed audit bundles/diagnostics remain local. Independent code/privacy review cleared the scoped changes. The simulator was verified Shutdown; about 154.4 GiB remained free, with no cleanup performed. The dedicated owned iPhone Duo/iOS 27.2 simulator is reused and restored to Shutdown. Build stages require at least 20 GiB free. No runtime download, physical device, signing, credentials, infrastructure or deployment is involved.

The native editor is still a partial preview/source/reading prototype. External providers, full Markdown/reference/asset/identity handling, actual disk-full/permission-loss/fsync failure campaigns, power-loss/crash-before-checkpoint, VoiceOver/real keyboard IME, physical devices, network isolation/security and release acceptance remain open. Public source availability does not change these gates.
