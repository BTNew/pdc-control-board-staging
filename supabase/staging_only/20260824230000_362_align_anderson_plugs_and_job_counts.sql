-- STAGING ONLY 362: align Anderson plugs and Board job summaries.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-362-anderson-electrical',0));
DO $guard$
DECLARE h text;n integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
  OR (SELECT count(*)FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel')IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824220000'AND name='361_persist_manual_estimated_hours_authority')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824220000'AND version~'^[0-9]{14}$')
  OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
  OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)THEN
  RAISE EXCEPTION 'PDC_362_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH';END IF;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_jobcard_work_key(text)'::regprocedure),'UTF8'),'sha256'),'hex')INTO h;
 IF h<>'299721a575227fe7d1a2da5b704e662d565a4c180abaafa33a50eca9be98fc73'THEN RAISE EXCEPTION 'PDC_362_CLASSIFIER_PREDECESSOR_DRIFT %',h;END IF;
 SELECT count(*)INTO n FROM public.pdc_authenticated_email_operation_lines l JOIN public.vehicles v ON v.id=l.vehicle_id WHERE lower(l.description)~'anderson\s+plug';
 IF n<>2 OR NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines WHERE operation_line_id='88defe77-ea59-4842-a592-c84a3cc20b72'AND description='50A ANDERSON PLUG IN HIDRIVE CANOPY NEXT TO ACC SOCKE')
  OR NOT EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines WHERE operation_line_id='fd3dad66-9b29-4708-97a0-cdca3631210b'AND description='50A ANDERSON PLUG MOUNTED NEXT TO TOWBAR TRAILER PLUG')
  OR NOT EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments WHERE adjustment_id='589342a7-8d42-48d5-8d3b-fde6ea878034'AND line_key='source:88defe77-ea59-4842-a592-c84a3cc20b72'AND stage_code='FABRICATION'AND estimated_hours=2 AND version=1 AND correction_origin='manual_operator'AND active)
  OR EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments WHERE line_key='source:fd3dad66-9b29-4708-97a0-cdca3631210b')THEN
  RAISE EXCEPTION 'PDC_362_ANDERSON_SCOPE_DRIFT';END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_email_jobcard_work_key(p_description text)RETURNS text LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog,public AS $function$
DECLARE d text:=public.pdc_email_normalized_clause(p_description);
BEGIN
 RETURN CASE
  WHEN d~'(^| )tow ?bars?( |$)' THEN 'fitting'
  WHEN d~'(^| )(long range(r)?( fuel)? tanks?|arb frontier.{0,80}(fuel )?tanks?|sub tank replacem[a-z]*)( |$)' THEN 'hoist'
  WHEN d~'(^| )fire ext(inguisher|inuisher|inguishers|inuishers)?( |$)' THEN 'fitting'
  WHEN d~'(^| )anderson plugs?( |$)' THEN 'electrical'
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
END $function$;
REVOKE ALL ON FUNCTION public.pdc_email_jobcard_work_key(text)FROM public,anon,authenticated,service_role;

