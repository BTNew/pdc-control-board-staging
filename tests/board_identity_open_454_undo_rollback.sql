-- r454 (F67) rolled-back test B: apply -> undo (byte-identical restore) -> re-apply; everything is rolled back (R454_RB_B).
-- Rolled-back release test window (F15, r405). Paste at the very top of every rolled-back test
-- that calls board write functions, and replace R454 with the release tag (e.g. R405).
--
-- Why: board write functions take the top-level change lock
-- (pg_advisory_xact_lock('pdc:workshop:top-level-mutation')) and keep it until the test's
-- ROLLBACK. The live clock tick runs every minute at :00 and waits only 3 s for that lock
-- (lock_timeout), so a test that holds it across a minute boundary makes the real tick fail
-- (21:25, 21:28 and 21:30 AWST on 20 Oct 2026, r404 tests).
--
-- Rule: 1) wait until this minute's tick has finished, 2) start between :02 and :15,
-- 3) never wait long for a live lock (lock_timeout 2 s), 4) stop and roll back before :50
-- (each statement's statement_timeout is cut to the time left; call pg_temp.deadline() before
-- each step). Locks are only taken after step 1, so waiting holds nothing.

-- 1+2. Wait for the tick (holds no locks; reads cron history only).
DO $window_wait$
DECLARE i integer := 0;
BEGIN
  LOOP
    EXIT WHEN extract(second FROM clock_timestamp()) BETWEEN 2 AND 15
      AND EXISTS (SELECT 1 FROM cron.job_run_details d JOIN cron.job j USING (jobid)
                  WHERE j.jobname = 'staging-workshop-clock-cascade'
                    AND d.start_time >= date_trunc('minute', clock_timestamp())
                    AND d.end_time IS NOT NULL);
    i := i + 1;
    IF i > 75 THEN RAISE EXCEPTION 'R454_WINDOW: clock tick not seen; test not started'; END IF;
    PERFORM pg_sleep(1);
  END LOOP;
END $window_wait$;
BEGIN;
SET LOCAL lock_timeout='2s';
CREATE TEMP TABLE t_res(k text, v jsonb) ON COMMIT DROP;
-- r454 (F67, Craig 22 Oct, decision 2): 9 board vehicles would not open ("The exact vehicle identity is unavailable" or
-- dealer_scope_denied). Cause: the dealer of a vehicle was resolved only from a CURRENT Navision record (or, for Tune intake,
-- from an open Tune job), but these vehicles stay on the board after that evidence went away:
--  * 5 Navision vehicles (active or RFT) whose only Navision record dropped out of the latest upload (not_in_latest_batch):
--    no dealer at all, so the board refused to open them before asking the server;
--  * 4 Tune intake vehicles never matched to Navision whose Tune job was checked out (review approved or closed): the board
--    opened them but the server refused (dealer_scope_denied).
-- Fix (identity resolution only; no vehicle, record, job, booking or history row is changed, merged or deleted):
--  * board_identity_dealer_454: such a Navision vehicle's dealer comes from its OWN source record (vehicles.source_record_id),
--    only when that record, source_batch_id and every record ever linked agree on one dealer (14450 or 37047);
--  * the board row carries it as identity_dealer_code (only when set), so the board can open the vehicle;
--  * workshop_board_identity_read_allowed_454: read-only Workshop detail and booking search for those two cases, only for
--    vehicles the board shows (board_vehicle_visible_453), active or RFT, inside the actor's dealer scope.
-- Changed: workshop_read_vehicle_allowed_20261013, get_vehicle_workshop_detail_scoped, get_workshop_booking_search_scoped,
-- get_pdc_email_vehicle_location_snapshot. Write paths keep public.pdc_auditor_vehicle_dealer (unchanged), so no write right is
-- added. New check board_identity_open_454 (sort 253). Not touched: workshop_clock_tick, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r454: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r454: staging only'; END IF;
 PERFORM set_config('pdc.r454_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r454_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r454_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r454: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r454') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454' OR added_in='r454') THEN RAISE EXCEPTION 'r454: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=253) THEN RAISE EXCEPTION 'r454: sort_order 253 taken'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.board_identity_dealer_454(uuid) already exists'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) already exists'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM 'e45bbe3ddc4d30c1845099ee3efd33c0' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)') IS DISTINCT FROM 'e45bbe3ddc4d30c1845099ee3efd33c0|r390' THEN RAISE EXCEPTION 'r454: pin of pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '2e059658db08521d92103504ddff7c97' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_vehicle_workshop_detail_scoped(uuid,text)') IS DISTINCT FROM '2e059658db08521d92103504ddff7c97|baseline' THEN RAISE EXCEPTION 'r454: pin of public.get_vehicle_workshop_detail_scoped(uuid,text) not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '1d4b86872f7559b106f40dbadd3f907f' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public,statement_timeout=15s' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_workshop_booking_search_scoped(jsonb)') IS DISTINCT FROM '1d4b86872f7559b106f40dbadd3f907f|baseline' THEN RAISE EXCEPTION 'r454: pin of public.get_workshop_booking_search_scoped(jsonb) not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '930f0f56572db71445d7de704f027aa3' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()') IS DISTINCT FROM '930f0f56572db71445d7de704f027aa3|r412' THEN RAISE EXCEPTION 'r454: pin of public.get_pdc_email_vehicle_location_snapshot() not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_vehicle_visible_453(uuid)')) IS DISTINCT FROM 'd98f1bce13cbc964fba7332d8a4f6d97' THEN RAISE EXCEPTION 'r454: r453 is not applied'; END IF;
 PERFORM set_config('pdc.r454_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.board_identity_dealer_454(p_vehicle_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r454 (F67): the dealer of an active or RFT Navision vehicle whose only Navision record dropped out of the latest upload
 -- (no current record at all). Taken from the vehicle's OWN source record (vehicles.source_record_id), and only when that
 -- record, the vehicle's source_batch_id and every Navision record ever linked to the vehicle name the same one dealer
 -- (14450 or 37047). NULL in every other case: a vehicle with a current record keeps public.pdc_auditor_vehicle_dealer().
 -- Read-only; never used by a write path.
 SELECT v.source_batch_id
 FROM public.vehicles v
 WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
   AND v.lifecycle_state IN('active','rft') AND v.source_system='microsoft_navision'
   AND v.source_batch_id IN('14450','37047')
   AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id AND n.is_current)
   AND EXISTS(SELECT 1 FROM public.navision_backend_records n
     WHERE n.id::text=v.source_record_id AND n.canonical_vehicle_id=v.id AND n.source_system='microsoft_navision'
       AND n.dealer_code=v.source_batch_id AND NOT n.is_current)
   AND (SELECT count(DISTINCT n.dealer_code) FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id)=1
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.board_identity_dealer_454(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_board_identity_read_allowed_454(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r454 (F67): read-only Workshop detail for a vehicle that is on the shared board but whose source evidence has gone:
 --  (a) a Navision vehicle whose only record dropped out of the latest upload: its dealer comes from its own source record
 --      (board_identity_dealer_454) and must be the requested dealer, inside the actor's dealer scope (14450 also reads 37047
 --      vehicles that own Pilbara Service operations, the existing bridge);
 --  (b) a Tune intake vehicle that was never matched to Navision, whose Tune review was approved or closed (checked out):
 --      read under the board's dealer 14450, the same scope the r390 Tune rule uses while its job is open.
 -- Only for vehicles the board shows (board_vehicle_visible_453), active or RFT. No write path calls this.
 SELECT coalesce(
  p_scope->>'environment'='staging' AND p_scope->>'role' IN('viewer','operator','administrator')
  AND NOT (p_scope ? 'department_scope')
  AND p_requested_dealer IN('14450','37047')
  AND public.pdc_auditor_vehicle_dealer(p_vehicle_id) IS NULL
  AND pdc_codex_intake_private.board_vehicle_visible_453(p_vehicle_id)
  AND (
   (pdc_codex_intake_private.board_identity_dealer_454(p_vehicle_id)=p_requested_dealer
    AND (p_scope->>'dealer_code'=p_requested_dealer
     OR (p_scope->>'dealer_code'='14450' AND p_requested_dealer='37047'
         AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=p_vehicle_id))))
   OR (p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450'
    AND EXISTS(SELECT 1 FROM public.vehicles v
      WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND v.visible_on_board
        AND v.lifecycle_state IN('active','rft') AND v.source_system='tune_pmg'
        AND nullif(btrim(v.stock_number),'') IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id)
        AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r
          WHERE r.vehicle_id=v.id AND r.source_kind='tune_pmg' AND r.status IN('approved','closed'))))
  ),false)
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ SELECT coalesce((public.pdc_workshop_actor_vehicle_allowed(p_scope,p_vehicle_id,p_requested_dealer)
 OR pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(p_scope,p_vehicle_id,p_requested_dealer)
 -- r454 (F67): a board vehicle whose Navision record left the latest upload, or a checked-out Tune vehicle (read only).
 OR pdc_codex_intake_private.workshop_board_identity_read_allowed_454(p_scope,p_vehicle_id,p_requested_dealer))
 AND (NOT (p_scope ? 'department_scope') OR
   (p_scope->>'department_scope'='138' AND p_scope->>'environment'='staging' AND p_scope->>'role' IN ('viewer','operator','administrator') AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450' AND EXISTS (
SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
WHERE v.id=p_vehicle_id AND (v.source_system='tune_pmg' OR (v.source_system='microsoft_navision' AND v.permanent_vehicle_id='TUNE/PMG:'||v.stock_number AND v.source_payload->>'intake_source_system'='tune_pmg')) AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR (j.departments IS DISTINCT FROM ARRAY['138']::text[] AND j.departments IS DISTINCT FROM ARRAY['139']::text[]) OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND ((o.department IS DISTINCT FROM '138' AND o.department IS DISTINCT FROM '139') OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
))),false); $function$;

CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid, p_dealer_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_scope jsonb; v_dealer text; v_vehicle_dealer text;
BEGIN
  v_scope:=pdc_codex_intake_private.workshop_read_actor_scope_20261013();
  v_dealer:=btrim(coalesce(p_dealer_code,''));
  IF NOT pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied','data',jsonb_build_object('environment','staging','dealer_code',v_dealer));
  END IF;
  SELECT public.pdc_auditor_vehicle_dealer(v.id) INTO v_vehicle_dealer
  FROM public.vehicles v
  WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active';
  IF v_vehicle_dealer IS DISTINCT FROM v_dealer AND NOT pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(v_scope,p_vehicle_id,v_dealer)
 AND NOT pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(v_scope,p_vehicle_id,v_dealer)
 AND NOT pdc_codex_intake_private.workshop_board_identity_read_allowed_454(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_dealer_scope','data',jsonb_build_object('vehicle_id',p_vehicle_id,'dealer_code',v_dealer));
  END IF;
  RETURN public.get_vehicle_workshop_detail(p_vehicle_id) || jsonb_build_object('imported_additions',
  (SELECT coalesce(jsonb_agg(jsonb_build_object('change_id',q.change_id,'description',q.proposed_source->>'operation_description',
    'department',q.proposed_source->>'department','job_card',q.repair_order_number,'line_number',q.original_line_number,
    'source_hours',q.proposed_source->'source_estimated_hours','status',coalesce(q.automation_result->>'code','classification_pending')) ORDER BY q.created_at),'[]')
   FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=p_vehicle_id AND q.status='pending'));
 
END
$function$;

CREATE OR REPLACE FUNCTION public.get_workshop_booking_search_scoped(p_vehicles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '15s'
AS $function$
DECLARE actor_scope jsonb; results jsonb;
BEGIN
 -- Actual signed-in identity plus the existing role check are required.
 -- The private read helper applies only the owner-authorised Department138 delegation.
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 PERFORM public.require_pdc_role('viewer');
 actor_scope:=pdc_codex_intake_private.workshop_read_actor_scope_20261013();
 IF jsonb_typeof(p_vehicles) IS DISTINCT FROM 'array' THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF jsonb_array_length(p_vehicles) NOT BETWEEN 1 AND 25 THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_vehicles) x WHERE jsonb_typeof(x) IS DISTINCT FROM 'object'
   OR jsonb_typeof(x->'vehicle_id') IS DISTINCT FROM 'string'
   OR coalesce(x->>'vehicle_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   OR jsonb_typeof(x->'dealer_code') IS DISTINCT FROM 'string'
   OR length(btrim(coalesce(x->>'dealer_code',''))) NOT BETWEEN 1 AND 80)
 OR (SELECT count(DISTINCT lower(x->>'vehicle_id')) FROM jsonb_array_elements(p_vehicles) x)<>jsonb_array_length(p_vehicles) THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;

 WITH requested AS MATERIALIZED (
  SELECT (x->>'vehicle_id')::uuid vehicle_id,btrim(x->>'dealer_code') dealer_code,ordinal
  FROM jsonb_array_elements(p_vehicles) WITH ORDINALITY q(x,ordinal)
 ), authorized AS MATERIALIZED (
  SELECT r.*,CASE
   WHEN pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(actor_scope,r.vehicle_id,r.dealer_code) IS NOT TRUE THEN 'dealer_scope_denied'
   WHEN NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=r.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
     AND (public.pdc_auditor_vehicle_dealer(v.id)=r.dealer_code OR pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(actor_scope,v.id,r.dealer_code)
      OR pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(actor_scope,v.id,r.dealer_code)))
     -- r454 (F67): board vehicles whose source record left the latest upload, or checked-out Tune vehicles (read only).
     AND NOT pdc_codex_intake_private.workshop_board_identity_read_allowed_454(actor_scope,r.vehicle_id,r.dealer_code) THEN 'vehicle_not_in_dealer_scope'
   ELSE NULL END error
  FROM requested r
 ), booking_rows AS (
  SELECT a.vehicle_id,jsonb_agg(jsonb_build_object(
   'booking_id',b.id,'booking_version',b.version,'work_category',b.work_category,'stage_code',s.code,'stage_name',s.display_name,
   'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',b.status,
   'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
   'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at)
   ORDER BY s.sort_order,b.scheduled_start_at,b.id) bookings
  FROM authorized a JOIN public.workshop_bookings b ON b.vehicle_id=a.vehicle_id AND a.error IS NULL
  JOIN public.workshop_stages s ON s.id=b.stage_id LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
  GROUP BY a.vehicle_id
 )
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',a.vehicle_id,'dealer_code',a.dealer_code,'ok',a.error IS NULL)
  ||CASE WHEN a.error IS NULL THEN jsonb_build_object('bookings',coalesce(b.bookings,'[]'::jsonb))
    ELSE jsonb_build_object('error',a.error) END ORDER BY a.ordinal)
 INTO results FROM authorized a LEFT JOIN booking_rows b ON b.vehicle_id=a.vehicle_id;
 RETURN jsonb_build_object('ok',true,'results',results);
END $function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_base jsonb; v_rows jsonb;
BEGIN
  -- r454 (F67): identity_dealer_code (only when set) gives a vehicle whose only Navision record left the latest upload its
  -- dealer back, so the board can open it read-only; see pdc_codex_intake_private.board_identity_dealer_454.
  -- r412 (F28): OFFSET 0 on the sourced/classified subqueries and the dept138 lateral keeps each per-operation helper
  -- (approved source, operation_station, pre-delivery test, department-138 station) a single evaluation; flattened, the
  -- planner copied approved_source and station_code into every reference (3-4 calls per operation). Same expressions.
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(row_value||public.pdc_vehicle_department_membership_20260919((row_value->>'id')::uuid)||jsonb_build_object(
 'navision_jita_identity_verified',jita.match_count=1,
 'navision_jita_column_present',CASE WHEN jita.match_count=1 THEN jita.column_present ELSE false END,
 'navision_jita_number_authority',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.authority ELSE NULL END,
 'navision_jita_number',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.jita_number ELSE NULL END,
 'navision_jita_identity_status',CASE WHEN jita.match_count=0 THEN 'not_found' WHEN jita.match_count=1 THEN 'exact' ELSE 'ambiguous' END
)||CASE WHEN EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews nr WHERE nr.vehicle_id=canonical.id AND nr.source_kind='tune_pmg') THEN public.pdc_tune_vehicle_details_v5(canonical.id) ELSE '{}'::jsonb END||jsonb_strip_nulls(jsonb_build_object('identity_dealer_code',pdc_codex_intake_private.board_identity_dealer_454(canonical.id)))||jsonb_build_object(
    'tune_checkout',pdc_codex_intake_private.vehicle_tune_checkout(canonical.id),'tune_service_locations',pdc_codex_intake_private.vehicle_service_locations(canonical.id),'location_override',canonical.location_override,'location_override_reason',canonical.location_override_reason,'location_override_at',canonical.location_override_at,'location_override_by',canonical.location_override_by,'automatic_location',canonical.current_location,'qc_completed_at',canonical.qc_completed_at,
    'qc_completed_by',canonical.qc_completed_by,
    'rft_transferred_at',canonical.rft_transferred_at,
    'parts_flags',public.pdc_parts_flags_vehicle_20260911(canonical.id),'qc_rework',public.pdc_qc_rework_scope_20260909((row_value->>'id')::uuid),'pilbara_service_operations',service_lines,
    'operation_lines',(SELECT coalesce(jsonb_agg(
   public.pdc_standard_operation_display_20260910(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE dept138.station_code WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',dept138.station_code,'station_assignment_source','department_138_shared_work') WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END) ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
   LEFT JOIN LATERAL (
     SELECT coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) AS station_code
     WHERE btrim(op->>'department')='138'
     OFFSET 0
   ) dept138 ON true
   LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=(row_value->>'id')::uuid
     AND a.line_key='source:'||(op->>'operation_line_id') AND a.active AND a.manual_assignment_locked
     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))
  ) ORDER BY coalesce(row_value->>'stock_number',row_value->>'id')),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) row_value
  JOIN public.vehicles canonical ON canonical.id=(row_value->>'id')::uuid
  LEFT JOIN LATERAL (
   SELECT count(*) AS match_count,
    bool_or(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)) AS column_present,
    max(n.normalized_data->>'navisionJitaNumberAuthority') AS authority,
    max(n.normalized_data->>'jitQty') AS jita_number
   FROM public.navision_backend_records n
   WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision'
    AND n.canonical_vehicle_id=canonical.id
    AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(canonical.stock_number))
  ) jita ON true
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',classified.operation_id,'department',classified.department,
      'operation_no','PD'||lpad(classified.original_line_number::text,3,'0')||'-'||upper(substr(classified.semantic_hash,1,8)),
      'work_key',CASE classified.station_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(classified.station_code) END,
      'job_card_number',classified.repair_order_number,'description',coalesce(classified.approved_source->>'operation_description',classified.operation_description),
      'estimated_hours',classified.effective_estimated_hours,
      'estimated_hours_source',CASE classified.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',classified.source_estimated_hours,'effective_estimated_hours',classified.effective_estimated_hours,
      'hours_provenance',classified.hours_provenance,'parts_on_backorder_raw',classified.parts_on_backorder_raw,'parts_semantics',classified.parts_semantics,
      'classification',classified.station_code,'classification_method',coalesce(classified.method,'review'),
      'classification_confidence',coalesce(classified.confidence,0),'classification_rationale',coalesce(classified.rationale,'No current classification; retained for Review.'),
      'source_description_hash',classified.source_description_hash,'classifier_version',classified.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||classified.stock_number||':'||classified.repair_order_number||':'||classified.original_line_number
    )) ORDER BY classified.source_order),'[]'::jsonb) service_lines
    FROM (
      SELECT sourced.*,
        CASE WHEN sourced.department='138' THEN pdc_bus_private.operation_station(sourced.operation_id)
             WHEN public.pdc_is_pre_delivery_20260910(coalesce(sourced.approved_source->>'operation_description',sourced.operation_description)) THEN 'FITTING'
             ELSE coalesce(sourced.category,sourced.proposed_station,'REVIEW') END AS station_code
      FROM (
        SELECT o.operation_id,o.department,o.original_line_number,o.semantic_hash,o.repair_order_number,o.operation_description,
          o.effective_estimated_hours,o.hours_provenance,o.source_estimated_hours,o.parts_on_backorder_raw,o.parts_semantics,
          o.proposed_station,o.stock_number,o.source_order,h.category,h.method,h.confidence,h.rationale,h.source_description_hash,h.classifier_version,
          public.pdc_tune_approved_operation_source_20260912(o.operation_id) AS approved_source
        FROM public.pdc_pilbara_service_operations o
        LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
        LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
        WHERE o.vehicle_id=(row_value->>'id')::uuid
        OFFSET 0
      ) sourced
      OFFSET 0
    ) classified
  ) projected
  WHERE NOT pdc_codex_intake_private.owner_board_hold_active_20261019(canonical.id,canonical.stock_number,NULL)
     OR canonical.lifecycle_state::text='completed';
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='cba3a1268c1363043c4df2b9d65b69e7',release='r454',note='r454: + board identity read rule (F67); r390 Key 243 + mixed 138/139 read',updated_at=clock_timestamp() WHERE signature='pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='c0ba734f2f4945e902a6c474cb589089',release='r454',note='r454: board identity read rule in the dealer check (F67)',updated_at=clock_timestamp() WHERE signature='public.get_vehicle_workshop_detail_scoped(uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f348c91e50b70c2dd14d8651f97d52a2',release='r454',note='r454: booking search; board identity read rule (F67)',updated_at=clock_timestamp() WHERE signature='public.get_workshop_booking_search_scoped(jsonb)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e7f77fad301b8a87ef548472a8f790a6',release='r454',note='Outer location snapshot (r412, F28) + identity_dealer_code (r454, F67)',updated_at=clock_timestamp() WHERE signature='public.get_pdc_email_vehicle_location_snapshot()';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.board_identity_dealer_454(uuid)','a1c3a6a592ac1e7e7c20df3b498748c9','r454','r454: dealer of a board vehicle whose only Navision record left the latest upload (F67)'),
 ('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)','88eb91cdfef653bad2013342c375af4b','r454','r454: read-only open for board vehicles without current source evidence (F67)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('board_identity_open_454','F67','Board vehicles whose source record left the latest upload, or checked-out Tune vehicles, open read-only (r454)',$chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r454'),
