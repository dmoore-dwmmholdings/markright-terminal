# Whole-source editor mounting candidate

This local follow-up starts from the unverified MRK-52 authoring checkpoint `0a1668f`, preserving the original branch and all earlier candidates. **The change is uncompiled and unrun.** It is tracked with the open MRK-39 recovery-input investigation and does not claim to fix that observed failure.

## Bounded change

Whole-document Source mode now uses the existing nonlazy `VStack` path. It contains one native source editor with its existing generation identity, value, selection and callback. This avoids relying on a lazy row remaining mounted as the surrounding save/recovery header changes the available viewport. Ordinary block editing and large reading documents retain their existing lazy path; the bounded reading-row retention policy is unchanged.

This condition already exists on the independent MRK-46 companion-preview branch. The authoring branch inherited the earlier lazy whole-source layout from its common base; the authoring commands did not remove a retention fix. This follow-up aligns the mounting policy without adding preview or merging either branch. No source mutation, persistence, generation reset, autofocus change, new input callback or external capability is added.

## Evidence and verification gap

Read-only source comparison found identical storage/session/model and recovery UI-test logic in the two branches. It found no concrete storage rollback defect. The prior MRK-39 failure first observed incomplete input after `app.typeText`, before checkpoint and restore comparisons. Its cause remains unknown. Lazy mounting is a risk to investigate, not an established explanation for that observation.

The existing `RecoveryWorkflowTests.testTypingContinuesWithoutRefocusAfterSaveFailureHeaderAppears` exercises the relevant transition: type an exact prefix, wait for save failure/current recovery acknowledgement, type the suffix without another tap, then require exact full UTF-8 source and a current checkpoint. The stricter diagnostic harness compiled at an earlier checkpoint but its selected runtime cases have not run. The new layout and accumulated MRK-50/51/52 code also remain uncompiled/unrun. Historical test/build counts do not qualify this candidate.

After a freshly coordinated native slot is available, compile the current app and test targets with warnings as errors, then run the two focused recovery methods on the existing owned simulator only if its separate boot gate is resolved safely. Observe native editor identity, focus, selection and undo across header relayout and scrolling; the UI source/keyboard checks alone do not prove native object identity or IME retention. Keep the complete-input, checkpoint and restore phases distinct, preserve failed logs and do not terminate after failed prerequisites. No speculative simulator repair, keyboard-setting change or unattended VoiceOver action is authorized by this change.

Only source review and `git diff --check` are available for this slice. Live host admission found competing compiler work, so no Markright Swift build, test, simulator or visible app was started and no other owner's process was interrupted. Full parser/renderer, actual OS input/IME/undo, accessibility, ingestion/isolation/provider/device and release gates remain open. Public-push and separate disclosure holds are unchanged.
