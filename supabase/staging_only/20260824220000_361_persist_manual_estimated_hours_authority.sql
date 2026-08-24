-- STAGING ONLY 361: preserve saved estimated-hour overlays as manual
-- scheduling authority and return them correctly to the Vehicle detail UI.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-361-hours-overlay',0));
DO $guard$
DECLARE h text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824210000' AND name='360_craig_owner_jobcard_work_key_precedence')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824210000' AND version~'^[0-9]{14}$')
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_361_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH';
 END IF;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'::regprocedure),'UTF8'),'sha256'),'hex') INTO h;
 IF h<>'a5f90f3e216be024890ee02a01e1d0e7f7547f56f585dc66d3002c24b750e327' THEN RAISE EXCEPTION 'PDC_361_UPSERT_PREDECESSOR_DRIFT %',h;END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.upsert_vehicle_workshop_line_adjustment(p_vehicle_id uuid,p_adjustment_id uuid,p_expected_version bigint,p_line_key text,p_stage_code text,p_description text,p_estimated_hours numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
DECLARE
 v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_vehicle public.vehicles%rowtype;v_before public.vehicle_workshop_line_adjustments%rowtype;v_after public.vehicle_workshop_line_adjustments%rowtype;
 v_line_key text:=btrim(coalesce(p_line_key,''));v_stage text:=upper(btrim(coalesce(p_stage_code,'')));
 v_description text:=btrim(coalesce(p_description,''));v_source_kind text;
BEGIN
 perform public.require_pdc_role('operator');
 if v_actor is null or v_email='' then return jsonb_build_object('ok',false,'code','unauthorized');end if;
 if p_expected_version is null or p_expected_version<0 or v_stage!~'^[A-Z][A-Z0-9_]{1,39}$'
    or length(v_description)not between 1 and 180 or v_description~'[[:cntrl:]]'
    or p_estimated_hours is null or p_estimated_hours<0 or p_estimated_hours>999.99 or mod(p_estimated_hours,0.01)<>0 then
  return jsonb_build_object('ok',false,'code','invalid_workshop_line');
 end if;
 select * into v_vehicle from public.vehicles v where v.id=p_vehicle_id and v.lifecycle_state='active'and v.deleted_at is null for update;
 if not found then return jsonb_build_object('ok',false,'code','vehicle_not_found');end if;
 perform 1 from public.vehicle_work_items wi where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
  and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))=v_stage;
 if not found then return jsonb_build_object('ok',false,'code','workshop_stage_not_editable');end if;
 if p_adjustment_id is null then
  if v_line_key='' then
   if p_expected_version<>v_vehicle.version then return jsonb_build_object('ok',false,'code','stale_vehicle_version','data',jsonb_build_object('current_version',v_vehicle.version));end if;
   v_source_kind:='manual';v_line_key:='manual:'||gen_random_uuid()::text;
  else
   if p_expected_version<>0 then return jsonb_build_object('ok',false,'code','stale_line_version');end if;
   if v_line_key!~'^(source|operation|display):'or length(v_line_key)>220 then return jsonb_build_object('ok',false,'code','invalid_workshop_line_key');end if;
   v_source_kind:=case when v_line_key like'display:%'then'display'else'source'end;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('vehicle-workshop-line:'||p_vehicle_id::text||':'||v_line_key,0));
  if exists(select 1 from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p_vehicle_id and a.line_key=v_line_key)then return jsonb_build_object('ok',false,'code','workshop_line_conflict');end if;
  insert into public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,created_by,updated_by)
  values(p_vehicle_id,v_line_key,v_source_kind,v_stage,v_description,p_estimated_hours,'manual_operator',v_actor,v_actor)returning * into v_after;
  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  values('insert','vehicle_workshop_line_adjustments',v_after.adjustment_id,p_vehicle_id,v_actor,v_email,null,to_jsonb(v_after),jsonb_build_object('source','vehicle_detail_workshop_line_361','source_kind',v_after.source_kind,'line_key',v_after.line_key,'hours_authority','manual_operator','bookings_changed',false,'parts_changed',false,'completion_changed',false));
 else
  select * into v_before from public.vehicle_workshop_line_adjustments a where a.adjustment_id=p_adjustment_id and a.vehicle_id=p_vehicle_id for update;
  if not found or not v_before.active then return jsonb_build_object('ok',false,'code','workshop_line_not_found');end if;
  if v_before.version<>p_expected_version then return jsonb_build_object('ok',false,'code','stale_line_version','data',jsonb_build_object('current_version',v_before.version));end if;
  if v_line_key<>''and v_line_key<>v_before.line_key then return jsonb_build_object('ok',false,'code','workshop_line_identity_mismatch');end if;
  update public.vehicle_workshop_line_adjustments set stage_code=v_stage,description=v_description,estimated_hours=p_estimated_hours,correction_origin='manual_operator',version=version+1,updated_by=v_actor,updated_at=clock_timestamp()where adjustment_id=v_before.adjustment_id returning * into v_after;
  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  values('update','vehicle_workshop_line_adjustments',v_after.adjustment_id,p_vehicle_id,v_actor,v_email,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('source','vehicle_detail_workshop_line_361','source_kind',v_after.source_kind,'line_key',v_after.line_key,'hours_authority','manual_operator','bookings_changed',false,'parts_changed',false,'completion_changed',false));
 end if;
 return jsonb_build_object('ok',true,'code','workshop_line_saved','data',jsonb_build_object('adjustment_id',v_after.adjustment_id,'line_key',v_after.line_key,'source_kind',v_after.source_kind,'stage_code',v_after.stage_code,'description',v_after.description,'estimated_hours',v_after.estimated_hours,'correction_origin',v_after.correction_origin,'active',v_after.active,'version',v_after.version,'vehicle_id',v_after.vehicle_id));
END $function$;
REVOKE ALL ON FUNCTION public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric) TO authenticated,service_role;
DO $post$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)'::regprocedure);
 IF position('correction_origin=''manual_operator'''in d)=0 OR position('hours_authority' in d)=0 THEN RAISE EXCEPTION 'PDC_361_FUNCTION_POSTCONDITION';END IF;
 IF has_function_privilege('anon','public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)','EXECUTE') OR NOT has_function_privilege('authenticated','public.upsert_vehicle_workshop_line_adjustment(uuid,uuid,bigint,text,text,text,numeric)','EXECUTE')THEN RAISE EXCEPTION 'PDC_361_ACL_POSTCONDITION';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)VALUES('20260824220000','361_persist_manual_estimated_hours_authority',array['Exact staging/head/function-hash containment','Mark Vehicle detail hour saves as manual_operator scheduling authority','Return correction_origin and immutable audit metadata','Preserve operator validation, optimistic concurrency and narrow ACL']);
NOTIFY pgrst,'reload schema';
COMMIT;