readers AS (
  SELECT count(*) FILTER (WHERE p.oid NOT IN (pg_catalog.to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)'),
     pg_catalog.to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)'),pg_catalog.to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)'))) other
  FROM pg_catalog.pg_proc p WHERE strpos(p.prosrc,'workshop_board_identity_read_allowed_454(')>0),
dealer_users AS (
  SELECT count(*) FILTER (WHERE p.oid NOT IN (pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()'),
     pg_catalog.to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)'))) other
  FROM pg_catalog.pg_proc p WHERE strpos(p.prosrc,'board_identity_dealer_454(')>0),
found AS (
  SELECT count(*) FILTER (WHERE pdc_codex_intake_private.board_identity_dealer_454(v.id) IS NOT NULL) n
  FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state IN ('active','rft'))
SELECT (SELECT n FROM pins)=6 AND (SELECT ok FROM pins)=6 AND (SELECT other FROM readers)=0 AND (SELECT other FROM dealer_users)=0 AS ok,
 'Board identity open (r454): r454 pins matching '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; other functions using the read rule: '||(SELECT other FROM readers)||' (must be 0: read paths only)'
 ||'; other functions using the dealer fallback: '||(SELECT other FROM dealer_users)
 ||'; active/RFT vehicles whose dealer comes from their own source record: '||(SELECT n FROM found) AS detail$chk$,true,253,'r454');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM 'cba3a1268c1363043c4df2b9d65b69e7' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM 'c0ba734f2f4945e902a6c474cb589089' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM 'f348c91e50b70c2dd14d8651f97d52a2' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public,statement_timeout=15s' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)')) IS DISTINCT FROM 'a1c3a6a592ac1e7e7c20df3b498748c9' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.board_identity_dealer_454(uuid) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)')) IS DISTINCT FROM '{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.board_identity_dealer_454(uuid) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)')) IS DISTINCT FROM '88eb91cdfef653bad2013342c375af4b' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r454')<>6 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r454_pins')::int+2 THEN RAISE EXCEPTION 'r454: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454' AND added_in='r454' AND sort_order=253) IS DISTINCT FROM '91d258c06dbb1a3dee061b19e97acf17' THEN RAISE EXCEPTION 'r454: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name IN ('board_identity_open_454') LOOP
  DECLARE y record; BEGIN EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r454: check % not OK: %',x.check_name,y.detail; END IF; END;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r454_tick') THEN RAISE EXCEPTION 'r454: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r454_frc') THEN RAISE EXCEPTION 'r454: fault_regression_check changed'; END IF;
END $g$;

