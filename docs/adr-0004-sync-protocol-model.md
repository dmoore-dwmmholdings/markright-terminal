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
