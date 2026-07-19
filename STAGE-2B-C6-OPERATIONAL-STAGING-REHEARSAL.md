# Stage 2B C6 — Operational Staging Rehearsal

## Scope and stop boundary

C6 starts from authoritative C5 commit `2fecc7c552dc1d1ee185b2dbf378b915896deb60` and remains limited to the exact guarded staging project `cdsmnqxtyyoeoznmbidd`.

C6 does **not** merge, deploy to production, retire browser-local authority, clear browser-local data, retire transitional direct SELECT, or start AI work. Browser-local records remain authoritative and no production workflow depends on the retained staging records.

## Controlled batch

- Immutable approved C4 package SHA-256: `980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016`.
- Deterministic selection: clean, attachment-free eligible C4 vehicles 6 through 30 in UTF-8 `record_ref` order.
- Selected count: **25**.
- Fresh preview must show 25 inserts, zero ambiguity, and zero conflicts.
- Apply requires the exact freshly approved preview checksum and explicit `--apply`.
- Every apply is replayed with its deterministic idempotency key; one committed response is discarded and recovered through a fresh guarded connection.

## Before-rehearsal gate

- [x] Authoritative C5 HEAD and clean feature branch verified.
- [x] Exact linked staging project and guarded database DSN verified.
- [x] Migration ledger recorded through `031`.
- [x] Baseline operational row counts and mutable revisions recorded.
- [x] Fresh encrypted staging backup created.
- [x] Backup checksum/decryption validated and restored into an isolated schema.
- [x] Restore row counts, 72 discovered/added foreign keys, indexes, audit relationships, and disabled notifications verified.

## Operational acceptance checklist

- [x] **Administrator:** authenticated staging administrator can read and perform an approved vehicle operation.
- [x] **Controller/operator:** two independent controller sessions can read and perform approved operations.
- [x] **Viewer:** directly reads exact allow-listed vehicle-core/lifecycle and narrow workshop-booking fields through authenticated staging REST, records the returned field sets, excludes technician/sensitive fields, and cannot mutate either.
- [x] **Reconnect after network loss:** two browser-context offline/online cycles prove HTTP and WebSocket loss, a clearly disconnected/stale state, refused offline mutation, authoritative refetch, zero duplicated channels/callbacks, and zero unexpected console/CSP/page errors.
- [x] **Browser refresh:** refreshed session resolves the same vehicle UUID and latest version.
- [x] **Concurrent edits:** two independent controllers race one expected version; exactly one succeeds.
- [x] **Stale edit rejection:** stale vehicle and lifecycle writes are refused and do not overwrite the winner.
- [x] **Duplicate/conflict refusal:** import replay is idempotent, a duplicate booking is refused, and cross-identity import preview is refused without apply.
- [x] **Lifecycle updates:** QC complete, RFT transfer, and collection succeed through protected RPCs.
- [x] **Workshop UUID retention:** schedule/start/stop/resume/complete/return-to-queue retain the original imported vehicle UUID at every step.
- [x] **Audit/history:** selected vehicle audit evidence and authenticated workshop booking history are present.
- [x] **Role cleanup:** no temporary C6 account or role remains.
- [x] **Fixture cleanup/retention:** no temporary schemas remain; the 25 imported vehicles and explicitly enumerated operational states are retained as the documented C6 pilot state.
- [x] **Two-user Realtime:** independent administrator/controller contexts observe the same UUID/version without manual data copying.
- [x] **Zero production requests:** browser request capture contains zero requests to the production project ref.
- [x] **Browser-local authority unchanged:** acceptance uses only Playwright ephemeral incognito contexts and never opens a persistent operator browser profile. Before the first staging document executes, each isolated context receives structurally valid canaries for ordinary `vehicleTrackingCore*` authority keys; every canary is present after login/bootstrap and the complete ordinary-key snapshot is byte-identical after all online/offline/reconnect/stale-edit cycles. The report preserves independently comparable before/after SHA-256, key-count, and byte-count observations for each context without retaining local payload values. No key is cleared.

## Backup, rollback, and reconciliation

1. Create a second encrypted post-import backup.
2. Restore it into a disposable full schema with all foreign keys and indexes.
3. Export only the selected namespace with resolver and vehicle-master revision values.
4. Independently advance each restored database revision inside its own transaction savepoint and prove the saved rollback is refused for vehicle-master and lifecycle-resolver independently; roll each advance back before apply.
5. Query and lock both exact authoritative revisions, freeze every table's baseline dependent/unrelated partition by stable primary key, delete only selected rows in FK-safe order, and prove both revisions and every frozen unrelated row remain present and byte-identical through apply. Relationship-field changes cannot move audit/history rows across this boundary.
6. Drop the disposable schema and prove public retained pilot rows did not change.
7. Reconcile all 25 selected records to original source refs, UUIDs, current versions, aliases, identifiers, and source evidence.
8. Verify complete unrelated-row hashes after operational scenarios.
9. Restore the encrypted pre-rehearsal backup and compare complete canonical rows across all 46 backed-up tables, freezing stable primary-key partitions that exclude only the 25 selected vehicles, their dependent rows, the four authenticated rehearsal roles, and global revision singletons. Record baseline population/dependent/unrelated counts and keyset hashes for reconciliation.
10. Repeat rollback in an isolated post-import restore and preserve frozen keyset and full-row hashes for all 46 tables; require zero missing, changed, or newly introduced rows outside the baseline partition, including nullable-FK and audit/history rows.

## Evidence set

Evidence is under `review-evidence/stage2b-c6/` and contains no credentials or non-null prohibited customer fields. `SOURCE-PROVENANCE.json` cryptographically reconstructs the Git commit and recursive tree objects, binds every committed package member to the exact source commit, and proves the authoritative C5 commit is its sole parent. The final package includes the sanitized approved-C4 assessment plus its committed ZIP SHA-256/blob provenance, but deliberately excludes the C4 ZIP itself so the extraction contains no nested archive. It also includes the exact committed C6 source and portable test snapshot, migrations through `031`, deterministic manifests, complete final matrix/CI results, operational/browser/backup/rollback evidence, reconciliation/cleanup/safety proof, and an exact-member checksum manifest. Every final gate's sanitized command output is copied under `FINAL-TEST-EVIDENCE/`, referenced directly from `FINAL-TEST-RESULTS.json`, checksum-bound in both the package manifest and build provenance, and required to resolve by the verifier. The extracted package verifier runs the root JavaScript aggregate, complete portable Stage 2B Python discovery, C2b parity/artifact suite, C6 focused tests, SQL parsing, syntax/compile checks, semantic evidence checks, credential/prohibited-content scans, exact Git-object provenance, final-gate evidence resolution, and checksum/member verification without secrets or live connections. Install the pinned independent-review dependencies from `requirements-review.txt` before running the verifier.

## Retained pilot state

The 25 imported staging vehicles remain clearly identified by source system `browser_local_c4` and C6 source batch. Deliberate C6 vehicle/lifecycle/workshop mutations are evidence-bearing staging-only pilot states, not user-facing production records. No temporary C6 users, roles, or schemas may remain.

## Stop

After a commit-exact ZIP passes pristine extraction verification and an independent reviewer approves the exact commit/package hash, stop. Do not begin a restricted live pilot automatically.
