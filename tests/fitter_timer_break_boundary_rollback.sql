-- Isolated staging transaction. The synthetic date-specific break is never committed.
BEGIN;
SET LOCAL statement_timeout='30s';
SET LOCAL lock_timeout='20s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
-- APPLY CANDIDATE MIGRATIONS HERE FOR ROLLBACK REVIEW.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
END $guard$;
CREATE TEMP TABLE timer_break_results(label text,pass boolean) ON COMMIT DROP;
UPDATE public.workshop_settings SET value=value||'[{"date":"2026-09-14","start":"12:00","end":"12:30"}]'::jsonb WHERE key='break_windows';
INSERT INTO timer_break_results VALUES
 ('Break is the next timer boundary',pdc_fitter_private.running_until('2026-09-14 11:59:45+08')='2026-09-14 12:00+08'::timestamptz),
 ('Inside break is not running',pdc_fitter_private.running_until('2026-09-14 12:05+08') IS NULL),
 ('Time before and after break retains seconds',pdc_fitter_private.operational_seconds('2026-09-14 11:59:45+08','2026-09-14 12:30:15+08')=30),
 ('After break resumes to closing boundary',pdc_fitter_private.running_until('2026-09-14 12:30:15+08')='2026-09-14 16:30+08'::timestamptz);
DO $assert$ BEGIN IF EXISTS(SELECT 1 FROM timer_break_results WHERE pass IS DISTINCT FROM true) THEN RAISE EXCEPTION 'Timer break regression failed'; END IF; END $assert$;
SELECT jsonb_agg(to_jsonb(r)) results FROM timer_break_results r;
ROLLBACK;

