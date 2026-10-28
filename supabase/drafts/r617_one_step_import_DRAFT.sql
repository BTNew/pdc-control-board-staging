-- r617 DRAFT (not applied). Two-call Service as a Whole import for Kajel. Staging cdsmnqxtyyoeoznmbidd only.
-- Call 1: Kajel submits the prepared partitions + envelope -> job id (management connection only).
-- Worker: pg_cron runs CALL pdc_import_616.run_jobs() every minute; each partition preview/apply is its own
--         committed transaction (same guards, pins, advisory locks, unban/re-ban inside that transaction so a
--         failure always rolls the unban back). Existing import functions are called unchanged (md5s stay).
-- Call 2: Kajel reads pdc_import_616.job_receipt(job_id) once it says done/held/failed.
-- TODO from Kajel's code before apply mode: hold split + re-preview rules, sanity gate (>15 archive / >15 new),
--      protected-state before/after snapshot, sublet PO dry-run gate, archive on last partition, readback.

CREATE SCHEMA IF NOT EXISTS pdc_import_616;
REVOKE ALL ON SCHEMA pdc_import_616 FROM PUBLIC, anon, authenticated;

CREATE TABLE pdc_import_616.jobs (
  job_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  report text NOT NULL CHECK (report = 'service_whole'),
  mode text NOT NULL CHECK (mode IN ('preview', 'apply')),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'done', 'held', 'failed')),
  workbook_sha256 text NOT NULL,
  envelope jsonb NOT NULL,              -- mailbox, sender, gmail_message_id, filename, provenance, approval_evidence
  partitions jsonb NOT NULL CHECK (jsonb_typeof(partitions) = 'array'),  -- Kajel's split, unchanged
  results jsonb NOT NULL DEFAULT '[]',  -- one entry per partition step
  receipt jsonb,
  error text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  started_at timestamptz,
  finished_at timestamptz
);
REVOKE ALL ON pdc_import_616.jobs FROM PUBLIC, anon, authenticated;
