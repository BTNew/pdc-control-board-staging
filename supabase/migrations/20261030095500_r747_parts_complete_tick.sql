-- r747 (F353) / sort 467. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 08:20: "build me a parts complete button here and tidy up the stoppage button. when we tick parts complete
-- it marks the parts complete on the vehicle location tab".
-- Adds a Parts complete tick to the vehicle side panel (Parts ETA section, beside Place as STOPPAGE).
-- Ticked: the vehicle's parts flags read green "Parts complete — marked on the board", so the Parts Jita box on Vehicle
-- Locations (and the Sales PMB box, which reads the same flags) shows a green tick. Unticked: the import status shows again.
-- Same people as the Parts ETA date (parts importer, workshop controller operator, administrator).
-- The import evidence is never changed; the email confirmation still wins when both exist.
-- Rollback: supabase/rollbacks/20261030095500_r747_parts_complete_tick.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '60s';

DO $guard747$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r747: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r747: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r747: an import job is running'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 467 OR fault_id = 'F353' OR added_in = 'r747' OR check_name = 'parts_complete_tick_747') THEN RAISE EXCEPTION 'r747: sort 467 or F353 is taken'; END IF;
  IF to_regclass('public.pdc_parts_board_complete_747') IS NOT NULL THEN RAISE EXCEPTION 'r747: already applied'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure))
     IS DISTINCT FROM md5($src$
DECLARE imported jsonb; c public.pdc_parts_completion_email_confirmations%rowtype; mark jsonb;
BEGIN
 imported:=public.pdc_imported_parts_flags_vehicle_20260912(p_vehicle_id);
 SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=p_vehicle_id AND active;
 IF NOT FOUND THEN RETURN imported; END IF;
 mark:=jsonb_build_object('colour','green','label','Parts complete — person confirmed','parts_complete',true,
 'override_source','authorised_email_confirmation','person_confirmed',true,'confirmation_id',c.confirmation_id,
 'confirmed_at',c.received_at,'confirmed_by',c.sender,'confirmed_by_name',coalesce(nullif(c.authentication->>'display_name',''),c.sender),
 'meaning','A person confirmed the parts are here. This confirmation takes priority over import backorder flags; original import evidence is retained.');
 RETURN coalesce(imported,'{}')||mark||jsonb_build_object('import_status',imported,
 'jobs',(SELECT coalesce(jsonb_agg(j||mark||jsonb_build_object('import_status',j)),'[]') FROM jsonb_array_elements(coalesce(imported->'jobs','[]')) j),
 'operations',(SELECT coalesce(jsonb_object_agg(key,value||mark||jsonb_build_object('import_status',value,'job_label','A person confirmed parts complete for this vehicle')),'{}') FROM jsonb_each(coalesce(imported->'operations','{}'))));
END $src$) THEN RAISE EXCEPTION 'r747: pdc_parts_flags_vehicle_20260911 is not the expected body'; END IF;
END $guard747$;

-- One row per vehicle. active = the Parts complete tick is on.
CREATE TABLE public.pdc_parts_board_complete_747 (
  vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
  active boolean NOT NULL DEFAULT true,
  set_by uuid,
  set_by_actor text NOT NULL,
  set_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  cleared_by_actor text,
  cleared_at timestamptz
);
CREATE TABLE public.pdc_parts_board_complete_history_747 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN ('complete', 'undo')),
  actor uuid,
  actor_email text NOT NULL,
  at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX pdc_parts_board_complete_history_747_vehicle ON public.pdc_parts_board_complete_history_747 (vehicle_id, at DESC);
ALTER TABLE public.pdc_parts_board_complete_747 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_parts_board_complete_history_747 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_parts_board_complete_747, public.pdc_parts_board_complete_history_747 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.set_pdc_parts_board_complete_747(p_vehicle_id uuid, p_complete boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $fn$
DECLARE
  v_role text := public.current_pdc_user_role()::text;
  v_uid uuid := auth.uid();
  v_actor text := coalesce(nullif(btrim(coalesce(auth.jwt()->>'email', '')), ''), v_uid::text, 'unknown');
  v_want boolean := coalesce(p_complete, false);
  v_row public.pdc_parts_board_complete_747%ROWTYPE;
  v_after public.pdc_parts_board_complete_747%ROWTYPE;
BEGIN
  -- r747 (F353): the side-panel Parts complete tick. Writes only this table, its history and the board revision.
  IF to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'staging_only');
  END IF;
  IF v_role IS DISTINCT FROM 'importer' AND v_role IS DISTINCT FROM 'operator' AND v_role IS DISTINCT FROM 'administrator' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
  END IF;
  IF p_vehicle_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.vehicles v WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL AND v.board_purged_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc_parts_board_complete_747:' || p_vehicle_id::text, 0));
  SELECT * INTO v_row FROM public.pdc_parts_board_complete_747 WHERE vehicle_id = p_vehicle_id FOR UPDATE;
  IF coalesce(v_row.active, false) = v_want THEN
    RETURN jsonb_build_object('ok', true, 'changed', false, 'complete', v_want, 'vehicle_id', p_vehicle_id,
      'set_by_actor', v_row.set_by_actor, 'set_at', v_row.set_at);
  END IF;
  INSERT INTO public.pdc_parts_board_complete_747 AS t (vehicle_id, active, set_by, set_by_actor, set_at)
  VALUES (p_vehicle_id, v_want, v_uid, v_actor, clock_timestamp())
  ON CONFLICT (vehicle_id) DO UPDATE SET
    active = v_want,
    set_by = CASE WHEN v_want THEN v_uid ELSE t.set_by END,
    set_by_actor = CASE WHEN v_want THEN v_actor ELSE t.set_by_actor END,
    set_at = CASE WHEN v_want THEN clock_timestamp() ELSE t.set_at END,
    cleared_by_actor = CASE WHEN v_want THEN NULL ELSE v_actor END,
    cleared_at = CASE WHEN v_want THEN NULL ELSE clock_timestamp() END
  WHERE t.vehicle_id = excluded.vehicle_id
  RETURNING * INTO v_after;
  INSERT INTO public.pdc_parts_board_complete_history_747 (vehicle_id, action, actor, actor_email)
  VALUES (p_vehicle_id, CASE WHEN v_want THEN 'complete' ELSE 'undo' END, v_uid, v_actor);
  -- The Vehicle Locations snapshot is cached per revision; the next read shows the new colour.
  UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1, updated_at = clock_timestamp() WHERE singleton;
  RETURN jsonb_build_object('ok', true, 'changed', true, 'complete', v_want, 'vehicle_id', p_vehicle_id,
    'set_by_actor', v_after.set_by_actor, 'set_at', v_after.set_at);
