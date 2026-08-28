# Corrected owner-scope incident — Stock 13000769 / 13017855

Date: 2026-08-28
Environment: staging only
Dashboard association: `20260828_161016_aa9508`

## Incident

A concurrent worker applied migration 746 to Stock `13000769` (`d777b071-a2b0-5367-893b-aa83a07fcfce`) after treating Craig's deletion instruction for Stock `13017855` as a complete staging removal request for `13000769`. Migration 746 recorded the wrong owner-scope reason in its immutable UID 639 replay fence and purge receipt and removed 29 tables / 207 rows.

The concurrent Parts task history independently identifies Stock `13017855`, Job Card `J139125422`, and explicitly says not to delete it. That establishes the scope-binding failure: the Parts instruction target and the purge target were different exact identities, but the purge lane was authored with the latter as its hard-coded target.

## Correction

- Migration 746, its purge receipt, and replay fence were not edited, deleted, or replayed.
- The encrypted staging target-closure backup was independently hash/decrypt/readback verified.
- Append-only migrations 747–750 restored the exact canonical Stock `13000769` closure, opened a new QC retest cycle, preserved old evidence as immutable superseded history, accepted a fresh mobile-photo evidence row, and projected all 17 operation lines through the existing Board snapshot.
- A database guard now blocks deletion/archive/unlink of the restored Stock `13000769` identity and does not apply to Stock `13017855`.
- The old UID 639 replay fence and claim floor 640 remain in force; monitor mailbox, stage writers, automatic rules and outbound email remain disabled.

Production was not contacted or changed.
