-- STAGING ONLY: align the retained U158318 Job Card descriptions with approved work keys.
-- The indicator/beacon mine-bar assembly is Electrical; standalone mine bars remain Fabrication.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260904010600-u158318-jobcard-classifier',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head text; v_classifier text;
BEGIN
 SELECT version INTO v_head FROM supabase_migrations.schema_migrations
 WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 v_classifier:=pg_get_functiondef('public.pdc_email_jobcard_work_key(text)'::regprocedure);
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260904010500'
    OR v_classifier NOT LIKE '%owner_supplied_document%'
    OR v_classifier NOT LIKE '%mine bar%'
    OR v_classifier NOT LIKE '%pit inspection%'
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260904010600')
 THEN RAISE EXCEPTION 'PDC_20260904010600_STAGING_CLASSIFIER_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- Unknown lines continue to fail closed to immutable mapping review. These seven
-- additions are deliberately narrow and preserve every retained source name.
CREATE OR REPLACE FUNCTION public.pdc_email_jobcard_work_key(p_description text)
RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog,public AS $classify$
DECLARE d text:=public.pdc_email_normalized_clause(p_description);
BEGIN
 d:=regexp_replace(d,'^op[ ]*[-:#/]?[ ]*[0-9]{1,5}[ ]*[-·|:—–]*[ ]*','','i');
 RETURN CASE
  WHEN d~'(^| )(sub|sublet)( |$)' OR d LIKE '%external provider%' OR d LIKE '%paint protection%' OR d~'^!sublet' THEN 'sublet'
  WHEN d~'wheel nut indicator|(^| )(tyres?|tires?|wheel alignment|wheel balance)( |$)|^!tyre' THEN 'tyre'
  WHEN d~'\mrock sliders?\M' THEN 'fitting'
  WHEN d!~'^!fab' AND d~'\mmine bar\M.*\mside facing indicators?\M.*\mswitched with beacon\M' THEN 'electrical'
  WHEN d~'\mbattery isolator\M.*\mred lockout\M|\m175 amp jump start\M.*\munder bonnet\M|\mheadlamps auto on\M.*\mhand brake off alarm\M' THEN 'electrical'
  WHEN d~'\mmounted wheel chocks?\M.*\mholder\M' THEN 'fitting'
  WHEN d~'\mpost rego conversion\M' THEN 'bus4x4'
  WHEN d~'fire extinguisher|(^| )(canopy|tray|fabricat|weld|service body|rops|mine bar|bull ?bar|jacking point)( |$)|^!fab' THEN 'fabrication'
  WHEN d~'(^| )(uhf|radio|electrical|wiring?|spot ?lights?|driving lights?|light bar|reverse beeper|reverse alarm|whip aerial|aerial|dual batter|brake controller|solis)( |$)|^!elec' THEN 'electrical'
  WHEN d~'(^| )(tint|tinting|window film)( |$)|^!tint' THEN 'tint'
  WHEN d~'(^| )(hoist|suspension|gvm|lift kit|weight upgrade)( |$)|^!hoist' THEN 'hoist'
  WHEN d~'(^| )(pit inspection|pit inspect|pit and weigh|roadworthy)( |$)|^!pit' THEN 'pitInspection'
  WHEN d~'(^| )(parts?|purchase order|p[.]?o[.]?|backorder|kit supplied)( |$)|^!parts' THEN 'PARTS'
  WHEN d~'(^| )(bus ?4x4|bus 4 x 4|department 138)( |$)|^!bus' THEN 'bus4x4'
  WHEN d~'(^| )(fit|fitting|install|pre delivery|pre-delivery|long range( fuel)? tank|tow ?bar|winch|snorkel|seat covers?|floor mats?|side steps?|nudge bar|first aid|safety triangle)( |$)|^!fit' THEN 'fitting'
  ELSE 'owner_supplied_document'
 END;
END $classify$;
REVOKE ALL ON FUNCTION public.pdc_email_jobcard_work_key(text) FROM public,anon,authenticated,service_role;

