-- r453 (F66, Craig 22 Oct, decision 1): History follows the board. Every board role (viewer, operator, importer, administrator)
-- sees a vehicle's History when the shared board shows that vehicle. Before, an account with a dealer-scope row (14450) was
-- refused History on board vehicles whose dealer was not recorded as 14450 (Tune intake, 37047 and head-office account
-- vehicles): 172 of 428 board vehicles for that account on 22 Oct. Vehicles the board does not show keep the old dealer rules
-- (nothing is widened beyond the board). Salesperson and fitter accounts stay refused (the board refuses them too).
-- New: pdc_codex_intake_private.board_vehicle_visible_453(uuid) (read-only; the board's own row rules, proven equal to the board
-- snapshot for all vehicles). Changed: public.get_pdc_vehicle_lifecycle_history_82000 (also used by the History panel's
-- get_pdc_vehicle_provenance_history). New check history_board_visibility_453 (sort 252).
-- Not touched: workshop_clock_tick, any vehicle, job, booking or history row, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r453: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r453: staging only'; END IF;
 PERFORM set_config('pdc.r453_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r453_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 IF current_setting('pdc.r453_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r453: clock tick does not match its pin (another release mid-apply?)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r453') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='history_board_visibility_453' OR added_in='r453') THEN RAISE EXCEPTION 'r453: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=252) THEN RAISE EXCEPTION 'r453: sort_order 252 taken'; END IF;
 IF to_regprocedure('pdc_codex_intake_private.board_vehicle_visible_453(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r453: pdc_codex_intake_private.board_vehicle_visible_453(uuid) already exists'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')) IS DISTINCT FROM '9f82ef530bd8c60ef1a0b55c22a85504' THEN RAISE EXCEPTION 'r453: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r453: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)') THEN RAISE EXCEPTION 'r453: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) unexpectedly pinned'; END IF;
 PERFORM set_config('pdc.r453_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.board_vehicle_visible_453(p_vehicle_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 -- r453 (F66): true when this vehicle is a row of the shared board (public.get_pdc_email_vehicle_location_snapshot) for any
 -- board role. The board itself has no dealer scope: every approved viewer, operator, importer or administrator sees the
 -- same rows. Each branch is that layer's own row rule, verbatim:
 --  1. pre168 (minus the r396 owner-document undo filter of pre_691);  2. the single pre_693 activation row;
 --  3. pre_750 collected/delivered rows;  4. pre_pilbara_service_v1 completed rows;  5. its external-completion rows;
 --  and the outer owner board hold (r20261019), which never hides a completed vehicle.
 -- Read-only. The release test proves it equals the board snapshot row set for every vehicle.
 SELECT coalesce((
  SELECT (NOT pdc_codex_intake_private.owner_board_hold_active_20261019(v.id,v.stock_number,NULL) OR v.lifecycle_state::text='completed')
   AND (
    (
     (
      (v.lifecycle_state IN('active','rft') AND v.visible_on_board)
      OR (v.lifecycle_state='completed' AND v.rft_collected_at IS NOT NULL
          AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_action_receipts_412 handover
                     WHERE handover.vehicle_id=v.id AND handover.action='collected'))
     )
     AND (
      EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts r WHERE r.vehicle_id=v.id)
      OR (v.lifecycle_state IN('active','rft') AND v.visible_on_board AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.stock_number=v.stock_number))
      OR EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND lower(wi.work_key)='sublet' AND wi.required)
      OR EXISTS(SELECT 1 FROM public.pdc_sublet_bookings s WHERE s.vehicle_id=v.id)
      OR EXISTS(
        SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
        WHERE r.run_id='HERMES-TEST-RUN-20260824' AND r.vehicle_id=v.id AND r.stock_number=v.stock_number
          AND v.stock_number~'^HERMES-TEST-(00[1-9]|01[0-9]|020)$'
          AND v.source_system='hermes_overnight_synthetic' AND v.source_batch_id=r.run_id AND v.source_record_id=r.stock_number
          AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only')
     )
     AND NOT EXISTS(
      SELECT 1 FROM public.pdc_owner_supplied_document_receipts_396 r
      JOIN public.pdc_owner_supplied_document_undo_receipts_396 u ON u.receipt_id=r.receipt_id
      WHERE r.vehicle_id=v.id
        AND NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts sibling
                       WHERE sibling.vehicle_id=r.vehicle_id AND sibling.receipt_id<>r.canonical_import_receipt_id))
    )
    OR (v.id='2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'::uuid AND public.normalize_vehicle_stock_number(v.stock_number)='13000765'
        AND v.lifecycle_state='active' AND v.visible_on_board AND v.source_system='microsoft_navision'
        AND v.source_batch_id IN('14450','37047') AND v.source_record_id IS NOT NULL
        AND EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=v.source_record_id::uuid AND n.is_current AND n.record_status='current'
                   AND n.dealer_code=v.source_batch_id AND public.normalize_vehicle_stock_number(n.normalized_data->>'batch')='13000765')
        AND EXISTS(SELECT 1 FROM public.navision_board_activations a WHERE a.canonical_vehicle_id=v.id AND a.active
                   AND public.normalize_vehicle_stock_number(a.activated_stock_number)='13000765'))
    OR (v.current_location IN('Collected','Completed')
        AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q WHERE q.vehicle_id=v.id AND q.action IN('collected','delivered')))
    OR ((v.current_location IN('Collected','Completed') OR v.lifecycle_state::text='completed')
        AND (EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.vehicle_id=v.id)
             OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q WHERE q.vehicle_id=v.id)
             OR public.pdc_lifecycle_history_payload_82000(v.id) IS NOT NULL))
    OR (v.lifecycle_state='completed' AND v.current_location='Completed'
        AND EXISTS(SELECT 1 FROM public.pdc_external_completion_receipts_20260903 r WHERE r.vehicle_id=v.id))
   )
  FROM public.vehicles v
  WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL
 ),false)
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.board_vehicle_visible_453(uuid) FROM PUBLIC, anon, authenticated, service_role;

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
  on_board boolean;
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
  -- r453 (F66): History follows the board. A vehicle that is a row of the shared board (same rows for every board role)
  -- shows its History to every board role; the dealer rules below still apply to vehicles that are not on the board.
  on_board:=pdc_codex_intake_private.board_vehicle_visible_453(p_vehicle_id);

  IF p_dealer_code IS NOT NULL AND p_dealer_code NOT IN('14450','37047') THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_scope');
  END IF;
  IF p_dealer_code IS NOT NULL AND dealer IS DISTINCT FROM p_dealer_code AND NOT on_board THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  SELECT count(*) INTO scoped
  FROM public.pdc_auditor_user_dealer_scopes s
  WHERE s.auth_user_id=uid
    AND s.normalized_email=v_actor_email
    AND s.environment='staging'
    AND s.active;
  IF NOT synthetic AND NOT on_board AND scoped>0 AND (
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

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)','7cc5705d90440dd229c349563259541f','r453','r453: History follows the board (F66)'),
 ('pdc_codex_intake_private.board_vehicle_visible_453(uuid)','d98f1bce13cbc964fba7332d8a4f6d97','r453','r453: true when the shared board shows this vehicle (F66)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('history_board_visibility_453','F66','History follows board visibility: every board role sees History on every vehicle the board shows (r453)',$chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r453'),
