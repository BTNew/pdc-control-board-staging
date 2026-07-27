begin;

-- Ready-for-QC is now an explicit, audited PMB -> QC Gate transition.
-- QC Gate itself remains eligible for the subsequent named QC sign-off.
create or replace function public.pdc_qc_gate_issues(p_vehicle_id uuid)
returns text[] language sql stable security definer set search_path=pg_catalog,public as $$
  with vehicle as (
    select id,upper(btrim(coalesce(current_location,''))) location,
           upper(regexp_replace(btrim(coalesce(pmb_stage,'')),'[^A-Z0-9]+','','g')) stage
    from public.vehicles where id=p_vehicle_id and lifecycle_state='active' and deleted_at is null
  ), outstanding as (
    select string_agg(distinct upper(btrim(wi.work_key)),', ' order by upper(btrim(wi.work_key))) labels
    from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and upper(regexp_replace(btrim(coalesce(wi.work_key,'')),'[^A-Z0-9]+','','g'))<>'QC'
      and public.workshop_stage_code_for_work_key(wi.work_key) is distinct from 'PIT_INSPECTION'
  ), active_planner as (
    select string_agg(distinct s.code,', ' order by s.code) labels
    from public.workshop_bookings b
    join public.workshop_stages s on s.id=b.stage_id
    where b.vehicle_id=p_vehicle_id and b.deleted_at is null
      and b.status in ('queued','planned','started','stoppage')
      and s.planner_enabled
  )
  select array_remove(array[
    case when not exists(select 1 from vehicle) then 'active_vehicle_required' end,
    case when (select location from vehicle) not in ('PMB','QC') then 'vehicle_must_be_at_pmb_or_qc_gate' end,
    case when coalesce((select stage from vehicle),'') not in ('','PITINSPECTION','PIT','PITS') then
      'vehicle_still_in_workshop_stage:'||(select stage from vehicle) end,
    case when (select labels from outstanding) is not null then
      'outstanding_required_work:'||(select labels from outstanding) end,
    case when (select labels from active_planner) is not null then
      'active_workshop_booking:'||(select labels from active_planner) end
  ],null::text)
$$;
revoke all on function public.pdc_qc_gate_issues(uuid) from public,anon,authenticated;
grant execute on function public.pdc_qc_gate_issues(uuid) to service_role;

