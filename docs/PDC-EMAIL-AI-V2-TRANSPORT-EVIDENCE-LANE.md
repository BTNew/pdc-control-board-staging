# PDC Email AI v2 transport/evidence lane

Status: implemented locally; shadow only; no operational write path.

## Boundary

`backend/pdc_email_ai_v2_transport.py` is the only mailbox-facing v2 adapter. It selects each configured folder with `readonly=True`, searches from a persisted UID cursor, fetches message bytes with `BODY.PEEK[]`, and reads flags before/after the fetch. It never issues `STORE`, `EXPUNGE`, or a business/database call. A UIDVALIDITY change fails closed and requires a new cursor boundary.

`backend/pdc_email_ai_successor_intake.py` retains the RFC822 bytes and each bounded attachment under content-addressed paths. The receipt includes the source/evidence digests, thread/message metadata, receive time, attachment hashes, and transport read-only metadata. Repeating the same source returns the original receipt with `duplicate=true`; a digest bound to incompatible metadata raises a conflict.

`backend/pdc_email_ai_v2_queue.py` stores only references to immutable receipts/planner inputs. It provides idempotent enqueue, bounded worker leases, heartbeat, expired-lease recovery, retry/review outcomes, append-only queue events, and a monotonic `(folder, UIDVALIDITY, high-water UID, source digest)` checkpoint. It is separate from the frozen legacy queue and does not call Supabase.

`build_planner_input()` provides a detached planner envelope. Complete correspondence and each attachment's extracted text/evidence reference remain present. The planner must assign one typed disposition to every instruction; unknown text is not dropped or converted into a mutation.

## Shadow comparison

`backend/pdc_email_ai_v2_shadow.py` loads and hashes the frozen-100 handoff at:

`C:/Users/nwmgr/HermesWorkspaces/development/pdc_email_ai_v2_taxonomy_handoff.md`

It verifies the complete 100-message read-only audit, proposal-only taxonomy status, and mandatory negative fixtures. Its comparator emits `PLANNED`, `REVIEW`, `UNSUPPORTED`, or `CONFLICT` decisions for every input line and compares each stable source-line ID with incumbent output. It always reports `operational_writes_attempted=false`, `mailbox_mutated=false`, `legacy_runtime_touched=false`, and `production_touched=false`.

The mixed line `FMG Signage 75mm Safety stripping, FMG Logo's, ID, Tare,GVM,GCM Decals` is checked before generic GVM matching and remains `REVIEW`, never Hoist. Generic reflective stripes remain review-only unless explicit Job Card SUBLET or authorized provider/booking evidence is supplied. Frozen audit recommendations for wheel-nut indicators, fire-extinguisher hardware/decal separation, and long-range tanks are covered by the regression suite.

## Verification

Run from this worktree:

`python -m unittest -v tests.test_pdc_email_ai_v2_transport tests.test_pdc_email_ai_successor_intake tests.test_pdc_email_ai_successor_poller tests.test_pdc_email_ai_successor_contract tests.test_pdc_email_ai_successor_planner tests.test_pdc_email_ai_successor_end_to_end`

This lane has no STAGING operational writer, no Supabase schema/RPC changes, no mailbox mutation, and no Production capability.
