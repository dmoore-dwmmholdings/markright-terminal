# MRK-9: bounded attended VoiceOver experiment (not performed)

MRK-9 stays open until this explicit experiment is run and recorded. Automated light/dark accessibility audits passed, but are not VoiceOver evidence. No one should enable a foreground screen reader unattended or disturb the user's active desktop.

## Setup and boundaries

Agree on a short attended window and coordinate simulator ownership with other workers. Use only Markright's dedicated simulator, never the user's physical devices or other projects' simulators. Save current simulator and accessibility settings, use synthetic fixture documents only, and agree on the screen-reader toggle/stop method before starting. If simulator VoiceOver is unsupported or unreliable, record that result and arrange a separately approved test device; do not claim simulator accessibility inspection is equivalent. Do not enable macOS VoiceOver as a substitute for iOS VoiceOver.

## Ten-minute script

1. Start with heading, paragraph, blank line, link-like text, code fence and table fixtures. Traverse forward/backward. Record spoken labels, role, order, focus visibility, duplicate/omitted elements, and blank-line edit discoverability.
2. Activate a paragraph. Confirm editable role, current text, insertion point and ability to edit literal Markdown. Type punctuation and emoji with VoiceOver keyboard operation. Exit with Done; confirm focus returns to the same block, not the start of the document.
3. Enter a code fence and table. Confirm the whole atomic block is editable and announced meaningfully. Move selection across boundaries, cancel/finish, and compare complete source bytes before/after.
4. Navigate around an active composing text field if a supported input method is available. Record actual IME separately; do not substitute the programmatic marked-text probe.
5. At larger Dynamic Type and in dark mode, repeat paragraph/Done navigation. Check that focus is not hidden by keyboard or safe-area controls.
6. Open the 1 MB fixture, navigate into/out of an edit and scroll away/back. Record responsiveness qualitatively and any lost focus/text. This is not a p95 input-to-paint benchmark.

Stop immediately on unexpected foreground interference or source loss. Capture OS/device/build commit, exact actions and spoken output, expected/actual results, source comparison, and defects. Restore the prior accessibility setting and shut down only the owned simulator. Keep MRK-9 open for failures or an unperformed test; downstream production accessibility acceptance remains separate even if this spike passes.
