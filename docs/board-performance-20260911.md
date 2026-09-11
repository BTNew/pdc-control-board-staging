# STAGING board refresh performance — 11 September 2026

Project: `cdsmnqxtyyoeoznmbidd`. Source baseline: `6af6340d9fbf97cc2aee3cda100ca3d2e2736860`.

The service-operation history lookup in `pdc_qc_operation_lines_379` scanned history once per operation because it lacked an operation-id index. Its parent operation lookup also lacked a vehicle-id index. The history table had recorded over 4.2 million sequential scans. No blocked queries or deadlocks were observed during this investigation.

Two lookup indexes were applied in migration `20260911010706`, guarded by the STAGING sentinel and a three-second lock timeout. No function, permissions, business data or production resource changed.

## Read-only measurements

The same projection across all 111 visible active vehicles was measured before and after:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT sum(octet_length(public.pdc_qc_operation_lines_379(v.id)::text))
FROM public.vehicles v
WHERE v.deleted_at IS NULL AND v.lifecycle_state = 'active' AND v.visible_on_board;
```

| Measurement | Before | After live indexes |
| --- | ---: | ---: |
| Execution time | 1667.936 ms | 161.413 ms |
| Shared buffer hits | 2,176,877 | 19,757 |
| Shared buffer reads | 0 | 11 |

This component was 10.3 times faster in the observed run, approximately 90% less time. These measurements are not an end-to-end browser load-time guarantee.

A transaction rollback trial retained each non-deleted vehicle's complete JSON job projection in a temporary table, created the indexes, then compared the results with `IS DISTINCT FROM`: **381 vehicles, zero differences**. The trial rolled back before the real migration. Post-apply readback retained **111 visible vehicles and 13 pending reviews**. Both index definitions and the migration ledger were verified.

## Website refresh changes

Navision and operational snapshot realtime callbacks now queue a trailing refresh instead of superseding an in-flight refresh. Bursts coalesce into one follow-up; an update arriving during that follow-up queues the next read. This avoids overlapping background snapshot reads without losing revisions that arrived after a snapshot was read. Sign-out invalidation clears queued work. Existing explicit supersede and duplicate-click behaviour remain covered.

Five new behavioural regressions cover revision bursts, revisions during follow-up, failed reads, invalidation and explicit supersede. The full local regression suite passes **347 tests**. Changed script URLs have fresh cache markers.

Supabase security and performance advisors were reviewed after DDL. No finding named either new index. Existing advisor findings include unindexed foreign keys and authentication/RLS items; these require a separate scoped review rather than indiscriminate index or permission changes. Reference: https://supabase.com/docs/guides/database/database-linter

Browser automation could not attach to the user's existing Chrome board tab (CDP timeout); no authenticated end-to-end browser timing is claimed.