layers AS (
  SELECT count(*) FILTER (WHERE md5(p.prosrc)=x.m) ok FROM (VALUES ('public.get_pdc_email_vehicle_location_snapshot_pre168()','d3b6f69bdf3420336403816fc7c60255'),('public.get_pdc_email_vehicle_location_snapshot_pre_691()','775d90e421042423670990b467f157be'),('public.get_pdc_email_vehicle_location_snapshot_pre_693()','4f3f4dd8cab754543d3c0cc934ad111f'),('public.get_pdc_email_vehicle_location_snapshot_pre_750()','714fa7a3a5f79e95f2cd891ba96045cc'),('public.get_pdc_email_vehicle_location_snapshot_pre_767()','db446d2222101f0028666333779fdf23'),('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','580bf52022a37d11b78f228c37254c4a')) x(sig,m)
  LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(x.sig)),
outer_hold AS (
  SELECT strpos(p.prosrc,'WHERE NOT pdc_codex_intake_private.owner_board_hold_active_20261019(canonical.id,canonical.stock_number,NULL)')>0 ok
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()')),
uses AS (
  SELECT strpos(p.prosrc,'on_board:=pdc_codex_intake_private.board_vehicle_visible_453(p_vehicle_id)')>0 ok
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')),
board AS (
  SELECT count(*) FILTER (WHERE pdc_codex_intake_private.board_vehicle_visible_453(v.id)) n FROM public.vehicles v WHERE v.deleted_at IS NULL)
SELECT (SELECT n FROM pins)=2 AND (SELECT ok FROM pins)=2 AND (SELECT ok FROM layers)=6
  AND coalesce((SELECT ok FROM outer_hold),false) AND coalesce((SELECT ok FROM uses),false) AS ok,
 'History follows the board (r453): r453 pins matching '||(SELECT ok FROM pins)||'/'||(SELECT n FROM pins)
 ||'; board row rules unchanged since r453 '||(SELECT ok FROM layers)||'/6 (if not, re-prove board_vehicle_visible_453 against the board)'
 ||'; outer hold rule '||CASE WHEN coalesce((SELECT ok FROM outer_hold),false) THEN 'present' ELSE 'CHANGED' END
 ||'; vehicles on the board now: '||(SELECT n FROM board) AS detail$chk$,true,252,'r453');

DO $g$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')) IS DISTINCT FROM '7cc5705d90440dd229c349563259541f' THEN RAISE EXCEPTION 'r453: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|s|postgres|search_path=pg_catalog, public' THEN RAISE EXCEPTION 'r453: public.get_pdc_vehicle_lifecycle_history_82000(uuid,text) owner/ACL/settings not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_vehicle_visible_453(uuid)')) IS DISTINCT FROM 'd98f1bce13cbc964fba7332d8a4f6d97' THEN RAISE EXCEPTION 'r453: pdc_codex_intake_private.board_vehicle_visible_453(uuid) is not the expected version'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||provolatile::text||'|'||proowner::regrole::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.board_vehicle_visible_453(uuid)')) IS DISTINCT FROM '{postgres=X/postgres}|true|s|postgres|search_path=pg_catalog' THEN RAISE EXCEPTION 'r453: pdc_codex_intake_private.board_vehicle_visible_453(uuid) owner/ACL/settings not as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r453')<>2 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r453_pins')::int+2 THEN RAISE EXCEPTION 'r453: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='history_board_visibility_453' AND added_in='r453' AND sort_order=252) IS DISTINCT FROM '691868b4034248a75b6ae05388590e0a' THEN RAISE EXCEPTION 'r453: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name IN ('history_board_visibility_453') LOOP
  DECLARE y record; BEGIN EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r453: check % not OK: %',x.check_name,y.detail; END IF; END;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r453_tick') THEN RAISE EXCEPTION 'r453: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r453_frc') THEN RAISE EXCEPTION 'r453: fault_regression_check changed'; END IF;
END $g$;
