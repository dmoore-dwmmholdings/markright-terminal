# ADR 0004: revision, encryption and enrollment protocol

Status: MRK-11 in progress. Local model and demo-only emulator rules; no production Firebase project/deployment, real sync client or cryptography implementation.

## Revision publication

Collection/document identities remain stable across path renames. Namespace every object by authenticated tenant and collection/document identity, never a client path. Immutable revisions point to verified, complete content-addressed blobs. Uploading bytes and committing a head are separate steps: interrupted uploads cannot become visible heads. Publish a revision via a server-validated transaction comparing the expected parent to the current head. Server-assigned transaction order decides the winner, not client clocks.

A loser retains its local and uploaded immutable candidate and exposes a conflict. Never overwrite the head via last-writer-wins. Repeating an already-published revision is idempotent after a lost acknowledgment. Reusing a revision ID with different data is rejected. Merge/restore creates a new explicit revision, retaining all parent history. The model currently has one parent; a full merge DAG and conflict-resolution UX remain gates.

Tombstones are revisions rather than immediate erasure. A stale offline edit cannot resurrect a deleted document; explicit restoration must be based on the tombstone. Retention/garbage collection must account for offline devices and references before removing blobs. No permanent purge is implemented or authorized here.

`src/sync-model.mjs` and six tests model races, upload completion, idempotency, immutable data, namespace separation and delete-versus-edit behavior. Namespace inputs are abstract test values, NOT authenticated identities. The client cannot be trusted to announce blob completion, its own tenant, or a digest. Production rules/server verification and Firebase Emulator tests must enforce those invariants.

## Firebase design candidate

Firestore stores revision metadata and conditional document heads; Cloud Storage holds blobs. Security Rules require authenticated tenant membership and ownership on every read/write. Immutable object creation, exact allowed fields and size limits, revoked-device denial, and transactional parent checks require emulator proof. A trusted finalize path verifies digest/size/completion before a revision can publish. Do not assume cross-service Storage/Firestore rules provide an atomic commit. Staged blobs, verified metadata, and orphan cleanup need a recoverable state machine.

Sync is explicitly opt-in, local-first and resumable. Default local edits succeed offline. An outbox tracks durable operation IDs; acknowledgment never deletes the only source copy before verified recovery. Firebase service errors, quota exhaustion, account changes, and lost device sessions must leave local documents usable. Path collision, rename/move, attachment references, shared collection authorization and account migration remain to model.

## Encryption, enrollment and recovery gate

Firebase transport/server-side encryption is not end-to-end encryption. If end-to-end protection is selected, use audited authenticated encryption and envelope keys; do not invent cryptography. Each revision/blob must bind tenant/document/revision/format metadata as authenticated context, with unique nonces. Hashes of plaintext can leak equality, so content-addressing and deduplication need privacy review. Metadata leakage must be documented.

Device enrollment should use authenticated user intent and a verified existing device or explicit recovery method to unwrap the collection key. Account login alone must not silently grant old plaintext access if that contradicts the selected threat model. Device revocation stops future server access but cannot erase plaintext/key material already copied; rotation and history access need explicit design. Keys belong in OS-protected storage, not synced document fields or logs.

Recovery alternatives have materially different costs: user-held recovery secret can protect against the service but loss risks unrecoverable data; server-assisted recovery improves availability but changes the trust model. This choice is a product/security gate, not a routine implementation assumption. No keys were created, saved or shared. Implement only after the threat model, enrollment/revocation, loss/recovery and test vectors are reviewed.

## Provisioning decisions to request later

Before production setup: Firebase account/project ownership, region/data residency, monthly spend cap and alerts, authentication providers, retention/deletion policy, encryption/recovery choice, and production versus emulator environment separation. No paid resources or permissions are needed for the current model. Do not use placeholder production credentials, silently provision a project, or treat this ADR as approval to spend.

### Local Firestore Rules evidence

A demo-only loopback emulator now exercises eleven actual Rules tests for owner/cross-user isolation, immutable metadata, trusted-only completion records, conditional heads, conflicting writes, tombstones, schema bounds and cross-collection parent isolation. No production setup or deployment occurred. Verified-blob metadata is a server-seeded test stand-in, NOT proof of Cloud Storage finalization or cryptography. Sharing, revocation, rate/cost constraints, batch adversarial cases, real uploads and encryption remain gates. See `spikes/firebase/README.md`; the test executable refuses to run without the exact emulator endpoint.

Independent review corrected a retry mismatch: identical revision reuploads now allow equality-only no-op updates; mutations remain forbidden. Emulator batch tests confirm forged completion and revision mutation abort the entire publication batch. These are scoped checks, not a complete server security review.

## Versioned encryption proposal for security review

This is an explicit candidate protocol, NOT implemented or cryptographically reviewed. MRK-31 must validate interoperable test vectors and obtain security review before beta. Recommend optional end-to-end encrypted collections with a user-held recovery secret plus existing-device enrollment. Dawson must choose/approve recovery UX and data-loss tradeoffs before production; account password reset alone must not recover collection plaintext. Do not quietly substitute server escrow.

### Keys, envelope and authenticated context

