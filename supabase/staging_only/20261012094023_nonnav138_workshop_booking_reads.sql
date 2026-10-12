-- STAGING ONLY. Read access for approved Company01/Division1 Department138 Tune vehicles without Navision.
-- No dealer identity, actor scope, booking, parts, operation, hours or progress is written.
SET LOCAL statement_timeout='120s';
DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection()
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging management required'; END IF;
 IF md5(pg_get_functiondef('public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)'::regprocedure)) IS DISTINCT FROM '8554e5b1d8d164a4c14ad30493def2ae' THEN RAISE EXCEPTION 'Current pdc_workshop_actor_vehicle_allowed differs from reviewed source'; END IF;
IF md5(pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure)) IS DISTINCT FROM '2807b8679f3001047f6e614a334154a9' THEN RAISE EXCEPTION 'Current get_vehicle_workshop_detail_scoped differs from reviewed source'; END IF;
IF md5(pg_get_functiondef('public.get_workshop_booking_search_scoped(jsonb)'::regprocedure)) IS DISTINCT FROM '68cef02e82fd09f75bb4cd991b8abe70' THEN RAISE EXCEPTION 'Current get_workshop_booking_search_scoped differs from reviewed source'; END IF;
 PERFORM set_config('lock_timeout','60s',true);
 PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
 PERFORM set_config('lock_timeout','5s',true);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 PERFORM set_config('pdc.nonnav138_read_protected',md5((jsonb_build_object(
'PMG_vehicles',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),
'PMG_operations',(SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_id) FROM public.pdc_pilbara_service_operations o),
'PMG_jobs',(SELECT jsonb_agg(to_jsonb(j) ORDER BY id) FROM pdc_parts_private.jobs j),
'PMG_bookings',(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),
'PMG_adjustments',(SELECT jsonb_agg(to_jsonb(a) ORDER BY adjustment_id) FROM public.vehicle_workshop_line_adjustments a),
'PMG_parts_updates',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.vehicle_parts_updates x),
'PMG_confirmations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.pdc_parts_completion_email_confirmations x),
'PMG_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.pdc_new_vehicle_reviews x),
'PMG_change_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.pdc_tune_operation_change_reviews x),
'KTA_vehicles',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM karratha135_pdc.vehicles v),
'KTA_operations',(SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_id) FROM karratha135_pdc.pdc_pilbara_service_operations o),
'KTA_jobs',(SELECT jsonb_agg(to_jsonb(j) ORDER BY id) FROM karratha135_parts.jobs j),
'KTA_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.pdc_new_vehicle_reviews x),
'KTA_change_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.pdc_tune_operation_change_reviews x),
'KTA_bookings',(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM karratha135_pdc.workshop_bookings b),
'KTA_adjustments',(SELECT jsonb_agg(to_jsonb(a) ORDER BY adjustment_id) FROM karratha135_pdc.vehicle_workshop_line_adjustments a),
'KTA_confirmations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.pdc_parts_completion_email_confirmations x),
'KTA_parts_updates',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.vehicle_parts_updates x),
'importer_ban',(SELECT banned_until FROM auth.users WHERE id='0640d2f1-9f97-4e20-8a4f-cb6069b005df')
))::text),true);
 PERFORM set_config('pdc.nonnav138_nav_matrix',(select md5(jsonb_agg(jsonb_build_array(v.id,d.scope,d.request,public.pdc_workshop_actor_vehicle_allowed(jsonb_build_object('environment','staging','role','operator','dealer_code',d.scope),v.id,d.request)) order by v.id,d.scope,d.request)::text) from public.vehicles v cross join (values ('14450','14450'),('14450','37047'),('37047','14450'),('37047','37047')) d(scope,request) where public.pdc_auditor_vehicle_dealer(v.id) is not null),true);
