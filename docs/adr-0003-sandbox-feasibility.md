# ADR 0003: constrained execution feasibility

Status: MRK-10 In Progress. No production runtime selected or iOS permission asserted.

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
