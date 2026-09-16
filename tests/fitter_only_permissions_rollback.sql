BEGIN;
DO $test$
DECLARE a uuid:=gen_random_uuid(); e text; path text; rejected boolean; r jsonb;
BEGIN
 e:='fitter-access-test-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
 UPDATE public.pdc_user_roles SET role='fitter',active=true,account_status='approved' WHERE auth_user_id=a;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 PERFORM set_config('request.method','POST',true);
 FOREACH path IN ARRAY ARRAY['/vehicles','/rpc/get_workshop_snapshot','/rpc/admin_list_users','/rpc/start_workshop_work','/rpc/get_pdc_usage_report_20260914','/rpc/get_pdc_auditor_snapshot','/rpc/update_vehicle','/rpc/graphql'] LOOP
  PERFORM set_config('request.path',path,true); rejected:=false;
  BEGIN PERFORM public.pdc_check_fitter_request(); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
  IF NOT rejected OR public.is_pdc_role('viewer') OR public.is_pdc_role('operator') OR public.workshop_is_planner_operator() THEN
   RAISE EXCEPTION 'Restricted endpoint allowed: %',path;
  END IF;
 END LOOP;
 PERFORM set_config('request.path','/rpc/get_fitter_roster',true);
 PERFORM public.pdc_check_fitter_request(); r:=public.get_fitter_roster();
 IF (r->>'ok')::boolean IS NOT TRUE OR public.workshop_is_planner_operator() THEN RAISE EXCEPTION 'Fitter roster authority failed'; END IF;
 PERFORM set_config('request.path','/rpc/fitter_job_command',true);
 PERFORM public.pdc_check_fitter_request();
 IF NOT public.workshop_is_planner_operator() OR NOT public.is_pdc_role('operator') OR public.is_pdc_role('administrator') OR public.is_pdc_role('importer') THEN RAISE EXCEPTION 'Fitter command authority failed'; END IF;
 PERFORM set_config('request.path','',true);
 IF public.is_pdc_role('viewer') OR public.workshop_is_planner_operator() THEN RAISE EXCEPTION 'Non-HTTP/Realtime access leaked'; END IF;
 PERFORM set_config('request.path','/rpc/get_fitter_roster',true);
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE auth_user_id=a;
 rejected:=false;
 BEGIN PERFORM public.pdc_check_fitter_request(); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected OR public.is_pdc_role('viewer') THEN RAISE EXCEPTION 'Disabled fitter retained access'; END IF;
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved' WHERE auth_user_id=a;
 PERFORM set_config('request.path','/rpc/get_workshop_snapshot',true);
 PERFORM public.pdc_check_fitter_request();
 IF NOT public.is_pdc_role('viewer') OR NOT public.workshop_is_planner_operator() OR public.is_pdc_role('administrator') THEN RAISE EXCEPTION 'Controller permissions changed'; END IF;
END $test$;
ROLLBACK;
SELECT 'Fitter access checks passed; synthetic account rolled back' AS result;
