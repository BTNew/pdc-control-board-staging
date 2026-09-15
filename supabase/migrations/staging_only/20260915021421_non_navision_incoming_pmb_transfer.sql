-- Release approved incoming non-Navision vehicles with an unknown location.
-- Existing canonical locations/history are not rewritten by this migration.
-- PMB arrival and incoming override clearing occur in the same protected RPC.
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: reviewed staging migration only';
 END IF;
 IF md5(pg_get_functiondef('public.pmb_transfer_vehicle(uuid,integer)'::regprocedure))<>'cd41b5b4f8b72644dd01214807ff50a4' THEN
  RAISE EXCEPTION 'pmb_transfer_vehicle changed since this successor was reviewed';
 END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.pmb_transfer_vehicle(uuid,integer)'::regprocedure)
    IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}' THEN
  RAISE EXCEPTION 'pmb_transfer_vehicle privileges changed since review';
 END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pmb_transfer_vehicle(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_before public.vehicles%rowtype; v_after public.vehicles%rowtype; v_location text; v_override text; v_now timestamptz:=clock_timestamp();
begin
  perform public.require_pdc_role('operator');
  if p_vehicle_id is null then return jsonb_build_object('ok',false,'error','invalid_vehicle'); end if;
  select * into v_before from public.vehicles where id=p_vehicle_id for update;
  if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
  if p_expected_version is null then return jsonb_build_object('ok',false,'error','missing_expected_version'); end if;
  if v_before.version<>p_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
  if v_before.lifecycle_state<>'active' or v_before.deleted_at is not null or v_before.board_purged_at is not null then return jsonb_build_object('ok',false,'error','not_in_active_lifecycle'); end if;
  v_location:=upper(btrim(coalesce(v_before.current_location,'')));
  -- Tune intake stores the display label; Navision vehicles may store its code.
  if v_location='YARD HOLD' then v_location:='YH';
  elsif v_location='IN TRANSIT' then v_location:='IT'; end if;
  v_override:=upper(btrim(coalesce(v_before.location_override,'')));
  if v_override='YARD HOLD' then v_override:='YH';
  elsif v_override='IN TRANSIT' then v_override:='IT'; end if;
  -- A stale raw incoming location cannot reopen QC, transport or collection.
  if v_before.qc_completed_at is not null or v_before.rft_transferred_at is not null
     or v_before.rft_collected_at is not null then
    return jsonb_build_object('ok',false,'error','pmb_transfer_requires_incoming_location');
  end if;
  if v_location='PMB' and v_override='' then
    return jsonb_build_object('ok',true,'code','already_at_pmb','vehicle',to_jsonb(v_before));
  end if;
  -- Overrides at a later operational stage must be resolved explicitly.
  if v_location not in ('YH','IT','OTHER','')
     or v_override not in ('YH','IT','OTHER','') then
    return jsonb_build_object('ok',false,'error','pmb_transfer_requires_incoming_location');
  end if;
  -- Unknown location is permitted only for an approved incoming non-Navision
  -- vehicle. Use recorded source and canonical links, never stock/dealer guesses.
  if v_location in ('OTHER','') and (
    not v_before.visible_on_board
    or lower(btrim(coalesce(v_before.source_system,''))) in ('microsoft_navision','navision','shared navision')
    or exists (
      select 1 from public.navision_backend_records n
      where n.canonical_vehicle_id=v_before.id
        and n.source_system='microsoft_navision'
        and n.is_current and n.record_status='current'
    )
  ) then
    return jsonb_build_object('ok',false,'error','pmb_transfer_requires_incoming_location');
  end if;
  update public.vehicles set current_location='PMB',location_override=null,location_override_reason=null,location_override_at=null,location_override_by=null,date_to_pmb=coalesce(date_to_pmb,(v_now at time zone 'Australia/Perth')::date),visible_on_board=true,pmb_stage=null,pmb_bay_stage=null,pmb_bay_number=null,source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('manual_location_authority','PMB','manual_location_updated_at',v_now,'manual_location_updated_by',public.current_actor_email()),version=version+1,updated_by=auth.uid() where id=p_vehicle_id returning * into v_after;
  insert into public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by) values(p_vehicle_id,v_before.current_location,'PMB',v_before.pmb_stage,null,v_before.pmb_bay_stage,null,v_before.pmb_bay_number,null,'Explicit Vehicle Locations release to PMB',auth.uid());
  perform public.audit_pdc_event('move','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('action','pmb_transfer_vehicle','from',v_before.current_location,'to','Released to PMB','date_to_pmb',v_after.date_to_pmb,'cleared_location_override',v_before.location_override));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
  return jsonb_build_object('ok',true,'code','transferred_to_pmb','vehicle',to_jsonb(v_after));
end;
$function$;

-- CREATE OR REPLACE retains the existing owner, signature and EXECUTE grants.
DO $check$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM pg_proc p WHERE p.oid='public.pmb_transfer_vehicle(uuid,integer)'::regprocedure
    AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
    AND p.proacl::text='{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'
    AND p.proconfig=ARRAY['search_path=pg_catalog, public']::text[]
 ) THEN RAISE EXCEPTION 'Transfer security attributes changed unexpectedly'; END IF;
END $check$;

