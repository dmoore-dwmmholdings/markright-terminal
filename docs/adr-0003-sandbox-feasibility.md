# ADR 0003: constrained execution feasibility

Status: MRK-10 completed as reviewed research. No production runtime selected, security acceptance granted or iOS execution permission asserted. Dated evidence below records the research progression; MRK-22–25/28 retain implementation and review gates.

## Threat model

Documents, includes, synced content, code, declared inputs, and cached output are untrusted. Opening/importing/syncing must never execute code. Host credentials, filesystem, network, DOM and native APIs must be absent. Local approval is bound to source/runtime/transitive-input hashes and invalidates on change. Stored trust must not sync as a boolean. Unknown operations fail closed. Only schema-validated, size/depth-count-limited data and approved document/control nodes cross the boundary. Raw HTML and arbitrary JavaScript objects must not cross it.

Adversaries can loop, allocate, recurse, return cyclic/huge data, exploit getters/prototypes, queue unbounded jobs, guess paths, attempt dynamic imports, and replay stale approval. A memory-safe wrapper is not a proof the embedded C runtime has no vulnerabilities. The runtime must live off the UI thread, with a killable process/worker boundary and bounded IPC in addition to interpreter quotas. No host callback may perform ambient I/O.

## Executable evidence

Pinned quickjs-emscripten 0.32.0 (test-only dev dependency) creates a fresh isolated runtime per probe. Heap limit 8 MiB, stack 256 KiB, interruption after 1,000 callback polls or a 100 ms deadline. No host functions or module loader are exposed. Six tests confirm absent fetch/require/process/document/WebSocket; interrupt an infinite loop; reject memory amplification and recursion; isolate prototype mutation across host and subsequent contexts; and retain exact 64-bit BigInt values.

Important limitation: interrupt deadlines are cooperative, not hard wall-clock limits. One memory amplification test took about 185 ms despite the 100 ms callback deadline. Host teardown/allocator time contributes too. Do not advertise a 100 ms hard execution cap. A separate killable boundary must be proven. The authored tests return only short primitives; arbitrary output dumping is NOT a safe production host API. Promise jobs, object serialization, interruption inside host callbacks, module loading attempts, side channels and a complete adversarial suite remain outstanding.

QuickJS enables more ECMAScript than the proposed profile. `eval`, Function, Date/randomness, promises and dynamic loading need an explicit language policy and enforcement. This package's WASM build is useful for desktop comparison, not proof of native iOS suitability or a portable runtime binary choice. No document is wired to automatic evaluation.

## iOS distribution gate

Checked Apple's official App Review Guidelines on November 8, 2026: https://developer.apple.com/app-store/review/guidelines/ . Section 2.5.2 restricts downloading/installing/executing code introducing or changing app functionality, with a limited educational-code exception. Section 4.7 has separate conditions for offered software; 4.7.2 prohibits exposing native platform APIs without Apple's prior permission. These do NOT establish blanket approval for Markright scripts. We should not assume this document editor qualifies as an educational app or that a general interpreter bypasses policy.

Recommendation: keep downloaded document scripts inert on iOS until runtime and distribution review resolve the gate. Preserve reading, static exported output, and an explicitly limited declarative calculator profile as a fallback. A bounded expression/data DSL with fixed operations differs materially from arbitrary downloaded scripts, but still needs policy/product review; it is not an automatic exemption. Native no-JIT feasibility and App Store approval are separate questions.

## Remaining gates

Prove worker/process termination, heap/output/job limits, schema validation, host API capability absence, trust invalidation and deterministic input handling. Compare native QuickJS/JavaScriptCore constraints, measure startup/footprint and Swift interoperability, test on device, and resolve current distribution interpretation. Any declarative fallback must preserve portability and clearly label unsupported computations. MRK-R10/R11/R12/R16 remain unaccepted.

### Killable-boundary proof

A separate Node worker initializes QuickJS with no cooperative interrupt handler and runs an endless guest loop. The parent waits for readiness and explicitly terminates the worker; the test verifies exit and a two-second termination upper bound. This passes and closes the narrow desktop-host feasibility question of stopping a noncooperating WASM guest. It is not an implementation of document trust, output validation, IPC quotas, mobile termination or an OS process sandbox. Worker startup/hard-deadline policy remains to be integrated. Under shared-machine load, cooperative allocation teardown also reached roughly 626 ms, reinforcing that its 100 ms callback deadline cannot be presented as a hard bound.

### Heap-evidence correction from independent review

The initial growing-array test could stop by CPU interruption, so it did not establish allocator enforcement by itself. The harness now retains error names/messages, labels that test as interruption-or-OOM, and separately requests a finite 16 MiB ArrayBuffer under the 8 MiB heap cap. That test explicitly requires `InternalError` with `out of memory`. The earlier broad heap-verification wording should be read only with this added allocator-specific evidence. A configured cap alone is not a proven cap; worker termination remains separate from memory verification.

