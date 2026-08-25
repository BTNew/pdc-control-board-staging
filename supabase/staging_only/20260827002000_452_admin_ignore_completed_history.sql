-- STAGING ONLY 452: completed Workshop history must not block new Admin downtime.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-452-admin-completed-history',0));

DO $pre$
DECLARE v_head text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR v_head IS DISTINCT FROM '20260827001000'
   OR to_regprocedure('public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb)') IS NULL
   OR to_regprocedure('public.workshop_admin_nearest_available_slot(uuid,timestamptz,integer)') IS NULL
   OR to_regprocedure('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)') IS NULL
   OR to_regprocedure('public.workshop_enforce_admin_block_fixed_booking_conflict()') IS NULL THEN
  RAISE EXCEPTION 'PDC_452_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $patch$
DECLARE
 ident regprocedure;
 original text;
 patched text;
 changed integer:=0;
BEGIN
 FOREACH ident IN ARRAY ARRAY[
   'public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb)'::regprocedure,
   'public.workshop_admin_nearest_available_slot(uuid,timestamptz,integer)'::regprocedure,
   'public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure,
   'public.workshop_enforce_admin_block_fixed_booking_conflict()'::regprocedure
 ] LOOP
   original:=pg_get_functiondef(ident);
   patched:=replace(original,'''queued'',''started'',''stoppage'',''completed''','''queued'',''started'',''stoppage''');
   IF patched=original THEN
     RAISE EXCEPTION 'PDC_452_PATCH_ANCHOR_MISSING: %',ident::text USING errcode='55000';
   END IF;
   IF patched ~* 'status[^\n]{0,80}completed' THEN
     RAISE EXCEPTION 'PDC_452_COMPLETED_BLOCKER_REMAINS: %',ident::text USING errcode='55000';
   END IF;
   EXECUTE patched;
   changed:=changed+1;
 END LOOP;
 IF changed<>4 THEN RAISE EXCEPTION 'PDC_452_PATCH_COUNT_MISMATCH' USING errcode='55000'; END IF;
END $patch$;

DO $post$
DECLARE ident regprocedure; d text;
BEGIN
 FOREACH ident IN ARRAY ARRAY[
   'public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb)'::regprocedure,
   'public.workshop_admin_nearest_available_slot(uuid,timestamptz,integer)'::regprocedure,
   'public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure,
   'public.workshop_enforce_admin_block_fixed_booking_conflict()'::regprocedure
 ] LOOP
   d:=pg_get_functiondef(ident);
   IF d ~* 'status[^\n]{0,80}completed' OR d !~* '''queued''\s*,\s*''started''\s*,\s*''stoppage''' THEN
     RAISE EXCEPTION 'PDC_452_POSTCONDITION_FAILED: %',ident::text USING errcode='55000';
   END IF;
 END LOOP;
 IF has_function_privilege('public','public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb)','EXECUTE')
   OR has_function_privilege('anon','public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_452_ADMIN_ACL_POSTCONDITION_FAILED' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827002000','452_admin_ignore_completed_history',ARRAY[
 'Completed Workshop bookings remain immutable history but no longer block Admin downtime creation, nearest-slot search or planned-row repacking',
 'Queued, started and stoppage bookings remain fixed blockers and preserve fail-closed physical-work truth',
 'Admin block ACLs, exact revision checks, atomic planned cascades, history and audit receipts remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
