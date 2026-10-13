-- Staging only: implement the owner's existing Department138 delegation for workshop reads.
-- No account, role, dealer-scope, booking, source-hour or progress records are changed.
SET LOCAL statement_timeout='120s';
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection()
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging management required'; END IF;
 IF md5(pg_get_functiondef('public.pdc_auditor_actor_scope()'::regprocedure)) IS DISTINCT FROM 'd91f6a93e74ee32beb9e5a57bb72624c' THEN RAISE EXCEPTION 'Reviewed function changed: pdc_auditor_actor_scope()'; END IF;
IF md5(pg_get_functiondef('public.get_workshop_booking_search_scoped(jsonb)'::regprocedure)) IS DISTINCT FROM 'c13a6a05d5c43af730e022b849dda2af' THEN RAISE EXCEPTION 'Reviewed function changed: get_workshop_booking_search_scoped(jsonb)'; END IF;
IF md5(pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure)) IS DISTINCT FROM '404212a7514bafdbd2912daf9f8285ea' THEN RAISE EXCEPTION 'Reviewed function changed: get_vehicle_workshop_detail_scoped(uuid,text)'; END IF;
IF md5(pg_get_functiondef('public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)'::regprocedure)) IS DISTINCT FROM 'a87d2986089f9b2ac9c2f0926409063b' THEN RAISE EXCEPTION 'Reviewed function changed: pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)'; END IF;
IF md5(pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure)) IS DISTINCT FROM 'ac4fb0eb639e8d01d4c86b972a807256' THEN RAISE EXCEPTION 'Reviewed function changed: save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'; END IF;
 PERFORM set_config('lock_timeout','60s',true);
 PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
 PERFORM set_config('lock_timeout','5s',true);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 PERFORM set_config('pdc.delegated138_protected',md5((jsonb_build_object(
'roles',(SELECT jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text) FROM public.pdc_user_roles r),
'scopes',(SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY to_jsonb(scope_row)::text) FROM public.pdc_auditor_user_dealer_scopes scope_row),
'auth_identity',(SELECT jsonb_agg(jsonb_build_array(u.id,u.email,u.banned_until) ORDER BY u.id) FROM auth.users u),
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
END $guard$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_delegated138_identity_20261013(p_uid uuid,p_email text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public
AS $identity$
 SELECT CASE WHEN count(*)=1 THEN jsonb_build_object(
 'user_id',p_uid,'email',lower(btrim(p_email)),'role',min(r.role::text),
 'dealer_code','14450','environment','staging','department_scope','138') ELSE NULL END
 FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE public.pdc_monitor_staging_guard()
 AND p_uid IS NOT NULL AND u.id=p_uid
 AND lower(btrim(p_email))='bhavesh.patel@pmgwa.com.au'
 AND lower(u.email)=lower(btrim(p_email)) AND lower(r.email)=lower(btrim(p_email))
 AND r.active AND r.account_status='approved' AND r.role::text IN ('operator','administrator')
 AND (u.banned_until IS NULL OR u.banned_until<=now())
 -- Never override an existing scope row, including an intentionally disabled row.
 AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s
   WHERE s.auth_user_id=p_uid OR s.normalized_email=lower(btrim(p_email)));
$identity$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_delegated138_identity_20261013(uuid,text) FROM public,anon,authenticated,service_role;
COMMENT ON FUNCTION pdc_codex_intake_private.workshop_delegated138_identity_20261013(uuid,text) IS 'Private identity predicate for the explicit owner-authorised Bhavesh Department138 workshop-read delegation. Does not create or modify accounts, scopes or roles.';

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,public
AS $scope$ DECLARE s jsonb; BEGIN
 s:=pdc_codex_intake_private.workshop_delegated138_identity_20261013(auth.uid(),auth.jwt()->>'email');
 IF s IS NOT NULL THEN RETURN s; END IF;
 RETURN public.pdc_auditor_actor_scope();
END $scope$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013() FROM public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(p_scope jsonb,p_vehicle_id uuid,p_requested_dealer text)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public
AS $gate$ SELECT coalesce(public.pdc_workshop_actor_vehicle_allowed(p_scope,p_vehicle_id,p_requested_dealer)
 AND (NOT (p_scope ? 'department_scope') OR
   (p_scope->>'department_scope'='138' AND p_scope->>'environment'='staging' AND p_scope->>'role' IN ('viewer','operator','administrator') AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450' AND EXISTS (
SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
WHERE v.id=p_vehicle_id AND v.source_system='tune_pmg' AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR j.departments IS DISTINCT FROM ARRAY['138']::text[] OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND (o.department IS DISTINCT FROM '138' OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
))),false); $gate$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text) FROM public,anon,authenticated,service_role;
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
DECLARE target_vehicle uuid; bh_uid uuid; s jsonb; t record; rejected boolean; candidate_count integer;
BEGIN
 SELECT id INTO STRICT bh_uid FROM auth.users WHERE lower(email)='bhavesh.patel@pmgwa.com.au';
 SELECT id INTO STRICT target_vehicle FROM public.vehicles WHERE stock_number='U158851' AND job_card_number='J138000823';
 s:=pdc_codex_intake_private.workshop_delegated138_identity_20261013(bh_uid,'bhavesh.patel@pmgwa.com.au');
 IF s IS NULL OR s->>'department_scope'<>'138' OR s->>'role'<>'operator' THEN RAISE EXCEPTION 'Actual delegated operator not recognised'; END IF;
 IF NOT pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(s,target_vehicle,'14450') THEN RAISE EXCEPTION 'Reported vehicle still denied'; END IF;
 FOR t IN SELECT * FROM (VALUES
 (NULL::uuid,'bhavesh.patel@pmgwa.com.au'),(bh_uid,NULL::text),
 ('00000000-0000-0000-0000-000000000000'::uuid,'bhavesh.patel@pmgwa.com.au'),
 (bh_uid,'craig.watson@broometoyota.com.au'),(bh_uid,'untrusted@pmgwa.com.au')) x(uid,email)
 LOOP
 IF pdc_codex_intake_private.workshop_delegated138_identity_20261013(t.uid,t.email) IS NOT NULL THEN RAISE EXCEPTION 'Mismatched identity accepted'; END IF;
 END LOOP;
 FOR t IN SELECT * FROM (VALUES (s,'37047'),(s,'135'),(s,NULL::text),
 (s||'{"department_scope":"139"}'::jsonb,'14450'),(s||'{"environment":"production"}'::jsonb,'14450'),
 (s||'{"role":"viewer"}'::jsonb,'135'),('{}'::jsonb,'14450')) x(scope,dealer)
 LOOP
 IF pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(t.scope,target_vehicle,t.dealer) THEN RAISE EXCEPTION 'Invalid read scope accepted'; END IF;
 END LOOP;
 IF pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(s,'00000000-0000-0000-0000-000000000000','14450') THEN RAISE EXCEPTION 'Unknown vehicle allowed'; END IF;
 SELECT count(*) INTO candidate_count FROM public.vehicles v WHERE pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(s,v.id,'14450');
 IF candidate_count<1 THEN RAISE EXCEPTION 'Empty eligible scope'; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles v
 WHERE pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(s,v.id,'14450')
 AND (v.deleted_at IS NOT NULL OR v.board_purged_at IS NOT NULL OR v.lifecycle_state<>'active' OR NOT v.visible_on_board
 OR NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews n WHERE n.vehicle_id=v.id AND n.status='approved')
 OR EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.departments IS DISTINCT FROM ARRAY['138']::text[])
 OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.department IS DISTINCT FROM '138')))
 THEN RAISE EXCEPTION 'Hidden pending or other department allowed'; END IF;
 -- The complete existing matrix must be unchanged for actors without the new narrow marker.
 IF EXISTS(SELECT 1 FROM public.vehicles v CROSS JOIN (VALUES ('14450','14450'),('14450','37047'),('37047','14450'),('37047','37047')) d(scope,request)
 WHERE pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb_build_object('environment','staging','role','operator','dealer_code',d.scope),v.id,d.request)
 IS DISTINCT FROM public.pdc_workshop_actor_vehicle_allowed(jsonb_build_object('environment','staging','role','operator','dealer_code',d.scope),v.id,d.request))
 THEN RAISE EXCEPTION 'Existing actor matrix changed'; END IF;
 IF md5(pg_get_functiondef('public.pdc_auditor_actor_scope()'::regprocedure)) IS DISTINCT FROM 'd91f6a93e74ee32beb9e5a57bb72624c' THEN RAISE EXCEPTION 'Protected function changed: pdc_auditor_actor_scope()'; END IF;
