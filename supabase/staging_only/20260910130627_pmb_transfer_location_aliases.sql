-- STAGING only: recognise the existing Tune intake location labels.
-- No vehicle rows, permissions, lifecycle gates or movement side effects are changed.
DO $migration$
DECLARE current_definition text;
BEGIN
 SELECT pg_get_functiondef('public.pmb_transfer_vehicle(uuid,integer)'::regprocedure) INTO current_definition;
 IF current_definition IS DISTINCT FROM $before$CREATE OR REPLACE FUNCTION public.pmb_transfer_vehicle(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_before public.vehicles%rowtype; v_after public.vehicles%rowtype; v_location text; v_now timestamptz:=clock_timestamp();
begin
  perform public.require_pdc_role('operator');
  if p_vehicle_id is null then return jsonb_build_object('ok',false,'error','invalid_vehicle'); end if;
  select * into v_before from public.vehicles where id=p_vehicle_id for update;
  if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
  if p_expected_version is null then return jsonb_build_object('ok',false,'error','missing_expected_version'); end if;
  if v_before.version<>p_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
  if v_before.lifecycle_state<>'active' or v_before.deleted_at is not null then return jsonb_build_object('ok',false,'error','not_in_active_lifecycle'); end if;
  v_location:=upper(btrim(coalesce(v_before.current_location,'')));
  if v_location='PMB' then return jsonb_build_object('ok',true,'code','already_at_pmb','vehicle',to_jsonb(v_before)); end if;
  if v_location not in ('YH','IT') then return jsonb_build_object('ok',false,'error','pmb_transfer_requires_yh_or_it'); end if;
  update public.vehicles set current_location='PMB',date_to_pmb=coalesce(date_to_pmb,(v_now at time zone 'Australia/Perth')::date),visible_on_board=true,pmb_stage=null,pmb_bay_stage=null,pmb_bay_number=null,source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('manual_location_authority','PMB','manual_location_updated_at',v_now,'manual_location_updated_by',public.current_actor_email()),version=version+1,updated_by=auth.uid() where id=p_vehicle_id returning * into v_after;
  insert into public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by) values(p_vehicle_id,v_before.current_location,'PMB',v_before.pmb_stage,null,v_before.pmb_bay_stage,null,v_before.pmb_bay_number,null,'Explicit Vehicle Locations release to PMB',auth.uid());
  perform public.audit_pdc_event('move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('action','pmb_transfer_vehicle','from',v_before.current_location,'to','Released to PMB','date_to_pmb',v_after.date_to_pmb));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
  return jsonb_build_object('ok',true,'code','transferred_to_pmb','vehicle',to_jsonb(v_after));
end;
$function$
$before$ THEN
  RAISE EXCEPTION 'pmb_transfer_vehicle changed since review; rebase this correction';
 END IF;
 EXECUTE $after$CREATE OR REPLACE FUNCTION public.pmb_transfer_vehicle(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_before public.vehicles%rowtype; v_after public.vehicles%rowtype; v_location text; v_now timestamptz:=clock_timestamp();
begin
  perform public.require_pdc_role('operator');
  if p_vehicle_id is null then return jsonb_build_object('ok',false,'error','invalid_vehicle'); end if;
  select * into v_before from public.vehicles where id=p_vehicle_id for update;
  if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
  if p_expected_version is null then return jsonb_build_object('ok',false,'error','missing_expected_version'); end if;
  if v_before.version<>p_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
  if v_before.lifecycle_state<>'active' or v_before.deleted_at is not null then return jsonb_build_object('ok',false,'error','not_in_active_lifecycle'); end if;
  v_location:=upper(btrim(coalesce(v_before.current_location,'')));
  -- Tune intake stores the display label; Navision vehicles may store its code.
  if v_location='YARD HOLD' then v_location:='YH';
  elsif v_location='IN TRANSIT' then v_location:='IT'; end if;
  if v_location='PMB' then return jsonb_build_object('ok',true,'code','already_at_pmb','vehicle',to_jsonb(v_before)); end if;
  if v_location not in ('YH','IT') then return jsonb_build_object('ok',false,'error','pmb_transfer_requires_yh_or_it'); end if;
  update public.vehicles set current_location='PMB',date_to_pmb=coalesce(date_to_pmb,(v_now at time zone 'Australia/Perth')::date),visible_on_board=true,pmb_stage=null,pmb_bay_stage=null,pmb_bay_number=null,source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('manual_location_authority','PMB','manual_location_updated_at',v_now,'manual_location_updated_by',public.current_actor_email()),version=version+1,updated_by=auth.uid() where id=p_vehicle_id returning * into v_after;
  insert into public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by) values(p_vehicle_id,v_before.current_location,'PMB',v_before.pmb_stage,null,v_before.pmb_bay_stage,null,v_before.pmb_bay_number,null,'Explicit Vehicle Locations release to PMB',auth.uid());
  perform public.audit_pdc_event('move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('action','pmb_transfer_vehicle','from',v_before.current_location,'to','Released to PMB','date_to_pmb',v_after.date_to_pmb));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
  return jsonb_build_object('ok',true,'code','transferred_to_pmb','vehicle',to_jsonb(v_after));
end;
$function$
$after$;
END $migration$;
