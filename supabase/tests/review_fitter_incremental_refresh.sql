-- Run only after the matching migration, using a privileged test connection.
-- All temporary role/revision edits roll back. No booking or operation is edited.
BEGIN;
DO $test$
DECLARE staff record; fitter record; technician uuid; other_technician uuid; booking uuid;
 counts jsonb; first_read jsonb; next_read jsonb; fresh jsonb; expected jsonb; token text; stage text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'Staging only'; END IF;
 IF has_function_privilege('anon','public.get_pdc_review_counts()','EXECUTE')
 OR has_function_privilege('anon','public.get_fitter_refresh(uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Anonymous execute privilege'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 PERFORM set_config('request.method','POST',true);
 PERFORM set_config('request.path','/rpc/get_pdc_review_counts',true);
 IF (public.get_pdc_review_counts()->>'ok')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Missing auth accepted'; END IF;
 SELECT auth_user_id,email,role,active,account_status INTO staff FROM public.pdc_user_roles
 WHERE active AND account_status='approved' AND role IN('administrator','operator') ORDER BY role LIMIT 1;
 IF staff.auth_user_id IS NULL THEN RAISE EXCEPTION 'Approved staff fixture required'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',staff.auth_user_id,'email',staff.email,'session_id','counts-test')::text,true);
 counts:=public.get_pdc_review_counts();
 PERFORM set_config('request.path','/rpc/list_pdc_new_vehicle_reviews',true);
 IF (counts->>'ok')::boolean IS DISTINCT FROM true
 OR counts#>>'{data,new_vehicles}' IS DISTINCT FROM public.list_pdc_new_vehicle_reviews(0,1)#>>'{data,total}'
 THEN RAISE EXCEPTION 'Badge vehicle count differs from authoritative paginated list'; END IF;
 PERFORM set_config('request.path','/rpc/list_pdc_tune_operation_changes',true);
 IF counts#>>'{data,operation_changes}' IS DISTINCT FROM public.list_pdc_tune_operation_changes(0,1)#>>'{data,total}'
 THEN RAISE EXCEPTION 'Badge counts differ from authoritative paginated lists'; END IF;
 SELECT jsonb_build_object('new_vehicles',(SELECT count(*) FROM public.pdc_new_vehicle_reviews r
  JOIN public.vehicles v ON v.id=r.vehicle_id WHERE r.status='pending' AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'),
  'operation_changes',(SELECT count(*) FROM public.pdc_tune_operation_change_reviews WHERE status='pending')) INTO expected;
 IF counts->'data' IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Archived or excluded queue rows counted'; END IF;
 PERFORM set_config('request.path','/rpc/get_pdc_review_counts',true);
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE auth_user_id=staff.auth_user_id;
 IF (public.get_pdc_review_counts()->>'ok')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Inactive account accepted'; END IF;
 UPDATE public.pdc_user_roles SET active=staff.active,account_status=staff.account_status,role=staff.role
 WHERE auth_user_id=staff.auth_user_id;
 SELECT auth_user_id,email INTO fitter FROM public.pdc_user_roles
 WHERE active AND account_status='approved' AND role='fitter' LIMIT 1;
 IF fitter.auth_user_id IS NULL THEN RAISE EXCEPTION 'Approved fitter fixture required'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',fitter.auth_user_id,'email',fitter.email,'session_id','fitter-test')::text,true);
 IF (public.get_pdc_review_counts()->>'ok')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Fitter gained review queue access'; END IF;
 PERFORM set_config('request.path','/rpc/get_workshop_overview_revisions',true);
 BEGIN
  PERFORM public.get_workshop_overview_revisions();
  RAISE EXCEPTION 'Fitter gained board access';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.path','/rpc/get_workshop_eligibility_snapshot',true);
 BEGIN
  PERFORM public.get_workshop_eligibility_snapshot();
  RAISE EXCEPTION 'Fitter gained planner access';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.path','/rpc/get_fitter_refresh',true);
 IF pdc_fitter_private.authorized_request(false) IS DISTINCT FROM true
 OR pdc_fitter_private.authorized_request(true) IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Incremental route must grant read-only fitter authority'; END IF;
 PERFORM set_config('request.path','/rpc/fitter_job_command',true);
 PERFORM set_config('request.method','GET',true);
 IF pdc_fitter_private.authorized_request(true) IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Fitter command granted write authority to GET'; END IF;
 PERFORM set_config('request.method','POST',true);
 IF pdc_fitter_private.authorized_request(true) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Existing fitter command POST authority was lost'; END IF;
 PERFORM set_config('request.path','/rpc/get_fitter_roster',true);
 IF (public.get_fitter_roster()->>'refresh_supported')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Fitter roster unavailable or capability absent'; END IF;
 SELECT t.id,b.id INTO technician,booking FROM public.workshop_bookings b
 JOIN public.vehicles v ON v.id=b.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
 JOIN public.workshop_technicians t ON t.active AND t.role_type='technician'
 WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
 AND pdc_fitter_private.assigned(b.id,t.id) ORDER BY b.id,t.id LIMIT 1;
 IF booking IS NULL THEN RAISE EXCEPTION 'Assigned booking fixture required'; END IF;
 PERFORM set_config('request.path','/rpc/get_fitter_refresh',true);
 first_read:=public.get_fitter_refresh(technician,booking,NULL);
 IF (first_read->>'ok')::boolean IS DISTINCT FROM true OR (first_read->>'unchanged')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Full fitter read failed'; END IF;
 booking:=(first_read->>'booking_id')::uuid; token:=first_read->>'revision';
 PERFORM set_config('request.path','/rpc/get_fitter_jobs',true);
 IF first_read->'jobs' IS DISTINCT FROM public.get_fitter_jobs(technician)->'jobs'
 THEN RAISE EXCEPTION 'Combined read differs from authoritative queue'; END IF;
 PERFORM set_config('request.path','/rpc/get_fitter_job',true);
 IF first_read->'detail' IS DISTINCT FROM public.get_fitter_job(technician,booking)
 THEN RAISE EXCEPTION 'Combined read differs from authoritative detail'; END IF;
 PERFORM set_config('request.path','/rpc/get_fitter_refresh',true);
 next_read:=public.get_fitter_refresh(technician,booking,token);
 IF (next_read->>'unchanged')::boolean IS DISTINCT FROM true OR next_read ? 'jobs' OR next_read ? 'detail'
 OR next_read#>'{timing,timer}' IS NULL THEN RAISE EXCEPTION 'Unchanged poll did not return timing only'; END IF;
 IF (public.get_fitter_refresh(technician,NULL,token)->>'unchanged')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Revision reused for a different selected booking'; END IF;
 SELECT id INTO other_technician FROM public.workshop_technicians WHERE active AND id<>technician LIMIT 1;
 IF other_technician IS NOT NULL AND (public.get_fitter_refresh(other_technician,NULL,token)->>'unchanged')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Revision reused for a different technician'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',staff.auth_user_id,'email',staff.email,'session_id','other-auth')::text,true);
 IF (public.get_fitter_refresh(technician,booking,token)->>'unchanged')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Revision reused for a different actor/session'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',fitter.auth_user_id,'email',fitter.email,'session_id','fitter-test')::text,true);
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1 WHERE singleton;
 fresh:=public.get_fitter_refresh(technician,booking,token);
 IF (fresh->>'unchanged')::boolean IS DISTINCT FROM false
 OR fresh#>>'{detail,version}' IS DISTINCT FROM first_read#>>'{detail,version}'
 THEN RAISE EXCEPTION 'Source revision did not refresh same-version checklist'; END IF;
 token:=fresh->>'revision';
 SELECT stage_code INTO stage FROM public.workshop_station_revision ORDER BY stage_code LIMIT 1;
 IF stage IS NULL THEN RAISE EXCEPTION 'Station revision fixture required'; END IF;
 UPDATE public.workshop_station_revision SET revision=revision+1 WHERE stage_code=stage;
 IF (public.get_fitter_refresh(technician,booking,token)->>'unchanged')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Station revision did not invalidate queue'; END IF;
END $test$;
SELECT 'review/fitter count, role, identity, source/station revision and timing-only checks passed' AS result;
ROLLBACK;