END $guard$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(p_scope jsonb,p_vehicle_id uuid,p_requested_dealer text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public
AS $allowed$ SELECT coalesce(p_scope->>'environment'='staging' AND p_scope->>'role' IN ('viewer','operator','administrator') AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450' AND EXISTS (
SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
WHERE v.id=p_vehicle_id AND v.source_system='tune_pmg' AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records nr WHERE nr.canonical_vehicle_id=v.id AND nr.is_current)
AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR j.departments IS DISTINCT FROM ARRAY['138']::text[] OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND (o.department IS DISTINCT FROM '138' OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
),false); $allowed$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text) FROM public,anon,authenticated,service_role;
COMMENT ON FUNCTION pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text) IS 'Internal read-only scope bridge for authenticated PDC14450 users and approved active visible Tune Company01 Division1 Department138 vehicles with exact native job and operation evidence, with no current Navision record. Does not assign a Navision dealer or authorise a booking.';
CREATE OR REPLACE FUNCTION public.pdc_workshop_actor_vehicle_allowed(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_requested_dealer text:=btrim(coalesce(p_requested_dealer,''));
  v_vehicle_dealer text;
BEGIN
  IF p_scope->>'environment' IS DISTINCT FROM 'staging'
     OR coalesce(p_scope->>'role','') NOT IN ('viewer','operator','administrator')
     OR v_requested_dealer NOT IN ('14450','37047')
  THEN RETURN false; END IF;

  IF pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(p_scope,p_vehicle_id,v_requested_dealer) THEN RETURN true; END IF;
  v_vehicle_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);
  IF v_vehicle_dealer IS DISTINCT FROM v_requested_dealer THEN RETURN false; END IF;

  -- The shared PDC board is scoped to dealer 14450 but intentionally imports
  -- dealer 37047 Pilbara Service job cards. Bridge only an exact active vehicle
  -- that actually owns immutable Pilbara Service operation evidence; this does
  -- not add or broaden actor dealer-scope rows.
  RETURN p_scope->>'dealer_code'=v_vehicle_dealer
    OR (
      p_scope->>'dealer_code'='14450'
      AND v_vehicle_dealer='37047'
      AND EXISTS(
        SELECT 1 FROM public.pdc_pilbara_service_operations o
        JOIN public.vehicles v ON v.id=o.vehicle_id
        WHERE o.vehicle_id=p_vehicle_id
          AND v.lifecycle_state='active' AND v.deleted_at IS NULL
      )
    );
END
$function$
;
CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid, p_dealer_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_scope jsonb; v_dealer text; v_vehicle_dealer text;
BEGIN
  v_scope:=public.pdc_auditor_actor_scope();
  v_dealer:=btrim(coalesce(p_dealer_code,''));
  IF NOT public.pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied','data',jsonb_build_object('environment','staging','dealer_code',v_dealer));
  END IF;
  SELECT public.pdc_auditor_vehicle_dealer(v.id) INTO v_vehicle_dealer
  FROM public.vehicles v
  WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active';
  IF v_vehicle_dealer IS DISTINCT FROM v_dealer AND NOT pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_dealer_scope','data',jsonb_build_object('vehicle_id',p_vehicle_id,'dealer_code',v_dealer));
  END IF;
  RETURN public.get_vehicle_workshop_detail(p_vehicle_id);
