-- Exercise the real station move against an existing pending Dept 138 line,
-- inside a transaction that rolls back every fixture and mutation.
BEGIN;
DO $test$
DECLARE actor uuid:=gen_random_uuid(); vehicle uuid; line jsonb; after_line jsonb;
 prior public.vehicle_workshop_line_adjustments%rowtype; result jsonb;
BEGIN
 INSERT INTO auth.users(id,email) VALUES(actor,'review-drag-fixture@example.invalid');
 INSERT INTO public.pdc_user_roles(email,auth_user_id,role,active,account_status)
 VALUES('review-drag-fixture@example.invalid',actor,'operator',true,'approved')
 ON CONFLICT(email) DO UPDATE SET auth_user_id=actor,role='operator',active=true,account_status='approved';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email','review-drag-fixture@example.invalid','role','authenticated')::text,true);
 SELECT r.vehicle_id,l INTO vehicle,line FROM public.pdc_new_vehicle_reviews r
 CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(r.vehicle_id)) l
 WHERE r.status='pending' AND l->>'department'='138' AND (l->>'active')::boolean AND NOT (l->>'completed')::boolean
 LIMIT 1;
 IF vehicle IS NULL THEN RAISE EXCEPTION 'no_pending_department_138_fixture'; END IF;
 SELECT * INTO prior FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=vehicle AND line_key=line->>'line_identity';
 result:=public.move_vehicle_workshop_source_line_stage(vehicle,prior.adjustment_id,coalesce(prior.version,0),line->>'line_identity','SUBLET');
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'move_failed: %',result; END IF;
 SELECT l INTO after_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l WHERE l->>'line_identity'=line->>'line_identity';
 IF after_line->>'stage_code'<>'SUBLET' OR after_line->'estimated_hours' IS DISTINCT FROM line->'estimated_hours'
  OR after_line->'description' IS DISTINCT FROM line->'description' THEN RAISE EXCEPTION 'station_or_evidence_mismatch'; END IF;
 SELECT * INTO prior FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=vehicle AND line_key=line->>'line_identity';
 result:=public.move_vehicle_workshop_source_line_stage(vehicle,prior.adjustment_id,prior.version,line->>'line_identity','FITTING');
 IF result#>>'{data,qc_line,stage_code}'<>'FITTING' THEN RAISE EXCEPTION 'second_move_failed'; END IF;
END $test$;
ROLLBACK;
