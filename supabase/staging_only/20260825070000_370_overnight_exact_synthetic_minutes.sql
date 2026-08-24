-- STAGING ONLY 370: exact sub-hour minutes for migration-369 registry-bound synthetic estimates.
-- Migration 369 source SHA-256: 152f101c80f8eec420f7d9c06de1570a81ede41620d8e5fc0ed8e479143c7f5c
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-370-overnight-exact-synthetic-minutes',0));
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_fleet_registry_363 IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_estimates_369 IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_estimate_receipts_369 IN SHARE MODE;
LOCK TABLE public.vehicles IN SHARE MODE;
LOCK TABLE public.workshop_stages IN SHARE MODE;
LOCK TABLE public.workshop_bookings IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.workshop_booking_assignments IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.workshop_booking_history IN SHARE ROW EXCLUSIVE MODE;

DO $guard$
DECLARE v_minutes_sha text;v_sync_sha text;v_dependency_sha text;v_acl text[];v_sync_acl text[];
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825060000' AND name='369_overnight_synthetic_estimates'
       AND statements=ARRAY[
        'Exact migration-368 staging head and structural installed-definition dependency checks; rollback review must bind exact installed hashes',
        'Target-based registry route guard including both established estimate relations and the synthetic estimate relation',
        'Exact scenario 005-007 positive estimates: 1.22h/73m Fitting, 1.02h/61m Electrical, 0.78h/47m Fitting, 0.98h/59m Electrical',
        'Administrator-only transaction-local wrapper, optimistic versions, immutable idempotency receipts and authoritative readback',
        'Protected/sibling estimate-relation digests, relation race locks and zero external notifications']::text[])<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825060000' AND version~'^[0-9]{14}$')
   OR NOT public.pdc_hermes_test_registry_guard_365()
   OR NOT public.pdc_hermes_test_dependency_guard_365()
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_370_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex'),
        encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex'),
        encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_hermes_test_dependency_guard_365()'::regprocedure),'UTF8'),'sha256'),'hex')
 INTO v_minutes_sha,v_sync_sha,v_dependency_sha;
 IF v_minutes_sha<>'c66f13a1859410449b2664236e1462e61bb3c09017962f7753865316bb58bd1b'
   OR v_sync_sha<>'36bc98f16010d4cc99d3d2d83f56688d3fa7860de2491c0bc7ca085564c544bc'
   OR v_dependency_sha<>'ecc6e83ca01dbc98ab682890b416234b18362d6ebd8716183ce5dc85f7e8eaaa' THEN
  RAISE EXCEPTION 'PDC_370_EXACT_PREDECESSOR_FUNCTION_MISMATCH' USING errcode='55000';
 END IF;
 SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
 INTO v_acl FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee
 WHERE p.oid='public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure;
 IF v_acl IS DISTINCT FROM ARRAY['postgres:EXECUTE']::text[] OR NOT EXISTS(SELECT 1 FROM pg_proc p
    WHERE p.oid='public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure AND p.prosecdef AND p.provolatile='s' AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[])
   OR has_function_privilege('public','public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)','EXECUTE')
   OR has_function_privilege('authenticated','public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_370_PREDECESSOR_OWNER_ACL_MISMATCH' USING errcode='55000';
 END IF;
 SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
 INTO v_sync_acl FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee
 WHERE p.oid='public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure;
 IF v_sync_acl IS DISTINCT FROM ARRAY['postgres:EXECUTE']::text[]
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure
      AND p.prosecdef AND p.provolatile='v' AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proconfig=ARRAY['search_path=pg_catalog, public, extensions']::text[])
   OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'
       AND c.relname IN('pdc_overnight_synthetic_estimates_369','pdc_overnight_synthetic_estimate_receipts_369')
       AND c.relkind='r' AND c.relrowsecurity AND NOT c.relforcerowsecurity AND pg_get_userbyid(c.relowner)='postgres'
       AND (SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
            FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee)
          =ARRAY['postgres:DELETE','postgres:INSERT','postgres:MAINTAIN','postgres:REFERENCES','postgres:SELECT','postgres:TRIGGER','postgres:TRUNCATE','postgres:UPDATE']::text[])<>2
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.pdc_overnight_synthetic_estimate_append_only_369()'::regprocedure
       AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
       AND encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')='c7881b2331e94744f7c5b8c7308b2744e5c5808ec1b2ed7711d7fee2ba0a5ba7'
       AND (SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
            FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee)=ARRAY['postgres:EXECUTE']::text[])
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.pdc_hermes_test_set_estimate_369(text,uuid,integer,bigint,uuid,text,numeric)'::regprocedure
       AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
       AND encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')='bdff67bb2b7d42a68c059e7c23dada6ac98acf23aef22c385b495c761004a91b'
       AND (SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
            FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee)=ARRAY['authenticated:EXECUTE','postgres:EXECUTE']::text[])
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.read_pdc_hermes_test_estimates_369(text,uuid)'::regprocedure
       AND p.prosecdef AND p.provolatile='s' AND pg_get_userbyid(p.proowner)='postgres'
       AND encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')='d379737a7c17cb5c66018ba60a20d2890bd4ae0cc2d0130e001666656d52db77'
       AND (SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
            FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee)=ARRAY['authenticated:EXECUTE','postgres:EXECUTE']::text[])
   OR (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relname IN('pdc_overnight_synthetic_estimates_369','pdc_overnight_synthetic_estimate_receipts_369') AND NOT t.tgisinternal AND t.tgqual IS NULL
       AND ((t.tgname='pdc_hermes_test_actor_route_guard_365' AND t.tgtype=31 AND t.tgfoid='public.pdc_hermes_test_actor_route_guard_365()'::regprocedure)
         OR (t.tgname IN('pdc_overnight_synthetic_estimates_append_only_369','pdc_overnight_synthetic_estimate_receipts_append_only_369')
             AND t.tgtype=27 AND t.tgfoid='public.pdc_overnight_synthetic_estimate_append_only_369()'::regprocedure)) AND t.tgenabled='O')<>4
   OR (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relname IN('pdc_overnight_synthetic_estimates_369','pdc_overnight_synthetic_estimate_receipts_369') AND NOT t.tgisinternal)<>4
   OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.pdc_overnight_synthetic_estimates_369'::regclass
       AND t.tgname='pdc_overnight_synthetic_estimates_append_only_369' AND t.tgenabled='O' AND t.tgqual IS NULL
       AND encode(extensions.digest(convert_to(pg_get_triggerdef(t.oid,true),'UTF8'),'sha256'),'hex')='303fe6cf3cca09b8ad6b4e94bed680e5aa824ec14c7496c9d0f9fb1e0a0c2f51')
   OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.pdc_overnight_synthetic_estimate_receipts_369'::regclass
       AND t.tgname='pdc_overnight_synthetic_estimate_receipts_append_only_369' AND t.tgenabled='O' AND t.tgqual IS NULL
       AND encode(extensions.digest(convert_to(pg_get_triggerdef(t.oid,true),'UTF8'),'sha256'),'hex')='a11bfda9c1b4be1c6e44c478b75313c0fc0965b95a0084a25fee7d888c19d8c3') THEN
  RAISE EXCEPTION 'PDC_370_MIGRATION_369_CATALOG_OR_SYNC_AUTHORITY_MISMATCH' USING errcode='55000';
 END IF;
