# MRK-11 loopback security-rule spike

This directory is an isolated Firebase **demo emulator** experiment, not a deployable service. No production project, credentials, key material or user documents are used. The script requires exactly `FIRESTORE_EMULATOR_HOST=127.0.0.1:18080` and a hardcoded `demo-markright-spike` project. It fails closed without that endpoint. Never deploy these partial rules.

Run from this directory with Node 24 and a working JDK:

```
firebase emulators:exec --project demo-markright-spike --only firestore --config firebase.json 'node --test rules-check.mjs'
```

Tested Firebase CLI 15.15.0, Java/Temurin 26.0.1, Firebase SDK 13.2.0 and rules-unit-testing 6.0.0. Dedicated loopback ports: Firestore 18080, hub 18440, logging 18450; UI disabled. Do not stop other workers' emulators. The exec command tears down its own emulators after tests. Logs/build state are ignored by git.

Eight passing emulator tests demonstrate authenticated namespace isolation, immutable revision records, trusted-only completion metadata, complete-blob head gating, concurrent sibling conflicts, tombstone/restore behavior, idempotent head retry, bounded metadata and cross-collection parent isolation. Expected permission-denied logs are negative-test evidence, not unexpected service failures.

Verified-blob metadata is seeded with rules disabled only inside the test environment to stand in for a future trusted finalize service. No real content digest, Storage object, byte length, upload or encryption is verified by this spike. Storage rules, trusted finalize implementation/authorization, batch/transaction adversarial cases, rate/cost limits, device revocation, sharing, queries, encryption/recovery and lifecycle tests remain gates. Metadata parent checks are not a complete merge/conflict UI.

Dependency audit initially flagged Firebase's transitive gRPC version for GHSA-m9gg-hp2v-232j. A compatible exact override to @grpc/grpc-js 1.13.6 removes that advisory; npm audit reports zero vulnerabilities at this checkpoint. Do not use `npm audit fix --force` to downgrade the SDK or treat a clean audit as security approval.