Use vetted platform/audited library implementations of AES-256-GCM, HKDF-SHA-256 and X25519 through an established HPKE implementation (RFC 9180), rather than writing primitives. Choose and pin actual interoperable libraries in MRK-31 after Swift/Windows/Linux review; algorithm names alone are not a library selection or security proof. Each collection epoch has a random 256-bit key stored only in OS-protected device storage and encrypted enrollment/recovery envelopes. Derive a fresh blob encryption key from the epoch key using HKDF with a random 256-bit object salt and a length-prefixed context identifying protocol/tenant/collection/document/revision/blob role. Generate an independent 96-bit GCM nonce from the OS CSPRNG. Persist the complete encrypted envelope before uploading; retries resend identical bytes, never re-encrypt changed bytes with the same key/nonce. Randomness failures fail closed. No plaintext-address deduplication.

Envelope v1 contains an exact allowlist: protocol version, algorithm suite, epoch ID, object salt, nonce, ciphertext length and ciphertext/tag. Authenticated associated data is a canonical, versioned, length-prefixed encoding of tenant, collection, document, revision, blob role, parent revision IDs, format profile, epoch and encryption suite. Bind the storage object identity separately through SHA-256 of the entire canonical encrypted envelope; avoid circular inclusion of its own digest in associated data. Parent and revision metadata mismatches must fail authentication after decrypt, even if the server returned a well-formed object. Define exact byte encodings and vectors before implementation, never rely on ad hoc JSON property order. Ciphertext digest/size validation proves upload integrity, not plaintext validity or trusted authorship.

The server sees account/collection/document identifiers, graph topology, sizes, times, ciphertext digests and device membership. Encrypt paths, titles, source, attachments and sensitive calculator values inside the content manifest. Randomized per-object keys prevent intended plaintext-equality deduplication, but size/timing/access patterns remain visible. A compromised enrolled device can read permitted content; E2EE does not sandbox a malicious document. A malicious server can deny service or replay an old valid head: clients must remember observed head/epoch history and report rollback/divergence rather than silently accepting it. Multi-device freshness transparency is a further security design gate, not solved by GCM.

### Enrollment, recovery and revocation state machine

1. New collection: generate epoch key and a high-entropy recovery secret locally, show a recovery artifact for explicit user custody, and verify the recovery step before claiming recoverability. Derive a wrapping key with HKDF domain separation; no human password is used directly as a high-entropy key. Upload only an authenticated encrypted key envelope, never the recovery secret.
2. New device: authenticated account session creates a pending enrollment with a device public key and short-lived challenge. An already trusted device verifies the target identity/key fingerprint through an explicit user action, then HPKE-wraps permitted epoch keys bound to account/collection/device/challenge. The server cannot approve enrollment by itself. Recovery-secret enrollment follows a separately audited flow and requires explicit user intent.
3. Active device: keys remain in OS-protected storage; server grants and local key possession are independent requirements. Background sync must stop on revoked/expired server authorization without deleting local documents. Never log key material, recovery strings or decrypted document contents.
4. Revocation: revoke server credentials/grants immediately and create a new collection epoch for future revisions, distributing it only to remaining approved devices. Old devices can retain old plaintext and keys; rotation cannot erase those. Whether to re-encrypt historical content is an explicit costly migration, not an automatic promise. An offline revoked device's uploads are rejected and retained locally for user-directed export/reconciliation.
5. Recovery/loss: existing trusted device OR user recovery secret can restore access. Loss of all devices and recovery secret means encrypted cloud content is unrecoverable; preserve ciphertext, explain the limit and never claim Firebase password reset fixes it. Recovery-secret replacement rotates wrapping material and invalidates server-held old envelopes but cannot retract copies already taken. Account deletion/irreversible purge requires its own authorized flow.

The proof has generated no keys and has not performed enrollment. Revoked-device Rules enforcement, replay tests, hostile server envelopes, interrupted rotations and cross-platform keychain accessibility/backup semantics belong to MRK-31.

### Recoverable Storage finalize protocol

Persist a local outbox record and encrypted bytes first. Allocate a tenant-scoped immutable staging object with expected ciphertext digest/length and operation ID. States are `local -> uploading -> staged -> verified -> revision-created -> head-CAS -> acknowledged`, with explicit `conflict`, retryable failure and quarantine branches. A trusted authenticated finalizer checks ownership, object generation, exact length/digest and immutable metadata, then creates the Firestore verified record idempotently. It never accepts a client-set `verified` boolean. Storage overwrite/generation changes invalidate verification. A verified record authorizes references only to its exact object generation; publication cannot race a mutable blob.

Revision creation may precede head publication and be retried with exact equal metadata. Head CAS either advances from the observed parent, recognizes the identical already-published revision, or retains the losing candidate as conflict. Acknowledgment records durable verification but never removes the only recoverable local source. Retries after any crash resume the recorded phase; they do not recreate ciphertext or silently change identity. Finalizer events may arrive out of order or more than once. Orphan cleanup is a separate retention-based operation with reference checks and offline-device policy, not implemented or authorized by this spike.

Identity is never inferred from paths: rename is a manifest revision for the same stable document ID. Two offline documents assigned the same display path remain separate IDs and become a visible path conflict; do not merge by filename. Cross-collection moves require a new encrypted destination object/context plus explicit source history treatment, not pointer reuse across keys/grants. Attachment manifests authenticate IDs/digests as dependencies. Sharing/ownership transfer and multi-parent merge encoding remain explicit protocol extensions, not implicitly supported by the current owner-only/single-parent emulator.

## Completion boundary

The eleven emulator checks and local race model demonstrate scoped invariants only. This candidate records the requested envelope, finalize, recovery and enrollment decisions; implementation, security review, real Storage finalizer tests, device revocation and cost/region/auth-provider approvals remain MRK-31/MRK-29 gates. Production permission is still absent. The architecture can be reviewed locally without pretending those gates passed.