IF md5(pg_get_functiondef('public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)'::regprocedure)) IS DISTINCT FROM 'a87d2986089f9b2ac9c2f0926409063b' THEN RAISE EXCEPTION 'Protected function changed: pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)'; END IF;
IF md5(pg_get_functiondef('public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure)) IS DISTINCT FROM 'ac4fb0eb639e8d01d4c86b972a807256' THEN RAISE EXCEPTION 'Protected function changed: save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'; END IF;
 FOR t IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_codex_intake_private' AND p.proname IN ('workshop_delegated138_identity_20261013','workshop_read_actor_scope_20261013','workshop_read_vehicle_allowed_20261013')
 LOOP
 IF has_function_privilege('authenticated',t.oid,'execute') OR has_function_privilege('anon',t.oid,'execute') OR has_function_privilege('service_role',t.oid,'execute') THEN RAISE EXCEPTION 'Private helper exposed'; END IF;
 END LOOP;
 IF auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'Management test must not impersonate a user'; END IF;
 rejected:=false;
 BEGIN PERFORM public.get_workshop_booking_search_scoped(jsonb_build_array(jsonb_build_object('vehicle_id',target_vehicle,'dealer_code','14450'))); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Unauthenticated search did not fail'; END IF;
 rejected:=false;
 BEGIN PERFORM public.get_vehicle_workshop_detail_scoped(target_vehicle,'14450'); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Unauthenticated detail did not fail'; END IF;
 IF md5((jsonb_build_object(
'roles',(SELECT jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text) FROM public.pdc_user_roles r),
'scopes',(SELECT jsonb_agg(to_jsonb(scope_row) ORDER BY to_jsonb(scope_row)::text) FROM public.pdc_auditor_user_dealer_scopes scope_row),
'auth_identity',(SELECT jsonb_agg(jsonb_build_array(u.id,u.email,u.banned_until) ORDER BY u.id) FROM auth.users u),
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
))::text) IS DISTINCT FROM current_setting('pdc.delegated138_protected') THEN RAISE EXCEPTION 'Read repair modified business or account data'; END IF;
END $verify$;
NOTIFY pgrst,'reload schema';