INSERT INTO t_res SELECT 'applied', jsonb_build_object('pins',(SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r454'),'idc',(SELECT count(*) FROM public.vehicles v WHERE pdc_codex_intake_private.board_identity_dealer_454(v.id) IS NOT NULL));
-- r454 undo (F67): restores workshop_read_vehicle_allowed_20261013 (e45bbe3d), get_vehicle_workshop_detail_scoped (2e059658),
-- get_workshop_booking_search_scoped (1d4b8687) and get_pdc_email_vehicle_location_snapshot (930f0f56) byte for byte with their
-- pins, drops board_identity_dealer_454 and workshop_board_identity_read_allowed_454, their pins and check board_identity_open_454.
-- Run between :02 and :45. Staging only. Changes no data rows.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r454 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r454 undo: staging only'; END IF;
 PERFORM set_config('pdc.r454_undo_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r454_undo_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r454_undo_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r454 undo: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM 'cba3a1268c1363043c4df2b9d65b69e7' THEN RAISE EXCEPTION 'r454 undo: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM 'c0ba734f2f4945e902a6c474cb589089' THEN RAISE EXCEPTION 'r454 undo: public.get_vehicle_workshop_detail_scoped(uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM 'f348c91e50b70c2dd14d8651f97d52a2' THEN RAISE EXCEPTION 'r454 undo: public.get_workshop_booking_search_scoped(jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r454 undo: public.get_pdc_email_vehicle_location_snapshot() is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)')) IS DISTINCT FROM 'a1c3a6a592ac1e7e7c20df3b498748c9' THEN RAISE EXCEPTION 'r454 undo: pdc_codex_intake_private.board_identity_dealer_454(uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)')) IS DISTINCT FROM '88eb91cdfef653bad2013342c375af4b' THEN RAISE EXCEPTION 'r454 undo: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) is not the expected version'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454' AND added_in='r454') THEN RAISE EXCEPTION 'r454 undo: r454 is not applied'; END IF;
END $g$;

-- Restores the exact previous definition of pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
-- byte for byte; its source has CRLF line endings, which only survive as base64 (decoded and run as-is).
DO $b64$ BEGIN EXECUTE convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcGRjX2NvZGV4X2ludGFrZV9wcml2YXRlLndvcmtzaG9wX3JlYWRfdmVoaWNsZV9hbGxvd2VkXzIwMjYxMDEzKHBfc2NvcGUganNvbmIsIHBfdmVoaWNsZV9pZCB1dWlkLCBwX3JlcXVlc3RlZF9kZWFsZXIgdGV4dCkKIFJFVFVSTlMgYm9vbGVhbgogTEFOR1VBR0Ugc3FsCiBTVEFCTEUKIFNFVCBzZWFyY2hfcGF0aCBUTyAncGdfY2F0YWxvZycsICdwdWJsaWMnCkFTICRmdW5jdGlvbiQgU0VMRUNUIGNvYWxlc2NlKChwdWJsaWMucGRjX3dvcmtzaG9wX2FjdG9yX3ZlaGljbGVfYWxsb3dlZChwX3Njb3BlLHBfdmVoaWNsZV9pZCxwX3JlcXVlc3RlZF9kZWFsZXIpDQogT1IgcGRjX2NvZGV4X2ludGFrZV9wcml2YXRlLndvcmtzaG9wX2FwcHJvdmVkX3BtZ19yZWFkX2FsbG93ZWRfMjAyNjEwMTkocF9zY29wZSxwX3ZlaGljbGVfaWQscF9yZXF1ZXN0ZWRfZGVhbGVyKSkNCiBBTkQgKE5PVCAocF9zY29wZSA/ICdkZXBhcnRtZW50X3Njb3BlJykgT1INCiAgIChwX3Njb3BlLT4+J2RlcGFydG1lbnRfc2NvcGUnPScxMzgnIEFORCBwX3Njb3BlLT4+J2Vudmlyb25tZW50Jz0nc3RhZ2luZycgQU5EIHBfc2NvcGUtPj4ncm9sZScgSU4gKCd2aWV3ZXInLCdvcGVyYXRvcicsJ2FkbWluaXN0cmF0b3InKSBBTkQgcF9zY29wZS0+PidkZWFsZXJfY29kZSc9JzE0NDUwJyBBTkQgcF9yZXF1ZXN0ZWRfZGVhbGVyPScxNDQ1MCcgQU5EIEVYSVNUUyAoDQpTRUxFQ1QgMSBGUk9NIHB1YmxpYy52ZWhpY2xlcyB2IEpPSU4gcHVibGljLnBkY19uZXdfdmVoaWNsZV9yZXZpZXdzIG4gT04gbi52ZWhpY2xlX2lkPXYuaWQNCldIRVJFIHYuaWQ9cF92ZWhpY2xlX2lkIEFORCAodi5zb3VyY2Vfc3lzdGVtPSd0dW5lX3BtZycgT1IgKHYuc291cmNlX3N5c3RlbT0nbWljcm9zb2Z0X25hdmlzaW9uJyBBTkQgdi5wZXJtYW5lbnRfdmVoaWNsZV9pZD0nVFVORS9QTUc6J3x8di5zdG9ja19udW1iZXIgQU5EIHYuc291cmNlX3BheWxvYWQtPj4naW50YWtlX3NvdXJjZV9zeXN0ZW0nPSd0dW5lX3BtZycpKSBBTkQgdi5saWZlY3ljbGVfc3RhdGU9J2FjdGl2ZScgQU5EIHYudmlzaWJsZV9vbl9ib2FyZCBBTkQgdi5kZWxldGVkX2F0IElTIE5VTEwgQU5EIHYuYm9hcmRfcHVyZ2VkX2F0IElTIE5VTEwgQU5EIG51bGxpZihidHJpbSh2LnN0b2NrX251bWJlciksJycpIElTIE5PVCBOVUxMDQpBTkQgbi5zdGF0dXM9J2FwcHJvdmVkJyBBTkQgbi5hcHByb3ZlZF9hdCBJUyBOT1QgTlVMTCBBTkQgbi5hcHByb3ZlZF9ieSBJUyBOT1QgTlVMTCBBTkQgbi5hcHByb3ZhbF9yZWNlaXB0LT4+J29rJz0ndHJ1ZScgQU5EIG4uYXBwcm92YWxfcmVjZWlwdC0+Pidjb2RlJz0nbmV3X3ZlaGljbGVfYXBwcm92ZWQnDQpBTkQgRVhJU1RTKFNFTEVDVCAxIEZST00gcGRjX3BhcnRzX3ByaXZhdGUuam9icyBqIFdIRVJFIGoudmVoaWNsZV9pZD12LmlkIEFORCBqLmNsb3NlZF9hdCBJUyBOVUxMIEFORCBqLnNvdXJjZV9zeXN0ZW09J3R1bmVfcG1nJyBBTkQgai5jb21wYW55PScwMScgQU5EIGouZGl2aXNpb249JzEnIEFORCBqLmRlcGFydG1lbnRzPUFSUkFZWycxMzgnXTo6dGV4dFtdIEFORCBqLnN0b2NrX251bWJlcj12LnN0b2NrX251bWJlcikNCkFORCBOT1QgRVhJU1RTKFNFTEVDVCAxIEZST00gcGRjX3BhcnRzX3ByaXZhdGUuam9icyBqIFdIRVJFIGoudmVoaWNsZV9pZD12LmlkIEFORCBqLmNsb3NlZF9hdCBJUyBOVUxMIEFORCAoai5zb3VyY2Vfc3lzdGVtIElTIERJU1RJTkNUIEZST00gJ3R1bmVfcG1nJyBPUiBqLmNvbXBhbnkgSVMgRElTVElOQ1QgRlJPTSAnMDEnIE9SIGouZGl2aXNpb24gSVMgRElTVElOQ1QgRlJPTSAnMScgT1IgKGouZGVwYXJ0bWVudHMgSVMgRElTVElOQ1QgRlJPTSBBUlJBWVsnMTM4J106OnRleHRbXSBBTkQgai5kZXBhcnRtZW50cyBJUyBESVNUSU5DVCBGUk9NIEFSUkFZWycxMzknXTo6dGV4dFtdKSBPUiBqLnN0b2NrX251bWJlciBJUyBESVNUSU5DVCBGUk9NIHYuc3RvY2tfbnVtYmVyKSkNCkFORCBFWElTVFMoU0VMRUNUIDEgRlJPTSBwdWJsaWMucGRjX3BpbGJhcmFfc2VydmljZV9vcGVyYXRpb25zIG8gSk9JTiBwZGNfcGFydHNfcHJpdmF0ZS5qb2JzIGogT04gai52ZWhpY2xlX2lkPW8udmVoaWNsZV9pZCBBTkQgai5yb19udW1iZXI9by5yZXBhaXJfb3JkZXJfbnVtYmVyIEFORCBqLmNsb3NlZF9hdCBJUyBOVUxMIFdIRVJFIG8udmVoaWNsZV9pZD12LmlkIEFORCBvLmRlcGFydG1lbnQ9JzEzOCcgQU5EIG8uc3RvY2tfbnVtYmVyPXYuc3RvY2tfbnVtYmVyIEFORCBvLnJhd19ldmlkZW5jZV9pZCBJUyBOT1QgTlVMTCkNCkFORCBOT1QgRVhJU1RTKFNFTEVDVCAxIEZST00gcHVibGljLnBkY19waWxiYXJhX3NlcnZpY2Vfb3BlcmF0aW9ucyBvIFdIRVJFIG8udmVoaWNsZV9pZD12LmlkIEFORCAoKG8uZGVwYXJ0bWVudCBJUyBESVNUSU5DVCBGUk9NICcxMzgnIEFORCBvLmRlcGFydG1lbnQgSVMgRElTVElOQ1QgRlJPTSAnMTM5JykgT1Igby5zdG9ja19udW1iZXIgSVMgRElTVElOQ1QgRlJPTSB2LnN0b2NrX251bWJlciBPUiBvLnJhd19ldmlkZW5jZV9pZCBJUyBOVUxMKSkNCikpKSxmYWxzZSk7ICRmdW5jdGlvbiQ=','base64'),'UTF8'); END $b64$;

-- Restores the exact previous definition of public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid, p_dealer_code text)
-- byte for byte; its source has CRLF line endings, which only survive as base64 (decoded and run as-is).
DO $b64$ BEGIN EXECUTE convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcHVibGljLmdldF92ZWhpY2xlX3dvcmtzaG9wX2RldGFpbF9zY29wZWQocF92ZWhpY2xlX2lkIHV1aWQsIHBfZGVhbGVyX2NvZGUgdGV4dCkKIFJFVFVSTlMganNvbmIKIExBTkdVQUdFIHBscGdzcWwKIFNUQUJMRSBTRUNVUklUWSBERUZJTkVSCiBTRVQgc2VhcmNoX3BhdGggVE8gJ3BnX2NhdGFsb2cnLCAncHVibGljJwpBUyAkZnVuY3Rpb24kDQpERUNMQVJFIHZfc2NvcGUganNvbmI7IHZfZGVhbGVyIHRleHQ7IHZfdmVoaWNsZV9kZWFsZXIgdGV4dDsNCkJFR0lODQogIHZfc2NvcGU6PXBkY19jb2RleF9pbnRha2VfcHJpdmF0ZS53b3Jrc2hvcF9yZWFkX2FjdG9yX3Njb3BlXzIwMjYxMDEzKCk7DQogIHZfZGVhbGVyOj1idHJpbShjb2FsZXNjZShwX2RlYWxlcl9jb2RlLCcnKSk7DQogIElGIE5PVCBwZGNfY29kZXhfaW50YWtlX3ByaXZhdGUud29ya3Nob3BfcmVhZF92ZWhpY2xlX2FsbG93ZWRfMjAyNjEwMTModl9zY29wZSxwX3ZlaGljbGVfaWQsdl9kZWFsZXIpIFRIRU4NCiAgICBSRVRVUk4ganNvbmJfYnVpbGRfb2JqZWN0KCdvaycsZmFsc2UsJ2NvZGUnLCdkZWFsZXJfc2NvcGVfZGVuaWVkJywnZGF0YScsanNvbmJfYnVpbGRfb2JqZWN0KCdlbnZpcm9ubWVudCcsJ3N0YWdpbmcnLCdkZWFsZXJfY29kZScsdl9kZWFsZXIpKTsNCiAgRU5EIElGOw0KICBTRUxFQ1QgcHVibGljLnBkY19hdWRpdG9yX3ZlaGljbGVfZGVhbGVyKHYuaWQpIElOVE8gdl92ZWhpY2xlX2RlYWxlcg0KICBGUk9NIHB1YmxpYy52ZWhpY2xlcyB2DQogIFdIRVJFIHYuaWQ9cF92ZWhpY2xlX2lkIEFORCB2LmRlbGV0ZWRfYXQgSVMgTlVMTCBBTkQgdi5saWZlY3ljbGVfc3RhdGU9J2FjdGl2ZSc7DQogIElGIHZfdmVoaWNsZV9kZWFsZXIgSVMgRElTVElOQ1QgRlJPTSB2X2RlYWxlciBBTkQgTk9UIHBkY19jb2RleF9pbnRha2VfcHJpdmF0ZS53b3Jrc2hvcF9ub25uYXYxMzhfcmVhZF9hbGxvd2VkXzIwMjYxMDEyKHZfc2NvcGUscF92ZWhpY2xlX2lkLHZfZGVhbGVyKQ0KIEFORCBOT1QgcGRjX2NvZGV4X2ludGFrZV9wcml2YXRlLndvcmtzaG9wX2FwcHJvdmVkX3BtZ19yZWFkX2FsbG93ZWRfMjAyNjEwMTkodl9zY29wZSxwX3ZlaGljbGVfaWQsdl9kZWFsZXIpIFRIRU4NCiAgICBSRVRVUk4ganNvbmJfYnVpbGRfb2JqZWN0KCdvaycsZmFsc2UsJ2NvZGUnLCd2ZWhpY2xlX25vdF9pbl9kZWFsZXJfc2NvcGUnLCdkYXRhJyxqc29uYl9idWlsZF9vYmplY3QoJ3ZlaGljbGVfaWQnLHBfdmVoaWNsZV9pZCwnZGVhbGVyX2NvZGUnLHZfZGVhbGVyKSk7DQogIEVORCBJRjsNCiAgUkVUVVJOIHB1YmxpYy5nZXRfdmVoaWNsZV93b3Jrc2hvcF9kZXRhaWwocF92ZWhpY2xlX2lkKSB8fCBqc29uYl9idWlsZF9vYmplY3QoJ2ltcG9ydGVkX2FkZGl0aW9ucycsDQogIChTRUxFQ1QgY29hbGVzY2UoanNvbmJfYWdnKGpzb25iX2J1aWxkX29iamVjdCgnY2hhbmdlX2lkJyxxLmNoYW5nZV9pZCwnZGVzY3JpcHRpb24nLHEucHJvcG9zZWRfc291cmNlLT4+J29wZXJhdGlvbl9kZXNjcmlwdGlvbicsDQogICAgJ2RlcGFydG1lbnQnLHEucHJvcG9zZWRfc291cmNlLT4+J2RlcGFydG1lbnQnLCdqb2JfY2FyZCcscS5yZXBhaXJfb3JkZXJfbnVtYmVyLCdsaW5lX251bWJlcicscS5vcmlnaW5hbF9saW5lX251bWJlciwNCiAgICAnc291cmNlX2hvdXJzJyxxLnByb3Bvc2VkX3NvdXJjZS0+J3NvdXJjZV9lc3RpbWF0ZWRfaG91cnMnLCdzdGF0dXMnLGNvYWxlc2NlKHEuYXV0b21hdGlvbl9yZXN1bHQtPj4nY29kZScsJ2NsYXNzaWZpY2F0aW9uX3BlbmRpbmcnKSkgT1JERVIgQlkgcS5jcmVhdGVkX2F0KSwnW10nKQ0KICAgRlJPTSBwdWJsaWMucGRjX3R1bmVfb3BlcmF0aW9uX2NoYW5nZV9yZXZpZXdzIHEgV0hFUkUgcS52ZWhpY2xlX2lkPXBfdmVoaWNsZV9pZCBBTkQgcS5zdGF0dXM9J3BlbmRpbmcnKSk7DQogDQpFTkQNCiRmdW5jdGlvbiQ=','base64'),'UTF8'); END $b64$;

