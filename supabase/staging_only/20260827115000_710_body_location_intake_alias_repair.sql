-- STAGING ONLY 710: repair the body-location intake alias collision.
--
-- This append-only successor follows the observed live head
-- 20260827114000 / 679_uid514_recovery_event_key_repair. It preserves 709,
-- 700-708, and all earlier migration history. Production is forbidden.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-710-body-location-intake-alias-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
DECLARE v_head text; v_body_hash text;
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
  THEN RAISE EXCEPTION 'PDC_710_STAGING_SENTINEL_OR_ROLE_FAILED' USING errcode='55000'; END IF;

  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF v_head<>'20260827114000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260827114000' AND name='679_uid514_recovery_event_key_repair')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version~'^[0-9]{14}$' AND version>'20260827114000')
  THEN RAISE EXCEPTION 'PDC_710_EXACT_LIVE_HEAD_REQUIRED' USING errcode='55000'; END IF;

  IF to_regprocedure('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regclass('public.pdc_navision_delivery_security_inventory_709') IS NULL
  THEN RAISE EXCEPTION 'PDC_710_REQUIRED_709_OBJECT_MISSING' USING errcode='55000'; END IF;

  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_body_hash;
  IF v_body_hash<>'cb03656f2c802370f6b0d7a4b047f95bd3b6ffd48360b8685a99e1213854441b'
  THEN RAISE EXCEPTION 'PDC_710_BODY_PREDECESSOR_HASH_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

DO $repair$
DECLARE
  v_def text;
  v_old text := $old$
  select * into i from public.ai_email_intake i where i.id=p_intake_id
    and i.status='processing'::public.ai_intake_status and i.locked_by=(s->>'user_id')::uuid
    and i.claim_token=p_claim_token and i.gateway_instance_id=btrim(p_gateway_instance_id)
    and i.locked_at>=clock_timestamp()-interval '10 minutes' and i.locked_at<=clock_timestamp()
    and i.received_at is not distinct from p_message_received_at for update;$old$;
  v_new text := $new$
  select intake_row.* into i from public.ai_email_intake intake_row where intake_row.id=p_intake_id
    and intake_row.status='processing'::public.ai_intake_status and intake_row.locked_by=(s->>'user_id')::uuid
    and intake_row.claim_token=p_claim_token and intake_row.gateway_instance_id=btrim(p_gateway_instance_id)
    and intake_row.locked_at>=clock_timestamp()-interval '10 minutes' and intake_row.locked_at<=clock_timestamp()
    and intake_row.received_at is not distinct from p_message_received_at for update;$new$;
BEGIN
  SELECT pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure) INTO v_def;
  IF length(v_def)-length(replace(v_def,v_old,''))<>length(v_old)
     OR position('select intake_row.* into i from public.ai_email_intake intake_row' in v_def)>0
     OR position('reconcile_navision_delivery_700(v_delivery_record_id)' in v_def)=0
  THEN RAISE EXCEPTION 'PDC_710_BODY_ALIAS_ANCHOR_MISMATCH' USING errcode='55000'; END IF;
  v_def:=replace(v_def,v_old,v_new);
  IF position('select * into i from public.ai_email_intake i where i.id=p_intake_id' in v_def)>0
     OR position('select intake_row.* into i from public.ai_email_intake intake_row where intake_row.id=p_intake_id' in v_def)=0
  THEN RAISE EXCEPTION 'PDC_710_BODY_ALIAS_REWRITE_FAILED' USING errcode='55000'; END IF;
  EXECUTE v_def;
END $repair$;

DO $post$
DECLARE d text; h text;
BEGIN
  SELECT pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure) INTO d;
  SELECT encode(extensions.digest(convert_to(d,'UTF8'),'sha256'),'hex') INTO h;
  IF position('select intake_row.* into i from public.ai_email_intake intake_row' in d)=0
     OR position('reconcile_navision_delivery_700(v_delivery_record_id)' in d)=0
     OR position('update public.vehicles set lifecycle_state=''completed''' in d)>0
     OR position('delivered_to_dealer_date=coalesce' in d)>0
     OR h='cb03656f2c802370f6b0d7a4b047f95bd3b6ffd48360b8685a99e1213854441b'
     OR has_function_privilege('anon','public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)','execute')
     OR has_function_privilege('service_role','public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)','execute')
  THEN RAISE EXCEPTION 'PDC_710_BODY_ALIAS_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827115000','710_body_location_intake_alias_repair',ARRAY[
  'Exact live-head guard: 20260827114000 / 679_uid514_recovery_event_key_repair; preserve applied 709 and 700-708 from source baseline f6219e5bbd833cce6889f44b9e4a04921b9bead9 and tree e450854f0f60ad6c8207590bfbfac51759de37f5',
  'Repair only the body-location PL/pgSQL intake-table alias collision by qualifying the table alias and selecting intake_row.* into the existing row variable',
  'Preserve the non-delivery ETA/Yard Hold/Body Builder branches and the 709 exact Delivered - At Dealer canonical route; no direct completion or location bypass is reintroduced',
  'Keep authenticated-only body execution, live auth/scope checks, canonical 700 timer/receipt/audit/replay behavior, and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
