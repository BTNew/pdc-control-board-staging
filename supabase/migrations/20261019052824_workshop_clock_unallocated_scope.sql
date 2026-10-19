-- Staging only. A returned, unstarted job without a bay reserves no time.
-- Its retained historical interval must not freeze scheduled vehicle followers.
DO $repair$
DECLARE definition text; before_clause text; after_clause text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 definition:=pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure);
 -- Check source and execution attributes directly: pg_get_functiondef's
 -- qualification output depends on search_path; Windows restores use CRLF.
 IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure
  AND md5(replace(prosrc,chr(13),''))='d447c6438786863ecdfa6d52f1858781' AND NOT prosecdef AND provolatile='v'
  AND proowner='postgres'::regrole
  AND proconfig=ARRAY['search_path=pg_catalog, public','lock_timeout=3s','statement_timeout=120s'])
 THEN RAISE EXCEPTION 'reviewed_clock_changed'; END IF;
 before_clause:='WHERE b.deleted_at IS NULL AND b.status IN(''planned'',''queued'',''started'',''stoppage'');';
 after_clause:='WHERE b.deleted_at IS NULL AND b.status IN(''planned'',''queued'',''started'',''stoppage'')
 AND NOT (b.status=''queued'' AND b.bay_id IS NULL AND b.actual_start_at IS NULL);';
 IF strpos(definition,before_clause)=0 THEN RAISE EXCEPTION 'reviewed_snapshot_clause_changed'; END IF;
 EXECUTE replace(definition,before_clause,after_clause);
END $repair$;