-- Restores the exact previous definition of public.get_workshop_booking_search_scoped(p_vehicles jsonb)
-- byte for byte; its source has CRLF line endings, which only survive as base64 (decoded and run as-is).
DO $b64$ BEGIN EXECUTE convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcHVibGljLmdldF93b3Jrc2hvcF9ib29raW5nX3NlYXJjaF9zY29wZWQocF92ZWhpY2xlcyBqc29uYikKIFJFVFVSTlMganNvbmIKIExBTkdVQUdFIHBscGdzcWwKIFNUQUJMRSBTRUNVUklUWSBERUZJTkVSCiBTRVQgc2VhcmNoX3BhdGggVE8gJ3BnX2NhdGFsb2cnLCAncHVibGljJwogU0VUIHN0YXRlbWVudF90aW1lb3V0IFRPICcxNXMnCkFTICRmdW5jdGlvbiQNCkRFQ0xBUkUgYWN0b3Jfc2NvcGUganNvbmI7IHJlc3VsdHMganNvbmI7DQpCRUdJTg0KIC0tIEFjdHVhbCBzaWduZWQtaW4gaWRlbnRpdHkgcGx1cyB0aGUgZXhpc3Rpbmcgcm9sZSBjaGVjayBhcmUgcmVxdWlyZWQuDQogLS0gVGhlIHByaXZhdGUgcmVhZCBoZWxwZXIgYXBwbGllcyBvbmx5IHRoZSBvd25lci1hdXRob3Jpc2VkIERlcGFydG1lbnQxMzggZGVsZWdhdGlvbi4NCiBJRiBhdXRoLnVpZCgpIElTIE5VTEwgVEhFTiBSQUlTRSBFWENFUFRJT04gJ0F1dGhlbnRpY2F0aW9uIHJlcXVpcmVkJyBVU0lORyBFUlJDT0RFPSc0MjUwMSc7IEVORCBJRjsNCiBQRVJGT1JNIHB1YmxpYy5yZXF1aXJlX3BkY19yb2xlKCd2aWV3ZXInKTsNCiBhY3Rvcl9zY29wZTo9cGRjX2NvZGV4X2ludGFrZV9wcml2YXRlLndvcmtzaG9wX3JlYWRfYWN0b3Jfc2NvcGVfMjAyNjEwMTMoKTsNCiBJRiBqc29uYl90eXBlb2YocF92ZWhpY2xlcykgSVMgRElTVElOQ1QgRlJPTSAnYXJyYXknIFRIRU4NCiAgUkVUVVJOIGpzb25iX2J1aWxkX29iamVjdCgnb2snLGZhbHNlLCdlcnJvcicsJ2ludmFsaWRfaWRlbnRpdHknKTsNCiBFTkQgSUY7DQogSUYganNvbmJfYXJyYXlfbGVuZ3RoKHBfdmVoaWNsZXMpIE5PVCBCRVRXRUVOIDEgQU5EIDI1IFRIRU4NCiAgUkVUVVJOIGpzb25iX2J1aWxkX29iamVjdCgnb2snLGZhbHNlLCdlcnJvcicsJ2ludmFsaWRfaWRlbnRpdHknKTsNCiBFTkQgSUY7DQogSUYgRVhJU1RTKFNFTEVDVCAxIEZST00ganNvbmJfYXJyYXlfZWxlbWVudHMocF92ZWhpY2xlcykgeCBXSEVSRSBqc29uYl90eXBlb2YoeCkgSVMgRElTVElOQ1QgRlJPTSAnb2JqZWN0Jw0KICAgT1IganNvbmJfdHlwZW9mKHgtPid2ZWhpY2xlX2lkJykgSVMgRElTVElOQ1QgRlJPTSAnc3RyaW5nJw0KICAgT1IgY29hbGVzY2UoeC0+Pid2ZWhpY2xlX2lkJywnJykgIX4qICdeWzAtOWEtZl17OH0tWzAtOWEtZl17NH0tWzEtNV1bMC05YS1mXXszfS1bODlhYl1bMC05YS1mXXszfS1bMC05YS1mXXsxMn0kJw0KICAgT1IganNvbmJfdHlwZW9mKHgtPidkZWFsZXJfY29kZScpIElTIERJU1RJTkNUIEZST00gJ3N0cmluZycNCiAgIE9SIGxlbmd0aChidHJpbShjb2FsZXNjZSh4LT4+J2RlYWxlcl9jb2RlJywnJykpKSBOT1QgQkVUV0VFTiAxIEFORCA4MCkNCiBPUiAoU0VMRUNUIGNvdW50KERJU1RJTkNUIGxvd2VyKHgtPj4ndmVoaWNsZV9pZCcpKSBGUk9NIGpzb25iX2FycmF5X2VsZW1lbnRzKHBfdmVoaWNsZXMpIHgpPD5qc29uYl9hcnJheV9sZW5ndGgocF92ZWhpY2xlcykgVEhFTg0KICBSRVRVUk4ganNvbmJfYnVpbGRfb2JqZWN0KCdvaycsZmFsc2UsJ2Vycm9yJywnaW52YWxpZF9pZGVudGl0eScpOw0KIEVORCBJRjsNCg0KIFdJVEggcmVxdWVzdGVkIEFTIE1BVEVSSUFMSVpFRCAoDQogIFNFTEVDVCAoeC0+Pid2ZWhpY2xlX2lkJyk6OnV1aWQgdmVoaWNsZV9pZCxidHJpbSh4LT4+J2RlYWxlcl9jb2RlJykgZGVhbGVyX2NvZGUsb3JkaW5hbA0KICBGUk9NIGpzb25iX2FycmF5X2VsZW1lbnRzKHBfdmVoaWNsZXMpIFdJVEggT1JESU5BTElUWSBxKHgsb3JkaW5hbCkNCiApLCBhdXRob3JpemVkIEFTIE1BVEVSSUFMSVpFRCAoDQogIFNFTEVDVCByLiosQ0FTRQ0KICAgV0hFTiBwZGNfY29kZXhfaW50YWtlX3ByaXZhdGUud29ya3Nob3BfcmVhZF92ZWhpY2xlX2FsbG93ZWRfMjAyNjEwMTMoYWN0b3Jfc2NvcGUsci52ZWhpY2xlX2lkLHIuZGVhbGVyX2NvZGUpIElTIE5PVCBUUlVFIFRIRU4gJ2RlYWxlcl9zY29wZV9kZW5pZWQnDQogICBXSEVOIE5PVCBFWElTVFMoU0VMRUNUIDEgRlJPTSBwdWJsaWMudmVoaWNsZXMgdiBXSEVSRSB2LmlkPXIudmVoaWNsZV9pZCBBTkQgdi5kZWxldGVkX2F0IElTIE5VTEwgQU5EIHYubGlmZWN5Y2xlX3N0YXRlPSdhY3RpdmUnDQogICAgIEFORCAocHVibGljLnBkY19hdWRpdG9yX3ZlaGljbGVfZGVhbGVyKHYuaWQpPXIuZGVhbGVyX2NvZGUgT1IgcGRjX2NvZGV4X2ludGFrZV9wcml2YXRlLndvcmtzaG9wX25vbm5hdjEzOF9yZWFkX2FsbG93ZWRfMjAyNjEwMTIoYWN0b3Jfc2NvcGUsdi5pZCxyLmRlYWxlcl9jb2RlKQ0KICAgICAgT1IgcGRjX2NvZGV4X2ludGFrZV9wcml2YXRlLndvcmtzaG9wX2FwcHJvdmVkX3BtZ19yZWFkX2FsbG93ZWRfMjAyNjEwMTkoYWN0b3Jfc2NvcGUsdi5pZCxyLmRlYWxlcl9jb2RlKSkpIFRIRU4gJ3ZlaGljbGVfbm90X2luX2RlYWxlcl9zY29wZScNCiAgIEVMU0UgTlVMTCBFTkQgZXJyb3INCiAgRlJPTSByZXF1ZXN0ZWQgcg0KICksIGJvb2tpbmdfcm93cyBBUyAoDQogIFNFTEVDVCBhLnZlaGljbGVfaWQsanNvbmJfYWdnKGpzb25iX2J1aWxkX29iamVjdCgNCiAgICdib29raW5nX2lkJyxiLmlkLCdib29raW5nX3ZlcnNpb24nLGIudmVyc2lvbiwnd29ya19jYXRlZ29yeScsYi53b3JrX2NhdGVnb3J5LCdzdGFnZV9jb2RlJyxzLmNvZGUsJ3N0YWdlX25hbWUnLHMuZGlzcGxheV9uYW1lLA0KICAgJ2JheV9udW1iZXInLGJheS5iYXlfbnVtYmVyLCdiYXlfbmFtZScsYmF5LmRpc3BsYXlfbmFtZSwnc3RhdHVzJyxiLnN0YXR1cywNCiAgICdzY2hlZHVsZWRfc3RhcnRfYXQnLGIuc2NoZWR1bGVkX3N0YXJ0X2F0LCdzY2hlZHVsZWRfZW5kX2F0JyxiLnNjaGVkdWxlZF9lbmRfYXQsDQogICAnZGVmYXVsdF9kdXJhdGlvbl9taW51dGVzJyxiLmRlZmF1bHRfZHVyYXRpb25fbWludXRlcywnYWN0dWFsX3N0YXJ0X2F0JyxiLmFjdHVhbF9zdGFydF9hdCwnYWN0dWFsX2VuZF9hdCcsYi5hY3R1YWxfZW5kX2F0KQ0KICAgT1JERVIgQlkgcy5zb3J0X29yZGVyLGIuc2NoZWR1bGVkX3N0YXJ0X2F0LGIuaWQpIGJvb2tpbmdzDQogIEZST00gYXV0aG9yaXplZCBhIEpPSU4gcHVibGljLndvcmtzaG9wX2Jvb2tpbmdzIGIgT04gYi52ZWhpY2xlX2lkPWEudmVoaWNsZV9pZCBBTkQgYS5lcnJvciBJUyBOVUxMDQogIEpPSU4gcHVibGljLndvcmtzaG9wX3N0YWdlcyBzIE9OIHMuaWQ9Yi5zdGFnZV9pZCBMRUZUIEpPSU4gcHVibGljLndvcmtzaG9wX2JheXMgYmF5IE9OIGJheS5pZD1iLmJheV9pZA0KICBXSEVSRSBiLmRlbGV0ZWRfYXQgSVMgTlVMTCBBTkQgYi5zdGF0dXMgSU4oJ3F1ZXVlZCcsJ3BsYW5uZWQnLCdzdGFydGVkJywnc3RvcHBhZ2UnLCdjb21wbGV0ZWQnKQ0KICBHUk9VUCBCWSBhLnZlaGljbGVfaWQNCiApDQogU0VMRUNUIGpzb25iX2FnZyhqc29uYl9idWlsZF9vYmplY3QoJ3ZlaGljbGVfaWQnLGEudmVoaWNsZV9pZCwnZGVhbGVyX2NvZGUnLGEuZGVhbGVyX2NvZGUsJ29rJyxhLmVycm9yIElTIE5VTEwpDQogIHx8Q0FTRSBXSEVOIGEuZXJyb3IgSVMgTlVMTCBUSEVOIGpzb25iX2J1aWxkX29iamVjdCgnYm9va2luZ3MnLGNvYWxlc2NlKGIuYm9va2luZ3MsJ1tdJzo6anNvbmIpKQ0KICAgIEVMU0UganNvbmJfYnVpbGRfb2JqZWN0KCdlcnJvcicsYS5lcnJvcikgRU5EIE9SREVSIEJZIGEub3JkaW5hbCkNCiBJTlRPIHJlc3VsdHMgRlJPTSBhdXRob3JpemVkIGEgTEVGVCBKT0lOIGJvb2tpbmdfcm93cyBiIE9OIGIudmVoaWNsZV9pZD1hLnZlaGljbGVfaWQ7DQogUkVUVVJOIGpzb25iX2J1aWxkX29iamVjdCgnb2snLHRydWUsJ3Jlc3VsdHMnLHJlc3VsdHMpOw0KRU5EICRmdW5jdGlvbiQ=','base64'),'UTF8'); END $b64$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_base jsonb; v_rows jsonb;
BEGIN
  -- r412 (F28): OFFSET 0 on the sourced/classified subqueries and the dept138 lateral keeps each per-operation helper
  -- (approved source, operation_station, pre-delivery test, department-138 station) a single evaluation; flattened, the
  -- planner copied approved_source and station_code into every reference (3-4 calls per operation). Same expressions.
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(row_value||public.pdc_vehicle_department_membership_20260919((row_value->>'id')::uuid)||jsonb_build_object(
 'navision_jita_identity_verified',jita.match_count=1,
 'navision_jita_column_present',CASE WHEN jita.match_count=1 THEN jita.column_present ELSE false END,
 'navision_jita_number_authority',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.authority ELSE NULL END,
 'navision_jita_number',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.jita_number ELSE NULL END,
 'navision_jita_identity_status',CASE WHEN jita.match_count=0 THEN 'not_found' WHEN jita.match_count=1 THEN 'exact' ELSE 'ambiguous' END
)||CASE WHEN EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews nr WHERE nr.vehicle_id=canonical.id AND nr.source_kind='tune_pmg') THEN public.pdc_tune_vehicle_details_v5(canonical.id) ELSE '{}'::jsonb END||jsonb_build_object(
    'tune_checkout',pdc_codex_intake_private.vehicle_tune_checkout(canonical.id),'tune_service_locations',pdc_codex_intake_private.vehicle_service_locations(canonical.id),'location_override',canonical.location_override,'location_override_reason',canonical.location_override_reason,'location_override_at',canonical.location_override_at,'location_override_by',canonical.location_override_by,'automatic_location',canonical.current_location,'qc_completed_at',canonical.qc_completed_at,
    'qc_completed_by',canonical.qc_completed_by,
    'rft_transferred_at',canonical.rft_transferred_at,
    'parts_flags',public.pdc_parts_flags_vehicle_20260911(canonical.id),'qc_rework',public.pdc_qc_rework_scope_20260909((row_value->>'id')::uuid),'pilbara_service_operations',service_lines,
    'operation_lines',(SELECT coalesce(jsonb_agg(
   public.pdc_standard_operation_display_20260910(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE dept138.station_code WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',dept138.station_code,'station_assignment_source','department_138_shared_work') WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END) ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
   LEFT JOIN LATERAL (
     SELECT coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) AS station_code
     WHERE btrim(op->>'department')='138'
     OFFSET 0
   ) dept138 ON true
   LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=(row_value->>'id')::uuid
     AND a.line_key='source:'||(op->>'operation_line_id') AND a.active AND a.manual_assignment_locked
     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))
  ) ORDER BY coalesce(row_value->>'stock_number',row_value->>'id')),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) row_value
  JOIN public.vehicles canonical ON canonical.id=(row_value->>'id')::uuid
  LEFT JOIN LATERAL (
   SELECT count(*) AS match_count,
    bool_or(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)) AS column_present,
    max(n.normalized_data->>'navisionJitaNumberAuthority') AS authority,
    max(n.normalized_data->>'jitQty') AS jita_number
   FROM public.navision_backend_records n
   WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision'
    AND n.canonical_vehicle_id=canonical.id
    AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(canonical.stock_number))
  ) jita ON true
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',classified.operation_id,'department',classified.department,
      'operation_no','PD'||lpad(classified.original_line_number::text,3,'0')||'-'||upper(substr(classified.semantic_hash,1,8)),
      'work_key',CASE classified.station_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(classified.station_code) END,
      'job_card_number',classified.repair_order_number,'description',coalesce(classified.approved_source->>'operation_description',classified.operation_description),
      'estimated_hours',classified.effective_estimated_hours,
      'estimated_hours_source',CASE classified.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',classified.source_estimated_hours,'effective_estimated_hours',classified.effective_estimated_hours,
      'hours_provenance',classified.hours_provenance,'parts_on_backorder_raw',classified.parts_on_backorder_raw,'parts_semantics',classified.parts_semantics,
      'classification',classified.station_code,'classification_method',coalesce(classified.method,'review'),
      'classification_confidence',coalesce(classified.confidence,0),'classification_rationale',coalesce(classified.rationale,'No current classification; retained for Review.'),
      'source_description_hash',classified.source_description_hash,'classifier_version',classified.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||classified.stock_number||':'||classified.repair_order_number||':'||classified.original_line_number
    )) ORDER BY classified.source_order),'[]'::jsonb) service_lines
    FROM (
      SELECT sourced.*,
        CASE WHEN sourced.department='138' THEN pdc_bus_private.operation_station(sourced.operation_id)
             WHEN public.pdc_is_pre_delivery_20260910(coalesce(sourced.approved_source->>'operation_description',sourced.operation_description)) THEN 'FITTING'
             ELSE coalesce(sourced.category,sourced.proposed_station,'REVIEW') END AS station_code
      FROM (
        SELECT o.operation_id,o.department,o.original_line_number,o.semantic_hash,o.repair_order_number,o.operation_description,
          o.effective_estimated_hours,o.hours_provenance,o.source_estimated_hours,o.parts_on_backorder_raw,o.parts_semantics,
          o.proposed_station,o.stock_number,o.source_order,h.category,h.method,h.confidence,h.rationale,h.source_description_hash,h.classifier_version,
          public.pdc_tune_approved_operation_source_20260912(o.operation_id) AS approved_source
        FROM public.pdc_pilbara_service_operations o
        LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
        LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
        WHERE o.vehicle_id=(row_value->>'id')::uuid
        OFFSET 0
      ) sourced
      OFFSET 0
    ) classified
  ) projected
  WHERE NOT pdc_codex_intake_private.owner_board_hold_active_20261019(canonical.id,canonical.stock_number,NULL)
     OR canonical.lifecycle_state::text='completed';
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$function$;

