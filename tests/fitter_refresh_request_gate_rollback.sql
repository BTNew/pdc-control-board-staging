-- Run only in the disposable local restore. No customer account is impersonated.
BEGIN;
DO $test$
DECLARE actor uuid:=gen_random_uuid(); email_address text; technician uuid;
 route text; method text; denied boolean; response jsonb;
BEGIN
 email_address:='fitter-refresh-test-'||actor||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(actor,'authenticated','authenticated',email_address,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
 UPDATE public.pdc_user_roles SET role='fitter',active=true,account_status='approved' WHERE auth_user_id=actor;
 IF NOT FOUND THEN RAISE EXCEPTION 'Synthetic fitter role missing'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email_address,'role','authenticated')::text,true);
 PERFORM set_config('request.method','POST',true);
 PERFORM set_config('request.path','/rpc/get_fitter_roster',true);
 PERFORM public.pdc_check_fitter_request(); response:=public.get_fitter_roster();
 IF (response->>'ok')::boolean IS DISTINCT FROM true OR (response->>'refresh_supported')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Fitter roster unavailable'; END IF;
 SELECT id INTO technician FROM public.workshop_technicians WHERE name='John Castagna' AND active AND role_type='technician';
 IF technician IS NULL THEN RAISE EXCEPTION 'John roster reference missing'; END IF;
 PERFORM set_config('request.path','/rpc/get_fitter_refresh',true);
 -- Crucially exercise the real pre-request gate before the RPC, as HTTP does.
 PERFORM public.pdc_check_fitter_request();
 IF NOT pdc_fitter_private.authorized_request(false) OR pdc_fitter_private.authorized_request(true)
 OR public.workshop_is_planner_operator() OR public.is_pdc_role('operator')
 THEN RAISE EXCEPTION 'Refresh must grant fitter read access only'; END IF;
 response:=public.get_fitter_refresh(technician,NULL,NULL);
 IF (response->>'ok')::boolean IS DISTINCT FROM true OR jsonb_typeof(response->'jobs')<>'array'
 OR response->>'revision' IS NULL THEN RAISE EXCEPTION 'John refresh failed: %',response; END IF;
 FOREACH method IN ARRAY ARRAY['GET','HEAD','PATCH','DELETE'] LOOP
  PERFORM set_config('request.method',method,true); denied:=false;
  BEGIN PERFORM public.pdc_check_fitter_request(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Unexpected refresh HTTP method allowed: %',method; END IF;
 END LOOP;
 PERFORM set_config('request.method','POST',true);
 FOREACH route IN ARRAY ARRAY['/vehicles','/rpc/get_workshop_snapshot','/rpc/get_pdc_review_counts','/rpc/admin_list_users','/rpc/start_workshop_work','/rpc/schedule_vehicle_work','/rpc/k135_get_fitter_refresh'] LOOP
  PERFORM set_config('request.path',route,true); denied:=false;
  BEGIN PERFORM public.pdc_check_fitter_request(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Unrelated route allowed: %',route; END IF;
 END LOOP;
 PERFORM set_config('request.path','/rpc/fitter_job_command',true);
 PERFORM public.pdc_check_fitter_request();
 IF NOT pdc_fitter_private.authorized_request(true) THEN RAISE EXCEPTION 'Existing command route lost'; END IF;
 PERFORM set_config('request.path','/rpc/get_fitter_refresh',true);
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE auth_user_id=actor;
 denied:=false;
 BEGIN PERFORM public.pdc_check_fitter_request(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Disabled fitter accepted'; END IF;
 UPDATE public.pdc_user_roles SET active=true,account_status='approved' WHERE auth_user_id=actor;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email','mismatch@example.invalid','role','authenticated')::text,true);
 denied:=false;
 BEGIN PERFORM public.pdc_check_fitter_request(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Mismatched fitter identity accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;
 BEGIN PERFORM public.get_fitter_refresh(technician,NULL,NULL); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied OR has_function_privilege('anon','public.get_fitter_refresh(uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous fitter read allowed'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: fitter HTTP gate, John refresh, read-only scope and denials; all rolled back' AS result;