END $guard$;

CREATE TEMP TABLE pdc_370_protected_minutes ON COMMIT DROP AS
SELECT v.id vehicle_id,s.id stage_id,public.workshop_vehicle_stage_estimated_duration_minutes(v.id,s.id) minutes
FROM public.vehicles v CROSS JOIN public.workshop_stages s
WHERE NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id);

CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id uuid,p_stage_id uuid)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
 WITH exact_synthetic AS(
  SELECT e.estimated_minutes
  FROM public.pdc_overnight_synthetic_estimates_369 e
  JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.run_id=e.run_id AND r.vehicle_id=e.vehicle_id AND r.scenario_no=e.scenario_no
  JOIN public.vehicles v ON v.id=e.vehicle_id AND v.stock_number=r.stock_number
   AND v.customer_name=r.customer_name AND v.job_card_number=r.job_card_number AND v.vehicle_description=r.vehicle_description
   AND v.source_system='hermes_overnight_synthetic' AND v.source_batch_id=e.run_id AND v.source_record_id=r.stock_number
   AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
   AND v.source_payload->>'run_id'=e.run_id AND (v.source_payload->>'scenario_no')::integer=e.scenario_no
  JOIN public.workshop_stages s ON s.id=p_stage_id AND s.code=e.stage_code
  WHERE e.run_id='HERMES-TEST-RUN-20260824' AND e.vehicle_id=p_vehicle_id
    AND e.estimated_minutes BETWEEN 1 AND 59
    AND e.estimated_minutes=round(e.estimated_hours*60)::integer
    AND public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,s.code)=e.estimated_hours
  LIMIT 1
 ), established AS(
  SELECT h.hours
  FROM public.workshop_stages s
  CROSS JOIN LATERAL(SELECT public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,s.code) hours) h
  WHERE s.id=p_stage_id
 )
 SELECT CASE WHEN x.estimated_minutes IS NOT NULL THEN x.estimated_minutes
             WHEN h.hours IS NULL THEN NULL ELSE greatest(60,round(h.hours*60)::integer) END
 FROM established h LEFT JOIN exact_synthetic x ON true
