-- STAGING ONLY 369: exact registry-bound estimates for HERMES scenarios 005-007.
-- Rollback review must bind pg_get_functiondef hashes from the exact installed staging
-- definitions before apply. This source intentionally does not claim unsourced live hashes.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-369-overnight-synthetic-estimates',0));

LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;
LOCK TABLE public.vehicle_workshop_line_adjustments IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.pdc_authenticated_email_operation_lines IN SHARE ROW EXCLUSIVE MODE;

DO $guard$
DECLARE v_hours_def text; v_minutes_def text; v_positive_def text;
DECLARE v_hours_sha text; v_minutes_sha text; v_positive_sha text; v_upsert_sha text; v_sync_sha text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825050000' AND name='368_overnight_registry_row_assignment')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825050000' AND version~'^[0-9]{14}$')
   OR (SELECT count(*) FROM public.pdc_overnight_synthetic_fleet_registry_363 WHERE run_id='HERMES-TEST-RUN-20260824')<>20
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR to_regprocedure('public.workshop_vehicle_stage_estimated_hours(uuid,text)') IS NULL
   OR to_regprocedure('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)') IS NULL
   OR to_regprocedure('public.workshop_require_positive_estimate_for_planned_booking_317()') IS NULL
   OR to_regprocedure('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)') IS NULL THEN
  RAISE EXCEPTION 'PDC_369_STAGING_TARGET_HEAD_CONTAINMENT_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
 END IF;
 v_hours_def:=pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure);
 v_minutes_def:=pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure);
 v_positive_def:=pg_get_functiondef('public.workshop_require_positive_estimate_for_planned_booking_317()'::regprocedure);
 v_hours_sha:=encode(extensions.digest(convert_to(v_hours_def,'UTF8'),'sha256'),'hex');
 v_minutes_sha:=encode(extensions.digest(convert_to(v_minutes_def,'UTF8'),'sha256'),'hex');
 v_positive_sha:=encode(extensions.digest(convert_to(v_positive_def,'UTF8'),'sha256'),'hex');
 v_upsert_sha:=encode(extensions.digest(convert_to(pg_get_functiondef('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'::regprocedure),'UTF8'),'sha256'),'hex');
 v_sync_sha:=encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex');
 IF v_hours_sha<>'546b542d63c4c3f3a27804e64bb20244bfa47ac747aaa6359612e3d9da29dae3'
   OR v_minutes_sha<>'c66f13a1859410449b2664236e1462e61bb3c09017962f7753865316bb58bd1b'
   OR v_positive_sha<>'9ee1da8e17e1ca3672c7b4cb8c129199db24457c4c4919f1ae3b02c4631d35e9'
   OR v_upsert_sha<>'03116b81f574bce427ebe84c356fdedeb8f8b0e0428db52841598c32bf08bb86'
   OR v_sync_sha<>'36bc98f16010d4cc99d3d2d83f56688d3fa7860de2491c0bc7ca085564c544bc'
   OR position('pdc_authenticated_email_operation_lines' in v_hours_def)=0
   OR position('vehicle_workshop_line_adjustments' in v_hours_def)=0
   OR position('estimated_hours>0' in replace(v_hours_def,' ',''))=0
   OR position('workshop_vehicle_stage_estimated_hours' in v_minutes_def)=0
   OR position('PDC_317_ESTIMATED_DURATION_REQUIRED' in v_positive_def)=0
   OR NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid='public.workshop_bookings'::regclass
      AND t.tgname='workshop_booking_045_estimated_duration_required_317' AND t.tgenabled='O' AND NOT t.tgisinternal
      AND t.tgfoid='public.workshop_require_positive_estimate_for_planned_booking_317()'::regprocedure)
   OR has_function_privilege('public','public.workshop_vehicle_stage_estimated_hours(uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.workshop_vehicle_stage_estimated_hours(uuid,text)','EXECUTE')
   OR has_function_privilege('authenticated','public.workshop_vehicle_stage_estimated_hours(uuid,text)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_369_EXACT_INSTALLED_ESTIMATE_DEFINITION_MISMATCH' USING errcode='55000';
 END IF;
END $guard$;

CREATE TABLE public.pdc_overnight_synthetic_estimates_369(
 estimate_id uuid PRIMARY KEY,
 run_id text NOT NULL CHECK(run_id='HERMES-TEST-RUN-20260824'),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 scenario_no integer NOT NULL CHECK(scenario_no BETWEEN 5 AND 7),
 stage_code text NOT NULL CHECK(stage_code IN('FITTING','ELECTRICAL')),
 estimated_hours numeric(4,2) NOT NULL CHECK(estimated_hours>0),
 estimated_minutes integer NOT NULL CHECK(estimated_minutes>0 AND estimated_minutes=round(estimated_hours*60)::integer),
 version bigint NOT NULL DEFAULT 1 CHECK(version=1),
 created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 created_by_email text NOT NULL CHECK(created_by_email=lower(btrim(created_by_email)) AND created_by_email<>''),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(run_id,vehicle_id,stage_code),
 UNIQUE(run_id,scenario_no,stage_code),
 CHECK((scenario_no=5 AND stage_code='FITTING' AND estimated_hours=1.22 AND estimated_minutes=73)
    OR (scenario_no=6 AND stage_code='ELECTRICAL' AND estimated_hours=1.02 AND estimated_minutes=61)
    OR (scenario_no=7 AND stage_code='FITTING' AND estimated_hours=0.78 AND estimated_minutes=47)
    OR (scenario_no=7 AND stage_code='ELECTRICAL' AND estimated_hours=0.98 AND estimated_minutes=59))
);
ALTER TABLE public.pdc_overnight_synthetic_estimates_369 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_overnight_synthetic_estimates_369 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_overnight_synthetic_estimate_receipts_369(
 receipt_id uuid PRIMARY KEY,
 run_id text NOT NULL CHECK(run_id='HERMES-TEST-RUN-20260824'),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_overnight_synthetic_estimate_receipts_369 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_overnight_synthetic_estimate_receipts_369 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_overnight_synthetic_estimate_append_only_369()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_369_APPEND_ONLY' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_overnight_synthetic_estimate_append_only_369() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_overnight_synthetic_estimates_append_only_369 BEFORE UPDATE OR DELETE ON public.pdc_overnight_synthetic_estimates_369
FOR EACH ROW EXECUTE FUNCTION public.pdc_overnight_synthetic_estimate_append_only_369();
CREATE TRIGGER pdc_overnight_synthetic_estimate_receipts_append_only_369 BEFORE UPDATE OR DELETE ON public.pdc_overnight_synthetic_estimate_receipts_369
FOR EACH ROW EXECUTE FUNCTION public.pdc_overnight_synthetic_estimate_append_only_369();

-- Target-based closure: every write whose target belongs to the registry must carry
-- the exact transaction-local 365 or 369 wrapper marker, regardless of caller identity.
CREATE OR REPLACE FUNCTION public.pdc_hermes_test_actor_route_guard_365()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $route$
DECLARE v_row jsonb:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END; v_vehicle_id uuid;
DECLARE v_allowed_365 text:=current_setting('pdc.hermes_test_wrapper_vehicle_365',true);
DECLARE v_allowed_369 text:=current_setting('pdc.hermes_test_estimate_wrapper_vehicle_369',true);
BEGIN
 IF TG_TABLE_NAME='vehicles' THEN v_vehicle_id:=nullif(v_row->>'id','')::uuid;
 ELSIF TG_TABLE_NAME IN('workshop_booking_assignments','workshop_booking_history') THEN
  SELECT b.vehicle_id INTO v_vehicle_id FROM public.workshop_bookings b WHERE b.id=nullif(v_row->>'booking_id','')::uuid;
 ELSE v_vehicle_id:=nullif(v_row->>'vehicle_id','')::uuid;
 END IF;
 IF v_vehicle_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v_vehicle_id)
   AND coalesce(v_allowed_365,'')<>v_vehicle_id::text AND coalesce(v_allowed_369,'')<>v_vehicle_id::text THEN
  RAISE EXCEPTION 'PDC_365_OVERNIGHT_TARGET_MUST_USE_EXACT_SYNTHETIC_WRAPPER' USING errcode='42501';
 END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $route$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_actor_route_guard_365() FROM public,anon,authenticated,service_role;

DO $routes$
DECLARE v_table text;
BEGIN
 FOREACH v_table IN ARRAY ARRAY['vehicles','vehicle_work_items','workshop_bookings','workshop_booking_assignments',
  'workshop_booking_history','workshop_parts_overrides','vehicle_parts_updates','pdc_sublet_booking_instances',
  'pdc_sublet_booking_instance_history','vehicle_movements','audit_events','vehicle_workshop_line_adjustments',
  'pdc_authenticated_email_operation_lines','pdc_overnight_synthetic_estimates_369',
  'pdc_overnight_synthetic_estimate_receipts_369'] LOOP
  EXECUTE format('DROP TRIGGER IF EXISTS pdc_hermes_test_actor_route_guard_365 ON public.%I',v_table);
  EXECUTE format('CREATE TRIGGER pdc_hermes_test_actor_route_guard_365 BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.pdc_hermes_test_actor_route_guard_365()',v_table);
 END LOOP;
END $routes$;

-- Preserve migration 365's exact core-function hash bindings while rebinding only
-- the intentionally replaced target route function and its expanded exact trigger set.
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
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex')<>'c66f13a1859410449b2664236e1462e61bb3c09017962f7753865316bb58bd1b'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_require_positive_estimate_for_planned_booking_317()'::regprocedure),'UTF8'),'sha256'),'hex')<>'9ee1da8e17e1ca3672c7b4cb8c129199db24457c4c4919f1ae3b02c4631d35e9'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'::regprocedure),'UTF8'),'sha256'),'hex')<>'03116b81f574bce427ebe84c356fdedeb8f8b0e0428db52841598c32bf08bb86'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex')<>'36bc98f16010d4cc99d3d2d83f56688d3fa7860de2491c0bc7ca085564c544bc'
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

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_protected_digest_365()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $digest$
 WITH protected AS MATERIALIZED(SELECT v.id FROM public.vehicles v WHERE NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=v.id)), material AS(
  SELECT 'vehicles' relation,to_jsonb(v) row_data FROM public.vehicles v JOIN protected p ON p.id=v.id
  UNION ALL SELECT 'vehicle_work_items',to_jsonb(x) FROM public.vehicle_work_items x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'workshop_bookings',to_jsonb(x) FROM public.workshop_bookings x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'workshop_booking_assignments',to_jsonb(a) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id JOIN protected p ON p.id=b.vehicle_id
  UNION ALL SELECT 'workshop_booking_history',to_jsonb(h) FROM public.workshop_booking_history h JOIN public.workshop_bookings b ON b.id=h.booking_id JOIN protected p ON p.id=b.vehicle_id
  UNION ALL SELECT 'workshop_parts_overrides',to_jsonb(x) FROM public.workshop_parts_overrides x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'vehicle_parts_updates',to_jsonb(x) FROM public.vehicle_parts_updates x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_sublet_booking_instances',to_jsonb(x) FROM public.pdc_sublet_booking_instances x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_sublet_booking_instance_history',to_jsonb(x) FROM public.pdc_sublet_booking_instance_history x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'vehicle_movements',to_jsonb(x) FROM public.vehicle_movements x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'audit_events',to_jsonb(x) FROM public.audit_events x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'vehicle_workshop_line_adjustments',to_jsonb(x) FROM public.vehicle_workshop_line_adjustments x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_authenticated_email_operation_lines',to_jsonb(x) FROM public.pdc_authenticated_email_operation_lines x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_overnight_synthetic_estimates_369',to_jsonb(x) FROM public.pdc_overnight_synthetic_estimates_369 x JOIN protected p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_overnight_synthetic_estimate_receipts_369',to_jsonb(x) FROM public.pdc_overnight_synthetic_estimate_receipts_369 x JOIN protected p ON p.id=x.vehicle_id
 ) SELECT jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object('relation',relation,'row',row_data) ORDER BY relation,row_data::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM material
