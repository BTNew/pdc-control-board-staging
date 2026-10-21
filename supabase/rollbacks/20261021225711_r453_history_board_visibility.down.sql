-- r453 undo (F66): restores public.get_pdc_vehicle_lifecycle_history_82000 byte for byte (md5 9f82ef530bd8c60ef1a0b55c22a85504),
-- drops board_vehicle_visible_453, its pins and check history_board_visibility_453. Undo r454 first (it uses the helper).
-- Run between :02 and :45. Staging only. Changes no data rows.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r453 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r453 undo: staging only'; END IF;
 PERFORM set_config('pdc.r453_undo_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r453_undo_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r453_undo_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r453 undo: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')) IS DISTINCT FROM '7cc5705d90440dd229c349563259541f' THEN RAISE EXCEPTION 'r453 undo: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_vehicle_visible_453(uuid)')) IS DISTINCT FROM 'd98f1bce13cbc964fba7332d8a4f6d97' THEN RAISE EXCEPTION 'r453 undo: pdc_codex_intake_private.board_vehicle_visible_453(uuid) is not the expected version'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)') IS NOT NULL THEN RAISE EXCEPTION 'r453 undo: undo r454 first (it uses board_vehicle_visible_453)'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='history_board_visibility_453' AND added_in='r453') THEN RAISE EXCEPTION 'r453 undo: r453 is not applied'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_pdc_vehicle_lifecycle_history_82000(p_vehicle_id uuid, p_dealer_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  actor_role text;
  v public.vehicles%rowtype;
  h jsonb;
  dealer text;
  scoped integer;
  synthetic boolean;
BEGIN
  IF NOT public.pdc_lifecycle_history_enabled_82000() OR uid IS NULL OR v_actor_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;

  SELECT r.role::text INTO actor_role
  FROM public.pdc_user_roles r
  WHERE r.auth_user_id=uid
    AND lower(r.email)=v_actor_email
    AND r.active
    AND r.account_status='approved'
  LIMIT 1;

  IF actor_role IS NULL OR actor_role NOT IN('viewer','operator','importer','administrator') THEN
    RETURN jsonb_build_object('ok',false,'code','forbidden');
  END IF;

  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND AND NOT EXISTS(
    SELECT 1 FROM public.pdc_vehicle_lifecycle_history_events_82000 WHERE vehicle_id=p_vehicle_id
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_found');
  END IF;

  dealer:=CASE
    WHEN v.source_batch_id IN('14450','37047') THEN v.source_batch_id
    ELSE (
      SELECT e.dealer_code
      FROM public.pdc_vehicle_lifecycle_history_events_82000 e
      WHERE e.vehicle_id=p_vehicle_id AND e.dealer_code IS NOT NULL
      ORDER BY e.event_id
      LIMIT 1
    )
  END;
  synthetic:=coalesce(v.source_system,'')='hermes_lifecycle_history_acceptance'
    OR coalesce(v.source_batch_id,'') LIKE 'HERMES-TEST-%';

  IF p_dealer_code IS NOT NULL AND p_dealer_code NOT IN('14450','37047') THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_scope');
  END IF;
  IF p_dealer_code IS NOT NULL AND dealer IS DISTINCT FROM p_dealer_code THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  SELECT count(*) INTO scoped
  FROM public.pdc_auditor_user_dealer_scopes s
  WHERE s.auth_user_id=uid
    AND s.normalized_email=v_actor_email
    AND s.environment='staging'
    AND s.active;
  IF NOT synthetic AND scoped>0 AND (
    dealer IS NULL OR NOT EXISTS(
      SELECT 1
      FROM public.pdc_auditor_user_dealer_scopes s
      WHERE s.auth_user_id=uid
        AND s.normalized_email=v_actor_email
        AND s.environment='staging'
        AND s.active
        AND s.dealer_code=dealer
    )
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  h:=public.pdc_lifecycle_history_payload_82000(p_vehicle_id);
  RETURN jsonb_build_object(
    'ok',true,
    'code','lifecycle_history',
    'data',jsonb_build_object(
      'vehicle',jsonb_build_object(
        'vehicle_id',p_vehicle_id,
        'stock_number',coalesce(v.stock_number,h->>'stock_number'),
        'job_card_number',coalesce(v.job_card_number,h->>'job_card_number'),
        'lifecycle_state',v.lifecycle_state::text,
        'deleted_at',v.deleted_at,
        'visible_on_board',v.visible_on_board
      ),
      'lifecycle_history',h,
      'production',false,
      'timezone','Australia/Perth',
      'authority','pdc_vehicle_lifecycle_history_82000'
    )
  );
END $function$;

DROP FUNCTION pdc_codex_intake_private.board_vehicle_visible_453(uuid);
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r453';
DELETE FROM pdc_ops.regression_checks WHERE check_name='history_board_visibility_453' AND added_in='r453';

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')) IS DISTINCT FROM '9f82ef530bd8c60ef1a0b55c22a85504' THEN RAISE EXCEPTION 'r453 undo: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r453 undo: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.board_vehicle_visible_453(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r453 undo: pdc_codex_intake_private.board_vehicle_visible_453(uuid) still exists'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r453') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r453') THEN RAISE EXCEPTION 'r453 undo: leftovers'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r453_undo_tick') THEN RAISE EXCEPTION 'r453 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r453_undo_frc') THEN RAISE EXCEPTION 'r453 undo: fault_regression_check changed'; END IF;
END $g$;
