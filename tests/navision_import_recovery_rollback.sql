-- STAGING diagnostic. Replays the retained Broome snapshot, then rolls everything back.
-- No customer approval/import is committed. Run after applying the performance migration.
BEGIN;
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='75s';
SELECT pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0));
CREATE TEMP TABLE navision_import_recovery_results(step text, result jsonb) ON COMMIT DROP;
DO $test$
DECLARE
 actor_id uuid:=gen_random_uuid(); actor_email text; rows jsonb; preview jsonb; applied jsonb; replay jsonb;
 started timestamptz; booking_before text; booking_after text; lifecycle_before text; lifecycle_after text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING only'; END IF;
 actor_email:='navision-recovery-'||actor_id||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(actor_id,'authenticated','authenticated',actor_email,clock_timestamp(),
  '{"provider":"email","providers":["email"]}','{"full_name":"Temporary rollback Navision probe"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='importer',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=actor_id AND email=actor_email;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_id,'email',actor_email,'role','authenticated')::text,true);
 SELECT jsonb_agg(raw_evidence||jsonb_build_object('recovery_test',true) ORDER BY source_record_id_normalized)
 INTO rows FROM public.navision_backend_records WHERE dealer_code='37047' AND is_current;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) INTO booking_before FROM public.workshop_bookings b;
 SELECT md5(coalesce(jsonb_agg(jsonb_build_array(v.id,v.current_location,v.location_override,v.lifecycle_state,v.visible_on_board,
  v.pmb_stage,v.pmb_bay_stage,v.pmb_bay_number,v.active_workshop_booking_id,v.workshop_status,v.qc_completed_at,v.rft_transferred_at,v.rft_collected_at)
  ORDER BY v.id),'[]'::jsonb)::text) INTO lifecycle_before FROM public.vehicles v;
 started:=clock_timestamp();
 preview:=public.preview_navision_backend_import(rows,'microsoft_navision','37047','Pasted text',NULL);
 IF preview->>'ok'<>'true' OR preview->'data'->>'blocking'='true' THEN RAISE EXCEPTION 'Preview failed: %',preview; END IF;
 INSERT INTO navision_import_recovery_results VALUES('preview',jsonb_build_object('counts',preview->'data'->'counts','elapsed_ms',extract(epoch from clock_timestamp()-started)*1000));
 started:=clock_timestamp();
 applied:=public.apply_navision_backend_import('rollback-navision-'||actor_id,rows,'microsoft_navision','37047','Pasted text',NULL,
  preview->'data'->>'source_hash',preview->'data'->>'preview_hash',(preview->'data'->>'base_revision')::bigint);
 IF applied->>'ok'<>'true' THEN RAISE EXCEPTION 'Apply failed: %',applied; END IF;
 SET CONSTRAINTS ALL IMMEDIATE;
 INSERT INTO navision_import_recovery_results VALUES('apply_and_commit_constraints',jsonb_build_object('ok',true,'counts',applied->'data'->'counts','elapsed_ms',extract(epoch from clock_timestamp()-started)*1000));
 started:=clock_timestamp();
 replay:=public.apply_navision_backend_import('rollback-navision-'||actor_id,rows,'microsoft_navision','37047','Pasted text',NULL,
  preview->'data'->>'source_hash',preview->'data'->>'preview_hash',(preview->'data'->>'base_revision')::bigint);
 IF replay->>'ok'<>'true' OR replay->'data'->>'batch_id' IS DISTINCT FROM applied->'data'->>'batch_id'
 OR replay->>'exact_retention_replay'<>'true' THEN RAISE EXCEPTION 'Exact replay failed: %',replay; END IF;
 INSERT INTO navision_import_recovery_results VALUES('same_batch_replay',jsonb_build_object('ok',true,'elapsed_ms',extract(epoch from clock_timestamp()-started)*1000));
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) INTO booking_after FROM public.workshop_bookings b;
 SELECT md5(coalesce(jsonb_agg(jsonb_build_array(v.id,v.current_location,v.location_override,v.lifecycle_state,v.visible_on_board,
  v.pmb_stage,v.pmb_bay_stage,v.pmb_bay_number,v.active_workshop_booking_id,v.workshop_status,v.qc_completed_at,v.rft_transferred_at,v.rft_collected_at)
  ORDER BY v.id),'[]'::jsonb)::text) INTO lifecycle_after FROM public.vehicles v;
 IF booking_before IS DISTINCT FROM booking_after OR lifecycle_before IS DISTINCT FROM lifecycle_after
 THEN RAISE EXCEPTION 'Retained snapshot changed workshop bookings or vehicle lifecycle'; END IF;
 IF public.pdc_navision_vehicle_parity_494(NULL)->>'ok'<>'true' THEN RAISE EXCEPTION 'Navision parity failed'; END IF;
 INSERT INTO navision_import_recovery_results VALUES('preservation',jsonb_build_object('bookings_unchanged',true,'lifecycle_unchanged',true,'parity_ok',true));
END $test$;
SELECT * FROM navision_import_recovery_results;
ROLLBACK;