$digest$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_protected_digest_365() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_hermes_test_sibling_digest_365(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $digest$
 WITH siblings AS MATERIALIZED(SELECT r.vehicle_id id FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id<>p_vehicle_id), material AS(
  SELECT 'vehicles' relation,to_jsonb(v) row_data FROM public.vehicles v JOIN siblings p ON p.id=v.id
  UNION ALL SELECT 'vehicle_work_items',to_jsonb(x) FROM public.vehicle_work_items x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'workshop_bookings',to_jsonb(x) FROM public.workshop_bookings x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'workshop_booking_assignments',to_jsonb(a) FROM public.workshop_booking_assignments a JOIN public.workshop_bookings b ON b.id=a.booking_id JOIN siblings p ON p.id=b.vehicle_id
  UNION ALL SELECT 'workshop_booking_history',to_jsonb(h) FROM public.workshop_booking_history h JOIN public.workshop_bookings b ON b.id=h.booking_id JOIN siblings p ON p.id=b.vehicle_id
  UNION ALL SELECT 'workshop_parts_overrides',to_jsonb(x) FROM public.workshop_parts_overrides x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'vehicle_parts_updates',to_jsonb(x) FROM public.vehicle_parts_updates x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_sublet_booking_instances',to_jsonb(x) FROM public.pdc_sublet_booking_instances x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_sublet_booking_instance_history',to_jsonb(x) FROM public.pdc_sublet_booking_instance_history x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'vehicle_movements',to_jsonb(x) FROM public.vehicle_movements x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'audit_events',to_jsonb(x) FROM public.audit_events x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'vehicle_workshop_line_adjustments',to_jsonb(x) FROM public.vehicle_workshop_line_adjustments x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_authenticated_email_operation_lines',to_jsonb(x) FROM public.pdc_authenticated_email_operation_lines x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_overnight_synthetic_estimates_369',to_jsonb(x) FROM public.pdc_overnight_synthetic_estimates_369 x JOIN siblings p ON p.id=x.vehicle_id
  UNION ALL SELECT 'pdc_overnight_synthetic_estimate_receipts_369',to_jsonb(x) FROM public.pdc_overnight_synthetic_estimate_receipts_369 x JOIN siblings p ON p.id=x.vehicle_id
 ) SELECT jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object('relation',relation,'row',row_data) ORDER BY relation,row_data::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) FROM material