DROP FUNCTION pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text);
DROP FUNCTION pdc_codex_intake_private.board_identity_dealer_454(uuid);
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e45bbe3ddc4d30c1845099ee3efd33c0',release='r390',note='Key 243 + mixed 138/139 read',updated_at=clock_timestamp() WHERE signature='pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='2e059658db08521d92103504ddff7c97',release='baseline',note=NULL,updated_at=clock_timestamp() WHERE signature='public.get_vehicle_workshop_detail_scoped(uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='1d4b86872f7559b106f40dbadd3f907f',release='baseline',note='booking search',updated_at=clock_timestamp() WHERE signature='public.get_workshop_booking_search_scoped(jsonb)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='930f0f56572db71445d7de704f027aa3',release='r412',note='Outer location snapshot: per-operation helpers evaluated once (OFFSET 0) (r412, F28)',updated_at=clock_timestamp() WHERE signature='public.get_pdc_email_vehicle_location_snapshot()';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r454';
DELETE FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454' AND added_in='r454';

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM 'e45bbe3ddc4d30c1845099ee3efd33c0' THEN RAISE EXCEPTION 'r454 undo: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454 undo: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '2e059658db08521d92103504ddff7c97' THEN RAISE EXCEPTION 'r454 undo: public.get_vehicle_workshop_detail_scoped(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454 undo: public.get_vehicle_workshop_detail_scoped(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '1d4b86872f7559b106f40dbadd3f907f' THEN RAISE EXCEPTION 'r454 undo: public.get_workshop_booking_search_scoped(jsonb) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public,statement_timeout=15s' THEN RAISE EXCEPTION 'r454 undo: public.get_workshop_booking_search_scoped(jsonb) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '930f0f56572db71445d7de704f027aa3' THEN RAISE EXCEPTION 'r454 undo: public.get_pdc_email_vehicle_location_snapshot() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454 undo: public.get_pdc_email_vehicle_location_snapshot() owner/ACL/settings not as expected'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r454 undo: pdc_codex_intake_private.board_identity_dealer_454(uuid) still exists'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'r454 undo: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) still exists'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r454') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r454') THEN RAISE EXCEPTION 'r454 undo: leftovers'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r454_undo_tick') THEN RAISE EXCEPTION 'r454 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r454_undo_frc') THEN RAISE EXCEPTION 'r454 undo: fault_regression_check changed'; END IF;
END $g$;

INSERT INTO t_res SELECT 'undone', jsonb_build_object('md5s',(SELECT jsonb_object_agg(p.proname,md5(p.prosrc)) FROM pg_proc p WHERE p.oid IN ('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)'::regprocedure,'public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure,'public.get_workshop_booking_search_scoped(jsonb)'::regprocedure,'public.get_pdc_email_vehicle_location_snapshot()'::regprocedure)),'pins',(SELECT jsonb_object_agg(signature,release||':'||prosrc_md5||':'||coalesce(note,'NULL')) FROM pdc_ops.expected_function_md5 WHERE signature IN ('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)','public.get_vehicle_workshop_detail_scoped(uuid,text)','public.get_workshop_booking_search_scoped(jsonb)','public.get_pdc_email_vehicle_location_snapshot()')));
-- r454 (F67, Craig 22 Oct, decision 2): 9 board vehicles would not open ("The exact vehicle identity is unavailable" or
-- dealer_scope_denied). Cause: the dealer of a vehicle was resolved only from a CURRENT Navision record (or, for Tune intake,
-- from an open Tune job), but these vehicles stay on the board after that evidence went away:
--  * 5 Navision vehicles (active or RFT) whose only Navision record dropped out of the latest upload (not_in_latest_batch):
--    no dealer at all, so the board refused to open them before asking the server;
--  * 4 Tune intake vehicles never matched to Navision whose Tune job was checked out (review approved or closed): the board
--    opened them but the server refused (dealer_scope_denied).
-- Fix (identity resolution only; no vehicle, record, job, booking or history row is changed, merged or deleted):
--  * board_identity_dealer_454: such a Navision vehicle's dealer comes from its OWN source record (vehicles.source_record_id),
--    only when that record, source_batch_id and every record ever linked agree on one dealer (14450 or 37047);
--  * the board row carries it as identity_dealer_code (only when set), so the board can open the vehicle;
--  * workshop_board_identity_read_allowed_454: read-only Workshop detail and booking search for those two cases, only for
--    vehicles the board shows (board_vehicle_visible_453), active or RFT, inside the actor's dealer scope.
-- Changed: workshop_read_vehicle_allowed_20261013, get_vehicle_workshop_detail_scoped, get_workshop_booking_search_scoped,
-- get_pdc_email_vehicle_location_snapshot. Write paths keep public.pdc_auditor_vehicle_dealer (unchanged), so no write right is
-- added. New check board_identity_open_454 (sort 253). Not touched: workshop_clock_tick, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r454: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r454: staging only'; END IF;
 PERFORM set_config('pdc.r454_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r454_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r454_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r454: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r454') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454' OR added_in='r454') THEN RAISE EXCEPTION 'r454: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=253) THEN RAISE EXCEPTION 'r454: sort_order 253 taken'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.board_identity_dealer_454(uuid) already exists'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) already exists'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM 'e45bbe3ddc4d30c1845099ee3efd33c0' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)') IS DISTINCT FROM 'e45bbe3ddc4d30c1845099ee3efd33c0|r390' THEN RAISE EXCEPTION 'r454: pin of pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '2e059658db08521d92103504ddff7c97' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_vehicle_workshop_detail_scoped(uuid,text)') IS DISTINCT FROM '2e059658db08521d92103504ddff7c97|baseline' THEN RAISE EXCEPTION 'r454: pin of public.get_vehicle_workshop_detail_scoped(uuid,text) not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '1d4b86872f7559b106f40dbadd3f907f' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public,statement_timeout=15s' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_workshop_booking_search_scoped(jsonb)') IS DISTINCT FROM '1d4b86872f7559b106f40dbadd3f907f|baseline' THEN RAISE EXCEPTION 'r454: pin of public.get_workshop_booking_search_scoped(jsonb) not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '930f0f56572db71445d7de704f027aa3' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() owner/ACL/settings not as expected'; END IF;
 IF (SELECT prosrc_md5||'|'||release FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_email_vehicle_location_snapshot()') IS DISTINCT FROM '930f0f56572db71445d7de704f027aa3|r412' THEN RAISE EXCEPTION 'r454: pin of public.get_pdc_email_vehicle_location_snapshot() not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_vehicle_visible_453(uuid)')) IS DISTINCT FROM 'd98f1bce13cbc964fba7332d8a4f6d97' THEN RAISE EXCEPTION 'r454: r453 is not applied'; END IF;
 PERFORM set_config('pdc.r454_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.board_identity_dealer_454(p_vehicle_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r454 (F67): the dealer of an active or RFT Navision vehicle whose only Navision record dropped out of the latest upload
 -- (no current record at all). Taken from the vehicle's OWN source record (vehicles.source_record_id), and only when that
 -- record, the vehicle's source_batch_id and every Navision record ever linked to the vehicle name the same one dealer
 -- (14450 or 37047). NULL in every other case: a vehicle with a current record keeps public.pdc_auditor_vehicle_dealer().
 -- Read-only; never used by a write path.
 SELECT v.source_batch_id
 FROM public.vehicles v
 WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
   AND v.lifecycle_state IN('active','rft') AND v.source_system='microsoft_navision'
   AND v.source_batch_id IN('14450','37047')
   AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id AND n.is_current)
   AND EXISTS(SELECT 1 FROM public.navision_backend_records n
     WHERE n.id::text=v.source_record_id AND n.canonical_vehicle_id=v.id AND n.source_system='microsoft_navision'
       AND n.dealer_code=v.source_batch_id AND NOT n.is_current)
   AND (SELECT count(DISTINCT n.dealer_code) FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id)=1
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.board_identity_dealer_454(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_board_identity_read_allowed_454(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r454 (F67): read-only Workshop detail for a vehicle that is on the shared board but whose source evidence has gone:
 --  (a) a Navision vehicle whose only record dropped out of the latest upload: its dealer comes from its own source record
 --      (board_identity_dealer_454) and must be the requested dealer, inside the actor's dealer scope (14450 also reads 37047
 --      vehicles that own Pilbara Service operations, the existing bridge);
 --  (b) a Tune intake vehicle that was never matched to Navision, whose Tune review was approved or closed (checked out):
 --      read under the board's dealer 14450, the same scope the r390 Tune rule uses while its job is open.
 -- Only for vehicles the board shows (board_vehicle_visible_453), active or RFT. No write path calls this.
 SELECT coalesce(
  p_scope->>'environment'='staging' AND p_scope->>'role' IN('viewer','operator','administrator')
  AND NOT (p_scope ? 'department_scope')
  AND p_requested_dealer IN('14450','37047')
  AND public.pdc_auditor_vehicle_dealer(p_vehicle_id) IS NULL
  AND pdc_codex_intake_private.board_vehicle_visible_453(p_vehicle_id)
  AND (
   (pdc_codex_intake_private.board_identity_dealer_454(p_vehicle_id)=p_requested_dealer
    AND (p_scope->>'dealer_code'=p_requested_dealer
     OR (p_scope->>'dealer_code'='14450' AND p_requested_dealer='37047'
         AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=p_vehicle_id))))
   OR (p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450'
    AND EXISTS(SELECT 1 FROM public.vehicles v
      WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND v.visible_on_board
        AND v.lifecycle_state IN('active','rft') AND v.source_system='tune_pmg'
        AND nullif(btrim(v.stock_number),'') IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id)
        AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r
          WHERE r.vehicle_id=v.id AND r.source_kind='tune_pmg' AND r.status IN('approved','closed'))))
  ),false)
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ SELECT coalesce((public.pdc_workshop_actor_vehicle_allowed(p_scope,p_vehicle_id,p_requested_dealer)
 OR pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(p_scope,p_vehicle_id,p_requested_dealer)
 -- r454 (F67): a board vehicle whose Navision record left the latest upload, or a checked-out Tune vehicle (read only).
 OR pdc_codex_intake_private.workshop_board_identity_read_allowed_454(p_scope,p_vehicle_id,p_requested_dealer))
 AND (NOT (p_scope ? 'department_scope') OR
   (p_scope->>'department_scope'='138' AND p_scope->>'environment'='staging' AND p_scope->>'role' IN ('viewer','operator','administrator') AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450' AND EXISTS (
SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
WHERE v.id=p_vehicle_id AND (v.source_system='tune_pmg' OR (v.source_system='microsoft_navision' AND v.permanent_vehicle_id='TUNE/PMG:'||v.stock_number AND v.source_payload->>'intake_source_system'='tune_pmg')) AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR (j.departments IS DISTINCT FROM ARRAY['138']::text[] AND j.departments IS DISTINCT FROM ARRAY['139']::text[]) OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND ((o.department IS DISTINCT FROM '138' AND o.department IS DISTINCT FROM '139') OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
))),false); $function$;

CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid, p_dealer_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_scope jsonb; v_dealer text; v_vehicle_dealer text;
BEGIN
  v_scope:=pdc_codex_intake_private.workshop_read_actor_scope_20261013();
  v_dealer:=btrim(coalesce(p_dealer_code,''));
  IF NOT pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied','data',jsonb_build_object('environment','staging','dealer_code',v_dealer));
  END IF;
  SELECT public.pdc_auditor_vehicle_dealer(v.id) INTO v_vehicle_dealer
  FROM public.vehicles v
  WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active';
  IF v_vehicle_dealer IS DISTINCT FROM v_dealer AND NOT pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(v_scope,p_vehicle_id,v_dealer)
 AND NOT pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(v_scope,p_vehicle_id,v_dealer)
 AND NOT pdc_codex_intake_private.workshop_board_identity_read_allowed_454(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_dealer_scope','data',jsonb_build_object('vehicle_id',p_vehicle_id,'dealer_code',v_dealer));
  END IF;
  RETURN public.get_vehicle_workshop_detail(p_vehicle_id) || jsonb_build_object('imported_additions',
  (SELECT coalesce(jsonb_agg(jsonb_build_object('change_id',q.change_id,'description',q.proposed_source->>'operation_description',
    'department',q.proposed_source->>'department','job_card',q.repair_order_number,'line_number',q.original_line_number,
    'source_hours',q.proposed_source->'source_estimated_hours','status',coalesce(q.automation_result->>'code','classification_pending')) ORDER BY q.created_at),'[]')
   FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=p_vehicle_id AND q.status='pending'));
 
END
$function$;

CREATE OR REPLACE FUNCTION public.get_workshop_booking_search_scoped(p_vehicles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '15s'
AS $function$
DECLARE actor_scope jsonb; results jsonb;
BEGIN
 -- Actual signed-in identity plus the existing role check are required.
 -- The private read helper applies only the owner-authorised Department138 delegation.
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 PERFORM public.require_pdc_role('viewer');
 actor_scope:=pdc_codex_intake_private.workshop_read_actor_scope_20261013();
 IF jsonb_typeof(p_vehicles) IS DISTINCT FROM 'array' THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF jsonb_array_length(p_vehicles) NOT BETWEEN 1 AND 25 THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_vehicles) x WHERE jsonb_typeof(x) IS DISTINCT FROM 'object'
   OR jsonb_typeof(x->'vehicle_id') IS DISTINCT FROM 'string'
   OR coalesce(x->>'vehicle_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   OR jsonb_typeof(x->'dealer_code') IS DISTINCT FROM 'string'
   OR length(btrim(coalesce(x->>'dealer_code',''))) NOT BETWEEN 1 AND 80)
 OR (SELECT count(DISTINCT lower(x->>'vehicle_id')) FROM jsonb_array_elements(p_vehicles) x)<>jsonb_array_length(p_vehicles) THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;

 WITH requested AS MATERIALIZED (
  SELECT (x->>'vehicle_id')::uuid vehicle_id,btrim(x->>'dealer_code') dealer_code,ordinal
  FROM jsonb_array_elements(p_vehicles) WITH ORDINALITY q(x,ordinal)
 ), authorized AS MATERIALIZED (
  SELECT r.*,CASE
   WHEN pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(actor_scope,r.vehicle_id,r.dealer_code) IS NOT TRUE THEN 'dealer_scope_denied'
   WHEN NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=r.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
     AND (public.pdc_auditor_vehicle_dealer(v.id)=r.dealer_code OR pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(actor_scope,v.id,r.dealer_code)
      OR pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(actor_scope,v.id,r.dealer_code)))
     -- r454 (F67): board vehicles whose source record left the latest upload, or checked-out Tune vehicles (read only).
     AND NOT pdc_codex_intake_private.workshop_board_identity_read_allowed_454(actor_scope,r.vehicle_id,r.dealer_code) THEN 'vehicle_not_in_dealer_scope'
   ELSE NULL END error
  FROM requested r
 ), booking_rows AS (
  SELECT a.vehicle_id,jsonb_agg(jsonb_build_object(
   'booking_id',b.id,'booking_version',b.version,'work_category',b.work_category,'stage_code',s.code,'stage_name',s.display_name,
   'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',b.status,
   'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
   'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at)
   ORDER BY s.sort_order,b.scheduled_start_at,b.id) bookings
  FROM authorized a JOIN public.workshop_bookings b ON b.vehicle_id=a.vehicle_id AND a.error IS NULL
  JOIN public.workshop_stages s ON s.id=b.stage_id LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
  GROUP BY a.vehicle_id
 )
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',a.vehicle_id,'dealer_code',a.dealer_code,'ok',a.error IS NULL)
  ||CASE WHEN a.error IS NULL THEN jsonb_build_object('bookings',coalesce(b.bookings,'[]'::jsonb))
    ELSE jsonb_build_object('error',a.error) END ORDER BY a.ordinal)
 INTO results FROM authorized a LEFT JOIN booking_rows b ON b.vehicle_id=a.vehicle_id;
 RETURN jsonb_build_object('ok',true,'results',results);
