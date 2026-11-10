# MRK-51 bounded native outline-label candidate

This follow-up to the MRK-47 source outline (PR #4) is ported from spike commit `62bc1c0`. It changes only `SourceOutline.swift` and its tests. Verification status is listed in the pull request.

The existing MRK-47 source outline abbreviates native labels at 80 Swift Characters. A combining sequence can form a single Character while retaining most of the 64 KiB source allowance in its label. The follow-up retains the 80-Character display-body limit and adds a **320 UTF-16-unit display-body limit**. Only complete grapheme clusters are appended. If the next whole cluster exceeds either remaining budget, the label ends with an explicit ellipsis. A first cluster exceeding the unit budget produces `…`; a genuinely empty heading keeps `(empty heading)`.

The ellipsis is one additional UTF-16 unit, so abbreviated title bodies fit at most 321 units including it. Level and physical-line metadata remain in the native menu title. Control sanitation is unchanged. This is display abbreviation only: original source bytes, BOM, physical endings, full heading ranges, line/level information, exact-source captured plans, native source selection and destination remain authoritative. Navigation selects the complete original heading even when its label is only an ellipsis. Source scanning still refuses above 64 KiB or 128 headings and retains its explicit unsupported-context behavior. No new rendering, resolution, file/clipboard/provider/network/script capability is added.

## Authored checks and review

Two additional shared methods exercise an oversized combining cluster with BOM/NFD/mixed endings and its complete navigation range; exact/over-unit-budget combining suffixes; and whole supplementary flag graphemes at the 80-Character/320-unit boundary. Existing Character truncation, empty/control sanitation, fence/HTML/byte/heading limits and stale/range regressions remain included. No UIKit/AppKit action wiring changed. ## Open gates

The iOS simulator runtime, attached UIKit interaction, actual OS input, VoiceOver, physical devices, full parser/renderer/authoring and release gates remain open. A display-size bound is not a latency or accessibility acceptance result.