$function$;
REVOKE ALL ON FUNCTION public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid,p_stage_code text,p_reason text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $function$
DECLARE
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;
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
   IF v_booking.status::text IN('queued','planned') AND v_booking.scheduled_start_at<=clock_timestamp() THEN
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconcile_deferred',v_before,v_before,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'proposed_duration_minutes',v_minutes,'reason','preserve already-started queued/planned booking window','initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
   ELSE
    UPDATE public.workshop_bookings SET default_duration_minutes=v_minutes,scheduled_end_at=v_end,version=version+1 WHERE id=v_booking.id;
    UPDATE public.workshop_booking_assignments SET scheduled_start_at=v_booking.scheduled_start_at,scheduled_end_at=v_end WHERE booking_id=v_booking.id AND released_at IS NULL;
    v_after:=public.workshop_booking_snapshot(v_booking.id);
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconciled',v_before,v_after,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'duration_minutes',v_minutes,'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
    v_count:=v_count+1;
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RETURN v_count;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RAISE;
END $function$;
REVOKE ALL ON FUNCTION public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_dependency_guard_365()
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $guard$
DECLARE v record; v_route_def text;
BEGIN
 FOR v IN SELECT * FROM (VALUES
  ('public.set_pdc_vehicle_work_states(uuid,integer,jsonb)'::regprocedure,'17819f99ab20d552cd13db3b2a09173ebc0f85bb4edb4aada0c46cc5a52aed2b'),
  ('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'::regprocedure,'80073fd48518fcad46da32969980dc75ec312568d44d54a702363ed244a8f49f'),
  ('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure,'4553354d22b9894598311a586b6f68916facaed08466c25f1f762f9f38ba9427'),
  ('public.start_workshop_work(uuid,integer,timestamptz,jsonb)'::regprocedure,'cdcd2210cbf6a0eeda5b1566646d6acb591b82be6f98c393551d86fdd2cda035'),
  ('public.stop_workshop_work(uuid,integer,text,jsonb)'::regprocedure,'f25e81d49e28d3076c1645050ce1783ddbd1acaae7c2218095eea688cbfceb7c'),
  ('public.resume_workshop_work(uuid,integer,jsonb)'::regprocedure,'6158f6a3e529a92884c392383a421b08723ce0ac62c158e92cfcfc29d101f20c'),
  ('public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)'::regprocedure,'f3100d5c0d1b4ae0ac300770066a1a4f642a2ac1e8050bfb09d36799155baefc'),
  ('public.pmb_transfer_vehicle(uuid,integer)'::regprocedure,'a96bd0ee479061c35b8506f30a1ad5234dc6d6059ce871f16229c37b53ab6567'),
  ('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure,'9436d6812ffb74bf2bd22d261ebd2992cde011dd698366e2127a2da4b1c46fc5'),
  ('public.rft_collect_vehicle(uuid,integer)'::regprocedure,'039ae7fc4dbb8d4015e113d407d22a1d9ee10342b39c513fc02ce65e49ed0cc9'),
  ('public.update_pdc_parts_eta(uuid,integer,date)'::regprocedure,'21537485317de3e01bfe0c9722408e00cdae256f0f2396b6a50a8ac365e2e61a'),
  ('public.mark_pdc_parts_ordered(uuid,integer)'::regprocedure,'6cfdf15e3bd2e1ed93fdbb6b9717cb889eaf1f7aae816212d9c7027057ce906b'),
  ('public.mark_pdc_parts_complete(uuid,integer)'::regprocedure,'f68e9bf7d214bf6bcdc15003937dbf95313b656c604041153420fbd67bd9777c'),
  ('public.create_pdc_sublet_booking(uuid,bigint,uuid,date,date,text,text)'::regprocedure,'c345ce45a88a26cb5abd588ec9ba7c600fc9682adeae4fafb4eccf7717ff30f2'),
  ('public.update_pdc_sublet_booking(uuid,bigint,date,date,text)'::regprocedure,'81b3db339ee6cd1ec3bd1411919ad385642b557e02f125b32e2e325d871ee36d'),
  ('public.return_pdc_sublet_booking(uuid,bigint,timestamptz)'::regprocedure,'cc6a7bb0209cc279e3548b9fc2e37ac4194495d26d5029d1a52034b0be8c51cc'),
  ('public.schedule_vehicle_work_pre345(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'::regprocedure,'38d0cb3c8f8ad17a1c4fdb6c684066348339b6d53845367e43572242ade44e36'),
  ('public.start_workshop_work_pre345(uuid,integer,timestamptz,jsonb)'::regprocedure,'44e6c4ffabb42589304c7d0363a57e629f66c701bf9f3dd9ce1d46a411956b20'),
  ('public.stop_workshop_work_pre345(uuid,integer,text,jsonb)'::regprocedure,'4453b847109fb0a6de109c4961ae94bdbde856b3409f4a6e850eda3ba0891916'),
  ('public.resume_workshop_work_pre345(uuid,integer,jsonb)'::regprocedure,'07f0883833571acd272cc9d3f778c4320f292a8fc65356da5a11e3fd700363b1'),
  ('public.complete_workshop_work_pre345(uuid,integer,text,timestamptz,jsonb)'::regprocedure,'57bd9202bf9fefebb2c809ff3bd3ec9d5cd96e6406726806dd42fd2c5e023ce6'),
  ('public.update_pdc_sublet_booking_pre171(uuid,bigint,date,date,text)'::regprocedure,'08e63ca21f2d4b91a7f23dbd2f6e7ef2d8e2b5a5bc057a220f86c961ced44529'),
  ('public.return_pdc_sublet_booking_pre172(uuid,bigint,timestamptz)'::regprocedure,'524d03f29871312c9028e2ffca531396bf1baa9b4dcc4a95fb4fb4838fd224ad')
 ) d(proc,sha256) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v.proc AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
    AND encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')=v.sha256
    AND NOT has_function_privilege('public',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) THEN RETURN false; END IF;
 END LOOP;
 v_route_def:=pg_get_functiondef('public.pdc_hermes_test_actor_route_guard_365()'::regprocedure);
 IF encode(extensions.digest(convert_to(v_route_def,'UTF8'),'sha256'),'hex')<>'b3efd31fed97d449ddbb06664f35df3e867d8ac66c651077c1555b9e4dbdb6f5'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'10116ae252a8529b643fc93151faf56069892f865eff7b80f0eebd3f7b16eb2e'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex')<>'6cf33245713fe9481976f4fa47fe5f8a4b1cf8e47d5d8568eb4cb8a602e5ceee'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_require_positive_estimate_for_planned_booking_317()'::regprocedure),'UTF8'),'sha256'),'hex')<>'9ee1da8e17e1ca3672c7b4cb8c129199db24457c4c4919f1ae3b02c4631d35e9'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'::regprocedure),'UTF8'),'sha256'),'hex')<>'03116b81f574bce427ebe84c356fdedeb8f8b0e0428db52841598c32bf08bb86'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'d69480f37eb6924a6c0cdfc1de2ca9e044841ce702cb6b6c3713840cb8c9e577'
   OR position('pdc.hermes_test_wrapper_vehicle_365' in v_route_def)=0
   OR position('pdc.hermes_test_estimate_wrapper_vehicle_369' in v_route_def)=0
   OR position('WHERE r.vehicle_id=v_vehicle_id' in v_route_def)=0
   OR position('r.actor_id=auth.uid()' in v_route_def)>0
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.pdc_hermes_test_actor_route_guard_365()'::regprocedure
        AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
        AND NOT has_function_privilege('public',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND NOT has_function_privilege('service_role',p.oid,'EXECUTE'))
   OR (SELECT array_agg(c.relname::text ORDER BY c.relname::text) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND t.tgname='pdc_hermes_test_actor_route_guard_365' AND t.tgfoid='public.pdc_hermes_test_actor_route_guard_365()'::regprocedure
       AND t.tgtype=31 AND t.tgenabled='O' AND t.tgqual IS NULL AND NOT t.tgisinternal)
    IS DISTINCT FROM ARRAY['audit_events','pdc_authenticated_email_operation_lines','pdc_overnight_synthetic_estimate_receipts_369','pdc_overnight_synthetic_estimates_369','pdc_sublet_booking_instance_history',
      'pdc_sublet_booking_instances','vehicle_movements','vehicle_parts_updates','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles',
      'workshop_booking_assignments','workshop_booking_history','workshop_bookings','workshop_parts_overrides']::text[] THEN RETURN false; END IF;
 RETURN true;
