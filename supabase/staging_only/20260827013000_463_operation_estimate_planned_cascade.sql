-- STAGING ONLY 463: reconcile late Job Card estimates into the whole planned bay sequence immediately.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-463-operation-estimate-cascade',0));
DO $pre$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827012000' AND name='462_authoritative_planned_repack')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827012000')
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')<>'d40084574f801e0ea2cfd24aa69761de677bd9039c18541bcb5910a54814d2c0'
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'d69480f37eb6924a6c0cdfc1de2ca9e044841ce702cb6b6c3713840cb8c9e577'
 THEN RAISE EXCEPTION 'PDC_463_STAGING_HEAD_OR_FUNCTION_MISMATCH' USING errcode='55000';END IF;
END $pre$;
DO $repack$ DECLARE d text;patched text;BEGIN
 d:=pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure);
 patched:=replace(d,'WHERE final_start IS DISTINCT FROM original_start','WHERE final_start IS DISTINCT FROM original_start OR final_end IS DISTINCT FROM original_end');
 IF patched=d THEN RAISE EXCEPTION 'PDC_463_REPACK_PATCH_ANCHOR_MISSING' USING errcode='55000';END IF;
 EXECUTE patched;
END $repack$;
CREATE OR REPLACE FUNCTION public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid, p_stage_code text, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;
 v_increment integer;v_from timestamptz;v_cascade jsonb;
 v_original_claims text:=current_setting('request.jwt.claims',true);v_initiator_uid uuid:=auth.uid();v_initiator_email text:=public.current_actor_email();
 v_system_actor uuid;v_system_email text;
BEGIN
 IF p_vehicle_id IS NULL OR v_stage IS NULL THEN RETURN 0;END IF;
 SELECT r.auth_user_id,r.email INTO v_system_actor,v_system_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role='administrator' AND r.auth_user_id IS NOT NULL ORDER BY r.created_at,r.id LIMIT 1;
 IF v_system_actor IS NULL THEN RAISE EXCEPTION 'PDC_156_WORKSHOP_SYSTEM_ACTOR_MISSING' USING errcode='55000';END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 LOCK TABLE public.workshop_bookings,public.workshop_booking_assignments IN EXCLUSIVE MODE;
 FOR v_booking IN SELECT b.* FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status::text IN('queued','planned','started','stoppage')
    AND public.workshop_canonical_stage_code(s.code)=v_stage ORDER BY b.scheduled_start_at,b.id FOR UPDATE OF b LOOP
  v_minutes:=coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_booking.stage_id),60);
  v_end:=public.workshop_add_operational_minutes(v_booking.scheduled_start_at,v_minutes);
  IF v_booking.default_duration_minutes IS DISTINCT FROM v_minutes OR v_booking.scheduled_end_at IS DISTINCT FROM v_end THEN
   v_before:=public.workshop_booking_snapshot(v_booking.id);
   IF v_booking.status::text<>'planned' THEN
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconcile_deferred',v_before,v_before,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'proposed_duration_minutes',v_minutes,'reason','protected_non_planned_booking_window','protected_status',v_booking.status::text,
      'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
   ELSE
    SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
    v_increment:=greatest(1,coalesce(v_increment,15));
    v_from:=CASE WHEN v_booking.scheduled_start_at>clock_timestamp() THEN v_booking.scheduled_start_at ELSE
      date_trunc('minute',clock_timestamp())+
      (v_increment-mod((extract(epoch from clock_timestamp())/60)::bigint,v_increment)) * interval '1 minute' END;
    v_cascade:=public.workshop_admin_repack_planned(v_booking.bay_id,v_from,
      jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
       'operation_estimate_duration_cascade',true,'recover_overdue',v_booking.scheduled_start_at<=clock_timestamp(),
       'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email));
    v_count:=v_count+coalesce((v_cascade->>'shifted_count')::integer,0);
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RETURN v_count;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RAISE;
END $function$;
REVOKE ALL ON FUNCTION public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.workshop_admin_repack_planned(uuid,timestamptz,jsonb) FROM public,anon,authenticated,service_role;
DO $post$ DECLARE a text:=pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure);b text:=pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure);BEGIN
 IF a NOT LIKE '%final_end IS DISTINCT FROM original_end%' OR b NOT LIKE '%operation_estimate_duration_cascade%' OR b NOT LIKE '%protected_non_planned_booking_window%' OR b LIKE '%preserve already-started queued/planned booking window%' THEN RAISE EXCEPTION 'PDC_463_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827013000','463_operation_estimate_planned_cascade',ARRAY['Late Job Card operation estimates immediately repack the entire eligible planned bay sequence','A stale duration is persisted even when the first planned start does not move','Queued started stoppage completed fixed and deleted history remain protected; production untouched']);
NOTIFY pgrst,'reload schema';COMMIT;
