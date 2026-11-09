# ADR 0005: native declarative calculator feasibility

Status: MRK-28 in progress; scoped research, not iOS script/distribution or production security acceptance. Build context: Disegno MRK v2, MRK-R16. MRK-10 is Done as reviewed research; MRK-9/12 and downstream data/runtime/client gates remain separate.

## Candidate and execution boundary

Carry a fixed, bundled Swift bit-field decoder as the native fallback candidate. It consumes typed declarations and a bounded integer string, producing an inert text table. No interpreter, downloaded native code, JIT, private API, generic host callback or file/network capability is needed by this implementation. It is not a general scripting substitute or a new Markright directive. Native UI does not invoke the kernel; its callers are tests only. Opening/importing/syncing never gains an execution path from this work.

Imported JavaScript remains inert. Preserve readable source and explicitly labeled static results when execution is unavailable. Product invocation controls, local consent, provenance/freshness and unsupported-state UX still require integrated design. Do not silently execute a script because its output resembles this decoder's table.

## Current Apple evidence — November 9, 2026

Apple's guidelines require public APIs (§2.5.1) and restrict downloaded/executed code that changes app functionality (§2.5.2). The limited educational exception is not assumed to cover Markright. §4.7 permits specified non-binary software subject to conditions, including prior Apple permission for exposed native APIs (§4.7.2), per-instance data/permission consent (§4.7.3), and indexing/age requirements. Whether document calculators fall within that category remains unresolved. TestFlight is not an exemption from review rules. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Do not claim a universal iOS JIT ban: Apple supplies JIT to authorized alternative-browser developers under a narrowly qualified EU entitlement program. That is not a general calculator-runtime route. [Alternative browser engines](https://developer.apple.com/support/alternative-browser-engines/)

Engineering inference: fixed bundled Swift operations over bounded data avoid the need for those runtime capabilities. This supports a feasibility candidate, not Apple's classification or approval of a finished app. Public policy, runtime feasibility and actual device/distribution review are distinct evidence.

## Typed native contract and limits

`spikes/ios-editor/Sources/DeclarativeDecoder.swift` accepts the fixed `markright.bitfields/0.1` kind; word widths 8/16/32/64; 1–64 nonoverlapping fields; ASCII identifiers up to 64 bytes; labels up to 4,096 UTF-16 units; and exact bounded integer positions/widths. Ranges validate by subtraction before shifts/addition. Identifier checks avoid an unbounded temporary byte-array copy. Input is at most 20 UTF-16 units, canonical nonnegative decimal or lowercase `0x` plus hexadecimal digits. Checked UInt64 multiplication/addition rejects overflow without floating point. Signed 64-bit output uses the original two's-complement bit pattern, including Int64.min.

Output has version `0.1`, kind `table`, fixed `Field`/`Value` columns, at most 64 rows and literal strings. Serialized UTF-8 JSON must fit 64 KiB before a result returns; consumers must not interpret cell text as markup, URLs or actions. Intermediate serialization is bounded by the fixed field/string limits; no hard latency/security guarantee is asserted.

This typed API is **not an untrusted JSON parser**. Foundation JSONDecoder appears only in the trusted test-corpus loader. Duplicate keys, unknown fields, original numeric-token validation, source quotas and document trust must be resolved before document JSON can reach native typed values (MRK-16/22/23). The JavaScript strict-JSON adapter's parser-only checks are not inferred from native typed-kernel parity.

## Shared vectors and static readability

`fixtures/bitfields-0.1.json` contains 49 authored trusted vectors: 16 exact tables and 33 refusals. They cover UInt64.max, signed extrema, partial/single-bit fields, 64 disjoint fields, literal labels, malformed input, overlap/duplicate IDs and range bounds. Expected strings are explicit, and both JavaScript and Swift consume the same file. Native-specific tests add Int.max range probes, UTF-16 limits and output-size/escaping cases.

`fixtures/calculator-static.md` is an authored ordinary Markdown document with a readable frozen result, data declaration and deliberately inert script-shaped text. It explicitly disclaims freshness/trust verification. The native `--static-calculator` fixture path reads only that bundled file; it does not call the decoder or an interpreter. Its UI check requires the result and literal script source to remain readable. This is fixture-level fallback evidence, not full snapshot import/export, provenance or interactive calculator UI acceptance.

## Verification and remaining gates

The full Node suite passes 81 tests, including both shared-vector groups. The native author additionally ran pure Swift warnings-as-errors probes over all 49 vectors and 18,432 exhaustive 8-bit field/value/signed combinations. These extra temporary probes are review evidence, not additional committed XCTest methods. Independent source review found no blocking arithmetic, inertness or boundary defect.

The first attempted native run could not find the old dedicated iOS 26.5 simulator/runtime after cleanup; it produced no test pass. A new dedicated Markright iPhone Duo simulator uses the already-installed iOS 27.2 runtime, without downloads or other projects' devices: `Markright-MRK28-iOS27-20261109`, `B41A0866-71EA-45B5-94DB-C1634AEC0F5B`. Seven native decoder tests and one static-readability UI test pass. Result: `spikes/ios-editor/build/MRK28-native-declarative-ios27-20261109.xcresult`; initial unavailable-destination evidence is retained separately. This targeted run did not rerun the existing editor/accessibility suites or test iPad/physical hardware. It is not a latency benchmark or security approval.

Untrusted-data ingestion, actual calculator UI/consent, freshness/provenance, physical iPhone/iPad behavior, App Review classification and the finished distribution design remain gates. No physical device, signing credential, submission, new entitlement, production service or screen reader was used. MRK-9 VoiceOver observation is not satisfied by these tests; MRK-12 framework/contract review remains gated.
