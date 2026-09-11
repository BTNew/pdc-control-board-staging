BEGIN;
DO $test$
DECLARE actor uuid:=gen_random_uuid(); vehicle uuid:=gen_random_uuid(); result jsonb; v public.vehicles%rowtype;
BEGIN
 IF public.set_pdc_vehicle_location_override(null,0,'PMB','test')->>'code'<>'not_authorized' THEN RAISE EXCEPTION 'anonymous_guard_failed'; END IF;
 INSERT INTO auth.users(id,email) VALUES(actor,'location-override-fixture@example.invalid');
 INSERT INTO public.pdc_user_roles(email,auth_user_id,role,active,account_status)
 VALUES('location-override-fixture@example.invalid',actor,'operator',true,'approved') ON CONFLICT(email) DO UPDATE SET auth_user_id=actor,role='operator',active=true,account_status='approved';
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email','location-override-fixture@example.invalid','role','authenticated')::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,current_location) VALUES(vehicle,'LOCATION-OVERRIDE-'||vehicle,'LOCATION-OVERRIDE-FIXTURE','YH');
 result:=public.set_pdc_vehicle_location_override(vehicle,1,'RFT','Physical location correction');
 IF result->>'ok'<>'true' THEN RAISE EXCEPTION 'save_failed: %',result; END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=vehicle;
 IF v.location_override<>'RFT' OR v.current_location<>'YH' OR v.qc_completed_at IS NOT NULL OR v.rft_transferred_at IS NOT NULL THEN RAISE EXCEPTION 'normal_state_modified'; END IF;
 IF public.set_pdc_vehicle_location_override(vehicle,1,'PMB','stale')->>'code'<>'version_conflict' THEN RAISE EXCEPTION 'stale_guard_failed'; END IF;
 IF public.set_pdc_vehicle_location_override(vehicle,v.version,'PMB','')->>'code'<>'invalid_location_or_reason' THEN RAISE EXCEPTION 'reason_guard_failed'; END IF;
 UPDATE public.vehicles SET current_location='PMB' WHERE id=vehicle;
 SELECT * INTO v FROM public.vehicles WHERE id=vehicle;
 IF v.location_override<>'RFT' THEN RAISE EXCEPTION 'override_lost_on_normal_update'; END IF;
 result:=public.set_pdc_vehicle_location_override(vehicle,v.version,NULL,'');
 IF result->>'ok'<>'true' THEN RAISE EXCEPTION 'clear_failed'; END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=vehicle;
 IF v.location_override IS NOT NULL OR v.current_location<>'PMB' THEN RAISE EXCEPTION 'clear_did_not_restore_current_normal_location'; END IF;
END $test$;
ROLLBACK;