-- Migration 069 compared the lifecycle enum directly with an empty string in
-- COALESCE. PostgreSQL tries to cast that empty string to the enum on every
-- vehicle update, so even a valid PMB -> QC location update fails. Keep the
-- same gate but compare the enum's text representation.
create or replace function public.pdc_enforce_qc_then_rft()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_issues text[];
begin
  if (upper(btrim(coalesce(new.current_location,'')))='RFT'
      or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft')
     and new.qc_completed_at is null then
    raise exception 'RFT vehicles must retain a prior QC sign-off' using errcode='22023';
  end if;

  if old.qc_completed_at is null and new.qc_completed_at is not null then
    if upper(btrim(coalesce(new.current_location,'')))='RFT'
       or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft' then
      raise exception 'QC sign-off and RFT transfer must be separate audited transitions' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'QC gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;

  if (upper(btrim(coalesce(old.current_location,''))) is distinct from 'RFT'
      and upper(btrim(coalesce(new.current_location,'')))='RFT')
     or (lower(btrim(coalesce(old.lifecycle_state::text,''))) is distinct from 'rft'
      and lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft') then
    if old.qc_completed_at is null then
      raise exception 'QC sign-off must be completed before RFT transfer' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'RFT gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.pdc_enforce_qc_then_rft() from public,anon,authenticated;

create or replace function public.mark_vehicle_ready_for_qc(
  p_vehicle_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_issues text[];
begin
  perform public.require_pdc_role('operator');
  select * into v_before from public.vehicles where id=p_vehicle_id for update;
  if not found then return jsonb_build_object('ok',false,'error','vehicle_not_found'); end if;
  if p_expected_version is null then return jsonb_build_object('ok',false,'error','missing_expected_version'); end if;
  if v_before.version<>p_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
  if upper(btrim(coalesce(v_before.current_location,'')))='QC' then
    return jsonb_build_object('ok',false,'error','already_ready_for_qc','vehicle',to_jsonb(v_before));
  end if;
  if v_before.lifecycle_state<>'active' or v_before.deleted_at is not null then
    return jsonb_build_object('ok',false,'error','not_in_active_lifecycle');
  end if;
  if upper(btrim(coalesce(v_before.current_location,'')))<>'PMB'
     or nullif(btrim(coalesce(v_before.pmb_stage,'')),'') is not null
     or nullif(btrim(coalesce(v_before.pmb_bay_stage,'')),'') is not null
     or nullif(btrim(coalesce(v_before.pmb_bay_number,'')),'') is not null then
    return jsonb_build_object('ok',false,'error','qc_gate_blocked','issues',jsonb_build_array('vehicle_must_be_pmb_unallocated'));
  end if;
  v_issues:=public.pdc_qc_gate_issues(p_vehicle_id);
  if coalesce(array_length(v_issues,1),0)>0 then
    return jsonb_build_object('ok',false,'error','qc_gate_blocked','issues',to_jsonb(v_issues));
  end if;
  update public.vehicles
  set current_location='QC',version=version+1,updated_by=auth.uid()
  where id=p_vehicle_id returning * into v_after;
  insert into public.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,
    reason,moved_by
  ) values (
    p_vehicle_id,v_before.current_location,'QC',v_before.pmb_stage,null,
    v_before.pmb_bay_stage,null,v_before.pmb_bay_number,null,
    'All required work complete - moved to QC Gate',auth.uid()
  );
  perform public.audit_pdc_event(
    'update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_after),
    jsonb_build_object('action','mark_vehicle_ready_for_qc','from','PMB','to','QC')
  );
  return jsonb_build_object('ok',true,'vehicle',to_jsonb(v_after),'ready_for_qc',true);
end;
$$;
revoke all on function public.mark_vehicle_ready_for_qc(uuid,integer) from public,anon,authenticated;
grant execute on function public.mark_vehicle_ready_for_qc(uuid,integer) to authenticated;

-- Append-only shared Parts ETA updates with vehicle-version concurrency.
create or replace function public.update_pdc_parts_eta(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_worst_eta date default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_vehicle_before public.vehicles%rowtype;
  v_vehicle_after public.vehicles%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
begin
  perform public.require_pdc_role('operator');
  select * into v_vehicle_before from public.vehicles where id=p_vehicle_id for update;
  if not found then return jsonb_build_object('ok',false,'error','vehicle_not_found'); end if;
  if p_expected_version is null then return jsonb_build_object('ok',false,'error','missing_expected_version'); end if;
  if v_vehicle_before.version<>p_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
  if v_vehicle_before.lifecycle_state<>'active' or v_vehicle_before.deleted_at is not null then
    return jsonb_build_object('ok',false,'error','not_in_active_lifecycle');
  end if;
  select * into v_parts_before from public.vehicle_parts_updates
  where vehicle_id=p_vehicle_id order by updated_at desc,id desc limit 1;
  insert into public.vehicle_parts_updates(
    vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
    parts_stoppage_reason,worst_eta,updated_by,updated_at
  ) values (
    p_vehicle_id,
    coalesce(v_parts_before.parts_required,false),
    coalesce(v_parts_before.parts_ordered,false),
    coalesce(v_parts_before.parts_received,false),
    coalesce(v_parts_before.parts_stoppage,false),
    v_parts_before.parts_stoppage_reason,p_worst_eta,auth.uid(),clock_timestamp()
  ) returning * into v_parts_after;
  update public.vehicles set version=version+1,updated_by=auth.uid()
  where id=p_vehicle_id returning * into v_vehicle_after;
  perform public.audit_pdc_event(
    'insert','vehicle_parts_updates',v_parts_after.id,p_vehicle_id,
    case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,
    to_jsonb(v_parts_after),
    jsonb_build_object('action','update_pdc_parts_eta','worst_eta',p_worst_eta)
  );
  return jsonb_build_object('ok',true,'vehicle',to_jsonb(v_vehicle_after),'parts_update',to_jsonb(v_parts_after));
end;
$$;
revoke all on function public.update_pdc_parts_eta(uuid,integer,date) from public,anon,authenticated;
grant execute on function public.update_pdc_parts_eta(uuid,integer,date) to authenticated;

create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $snapshot$
declare
  v_role text;
  v_revision bigint;
  v_rows jsonb;
begin
  v_role:=public.current_pdc_user_role()::text;
  if v_role not in ('viewer','operator','importer','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select revision into v_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,
    'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,
    'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,
    'salesperson_reference',v.salesperson_reference,'registration',v.registration,
    'eta_to_kewdale',v.eta_to_kewdale,'current_location',v.current_location,
    'visible_on_board',v.visible_on_board,'source_system',v.source_system,
    'source_record_id',v.source_record_id,'updated_at',v.updated_at,
    'work_items',coalesce((select jsonb_agg(jsonb_build_object(
      'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
      'completed_at',wi.completed_at,'completed_by',wi.completed_by
    ) order by wi.work_key) from public.vehicle_work_items wi where wi.vehicle_id=v.id),'[]'::jsonb),
    'parts_required',coalesce((select pu.parts_required from public.vehicle_parts_updates pu
      where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),false),
    'parts_completed',coalesce((select wi.completed from public.vehicle_work_items wi
      where wi.vehicle_id=v.id and wi.work_key='PARTS'),false),
    'parts_update',coalesce((select jsonb_build_object(
      'parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,
      'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,
      'parts_stoppage_reason',pu.parts_stoppage_reason,'worst_eta',pu.worst_eta,
      'updated_at',pu.updated_at
    ) from public.vehicle_parts_updates pu where pu.vehicle_id=v.id
      order by pu.updated_at desc,pu.id desc limit 1),'{}'::jsonb),
    'sublet_booking',coalesce((select jsonb_build_object(
      'provider',s.provider,'provider_email',s.provider_email,
      'po_sent_date',s.po_sent_date,'booking_date',s.booking_date,
      'expected_return_date',s.expected_return_date,'actual_return_date',s.actual_return_date,
      'notes',s.notes,'email_sent',s.email_sent,'version',s.version,'updated_at',s.updated_at
    ) from public.pdc_sublet_bookings s where s.vehicle_id=v.id),'{}'::jsonb)
  ) order by coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb)
  into v_rows
  from public.vehicles v
  where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id);
  return public.navision_backend_response(true,'ok',jsonb_build_object(
    'revision',coalesce(v_revision,1),'vehicles',v_rows
  ));
end;
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot()
  from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot()
  to authenticated;

commit;
