-- STAGING ONLY 360: align canonical Job Card classification with Craig's
-- durable owner routing rules before generic tray/canopy/fit terms.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-360-owner-work-key-precedence',0));
DO $guard$
DECLARE h text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824200000' AND name='359_defer_past_planned_booking_duration_sync')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824200000' AND version~'^[0-9]{14}$')
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_360_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH';
 END IF;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_jobcard_work_key(text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO h;
 IF h<>'33791874c6f3badc1c6426dd5fbde15fc4dc3094a2383e416ecad176a15fd5c7' THEN RAISE EXCEPTION 'PDC_360_PREDECESSOR_FUNCTION_DRIFT %',h;END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_email_jobcard_work_key(p_description text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog,public AS $classify$
DECLARE d text:=public.pdc_email_normalized_clause(p_description);
BEGIN
 RETURN CASE
  WHEN d~'(^| )tow ?bars?( |$)' THEN 'fitting'
  WHEN d~'(^| )(long range(r)?( fuel)? tanks?|arb frontier.{0,80}(fuel )?tanks?|sub tank replacem[a-z]*)( |$)' THEN 'hoist'
  WHEN d~'(^| )fire ext(inguisher|inuisher|inguishers|inuishers)?( |$)' THEN 'fitting'
  WHEN d~'(^| )12v.{0,60}(acc(essory)? socket|plugs?)( |$)' OR d~'(^| )(acc(essory)? socket|plugs?).{0,60}12v( |$)' THEN 'electrical'
  WHEN d~'(^| )((arb )?battery box|bcdc[0-9]*|xrs ?370c|navman|cardex)( |$)' THEN 'electrical'
  WHEN d~'(^| )(uhf|radio|electrical|spot ?lights?|light bar)( |$)' THEN 'electrical'
  WHEN d~'(^| )(tyres?|tires?)( |$)' THEN 'tyre'
  WHEN d~'(^| )(canopy|tray|fabricat)' THEN 'fabrication'
  WHEN d~'(^| )(tint)( |$)' THEN 'tint'
  WHEN d~'(^| )(hoist)( |$)' THEN 'hoist'
  WHEN d~'(^| )(pit inspection|pit inspect)( |$)' THEN 'pitInspection'
  WHEN d~'(^| )(parts?)( |$)' THEN 'PARTS'
  WHEN d~'(^| )(bus ?4x4)( |$)' THEN 'bus4x4'
  WHEN d~'(^| )(fit|install)( |$)' THEN 'fitting'
  ELSE NULL END;
END $classify$;
REVOKE ALL ON FUNCTION public.pdc_email_jobcard_work_key(text) FROM public,anon,authenticated,service_role;

DO $post$
DECLARE cases jsonb:=jsonb_build_array(
 jsonb_build_object('d','Tow Bar [For 2550mm/2100mm/1800mm Tray Body] with Smart Pin','w','fitting'),
 jsonb_build_object('d','Tow Bar Tongue Kit (Long) with Flat Plug','w','fitting'),
 jsonb_build_object('d','ARB FRONTIER LONG RANGE FUEL TANK - SUB TANK REPLACEM','w','hoist'),
 jsonb_build_object('d','1.5 KG FIRE EXT TO CARGO BARRIER or L/H Tray Head Boa','w','fitting'),
 jsonb_build_object('d','SUPPLY AND FIT DUAL 12V ACC SOCKET IN MODULE','w','electrical'),
 jsonb_build_object('d','Supply and Fit 12v PLUG To Rear','w','electrical'),
 jsonb_build_object('d','ARB Battery Box Mounted in Tray - BCDC1225D - 100Ah','w','electrical'),
 jsonb_build_object('d','FIT XRS 370c -Select Aerial additional Job Line','w','electrical'),
 jsonb_build_object('d','Fit Navman IVMS with Cardex Interface system','w','electrical'));
 c jsonb;
BEGIN
 FOR c IN SELECT value FROM jsonb_array_elements(cases) LOOP
  IF public.pdc_email_jobcard_work_key(c->>'d') IS DISTINCT FROM c->>'w' THEN RAISE EXCEPTION 'PDC_360_CLASSIFIER_POSTCONDITION_FAILED %',c->>'d';END IF;
 END LOOP;
 IF has_function_privilege('authenticated','public.pdc_email_jobcard_work_key(text)','EXECUTE') THEN RAISE EXCEPTION 'PDC_360_FUNCTION_ACL_FAILED';END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260824210000','360_craig_owner_jobcard_work_key_precedence',array[
 'Require exact staging sentinel, migration 359 head, stopped ingestion and exact predecessor function hash',
 'Apply Craig owner routing rules before generic tray, canopy and fit classification',
 'Cover Towbars, long-range tanks, fire extinguisher variants, 12V sockets/plugs, battery box/BCDC, XRS 370c and Navman/Cardex',
 'Verify nine representative descriptions transactionally and retain private helper ACL',
 'Grant no generic DML, Monitor, mailbox, writer or Production authority'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