$digest$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_sibling_digest_365(uuid) FROM public,anon,authenticated,service_role;

-- Preserve established estimates and add only the four exact synthetic catalog rows.
CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid,p_stage_code text)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $hours$
 WITH source_lines AS(
  SELECT coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)) stage_code,
         coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours
  FROM public.pdc_authenticated_email_operation_lines ol
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=ol.vehicle_id
   AND a.line_key='source:'||ol.operation_line_id::text AND a.active
  WHERE ol.vehicle_id=p_vehicle_id
 ), manual_lines AS(
  SELECT a.stage_code,a.estimated_hours FROM public.vehicle_workshop_line_adjustments a
  WHERE a.vehicle_id=p_vehicle_id AND a.active AND a.source_kind='manual'
 ), synthetic_lines AS(
  SELECT e.stage_code,e.estimated_hours FROM public.pdc_overnight_synthetic_estimates_369 e
  JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.run_id=e.run_id AND r.vehicle_id=e.vehicle_id AND r.scenario_no=e.scenario_no
  WHERE e.vehicle_id=p_vehicle_id AND e.run_id='HERMES-TEST-RUN-20260824'
 )
 SELECT nullif(round(sum(q.estimated_hours)::numeric,2),0)
 FROM (SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines UNION ALL SELECT * FROM synthetic_lines) q
 WHERE q.stage_code=public.workshop_canonical_stage_code(p_stage_code) AND q.estimated_hours>0