END
$function$
;
CREATE OR REPLACE FUNCTION public.get_workshop_booking_search_scoped(p_vehicles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '15s'
AS $function$
DECLARE actor_scope jsonb; results jsonb;
BEGIN
 -- Both checks are required by the existing scoped detail contract. The
 -- private predicate additionally permits only the established exact Pilbara
 -- source bridge; no new actor/dealer permissions are introduced here.
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 PERFORM public.require_pdc_role('viewer');
 actor_scope:=public.pdc_auditor_actor_scope();
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
   WHEN public.pdc_workshop_actor_vehicle_allowed(actor_scope,r.vehicle_id,r.dealer_code) IS NOT TRUE THEN 'dealer_scope_denied'
   WHEN NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=r.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
     AND (public.pdc_auditor_vehicle_dealer(v.id)=r.dealer_code OR pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(actor_scope,v.id,r.dealer_code))) THEN 'vehicle_not_in_dealer_scope'
   ELSE NULL END error
  FROM requested r
 ), booking_rows AS (
  SELECT a.vehicle_id,jsonb_agg(jsonb_build_object(
   'booking_id',b.id,'booking_version',b.version,'stage_code',s.code,'stage_name',s.display_name,
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
END $function$
;
DO $verify$
DECLARE target_vehicle uuid; s jsonb; rejected boolean:=false; n integer; test record;
BEGIN
 SELECT id INTO STRICT target_vehicle FROM public.vehicles WHERE stock_number='U158851' AND job_card_number='J138000823';
 s:='{"environment":"staging","role":"operator","dealer_code":"14450"}'::jsonb;
 IF NOT pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(s,target_vehicle,'14450') OR NOT public.pdc_workshop_actor_vehicle_allowed(s,target_vehicle,'14450') THEN RAISE EXCEPTION 'Reported vehicle still denied'; END IF;
 FOR test IN SELECT * FROM (VALUES
 ('{}'::jsonb,'14450'),
 ('{"environment":"production","role":"operator","dealer_code":"14450"}'::jsonb,'14450'),
 ('{"environment":"staging","role":"anonymous","dealer_code":"14450"}'::jsonb,'14450'),
 ('{"environment":"staging","role":"operator","dealer_code":"37047"}'::jsonb,'14450'),
 (s,'37047'),(s,'135'),(s,NULL::text)) x(scope,dealer)
 LOOP
  IF pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(test.scope,target_vehicle,test.dealer) THEN RAISE EXCEPTION 'Invalid scope allowed'; END IF;
 END LOOP;
 IF pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(s,'00000000-0000-0000-0000-000000000000','14450') THEN RAISE EXCEPTION 'Unknown identity allowed'; END IF;
 SELECT count(*) INTO n FROM public.vehicles x WHERE pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(s,x.id,'14450');
 IF n<>11 THEN RAISE EXCEPTION 'Approved source preview changed: % eligible',n; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles x WHERE pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(s,x.id,'14450') AND (x.deleted_at IS NOT NULL OR x.lifecycle_state<>'active' OR NOT x.visible_on_board OR EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=x.id AND j.closed_at IS NULL AND j.departments IS DISTINCT FROM ARRAY['138']::text[]))) THEN RAISE EXCEPTION 'Hidden closed or mixed scope admitted'; END IF;
 IF (select md5(jsonb_agg(jsonb_build_array(v.id,d.scope,d.request,public.pdc_workshop_actor_vehicle_allowed(jsonb_build_object('environment','staging','role','operator','dealer_code',d.scope),v.id,d.request)) order by v.id,d.scope,d.request)::text) from public.vehicles v cross join (values ('14450','14450'),('14450','37047'),('37047','14450'),('37047','37047')) d(scope,request) where public.pdc_auditor_vehicle_dealer(v.id) is not null) IS DISTINCT FROM current_setting('pdc.nonnav138_nav_matrix') THEN RAISE EXCEPTION 'Existing Navision scope changed'; END IF;
 IF md5((jsonb_build_object(
'PMG_vehicles',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),
'PMG_operations',(SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_id) FROM public.pdc_pilbara_service_operations o),
'PMG_jobs',(SELECT jsonb_agg(to_jsonb(j) ORDER BY id) FROM pdc_parts_private.jobs j),
'PMG_bookings',(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),
'PMG_adjustments',(SELECT jsonb_agg(to_jsonb(a) ORDER BY adjustment_id) FROM public.vehicle_workshop_line_adjustments a),
'PMG_parts_updates',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.vehicle_parts_updates x),
'PMG_confirmations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.pdc_parts_completion_email_confirmations x),
'PMG_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.pdc_new_vehicle_reviews x),
'PMG_change_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM public.pdc_tune_operation_change_reviews x),
'KTA_vehicles',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM karratha135_pdc.vehicles v),
'KTA_operations',(SELECT jsonb_agg(to_jsonb(o) ORDER BY operation_id) FROM karratha135_pdc.pdc_pilbara_service_operations o),
'KTA_jobs',(SELECT jsonb_agg(to_jsonb(j) ORDER BY id) FROM karratha135_parts.jobs j),
'KTA_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.pdc_new_vehicle_reviews x),
'KTA_change_reviews',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.pdc_tune_operation_change_reviews x),
'KTA_bookings',(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM karratha135_pdc.workshop_bookings b),
'KTA_adjustments',(SELECT jsonb_agg(to_jsonb(a) ORDER BY adjustment_id) FROM karratha135_pdc.vehicle_workshop_line_adjustments a),
'KTA_confirmations',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.pdc_parts_completion_email_confirmations x),
'KTA_parts_updates',(SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM karratha135_pdc.vehicle_parts_updates x),
'importer_ban',(SELECT banned_until FROM auth.users WHERE id='0640d2f1-9f97-4e20-8a4f-cb6069b005df')
))::text) IS DISTINCT FROM current_setting('pdc.nonnav138_read_protected') THEN RAISE EXCEPTION 'Read repair modified business data'; END IF;
 IF md5(pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure))<>'ac4fb0eb639e8d01d4c86b972a807256' THEN RAISE EXCEPTION 'Hours write path changed'; END IF;
 IF has_function_privilege('authenticated','pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)','execute') OR has_function_privilege('anon','pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)','execute') OR has_function_privilege('service_role','pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)','execute') THEN RAISE EXCEPTION 'Private helper exposed'; END IF;
 IF auth.uid() IS NULL THEN
  BEGIN PERFORM public.get_workshop_booking_search_scoped(jsonb_build_array(jsonb_build_object('vehicle_id',target_vehicle,'dealer_code','14450'))); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
  IF NOT rejected THEN RAISE EXCEPTION 'Unauthenticated search did not fail'; END IF;
 END IF;
END $verify$;
NOTIFY pgrst,'reload schema';