## Runtime comparison and proposed research decision

| Candidate | Strength | Constraint / disposition |
| --- | --- | --- |
| QuickJS WASM in a desktop worker | Explicit allocator/stack/interrupt controls; tested termination, BigInt and absent ambient APIs | Carry forward for desktop prototype only. WASM overhead and native binary packaging still unmeasured. Worker is not OS isolation. |
| Native QuickJS interpreter behind Swift/C | Interpreter architecture does not require JIT; same language family across platforms | Unbuilt candidate, not a demonstrated iOS binary. C memory safety, interrupt/allocator integration, signed packaging, device killability and App Review need MRK-28 review. Do not assume WASM test results apply to it. |
| JavaScriptCore via public Apple API | System integration, native Swift/Objective-C bridge | Reject as the initial portable untrusted runtime: does not provide this spike's proven per-runtime heap/interrupt/kill contract, and is not a shared Windows/Linux solution. JIT availability is platform/entitlement-dependent; no entitlement should be requested to bypass policy. |
| Fixed declarative decoder | Bounded field extraction, no user instructions, precise integers, portable static fallback | Carry forward on all platforms as a limited calculator candidate; not a general scripting replacement or App Store exemption. |

The research recommendation is desktop QuickJS worker experimentation plus an iOS inert/declarative-first path, with native execution explicitly blocked on MRK-28. No downloaded native code, JIT entitlement or private API is proposed. Ship only bundled reviewed code; imported JavaScript stays inert on iOS pending that separate gate.

### Proposed host profile 0.1 (not implemented)

Each execution consumes a length-bounded UTF-8 JSON request containing a supported profile/runtime version, immutable source hash and declared input snapshots. Inputs include only explicitly selected typed document values, never host objects or a generic callback bridge. Version/hash/transitive-input changes invalidate local approval. Fresh runtime per execution; no context reuse. Reject dynamic import/module loading, eval/Function constructors, promises/jobs/async, Date/randomness, proxies and host I/O in the constrained language profile. A syntax allowlist plus removal of reachable intrinsics and absence of host capabilities must be independently reviewed: lexical filtering alone is not enforcement. Existing QuickJS probes have NOT implemented this restricted profile.

The proposed response is one JSON string, at most 64 KiB, with an explicit version and an allowlisted text-only table shape. No raw objects, callable values, markup interpretation, URLs, event handlers, native handles or arbitrary actions cross the boundary. Validate byte length before parse, reject duplicate/prototype keys, bound nesting/nodes/strings and validate exact fields. Future control nodes require a separate versioned schema and explicit capability review. Bound serialization inside the guest before transferring bytes; the host validator alone does not prevent a guest allocating a huge serialized result. Enforce IPC frame size and process/worker quotas before host allocation in production.

### Executed structured-output and declarative proof

`spikes/runtime/output-boundary.mjs` uses pinned jsonc-parser 3.3.1 to preflight strict JSON (no comments/trailing commas, duplicate keys or prototype keys), with a 64 KiB input cap, depth 12, 4,096 visited values/properties/containers and 4,096 UTF-16-unit strings. Output permits only version 0.1 tables with 1–8 columns and at most 64 rows of plain strings. It is a test-only adapter, not wired to a renderer, IPC or runtime evaluation. HTML-looking cells are retained as text and MUST NOT be interpreted downstream.

A `markright-data` JSON body may describe `kind: "markright.bitfields/0.1"`, `bits` (8/16/32/64) and fields containing exactly `id`, `label`, `lsb`, `width`, `signed`. The fixed evaluator takes a separate decimal/hex string, rejects overlaps/out-of-range/duplicate fields and returns validated table output. BigInt preserves unsigned 64-bit maximum and signed two's-complement results. Unsupported kinds/fields/versions produce a local diagnostic, leave source readable and never fall back to eval. This proposed data shape does not add a language directive, scrape document text or auto-run on open. A product UI, trust affordance, input controls and native implementation remain MRK-22–25/28 work.

Four added tests cover strict JSON failure modes, output schema refusal, exact signed/unsigned 64-bit results, invalid operations/ranges/overlaps and malformed input. No crypto, native API, file/network bridge or production trust store is created. This demonstrates a bounded fallback computation, not complete runtime security acceptance.

Independent review found JSON number rounding could turn fractional field widths into allowed integers. The boundary now accepts numeric tokens only as canonical nonnegative decimal safe integers, checked against original lexemes before parsed values are used; exact 64-bit inputs/results remain strings. Fractional/exponent/negative-zero/unsafe numeric tokens fail closed. This is a deliberately narrower research schema, not a general document JSON parser. Five output/fallback tests cover the corrected boundary.

MRK-28's later native typed-kernel, shared vector and static-readability follow-up is recorded in `adr-0005-ios-declarative-fallback.md`. It retains the inert iOS scripting/distribution gate; typed native parity does not implement untrusted document JSON validation.
