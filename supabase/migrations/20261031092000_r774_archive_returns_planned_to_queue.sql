-- r774 (F376) / sort 489. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig's 08:40 import: 15 parts skipped (r771), 24 applied, last part refused again, now with
-- "Workshop Planner validation rejected booking: bay_required". r772 released the bay before completing the car, but a
-- planned booking with its bay cleared is still 'planned', and the planner's validation trigger requires a bay for that.
-- The planner itself returns such a booking to the queue (status queued, bay null, returned_to_queue_at, version+1) under a
-- single-use transition authorisation; the archive now does the same, as the import actor. A queued booking just loses its bay.
-- Backup: pdc_backup_r763_20261031.function_sources (archive_569 r772 state saved as *@r772). Rollback: supabase/rollbacks/20261031092000_r774_archive_returns_planned_to_queue.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)@r772', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r774$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure;
  a1 text := E'  UPDATE public.workshop_bookings b SET bay_id=NULL\n  WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status IN (''queued'',''planned'') AND b.bay_id IS NOT NULL;\n';
  b1 text := E'  -- r774 (F376): a planned bay booking goes back to the queue the way the planner does it (authorised return); a queued one just loses its bay.\n'
    || E'  INSERT INTO public.workshop_transition_authorizations(txid, booking_id, transition, authorized_by)\n'
    || E'  SELECT txid_current(), b.id, ''return_to_queue'', coalesce(v_actor, b.updated_by) FROM public.workshop_bookings b\n'
    || E'  WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status=''planned'' AND b.bay_id IS NOT NULL\n'
    || E'  ON CONFLICT DO NOTHING;\n'
    || E'  UPDATE public.workshop_bookings b SET status=''queued'', bay_id=NULL, returned_to_queue_at=clock_timestamp(),\n'
    || E'    updated_by=coalesce(v_actor, b.updated_by), updated_at=clock_timestamp(), version=version+1\n'
    || E'  WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status=''planned'' AND b.bay_id IS NOT NULL;\n'
    || E'  UPDATE public.workshop_bookings b SET bay_id=NULL\n'
    || E'  WHERE b.vehicle_id=v_row.vehicle_id AND b.deleted_at IS NULL AND b.status=''queued'' AND b.bay_id IS NOT NULL;\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r774: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 489 OR fault_id = 'F376' OR added_in = 'r774') THEN RAISE EXCEPTION 'r774: sort 489 or F376 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r774: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '34f558bfb7c2f5f0b5de36f3df412a0b' THEN RAISE EXCEPTION 'r774: archive_569 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r774: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r774: readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('archive_returns_planned_to_queue_774', 'F376',
    'Upload (r774): when a car leaves the board, its planned bay bookings are returned to the queue under a transition authorisation (status queued, bay null, returned_to_queue_at), before the car is completed.',
    $chk$
SELECT position('workshop_transition_authorizations(txid, booking_id, transition, authorized_by)' IN s.src) > 0
   AND position($$SET status='queued', bay_id=NULL, returned_to_queue_at=clock_timestamp()$$ IN s.src) > 0
   AND position($$SET status='queued', bay_id=NULL$$ IN s.src) < position($$board_purge_reason='r759$$ IN s.src)
 AS ok, 'planned bookings return to the queue before the car completes' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)')) s
$chk$, true, 489, 'r774');
END $r774$;