DO $apply$
DECLARE actor uuid;email text;fam uuid;ver uuid;before_row public.vehicle_workshop_line_adjustments%rowtype;after_row public.vehicle_workshop_line_adjustments%rowtype;vehicle2 uuid;
BEGIN
 SELECT auth_user_id,lower(email)INTO actor,email FROM public.pdc_user_roles WHERE lower(email)='craig.watson@broometoyota.com.au'AND role='administrator'AND active AND account_status='approved'LIMIT 1;
 IF actor IS NULL THEN RAISE EXCEPTION 'PDC_362_CRAIG_AUTHORIZER_MISSING';END IF;
 SELECT family_id INTO fam FROM public.pdc_supervised_rule_families WHERE family_key='accessory_12v_socket_plug_electrical';
 SELECT version_id INTO ver FROM public.pdc_supervised_rule_versions WHERE family_id=fam AND EXISTS(SELECT 1 FROM public.pdc_supervised_rule_events e WHERE e.version_id=pdc_supervised_rule_versions.version_id AND e.event_kind='activated')AND NOT EXISTS(SELECT 1 FROM public.pdc_supervised_rule_events e WHERE e.version_id=pdc_supervised_rule_versions.version_id AND e.event_kind IN('superseded','disabled','undo'))ORDER BY version_no DESC LIMIT 1;
 IF ver IS NULL THEN RAISE EXCEPTION 'PDC_362_ACTIVE_RULE_MISSING';END IF;
 INSERT INTO public.pdc_supervised_rule_aliases(version_id,alias)VALUES(ver,'anderson plug')ON CONFLICT(version_id,alias)DO NOTHING;
 INSERT INTO public.pdc_supervised_rule_examples(version_id,example_kind,example_text)
 SELECT ver,'positive','50A ANDERSON PLUG IN HIDRIVE CANOPY NEXT TO ACC SOCKET' WHERE NOT EXISTS(SELECT 1 FROM public.pdc_supervised_rule_examples WHERE version_id=ver AND example_kind='positive'AND example_text='50A ANDERSON PLUG IN HIDRIVE CANOPY NEXT TO ACC SOCKET');
 UPDATE public.pdc_supervised_revision SET revision=revision+1,updated_at=clock_timestamp()WHERE singleton;

 SELECT * INTO before_row FROM public.vehicle_workshop_line_adjustments WHERE adjustment_id='589342a7-8d42-48d5-8d3b-fde6ea878034'FOR UPDATE;
 UPDATE public.vehicle_workshop_line_adjustments SET stage_code='ELECTRICAL',version=version+1,updated_by=actor,updated_at=clock_timestamp()WHERE adjustment_id=before_row.adjustment_id RETURNING * INTO after_row;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)VALUES('update','vehicle_workshop_line_adjustments',after_row.adjustment_id,after_row.vehicle_id,actor,email,to_jsonb(before_row),to_jsonb(after_row),jsonb_build_object('source','craig_owner_rule_362','family','accessory_12v_socket_plug_electrical','hours_preserved',true,'bookings_changed',false,'parts_changed',false,'completion_changed',false));

 SELECT vehicle_id INTO vehicle2 FROM public.pdc_authenticated_email_operation_lines WHERE operation_line_id='fd3dad66-9b29-4708-97a0-cdca3631210b';
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
 SELECT vehicle2,'source:'||operation_line_id::text,'source','ELECTRICAL',description,estimated_hours,actor,actor FROM public.pdc_authenticated_email_operation_lines WHERE operation_line_id='fd3dad66-9b29-4708-97a0-cdca3631210b'RETURNING * INTO after_row;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)VALUES('insert','vehicle_workshop_line_adjustments',after_row.adjustment_id,after_row.vehicle_id,actor,email,null,to_jsonb(after_row),jsonb_build_object('source','craig_owner_rule_362','family','accessory_12v_socket_plug_electrical','bookings_changed',false,'parts_changed',false,'completion_changed',false));
END $apply$;

DO $post$
DECLARE n integer;
BEGIN
 SELECT count(*)INTO n FROM public.pdc_authenticated_email_operation_lines l JOIN public.vehicles v ON v.id=l.vehicle_id JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=v.id AND a.line_key='source:'||l.operation_line_id::text AND a.active AND a.stage_code='ELECTRICAL'WHERE lower(l.description)~'anderson\s+plug';
 IF n<>2 OR public.pdc_email_jobcard_work_key('50A ANDERSON PLUG IN HIDRIVE CANOPY NEXT TO ACC SOCKET')<>'electrical'OR public.pdc_email_jobcard_work_key('TOW BAR WITH ANDERSON PLUG')<>'fitting'
  OR NOT EXISTS(SELECT 1 FROM public.pdc_supervised_rule_aliases a JOIN public.pdc_supervised_rule_versions v USING(version_id)JOIN public.pdc_supervised_rule_families f USING(family_id)WHERE f.family_key='accessory_12v_socket_plug_electrical'AND a.alias='anderson plug')
  OR NOT EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments WHERE adjustment_id='589342a7-8d42-48d5-8d3b-fde6ea878034'AND stage_code='ELECTRICAL'AND estimated_hours=2 AND correction_origin='manual_operator'AND version=2)
  THEN RAISE EXCEPTION 'PDC_362_POSTCONDITION';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)VALUES('20260824230000','362_align_anderson_plugs_and_job_counts',array['Exact staging/head/classifier-hash/two-line scope containment','Persist Anderson plug alias and positive example under Craig 12V sockets/plugs Electrical family','Align canonical Job Card classifier while preserving Towbar precedence','Correct exactly two existing Anderson plug overlays to Electrical and preserve the entered two-hour estimate','Append audit evidence; change no booking, Parts, completion or physical-work state']);
NOTIFY pgrst,'reload schema';
COMMIT;