$hours$;
-- CREATE OR REPLACE preserves the installed owner and ACL; do not invent or alter a
-- service_role grant without exact live evidence. Public/anon/authenticated denial was
-- proven in the precondition and is re-proven below.

CREATE FUNCTION public.pdc_hermes_test_set_estimate_369(
 p_run_id text,p_vehicle_id uuid,p_expected_vehicle_version integer,p_expected_estimate_version bigint,
 p_idempotency_key uuid,p_stage_code text,p_estimated_hours numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $apply$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_registry public.pdc_overnight_synthetic_fleet_registry_363%rowtype; v_vehicle public.vehicles%rowtype;
 v_existing public.pdc_overnight_synthetic_estimates_369%rowtype; v_receipt public.pdc_overnight_synthetic_estimate_receipts_369%rowtype;
 v_stage text:=upper(btrim(coalesce(p_stage_code,''))); v_minutes integer; v_request jsonb; v_sha text; v_id uuid; v_response jsonb; v_replay boolean:=false;
 v_protected_before jsonb; v_protected_after jsonb; v_sibling_before jsonb; v_sibling_after jsonb; v_notifications_before bigint;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
   OR p_expected_estimate_version IS NULL OR p_expected_estimate_version<0 OR p_idempotency_key IS NULL OR p_estimated_hours IS NULL THEN
  RAISE EXCEPTION 'PDC_369_INVALID_INPUT' USING errcode='22023'; END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role='administrator' AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_369_ADMINISTRATOR_REQUIRED' USING errcode='42501'; END IF;
 v_request:=jsonb_build_object('contract','pdc-overnight-synthetic-estimate-369','run_id',p_run_id,'vehicle_id',p_vehicle_id,
   'expected_vehicle_version',p_expected_vehicle_version,'expected_estimate_version',p_expected_estimate_version,
   'idempotency_key',p_idempotency_key,'stage_code',v_stage,'estimated_hours',p_estimated_hours);
 v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-369-receipt:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_overnight_synthetic_estimate_receipts_369 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_sha OR v_receipt.actor_email<>v_email THEN RAISE EXCEPTION 'PDC_369_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH' USING errcode='22023'; END IF;
  v_replay:=true;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-369-vehicle:'||p_vehicle_id::text,0));
 LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_work_items IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.workshop_bookings IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.workshop_booking_assignments IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.workshop_booking_history IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.workshop_parts_overrides IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_parts_updates IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.pdc_sublet_booking_instances IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.pdc_sublet_booking_instance_history IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_movements IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.audit_events IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_workshop_line_adjustments IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.pdc_authenticated_email_operation_lines IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.pdc_overnight_synthetic_estimates_369 IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.pdc_overnight_synthetic_estimate_receipts_369 IN SHARE ROW EXCLUSIVE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_hermes_test_dependency_guard_365()
   OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_369_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 SELECT * INTO v_registry FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id FOR SHARE;
 IF NOT FOUND OR v_registry.scenario_no NOT BETWEEN 5 AND 7 THEN RAISE EXCEPTION 'PDC_369_REGISTRY_OR_SCENARIO_MISMATCH' USING errcode='42501'; END IF;
 SELECT * INTO v_vehicle FROM public.vehicles v WHERE v.id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v_vehicle.version<>p_expected_vehicle_version OR v_vehicle.stock_number<>v_registry.stock_number
   OR v_vehicle.source_system<>'hermes_overnight_synthetic' OR v_vehicle.source_batch_id<>p_run_id OR v_vehicle.source_record_id<>v_registry.stock_number THEN
  RAISE EXCEPTION 'PDC_369_VEHICLE_IDENTITY_OR_VERSION_MISMATCH' USING errcode='40001'; END IF;
 v_minutes:=round(p_estimated_hours*60)::integer;
 IF NOT ((v_registry.scenario_no=5 AND v_stage='FITTING' AND p_estimated_hours=1.22 AND v_minutes=73)
   OR (v_registry.scenario_no=6 AND v_stage='ELECTRICAL' AND p_estimated_hours=1.02 AND v_minutes=61)
   OR (v_registry.scenario_no=7 AND v_stage='FITTING' AND p_estimated_hours=0.78 AND v_minutes=47)
   OR (v_registry.scenario_no=7 AND v_stage='ELECTRICAL' AND p_estimated_hours=0.98 AND v_minutes=59)) THEN
  RAISE EXCEPTION 'PDC_369_EXACT_CATALOG_STAGE_HOURS_MISMATCH' USING errcode='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed
   AND public.workshop_stage_code_for_work_key(wi.work_key)=v_stage) THEN
  RAISE EXCEPTION 'PDC_369_REQUIRED_INCOMPLETE_STAGE_MISSING' USING errcode='55000'; END IF;
 PERFORM set_config('pdc.hermes_test_estimate_wrapper_vehicle_369',p_vehicle_id::text,true);
 PERFORM 1 FROM public.vehicles v ORDER BY v.id FOR SHARE;
 v_protected_before:=public.pdc_hermes_test_protected_digest_365(); v_sibling_before:=public.pdc_hermes_test_sibling_digest_365(p_vehicle_id);
 v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT * INTO v_existing FROM public.pdc_overnight_synthetic_estimates_369 e WHERE e.run_id=p_run_id AND e.vehicle_id=p_vehicle_id AND e.stage_code=v_stage FOR UPDATE;
 IF v_replay THEN
  IF NOT FOUND OR v_existing.scenario_no<>v_registry.scenario_no OR v_existing.estimated_hours<>p_estimated_hours OR v_existing.estimated_minutes<>v_minutes
    OR public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,v_stage)<>p_estimated_hours
    OR public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,(SELECT id FROM public.workshop_stages WHERE code=v_stage))<>v_minutes
    OR v_notifications_before<>0 THEN
   RAISE EXCEPTION 'PDC_369_REPLAY_READBACK_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)||jsonb_build_object('replay_current_state_readback',true,
   'current_protected_state',v_protected_before,'current_sibling_state',v_sibling_before,'current_vehicle_version',v_vehicle.version,
   'current_estimate_version',v_existing.version,'current_notification_count',v_notifications_before);
 END IF;
 IF FOUND THEN
  IF p_expected_estimate_version<>v_existing.version OR v_existing.scenario_no<>v_registry.scenario_no OR v_existing.estimated_hours<>p_estimated_hours OR v_existing.estimated_minutes<>v_minutes THEN
   RAISE EXCEPTION 'PDC_369_ESTIMATE_VERSION_OR_IMMUTABLE_VALUE_MISMATCH' USING errcode='40001'; END IF;
 ELSE
  IF p_expected_estimate_version<>0 THEN RAISE EXCEPTION 'PDC_369_ESTIMATE_VERSION_MISMATCH' USING errcode='40001'; END IF;
  v_id:=extensions.uuid_generate_v5('36900000-0000-5000-8000-000000000369'::uuid,p_run_id||':'||v_registry.scenario_no::text||':'||v_stage);
  INSERT INTO public.pdc_overnight_synthetic_estimates_369(estimate_id,run_id,vehicle_id,scenario_no,stage_code,estimated_hours,estimated_minutes,created_by,created_by_email)
  VALUES(v_id,p_run_id,p_vehicle_id,v_registry.scenario_no,v_stage,p_estimated_hours,v_minutes,v_actor,v_email) RETURNING * INTO v_existing;
 END IF;
 v_protected_after:=public.pdc_hermes_test_protected_digest_365(); v_sibling_after:=public.pdc_hermes_test_sibling_digest_365(p_vehicle_id);
 IF v_protected_after IS DISTINCT FROM v_protected_before OR v_sibling_after IS DISTINCT FROM v_sibling_before
   OR v_notifications_before<>0 OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,v_stage)<>p_estimated_hours
   OR public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,(SELECT id FROM public.workshop_stages WHERE code=v_stage))<>v_minutes THEN
  RAISE EXCEPTION 'PDC_369_DIGEST_NOTIFICATION_OR_READBACK_POSTCONDITION' USING errcode='55000'; END IF;
 v_id:=extensions.uuid_generate_v5('36900000-0000-5000-8000-000000000369'::uuid,p_run_id||':'||v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','synthetic_estimate_bound','synthetic_wrapper',true,'replay',false,'receipt_id',v_id,
  'request_sha256',v_sha,'run_id',p_run_id,'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle.version,'estimate_id',v_existing.estimate_id,
  'estimate_version',v_existing.version,'scenario_no',v_registry.scenario_no,'stage_code',v_stage,'estimated_hours',p_estimated_hours,
  'estimated_minutes',v_minutes,'protected_state',v_protected_after,'sibling_state',v_sibling_after,'notification_delta',0);
 INSERT INTO public.pdc_overnight_synthetic_estimate_receipts_369(receipt_id,run_id,vehicle_id,actor_id,actor_email,idempotency_key,request_sha256,request_payload,response)
 VALUES(v_id,p_run_id,p_vehicle_id,v_actor,v_email,p_idempotency_key,v_sha,v_request,v_response);
 RETURN v_response;