END
$fn$;
REVOKE ALL ON FUNCTION public.set_pdc_parts_board_complete_747(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_parts_board_complete_747(uuid, boolean) TO authenticated;

-- The parts flags read the tick after the email confirmation. Same signature, same attributes.
CREATE OR REPLACE FUNCTION public.pdc_parts_flags_vehicle_20260911(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE imported jsonb; c public.pdc_parts_completion_email_confirmations%rowtype; b public.pdc_parts_board_complete_747%rowtype; mark jsonb;
BEGIN
 imported:=public.pdc_imported_parts_flags_vehicle_20260912(p_vehicle_id);
 SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=p_vehicle_id AND active;
 IF FOUND THEN
 mark:=jsonb_build_object('colour','green','label','Parts complete — person confirmed','parts_complete',true,
 'override_source','authorised_email_confirmation','person_confirmed',true,'confirmation_id',c.confirmation_id,
 'confirmed_at',c.received_at,'confirmed_by',c.sender,'confirmed_by_name',coalesce(nullif(c.authentication->>'display_name',''),c.sender),
 'meaning','A person confirmed the parts are here. This confirmation takes priority over import backorder flags; original import evidence is retained.');
 ELSE
 -- r747 (F353): the side-panel Parts complete tick.
 SELECT * INTO b FROM public.pdc_parts_board_complete_747 WHERE vehicle_id=p_vehicle_id AND active;
 IF NOT FOUND THEN RETURN imported; END IF;
 mark:=jsonb_build_object('colour','green','label','Parts complete — marked on the board','parts_complete',true,
 'override_source','board_parts_complete','person_confirmed',true,
 'confirmed_at',b.set_at,'confirmed_by',b.set_by_actor,'confirmed_by_name',b.set_by_actor,
 'meaning','Parts complete was ticked on the board. This takes priority over import backorder flags; original import evidence is retained.');
 END IF;
 RETURN coalesce(imported,'{}')||mark||jsonb_build_object('import_status',imported,
 'jobs',(SELECT coalesce(jsonb_agg(j||mark||jsonb_build_object('import_status',j)),'[]') FROM jsonb_array_elements(coalesce(imported->'jobs','[]')) j),
 'operations',(SELECT coalesce(jsonb_object_agg(key,value||mark||jsonb_build_object('import_status',value,'job_label','A person confirmed parts complete for this vehicle')),'{}') FROM jsonb_each(coalesce(imported->'operations','{}'))));
END $function$;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('parts_complete_tick_747', 'F353',
  'The side-panel Parts complete tick turns the parts flags green (board_parts_complete) after the email confirmation, and only parts, controllers and administrators can set it.',
  $chk$
SELECT strpos(f.src, 'board_parts_complete') > 0
   AND strpos(f.src, 'pdc_parts_completion_email_confirmations') > 0
   AND strpos(s.src, '''importer''') > 0 AND strpos(s.src, 'not_authorized') > 0
   AND has_function_privilege('authenticated', 'public.set_pdc_parts_board_complete_747(uuid,boolean)', 'EXECUTE')
   AND NOT has_function_privilege('anon', 'public.set_pdc_parts_board_complete_747(uuid,boolean)', 'EXECUTE')
   AND NOT has_table_privilege('authenticated', 'public.pdc_parts_board_complete_747', 'SELECT') AS ok,
 'parts complete tick reads green and is guarded' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.pdc_parts_flags_vehicle_20260911(uuid)')) f,
     (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.set_pdc_parts_board_complete_747(uuid,boolean)')) s
$chk$, true, 467, 'r747');

-- The 514 and 515 checks pin the parts flags body; move them to the r747 body (applied 30 Oct 09:58 as r747_parts_flags_pin_follows).
DO $pin747$
DECLARE v_new text; v_n integer;
BEGIN
  SELECT md5(prosrc) INTO v_new FROM pg_proc WHERE oid = 'public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, '6c828cb4ffdd7e0717bd5d9f50f4c764', v_new)
  WHERE check_name IN ('outlook_parts_completion_514', 'outlook_internal_parts_auth_515') AND strpos(check_sql, '6c828cb4ffdd7e0717bd5d9f50f4c764') > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 2 THEN RAISE EXCEPTION 'r747 pin: expected 2 checks, moved %', v_n; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = v_new WHERE prosrc_md5 = '6c828cb4ffdd7e0717bd5d9f50f4c764';
END $pin747$;

DO $post747$
DECLARE r record;
BEGIN
  -- Runs only this release's check (the full suite takes longer than the statement limit).
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'parts_complete_tick_747') INTO r;
  IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r747: parts_complete_tick_747 red after apply: %', r.detail; END IF;
END $post747$;
