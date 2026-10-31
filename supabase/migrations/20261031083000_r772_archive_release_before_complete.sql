-- r772 (F373) / sort 487. Staging cdsmnqxtyyoeoznmbidd only.
-- Found on Craig's 07:52 import (job done 08:15, 39 of 40 parts applied): the last part was refused with
-- "Workshop Planner validation rejected booking: vehicle_inactive_or_missing". r759 completes a car that left the Revolution
-- list (lifecycle 'completed') and only then clears the bay of its planned/queued bookings; the booking trigger validates
-- that UPDATE against an active vehicle and refuses. Because r763 archives on the last part only, the whole last part
-- (3 new cars) rolled back and the leaving-the-board step never ran.
-- Fix: release the bay bookings first, while the car is still active, then complete it (same predicate for both).
-- Also: begin_728 treats a file as a duplicate only when every part applied; a file with a refused part can be sent again
-- and r771 skips the parts that already applied.
-- Backup: pdc_backup_r763_20261031.function_sources (archive_569 r763 state saved as *_r763). Rollback: supabase/rollbacks/20261031083000_r772_archive_release_before_complete.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)@r763', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure
ON CONFLICT (sig) DO NOTHING;
INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'public.revolution_upload_begin_728(text,text,text)@r763', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.revolution_upload_begin_728(text,text,text)'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r772$
DECLARE v_old text; v_new text; v_def text; v_rel text; v_start integer; v_end integer; sig regprocedure;
  a_nf text := E'  IF NOT FOUND THEN CONTINUE; END IF;\n';
  a_end text := E'  v_released := v_released + coalesce(jsonb_array_length(v_released_rows), 0);\n';
  a_upd text := E'  UPDATE public.vehicles SET visible_on_board=false, board_purged_at=clock_timestamp(),\n    board_purge_reason=''r759';
  guard text := E'  -- r772 (F373): release planned/queued bay bookings while the car is still active (the booking trigger refuses an inactive car), then complete it.\n'
    || E'  IF NOT EXISTS (SELECT 1 FROM public.vehicles x WHERE x.id=v_row.vehicle_id AND x.deleted_at IS NULL AND x.board_purged_at IS NULL AND x.lifecycle_state::text=''active''\n'
    || E'    AND NOT EXISTS (SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=x.id AND o.department=''135'')) THEN CONTINUE; END IF;\n';
  a3 text := E'      AND EXISTS (SELECT 1 FROM jsonb_array_elements(j.parts) p WHERE p->''apply''->>''ok'' = ''true'')) THEN -- r763 (F369): applied nothing = not a duplicate\n';
  b3 text := E'      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j.parts) p WHERE p->''apply''->>''ok'' IS DISTINCT FROM ''true'')) THEN -- r772 (F373): every part applied = duplicate; otherwise it can be sent again\n';
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r772: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 487 OR fault_id = 'F373' OR added_in = 'r772') THEN RAISE EXCEPTION 'r772: sort 487 or F373 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r772: an import job is running'; END IF;

  sig := 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '96a4aa80c2a2320dc0fdc082599b8683' THEN RAISE EXCEPTION 'r772: archive_569 is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a_nf, ''))) / length(a_nf) <> 1 OR (length(v_old) - length(replace(v_old, a_end, ''))) / length(a_end) <> 1
     OR (length(v_old) - length(replace(v_old, a_upd, ''))) / length(a_upd) <> 1 THEN RAISE EXCEPTION 'r772: archive anchors not found once'; END IF;
  v_start := position(a_nf IN v_old) + length(a_nf);
  v_end := position(a_end IN v_old) + length(a_end);
  IF v_start >= v_end OR position(a_upd IN v_old) >= v_start THEN RAISE EXCEPTION 'r772: archive anchors out of order'; END IF;
  v_rel := substring(v_old FROM v_start FOR v_end - v_start);
  IF v_rel NOT LIKE '%UPDATE public.workshop_booking_assignments a SET released_at=clock_timestamp()%' OR v_rel NOT LIKE '%UPDATE public.workshop_bookings b SET bay_id=NULL%'
     OR v_rel LIKE '%UPDATE public.vehicles%' THEN RAISE EXCEPTION 'r772: release block is not what was expected'; END IF;
  v_new := replace(v_old, v_rel, '');
  v_new := replace(v_new, a_upd, guard || v_rel || a_upd);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r772: archive readback differs'; END IF;
  IF position('UPDATE public.workshop_bookings b SET bay_id=NULL' IN v_new) > position(a_upd IN v_new) THEN RAISE EXCEPTION 'r772: bookings are still released after the vehicle update'; END IF;

  sig := 'public.revolution_upload_begin_728(text,text,text)'::regprocedure;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a3, ''))) / length(a3) <> 1 THEN RAISE EXCEPTION 'r772: begin_728 anchor not found once'; END IF;
  v_new := replace(v_old, a3, b3);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r772: begin_728 readback differs'; END IF;

  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, $$p->'apply'->>'ok' = 'true'$$, $$p->'apply'->>'ok' IS DISTINCT FROM 'true'$$),
    description = replace(description, 'a done job that applied nothing is not a duplicate', 'a done job is a duplicate only when every part applied (r772)')
  WHERE check_name = 'website_snapshot_recorded_763';

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('archive_release_before_complete_772', 'F373',
    'Upload (r772): service_whole_archive_569 clears the bay of planned/queued bookings before it completes the car (the booking trigger refuses an inactive vehicle).',
    $chk$
SELECT position('UPDATE public.workshop_bookings b SET bay_id=NULL' IN s.src) > 0
   AND position('UPDATE public.workshop_bookings b SET bay_id=NULL' IN s.src) < position($$board_purge_reason='r759$$ IN s.src)
   AND position('r772 (F373)' IN s.src) > 0
 AS ok, 'bookings released while the car is still active, then completed' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)')) s
$chk$, true, 487, 'r772');
END $r772$;