END $function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_base jsonb; v_rows jsonb;
BEGIN
  -- r454 (F67): identity_dealer_code (only when set) gives a vehicle whose only Navision record left the latest upload its
  -- dealer back, so the board can open it read-only; see pdc_codex_intake_private.board_identity_dealer_454.
  -- r412 (F28): OFFSET 0 on the sourced/classified subqueries and the dept138 lateral keeps each per-operation helper
  -- (approved source, operation_station, pre-delivery test, department-138 station) a single evaluation; flattened, the
  -- planner copied approved_source and station_code into every reference (3-4 calls per operation). Same expressions.
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(row_value||public.pdc_vehicle_department_membership_20260919((row_value->>'id')::uuid)||jsonb_build_object(
 'navision_jita_identity_verified',jita.match_count=1,
 'navision_jita_column_present',CASE WHEN jita.match_count=1 THEN jita.column_present ELSE false END,
 'navision_jita_number_authority',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.authority ELSE NULL END,
 'navision_jita_number',CASE WHEN jita.match_count=1 AND jita.column_present THEN jita.jita_number ELSE NULL END,
 'navision_jita_identity_status',CASE WHEN jita.match_count=0 THEN 'not_found' WHEN jita.match_count=1 THEN 'exact' ELSE 'ambiguous' END
)||CASE WHEN EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews nr WHERE nr.vehicle_id=canonical.id AND nr.source_kind='tune_pmg') THEN public.pdc_tune_vehicle_details_v5(canonical.id) ELSE '{}'::jsonb END||jsonb_strip_nulls(jsonb_build_object('identity_dealer_code',pdc_codex_intake_private.board_identity_dealer_454(canonical.id)))||jsonb_build_object(
    'tune_checkout',pdc_codex_intake_private.vehicle_tune_checkout(canonical.id),'tune_service_locations',pdc_codex_intake_private.vehicle_service_locations(canonical.id),'location_override',canonical.location_override,'location_override_reason',canonical.location_override_reason,'location_override_at',canonical.location_override_at,'location_override_by',canonical.location_override_by,'automatic_location',canonical.current_location,'qc_completed_at',canonical.qc_completed_at,
    'qc_completed_by',canonical.qc_completed_by,
    'rft_transferred_at',canonical.rft_transferred_at,
    'parts_flags',public.pdc_parts_flags_vehicle_20260911(canonical.id),'qc_rework',public.pdc_qc_rework_scope_20260909((row_value->>'id')::uuid),'pilbara_service_operations',service_lines,
    'operation_lines',(SELECT coalesce(jsonb_agg(
   public.pdc_standard_operation_display_20260910(CASE WHEN btrim(op->>'department')='138' THEN op||jsonb_build_object('work_key',CASE dept138.station_code WHEN 'TINT' THEN 'tint' WHEN 'TYRE' THEN 'tyre' ELSE 'bus4x4' END,'classification',dept138.station_code,'station_assignment_source','department_138_shared_work') WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END) ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
   LEFT JOIN LATERAL (
     SELECT coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) AS station_code
     WHERE btrim(op->>'department')='138'
     OFFSET 0
   ) dept138 ON true
   LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=(row_value->>'id')::uuid
     AND a.line_key='source:'||(op->>'operation_line_id') AND a.active AND a.manual_assignment_locked
     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))
  ) ORDER BY coalesce(row_value->>'stock_number',row_value->>'id')),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) row_value
  JOIN public.vehicles canonical ON canonical.id=(row_value->>'id')::uuid
  LEFT JOIN LATERAL (
   SELECT count(*) AS match_count,
    bool_or(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)) AS column_present,
    max(n.normalized_data->>'navisionJitaNumberAuthority') AS authority,
    max(n.normalized_data->>'jitQty') AS jita_number
   FROM public.navision_backend_records n
   WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision'
    AND n.canonical_vehicle_id=canonical.id
    AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(canonical.stock_number))
  ) jita ON true
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(public.pdc_standard_operation_display_20260910(jsonb_build_object(
      'operation_line_id',classified.operation_id,'department',classified.department,
      'operation_no','PD'||lpad(classified.original_line_number::text,3,'0')||'-'||upper(substr(classified.semantic_hash,1,8)),
      'work_key',CASE classified.station_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(classified.station_code) END,
      'job_card_number',classified.repair_order_number,'description',coalesce(classified.approved_source->>'operation_description',classified.operation_description),
      'estimated_hours',classified.effective_estimated_hours,
      'estimated_hours_source',CASE classified.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',classified.source_estimated_hours,'effective_estimated_hours',classified.effective_estimated_hours,
      'hours_provenance',classified.hours_provenance,'parts_on_backorder_raw',classified.parts_on_backorder_raw,'parts_semantics',classified.parts_semantics,
      'classification',classified.station_code,'classification_method',coalesce(classified.method,'review'),
      'classification_confidence',coalesce(classified.confidence,0),'classification_rationale',coalesce(classified.rationale,'No current classification; retained for Review.'),
      'source_description_hash',classified.source_description_hash,'classifier_version',classified.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||classified.stock_number||':'||classified.repair_order_number||':'||classified.original_line_number
    )) ORDER BY classified.source_order),'[]'::jsonb) service_lines
    FROM (
      SELECT sourced.*,
        CASE WHEN sourced.department='138' THEN pdc_bus_private.operation_station(sourced.operation_id)
             WHEN public.pdc_is_pre_delivery_20260910(coalesce(sourced.approved_source->>'operation_description',sourced.operation_description)) THEN 'FITTING'
             ELSE coalesce(sourced.category,sourced.proposed_station,'REVIEW') END AS station_code
      FROM (
        SELECT o.operation_id,o.department,o.original_line_number,o.semantic_hash,o.repair_order_number,o.operation_description,
          o.effective_estimated_hours,o.hours_provenance,o.source_estimated_hours,o.parts_on_backorder_raw,o.parts_semantics,
          o.proposed_station,o.stock_number,o.source_order,h.category,h.method,h.confidence,h.rationale,h.source_description_hash,h.classifier_version,
          public.pdc_tune_approved_operation_source_20260912(o.operation_id) AS approved_source
        FROM public.pdc_pilbara_service_operations o
        LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
        LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
        WHERE o.vehicle_id=(row_value->>'id')::uuid
        OFFSET 0
      ) sourced
      OFFSET 0
    ) classified
  ) projected
  WHERE NOT pdc_codex_intake_private.owner_board_hold_active_20261019(canonical.id,canonical.stock_number,NULL)
     OR canonical.lifecycle_state::text='completed';
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$function$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='cba3a1268c1363043c4df2b9d65b69e7',release='r454',note='r454: + board identity read rule (F67); r390 Key 243 + mixed 138/139 read',updated_at=clock_timestamp() WHERE signature='pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='c0ba734f2f4945e902a6c474cb589089',release='r454',note='r454: board identity read rule in the dealer check (F67)',updated_at=clock_timestamp() WHERE signature='public.get_vehicle_workshop_detail_scoped(uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f348c91e50b70c2dd14d8651f97d52a2',release='r454',note='r454: booking search; board identity read rule (F67)',updated_at=clock_timestamp() WHERE signature='public.get_workshop_booking_search_scoped(jsonb)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e7f77fad301b8a87ef548472a8f790a6',release='r454',note='Outer location snapshot (r412, F28) + identity_dealer_code (r454, F67)',updated_at=clock_timestamp() WHERE signature='public.get_pdc_email_vehicle_location_snapshot()';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_codex_intake_private.board_identity_dealer_454(uuid)','a1c3a6a592ac1e7e7c20df3b498748c9','r454','r454: dealer of a board vehicle whose only Navision record left the latest upload (F67)'),
 ('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)','88eb91cdfef653bad2013342c375af4b','r454','r454: read-only open for board vehicles without current source evidence (F67)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('board_identity_open_454','F67','Board vehicles whose source record left the latest upload, or checked-out Tune vehicles, open read-only (r454)',$chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r454'),
readers AS (
  SELECT count(*) FILTER (WHERE p.oid NOT IN (pg_catalog.to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)'),
     pg_catalog.to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)'),pg_catalog.to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)'))) other
  FROM pg_catalog.pg_proc p WHERE strpos(p.prosrc,'workshop_board_identity_read_allowed_454(')>0),
dealer_users AS (
  SELECT count(*) FILTER (WHERE p.oid NOT IN (pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()'),
     pg_catalog.to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)'))) other
  FROM pg_catalog.pg_proc p WHERE strpos(p.prosrc,'board_identity_dealer_454(')>0),
found AS (
  SELECT count(*) FILTER (WHERE pdc_codex_intake_private.board_identity_dealer_454(v.id) IS NOT NULL) n
  FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state IN ('active','rft'))
SELECT (SELECT n FROM pins)=6 AND (SELECT ok FROM pins)=6 AND (SELECT other FROM readers)=0 AND (SELECT other FROM dealer_users)=0 AS ok,
 'Board identity open (r454): r454 pins matching '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; other functions using the read rule: '||(SELECT other FROM readers)||' (must be 0: read paths only)'
 ||'; other functions using the dealer fallback: '||(SELECT other FROM dealer_users)
 ||'; active/RFT vehicles whose dealer comes from their own source record: '||(SELECT n FROM found) AS detail$chk$,true,253,'r454');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM 'cba3a1268c1363043c4df2b9d65b69e7' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres}|false|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM 'c0ba734f2f4945e902a6c474cb589089' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_vehicle_workshop_detail_scoped(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_vehicle_workshop_detail_scoped(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM 'f348c91e50b70c2dd14d8651f97d52a2' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_workshop_booking_search_scoped(jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public,statement_timeout=15s' THEN RAISE EXCEPTION 'r454: public.get_workshop_booking_search_scoped(jsonb) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM 'e7f77fad301b8a87ef548472a8f790a6' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r454: public.get_pdc_email_vehicle_location_snapshot() owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)')) IS DISTINCT FROM 'a1c3a6a592ac1e7e7c20df3b498748c9' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.board_identity_dealer_454(uuid) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_identity_dealer_454(uuid)')) IS DISTINCT FROM '{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.board_identity_dealer_454(uuid) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)')) IS DISTINCT FROM '88eb91cdfef653bad2013342c375af4b' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r454: pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r454')<>6 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r454_pins')::int+2 THEN RAISE EXCEPTION 'r454: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='board_identity_open_454' AND added_in='r454' AND sort_order=253) IS DISTINCT FROM '91d258c06dbb1a3dee061b19e97acf17' THEN RAISE EXCEPTION 'r454: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name IN ('board_identity_open_454') LOOP
  DECLARE y record; BEGIN EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r454: check % not OK: %',x.check_name,y.detail; END IF; END;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r454_tick') THEN RAISE EXCEPTION 'r454: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r454_frc') THEN RAISE EXCEPTION 'r454: fault_regression_check changed'; END IF;
END $g$;

INSERT INTO t_res SELECT 'reapplied', to_jsonb((SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r454'));
DO $f$ BEGIN RAISE EXCEPTION 'R454_RB_B %', (SELECT jsonb_object_agg(k,v) FROM t_res); END $f$;