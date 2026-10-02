-- Run only after applying/rehearsing the candidate in a single rollback transaction.
-- Synthetic accounts and metadata only. Never create a saved vehicle, real file or email.
BEGIN;
SET LOCAL statement_timeout='45s';
SET LOCAL lock_timeout='5s';
CREATE TEMP TABLE deep_security_fixture(label text PRIMARY KEY,actor uuid,email text);
CREATE TEMP TABLE deep_security_values(key text PRIMARY KEY,value text);
GRANT SELECT ON deep_security_fixture TO authenticated;
INSERT INTO deep_security_values
 SELECT 'business_hash',md5(jsonb_build_object(
  'vehicles',(SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb) FROM public.vehicles v),
  'bookings',(SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]'::jsonb) FROM public.workshop_bookings b),
  'parts',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'::jsonb) FROM public.vehicle_parts_updates p),
  'navision',(SELECT coalesce(jsonb_agg(to_jsonb(n) ORDER BY id),'[]'::jsonb) FROM public.navision_backend_records n)
 )::text);
DO $fixtures$
DECLARE label text; actor uuid; email text; assigned_role public.pdc_role;
BEGIN
 FOREACH label IN ARRAY ARRAY['operator','importer','administrator','salesperson','viewer','fitter','pending','disabled','rejected','monitor'] LOOP
  actor:=gen_random_uuid();email:='deep-security-'||label||'-'||actor||'@example.invalid';
  INSERT INTO deep_security_fixture VALUES(label,actor,email);
  INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
   VALUES(actor,'authenticated','authenticated',email,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
  assigned_role:=CASE WHEN label='disabled' THEN 'operator'::public.pdc_role
   WHEN label IN('pending','rejected') THEN NULL WHEN label='monitor' THEN 'viewer'::public.pdc_role ELSE label::public.pdc_role END;
  UPDATE public.pdc_user_roles SET role=assigned_role,active=label NOT IN('pending','disabled','rejected'),
    account_status=(CASE WHEN label IN('pending','disabled','rejected') THEN label ELSE 'approved' END)::public.pdc_account_status WHERE auth_user_id=actor;
 END LOOP;
END $fixtures$;
DO $acl$
DECLARE signature text;
BEGIN
 FOREACH signature IN ARRAY ARRAY[
  'public.pdc_navision_vehicle_parity_494(uuid)',
  'public.pdc_operation_projection_parity_493(uuid)',
  'public.pdc_qc_operation_lines_379(uuid)',
  'public.pdc_vehicle_milestone_json(uuid)',
  'public.workshop_require_booking_schedule_eligibility(uuid,text)',
  'public.workshop_station_eligibility(text)',
  'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,workshop_booking_status,uuid)',
  'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,workshop_booking_status,uuid,boolean)'
 ] LOOP
  IF has_function_privilege('anon',signature,'EXECUTE') OR has_function_privilege('authenticated',signature,'EXECUTE') THEN
   RAISE EXCEPTION 'Internal helper is callable by browser clients: %',signature;
  END IF;
 END LOOP;
END $acl$;

SET LOCAL ROLE authenticated;
DO $roles$
DECLARE f record; denied boolean; missing uuid:='11111111-1111-4111-8111-111111111111'; observed text; snap jsonb; spoof text;
BEGIN
 FOR f IN SELECT * FROM deep_security_fixture WHERE label<>'monitor' LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
  PERFORM set_config('request.method','POST',true);
  PERFORM set_config('request.path',CASE WHEN f.label='fitter' THEN '/rpc/fitter_job_command' ELSE '/rpc/append_vehicle_timeline_event' END,true);
  FOREACH spoof IN ARRAY ARRAY['','pdc-email-ai-v2|untrusted-fabricated-token-value'] LOOP
   PERFORM set_config('pdc.monitor.v2_canonical_action_capability_20260902',spoof,true);
   observed:='no_error';
   BEGIN PERFORM public.append_vehicle_timeline_event(missing,'audit_guard_probe');
   EXCEPTION WHEN OTHERS THEN observed:=SQLSTATE; END;
   IF f.label IN('operator','importer','administrator','fitter') THEN
    IF observed<>'P0002' THEN RAISE EXCEPTION 'Legitimate timeline scope failed for %: %',f.label,observed; END IF;
   ELSIF observed<>'42501' THEN RAISE EXCEPTION 'Timeline scope leaked for %: %',f.label,observed; END IF;
   PERFORM set_config('request.path','/rpc/record_vehicle_eta_history',true);
   observed:='no_error';
   BEGIN PERFORM public.record_vehicle_eta_history(missing,'audit_guard_probe');
   EXCEPTION WHEN OTHERS THEN observed:=SQLSTATE; END;
   IF f.label IN('importer','administrator') THEN
    IF observed<>'P0002' THEN RAISE EXCEPTION 'Legitimate ETA scope failed for %: %',f.label,observed; END IF;
   ELSIF observed<>'42501' THEN RAISE EXCEPTION 'ETA scope leaked for %: %',f.label,observed; END IF;
   PERFORM set_config('request.path',CASE WHEN f.label='fitter' THEN '/rpc/fitter_job_command' ELSE '/rpc/append_vehicle_timeline_event' END,true);
  END LOOP;
  PERFORM set_config('pdc.monitor.v2_canonical_action_capability_20260902','',true);
  -- Heavy board/station snapshots run once in the separate compatibility file.
  IF f.label='fitter' THEN
   PERFORM set_config('request.path','/rpc/get_fitter_roster',true);
   PERFORM public.pdc_check_fitter_request(); snap:=public.get_fitter_roster();
   IF snap->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Fitter roster regressed'; END IF;
  END IF;
  -- Metadata INSERT exercises real Storage RLS; no file bytes are uploaded.
  PERFORM set_config('request.path','/object/pdc-qc-evidence-staging',true);
  denied:=false;
  BEGIN
   INSERT INTO storage.objects(bucket_id,name,owner_id)
    VALUES('pdc-qc-evidence-staging','qc-finalization/'||f.actor||'/deep-audit-probe.jpg',f.actor::text);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF f.label IN('operator','administrator') THEN
   IF denied THEN RAISE EXCEPTION 'Legitimate QC metadata upload denied: %',f.label; END IF;
  ELSIF NOT denied THEN RAISE EXCEPTION 'QC upload policy permits %',f.label; END IF;
 END LOOP;
 -- JWT email alone cannot inherit another principal's approved role.
 SELECT * INTO f FROM deep_security_fixture WHERE label='operator';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',missing,'email',f.email,'role','authenticated')::text,true);
 observed:='no_error';
 BEGIN PERFORM public.append_vehicle_timeline_event(missing,'audit_guard_probe'); EXCEPTION WHEN OTHERS THEN observed:=SQLSTATE; END;
 IF observed<>'42501' THEN RAISE EXCEPTION 'Mismatched principal inherited role'; END IF;
 -- Authenticated with no identity also fails closed.
 PERFORM set_config('request.jwt.claims','{"role":"authenticated"}',true);
 observed:='no_error';
 BEGIN PERFORM public.append_vehicle_timeline_event(missing,'audit_guard_probe'); EXCEPTION WHEN OTHERS THEN observed:=SQLSTATE; END;
 IF observed<>'42501' THEN RAISE EXCEPTION 'Missing principal inherited role'; END IF;
END $roles$;
RESET ROLE;

-- Check the already-sealed monitor predicate using only synthetic authorization fixtures.
DO $monitor$
DECLARE f record; approver uuid; observed text; missing uuid:='11111111-1111-4111-8111-111111111111';
BEGIN
 SELECT * INTO f FROM deep_security_fixture WHERE label='monitor';
 SELECT actor INTO approver FROM deep_security_fixture WHERE label='administrator';
 INSERT INTO public.pdc_email_ai_successor_runtime_identities(
  auth_user_id,normalized_email,environment,identity_purpose,gateway_instance_id,transport_release_version,
  model_version,prompt_version,taxonomy_version,rule_version,action_contract_version,approved_by)
 VALUES(f.actor,f.email,'staging','pdc_email_ai_transaction_successor','deep-audit-rollback','audit','audit','audit','audit','audit','pdc-email-ai-actions-v1',approver);
 INSERT INTO public.pdc_monitor_stage_activation_writers(user_id,reason,granted_by)
 VALUES(f.actor,'Synthetic rollback security verification',approver);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',f.actor,'email',f.email,'role','authenticated')::text,true);
 PERFORM set_config('pdc.monitor.v2_canonical_action_capability_20260902','pdc-email-ai-v2|synthetic-read-only-test-authority',true);
 IF NOT coalesce(public.pdc_email_ai_v2_canonical_action_capability_20260902(),false) THEN RAISE EXCEPTION 'Trusted monitor predicate fixture invalid'; END IF;
 observed:='no_error';
 BEGIN PERFORM public.append_vehicle_timeline_event(missing,'audit_guard_probe'); EXCEPTION WHEN OTHERS THEN observed:=SQLSTATE; END;
 IF observed<>'P0002' THEN RAISE EXCEPTION 'Trusted monitor timeline scope regressed: %',observed; END IF;
 observed:='no_error';
 BEGIN PERFORM public.record_vehicle_eta_history(missing,'audit_guard_probe'); EXCEPTION WHEN OTHERS THEN observed:=SQLSTATE; END;
 IF observed<>'P0002' THEN RAISE EXCEPTION 'Trusted monitor ETA scope regressed: %',observed; END IF;
 UPDATE public.pdc_monitor_stage_activation_writers SET active=false,revoked_at=now() WHERE user_id=f.actor;
 observed:='no_error';
 BEGIN PERFORM public.append_vehicle_timeline_event(missing,'audit_guard_probe'); EXCEPTION WHEN OTHERS THEN observed:=SQLSTATE; END;
 IF observed<>'42501' THEN RAISE EXCEPTION 'Revoked monitor retained timeline authority'; END IF;
END $monitor$;

-- Synthetic Storage metadata disappears with the final rollback; no file bytes exist.
DO $unchanged$
DECLARE after_hash text;
BEGIN
 SELECT md5(jsonb_build_object(
  'vehicles',(SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb) FROM public.vehicles v),
  'bookings',(SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY id),'[]'::jsonb) FROM public.workshop_bookings b),
  'parts',(SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY id),'[]'::jsonb) FROM public.vehicle_parts_updates p),
  'navision',(SELECT coalesce(jsonb_agg(to_jsonb(n) ORDER BY id),'[]'::jsonb) FROM public.navision_backend_records n)
 )::text) INTO after_hash;
 IF after_hash IS DISTINCT FROM (SELECT value FROM deep_security_values WHERE key='business_hash') THEN
  RAISE EXCEPTION 'Operational business records changed during scope checks';
 END IF;
END $unchanged$;
ROLLBACK;
SELECT 'Security scope, helper closure, QC policy, operational wrapper and monitor compatibility checks passed; all fixtures rolled back' AS verification;

