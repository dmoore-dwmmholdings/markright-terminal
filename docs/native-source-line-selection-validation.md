# MRK-52 native source-line selection candidate

This local candidate starts from MRK-51 `62bc1c0` on `spike/native-source-line-selection`, reusing its worktree and owned caches. It includes the still-unverified MRK-50/51 source candidates. **All new compilation and execution remain pending.** Earlier MRK-49 counts are historical evidence, not acceptance of this code.

The native whole-document contextual menu adds **Select source lines**. It expands the current caret or selection to complete touched physical rows, including their original CR, LF or CRLF endings. A nonempty selection ending exactly at a later row's start excludes that untouched row. The destination excludes the initial BOM, even when the original selection included it; internal BOMs remain literal. A caret at EOF without a trailing ending selects the final nonempty row. An empty EOF row after a trailing ending has no action, while an interior blank row can select its ending. An already-expanded selection is disabled.

This makes whole-row heading, quote, list and task source commands easier to apply after native word selection. It selects literal physical rows, independent of Markdown constructs. It does not insert or replace source, parse code, resolve references, access a file/provider/clipboard, use network or execute scripts.

Source is limited to 1 MiB UTF-8 before native string bridging or range arithmetic. Original UTF-16 endpoints must pass the existing surrogate/CRLF validation. A transient UTF-16 array contains at most 1,048,576 units (about 2 MiB payload plus array overhead) for constant-index row scans. The plan retains the original source and selection; its destination is independently validated. No latency, total-memory or production security guarantee is asserted from these bounds.

AppKit and UIKit reuse the existing selection-and-scroll reporter path and exact-source/current-selection `SourceNavigationPlan`. Action execution rechecks attached native focus, editability, one selection, composition and captured source/range. UIKit has an independent whole-document flag set on both view creation and update; fragments/recovery views remain outside scope. Retained menu actions weakly reference their source view. AppKit's direct root-menu item also validates availability so automatic menu enabling cannot revive nil or stale plans. Existing Find menus retain their auto-enable policy.

## Authored verification

Shared cases cover all valid caret positions in Unicode/BOM/mixed-ending rows, exclusive ending ownership, partial/multi-row expansion, internal BOMs, blank rows, empty EOF and no-ops, surrogate/CRLF/overflow refusals, exact and excessive 1 MiB ASCII/Unicode input, literal code/URI/separator text and exact-byte/original-selection stale guards.

The AppKit runner adds real local menu targets and root validation, exact ending/BOM-excluded native/reported selection, retained focus and typing undo/redo, and stale/read-only/non-source/multiple/marked/detached refusals with exact before/after state. Whole-workspace clean/conflicted cases require the same source revision, generation, editor/session, full fixture file bytes/modification dates and current recovery checkpoint after 650 ms; a conflicted baseline first settles for a separate 650 ms. Final no-activation/hidden-window/real-manager guards remain required. UIKit detached/scope/context-range cases are authored for compilation only.

Independent read-only review found no blocking issue in UTF-16/half-open row ownership, BOM/EOF/no-op handling, arithmetic bounds, native guard/reporting behavior, authored preservation checks or package/project wiring. It gives GO for a local checkpoint pending serial verification. `git diff --check` passes. No test or build has run; execution evidence remains separate from source review. Pending serial verification is the complete shared corpus, invisible AppKit runner and unsigned Mac/iOS test-bundle builds, with fresh coordination, at least 20 GiB free and at most two compiler jobs. Other owners' native tests are left untouched. No simulator boot or UIKit test is started automatically.

## Preserved launch-preflight result

After review, a preliminary inventory showed no active compiler/native jobs. The final shared-test launch guard then detected a newly active Xcode process and refused **before starting Swift or creating the test log**. No test/build result was produced, no other process was stopped and no competing Markright heavy job began. Source checkpoint `f7fc1b8` remains preserved. This is a resource-preflight refusal, not a compiler or test failure; verification still needs a coordinated quiet slot.

## Preserved gates

The full parser/renderer/authoring, actual OS menus/keyboard/IME/undo, attached UIKit behavior, attended VoiceOver, physical devices, MRK-46 preview AX observation, untrusted ingestion, network isolation/provider/security and release gates remain open. No main merge, push, alternate publication, credentials, deployment or held external documentation write occurred. Earlier local checkpoints, visible Debug app/preview and other owners' work stay preserved.