END $apply$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_set_estimate_369(text,uuid,integer,bigint,uuid,text,numeric) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_set_estimate_369(text,uuid,integer,bigint,uuid,text,numeric) TO authenticated;

CREATE FUNCTION public.read_pdc_hermes_test_estimates_369(p_run_id text,p_vehicle_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_result jsonb;
BEGIN
 IF p_run_id IS DISTINCT FROM 'HERMES-TEST-RUN-20260824' OR v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r
  WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved') THEN
  RAISE EXCEPTION 'PDC_369_READ_UNAUTHORIZED_OR_RUN_INVALID' USING errcode='42501'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
  OR NOT public.pdc_hermes_test_dependency_guard_365()
  OR NOT public.pdc_hermes_test_registry_guard_365()
  OR (SELECT count(*) FROM public.vehicle_notifications)<>0
  OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active) OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
  OR (p_vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id=p_run_id AND r.vehicle_id=p_vehicle_id)) THEN
  RAISE EXCEPTION 'PDC_369_READ_CONTAINMENT_OR_SCOPE_DRIFT' USING errcode='55000'; END IF;
 SELECT jsonb_build_object('ok',true,'run_id',p_run_id,'vehicle_id',p_vehicle_id,
  'estimates',coalesce(jsonb_agg(jsonb_build_object('estimate',to_jsonb(e),'canonical_hours',public.workshop_vehicle_stage_estimated_hours(e.vehicle_id,e.stage_code),
   'canonical_minutes',public.workshop_vehicle_stage_estimated_duration_minutes(e.vehicle_id,s.id),
   'receipts',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.receipt_id) FROM public.pdc_overnight_synthetic_estimate_receipts_369 x WHERE x.vehicle_id=e.vehicle_id),'[]'::jsonb))
   ORDER BY e.scenario_no,e.stage_code),'[]'::jsonb),'protected_state',public.pdc_hermes_test_protected_digest_365(),
  'notification_count',(SELECT count(*) FROM public.vehicle_notifications)) INTO v_result
 FROM public.pdc_overnight_synthetic_estimates_369 e JOIN public.workshop_stages s ON s.code=e.stage_code
 WHERE e.run_id=p_run_id AND (p_vehicle_id IS NULL OR e.vehicle_id=p_vehicle_id);
 RETURN v_result;
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_hermes_test_estimates_369(text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_hermes_test_estimates_369(text,uuid) TO authenticated;

DO $post$
DECLARE v_route_tables text[];
BEGIN
 SELECT array_agg(c.relname::text ORDER BY c.relname::text) INTO v_route_tables FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND t.tgname='pdc_hermes_test_actor_route_guard_365' AND t.tgfoid='public.pdc_hermes_test_actor_route_guard_365()'::regprocedure
  AND t.tgtype=31 AND t.tgenabled='O' AND t.tgqual IS NULL AND NOT t.tgisinternal;
 IF v_route_tables IS DISTINCT FROM ARRAY['audit_events','pdc_authenticated_email_operation_lines','pdc_overnight_synthetic_estimate_receipts_369','pdc_overnight_synthetic_estimates_369','pdc_sublet_booking_instance_history',
  'pdc_sublet_booking_instances','vehicle_movements','vehicle_parts_updates','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles',
  'workshop_booking_assignments','workshop_booking_history','workshop_bookings','workshop_parts_overrides']::text[]
  OR has_function_privilege('public','public.pdc_hermes_test_set_estimate_369(text,uuid,integer,bigint,uuid,text,numeric)','EXECUTE')
  OR has_function_privilege('anon','public.pdc_hermes_test_set_estimate_369(text,uuid,integer,bigint,uuid,text,numeric)','EXECUTE')
  OR has_table_privilege('authenticated','public.pdc_overnight_synthetic_estimates_369','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege('service_role','public.pdc_overnight_synthetic_estimates_369','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege('authenticated','public.pdc_overnight_synthetic_estimate_receipts_369','SELECT,INSERT,UPDATE,DELETE')
  OR has_table_privilege('service_role','public.pdc_overnight_synthetic_estimate_receipts_369','SELECT,INSERT,UPDATE,DELETE')
  OR NOT has_function_privilege('authenticated','public.pdc_hermes_test_set_estimate_369(text,uuid,integer,bigint,uuid,text,numeric)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.read_pdc_hermes_test_estimates_369(text,uuid)','EXECUTE')
  OR has_function_privilege('public','public.workshop_vehicle_stage_estimated_hours(uuid,text)','EXECUTE')
  OR has_function_privilege('anon','public.workshop_vehicle_stage_estimated_hours(uuid,text)','EXECUTE')
  OR has_function_privilege('authenticated','public.workshop_vehicle_stage_estimated_hours(uuid,text)','EXECUTE')
  OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure
       AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres')
  OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='public' AND c.relname IN('pdc_overnight_synthetic_estimates_369','pdc_overnight_synthetic_estimate_receipts_369')
         AND pg_get_userbyid(c.relowner)<>'postgres')
  OR (SELECT count(*) FROM pg_proc p WHERE p.oid IN(
       'public.pdc_overnight_synthetic_estimate_append_only_369()'::regprocedure,
       'public.pdc_hermes_test_set_estimate_369(text,uuid,integer,bigint,uuid,text,numeric)'::regprocedure,
       'public.read_pdc_hermes_test_estimates_369(text,uuid)'::regprocedure)
       AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres')<>3
  OR position('PDC_317_ESTIMATED_DURATION_REQUIRED' in pg_get_functiondef('public.workshop_require_positive_estimate_for_planned_booking_317()'::regprocedure))=0 THEN
  RAISE EXCEPTION 'PDC_369_ROUTE_ACL_OR_POSITIVE_ESTIMATE_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260825060000','369_overnight_synthetic_estimates',array[
 'Exact migration-368 staging head and structural installed-definition dependency checks; rollback review must bind exact installed hashes',
 'Target-based registry route guard including both established estimate relations and the synthetic estimate relation',
 'Exact scenario 005-007 positive estimates: 1.22h/73m Fitting, 1.02h/61m Electrical, 0.78h/47m Fitting, 0.98h/59m Electrical',
 'Administrator-only transaction-local wrapper, optimistic versions, immutable idempotency receipts and authoritative readback',
 'Protected/sibling estimate-relation digests, relation race locks and zero external notifications'
]);
COMMIT;