END $guard$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_dependency_guard_365() FROM public,anon,authenticated,service_role;


DO $post$
DECLARE v_route_tables text[];v_acl text[];v_sync_acl text[];
BEGIN
 IF encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex')<>'6cf33245713fe9481976f4fa47fe5f8a4b1cf8e47d5d8568eb4cb8a602e5ceee'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'d69480f37eb6924a6c0cdfc1de2ca9e044841ce702cb6b6c3713840cb8c9e577'
   OR NOT public.pdc_hermes_test_dependency_guard_365()
   OR NOT public.pdc_hermes_test_registry_guard_365()
   OR EXISTS(SELECT 1 FROM pdc_370_protected_minutes b JOIN public.vehicles v ON v.id=b.vehicle_id JOIN public.workshop_stages s ON s.id=b.stage_id
       WHERE public.workshop_vehicle_stage_estimated_duration_minutes(v.id,s.id) IS DISTINCT FROM b.minutes)
   OR public.workshop_vehicle_stage_estimated_duration_minutes(
       (SELECT vehicle_id FROM public.pdc_overnight_synthetic_fleet_registry_363 WHERE run_id='HERMES-TEST-RUN-20260824' AND scenario_no=5),
       (SELECT id FROM public.workshop_stages WHERE code='FITTING'))<>73
   OR public.workshop_vehicle_stage_estimated_duration_minutes(
       (SELECT vehicle_id FROM public.pdc_overnight_synthetic_fleet_registry_363 WHERE run_id='HERMES-TEST-RUN-20260824' AND scenario_no=6),
       (SELECT id FROM public.workshop_stages WHERE code='ELECTRICAL'))<>61
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.workshop_bookings'::regclass
      AND t.tgname='workshop_booking_045_estimated_duration_required_317' AND t.tgenabled='O' AND t.tgtype=23 AND t.tgqual IS NULL AND NOT t.tgisinternal
      AND t.tgfoid='public.workshop_require_positive_estimate_for_planned_booking_317()'::regprocedure
      AND encode(extensions.digest(convert_to(pg_get_triggerdef(t.oid,true),'UTF8'),'sha256'),'hex')='f8f85ab7cfd7e560a2d36aa57182d0547ec8bfd1b80091b790398a27525e9d63') THEN
  RAISE EXCEPTION 'PDC_370_FUNCTION_CONTAINMENT_OR_ESTABLISHED_BEHAVIOR_POSTCONDITION' USING errcode='55000';
 END IF;
 SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
 INTO v_acl FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee
 WHERE p.oid='public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure;
 SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
 INTO v_sync_acl FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee
 WHERE p.oid='public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure;
 SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO v_route_tables FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND t.tgname='pdc_hermes_test_actor_route_guard_365' AND t.tgfoid='public.pdc_hermes_test_actor_route_guard_365()'::regprocedure
   AND t.tgtype=31 AND t.tgenabled='O' AND t.tgqual IS NULL AND NOT t.tgisinternal;
 IF v_acl IS DISTINCT FROM ARRAY['postgres:EXECUTE']::text[]
   OR v_sync_acl IS DISTINCT FROM ARRAY['postgres:EXECUTE']::text[]
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure
       AND p.prosecdef AND p.provolatile='v' AND pg_get_userbyid(p.proowner)='postgres'
       AND p.proconfig=ARRAY['search_path=pg_catalog, public, extensions']::text[])
   OR v_route_tables IS DISTINCT FROM ARRAY['audit_events','pdc_authenticated_email_operation_lines','pdc_overnight_synthetic_estimate_receipts_369','pdc_overnight_synthetic_estimates_369','pdc_sublet_booking_instance_history','pdc_sublet_booking_instances','vehicle_movements','vehicle_parts_updates','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_booking_assignments','workshop_booking_history','workshop_bookings','workshop_parts_overrides']::text[]
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_370_ACL_ROUTE_OR_RUNTIME_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825070000','370_overnight_exact_synthetic_minutes',ARRAY[
 'Exact migration-369 staging head, ledger statements, installed definitions, ACLs and containment',
 'Exact positive rounded minutes below 60 only for registry-bound migration-369 synthetic estimates',
 'Byte-identical established 60-minute floor and null behavior for every protected/non-test vehicle',
 'Booking-duration reconciliation delegates to the canonical registry-aware minute function',
 'Rebound dependency guard, exact route inventory, migration-317 positive-estimate trigger and zero notifications'
]::text[]);
COMMIT;