DO $post$
DECLARE outer_def text; inner_def text;
BEGIN
 outer_def:=pg_get_functiondef('public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)'::regprocedure);
 inner_def:=pg_get_functiondef('public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)'::regprocedure);
 IF public.pdc_email_jobcard_work_key('BUS 4X4 CONVERSION SLWB & COMMUTER 05C2B') IS DISTINCT FROM 'bus4x4'
    OR public.pdc_email_jobcard_work_key('Bus 4x4 Conversion 5x BFG 265/65R17 Tyres and Rims') IS DISTINCT FROM 'tyre'
    OR public.pdc_email_jobcard_work_key('BUS 4X4 Tanami Snorkel') IS DISTINCT FROM 'bus4x4'
    OR public.pdc_email_jobcard_work_key('Hiace Rock Sliders') IS DISTINCT FROM 'fitting'
    OR public.pdc_email_jobcard_work_key('MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON -ACOT500') IS DISTINCT FROM 'electrical'
    OR public.pdc_email_jobcard_work_key('BATTERY ISOLATOR WITH RED LOCKOUT') IS DISTINCT FROM 'electrical'
    OR public.pdc_email_jobcard_work_key('175 AMP JUMP START UNDER BONNET') IS DISTINCT FROM 'electrical'
    OR public.pdc_email_jobcard_work_key('Headlamps Auto On & Hand Brake OFF Alarm -DYNAMCO') IS DISTINCT FROM 'electrical'
    OR public.pdc_email_jobcard_work_key('MMT COMMUTER SEAT COVERS -CANVAS') IS DISTINCT FROM 'fitting'
    OR public.pdc_email_jobcard_work_key('MOUNTED WHEEL CHOCKS AND HOLDER') IS DISTINCT FROM 'fitting'
    OR public.pdc_email_jobcard_work_key('SAFETY TRIANGLE IN PMB HOLDER') IS DISTINCT FROM 'fitting'
    OR public.pdc_email_jobcard_work_key('WHEEL NUT INDICATORS -COMMUTER') IS DISTINCT FROM 'tyre'
    OR public.pdc_email_jobcard_work_key('UHF GME XRS370C WITH AE4704B AERIAL') IS DISTINCT FROM 'electrical'
    OR public.pdc_email_jobcard_work_key('SUB REFLECTIVE STRIPING YELLOW') IS DISTINCT FROM 'sublet'
    OR public.pdc_email_jobcard_work_key('Darkest Legal Tint Commuter van') IS DISTINCT FROM 'tint'
    OR public.pdc_email_jobcard_work_key('NARVA (72843) 20" EX2-R LIGHT BAR RGB DOUBLE RGB ENABLED') IS DISTINCT FROM 'electrical'
    OR public.pdc_email_jobcard_work_key('POST REGO CONVERSION') IS DISTINCT FROM 'bus4x4'
    OR public.pdc_email_jobcard_work_key('2.5KG FIRE EXTINGUISHER') IS DISTINCT FROM 'fabrication'
    OR public.pdc_email_jobcard_work_key('MINE BAR') IS DISTINCT FROM 'fabrication'
    OR public.pdc_email_jobcard_work_key('!FAB MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON') IS DISTINCT FROM 'fabrication'
    OR public.pdc_email_jobcard_work_key('Bedrock Sliders') IS DISTINCT FROM 'owner_supplied_document'
    OR public.pdc_email_jobcard_work_key('Unmapped bespoke instruction') IS DISTINCT FROM 'owner_supplied_document'
    OR public.pdc_email_safe_nonnegative_numeric_20260904('0.00'::jsonb,999.99) IS DISTINCT FROM 0.00
    OR public.pdc_email_safe_nonnegative_numeric_20260904('null'::jsonb,999.99) IS NOT NULL
    OR NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_non_navision_mapping_reviews_20260904'::regclass)
    OR has_table_privilege('authenticated','public.pdc_non_navision_mapping_reviews_20260904','select')
    OR has_function_privilege('authenticated','public.pdc_process_non_navision_jobcard_pre209(uuid,text,text,jsonb,text)','execute')
    OR has_function_privilege('anon','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute')
    OR has_function_privilege('service_role','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute')
    OR NOT has_function_privilege('authenticated','public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)','execute')
    OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='pdc_non_navision_operation_lines_immutable' AND tgenabled='O')
    OR (SELECT planner_enabled FROM public.workshop_stages WHERE code='PIT_INSPECTION') IS DISTINCT FROM false
    OR outer_def NOT LIKE '%pdc.recreation_source_hash%'
    OR outer_def NOT LIKE '%pdc_process_non_navision_jobcard_pre209%'
    OR inner_def NOT LIKE '%''active'',true,''YH'',null,''authenticated_email''%'
    OR inner_def NOT LIKE '%pdc_non_navision_mapping_reviews_20260904%'
    OR inner_def NOT LIKE '%booking_created'',false%'
    OR inner_def NOT LIKE '%completion_created'',false%'
 THEN RAISE EXCEPTION 'PDC_20260904010600_CLASSIFIER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260904010600','u158318_jobcard_classifier',ARRAY[
 'Classify all 18 retained U158318 source descriptions with approved work keys',
 'Keep the indicator/beacon mine-bar assembly Electrical while standalone mine bars remain Fabrication',
 'Preserve explicit zero, YH creation, unknown immutable Review, Sublet, PIT/QC, ACL and idempotency controls',
 'Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
