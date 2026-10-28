# Kajel: one-step Service as a Whole import (r620)

Staging `cdsmnqxtyyoeoznmbidd` only, on the same management/postgres connection as today. Never production.
Parts, BT and KTA are unchanged. Only section 1 (Service as a Whole) changes.

## What stays the same
- Intake, envelope, `prepare-service.py` (parse, depts 138/139, collapse, ARB estimates, reviewed standards).
- Recording the snapshot (`record_snapshot_479`) before an apply run.
- The import windows and "latest file only".

## What changes
Do not run `build-parts.py`, the part-NN `preview.sql` / `apply.sql`, `holdstock.py` or `droprows.py`.
The database now partitions (by stock, max 180 rows), previews, holds, applies and archives itself, with the same
md5 pins, advisory locks, LOCK TABLE, importer unban/re-ban, before/after snapshots and RAISEs as your apply.sql.

### Call 1: submit
```sql
SELECT pdc_import_620.submit_service_whole(
  '<all prepared rows as one JSON array>'::jsonb,   -- every row prepare-service.py would send (all parts together)
  '<workbook sha256>',
  '{"mailbox":"pdc@pmgwa.com.au","sender":"noreply@revolutionsoftware.com.au",
    "gmail_message_id":"<internet_message_id>","filename":"<attachment filename>",
    "approval_evidence":"<same approval text you use today>",
    "provenance":{ <same provenance object you put in the manifest today, without "partition"> }}'::jsonb,
  'preview'    -- or 'apply'
);
```
Returns `job_id`, rows sent / held, partition count, new board vehicles.
`mode='apply'` with more than 15 new board vehicles comes back `held` straight away (sanity gate).

### The worker
pg_cron runs `CALL pdc_import_620.run_jobs()` every minute. It previews every part first, then applies them in order.
A conflict at preview or a staff-locked change at apply holds that whole stock and re-runs the part without it.
The last part (which archives) is rolled back and the job `held` if it would archive more than 15.

### Call 2: receipt (once, after a few minutes)
```sql
SELECT pdc_import_620.job_receipt('<job_id>');
```
`status`: `queued` / `running` / `done` / `held` (see `note`) / `failed` (see `error`).
Also: partitions, previewed, applied, inserted, updated, archived_now, holds (with reasons) and per-part detail.
Only one job runs at a time; a second submit while one is running is refused (`job_already_running`).

### Holds
Standing holds are built in (13044312 line 7; 13042994, 13092999, 13073002). Holds found in a run carry forward to the
next run, like `staff-lock-holds.json`. To carry over your current holds once:
```sql
SELECT pdc_import_620.add_hold('<stock>', 'held_from_kajel:<reason>');              -- whole stock
SELECT pdc_import_620.add_hold('<stock>', 'held_from_kajel:<reason>', '<R/O>', <line>);  -- one line
```

## First run (side by side)
1. Next import: run your normal steps as today, then submit the same file with `mode='preview'` and read the receipt.
   Previews write nothing to the board. Send the receipt (counts and holds only) to Claude to compare.
2. When it matches and Craig gives the go-live, use `mode='apply'` instead of the part-NN steps.
3. The stalled 28 Oct 12:30 file: re-run the whole file. Parts already applied replay as unchanged.
