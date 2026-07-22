-- Blocker-only release closure. Supersedes rejected, never-applied migration 043.
-- Prerequisite: migration 042. This migration is additive to the live staging schema,
-- contains no operational vehicle-data rewrite and leaves Sublet planner-disabled.

-- Migration 042 canonicalized PITSHOIST and PITINSPECTION to the same stored
-- work key. Their provenance is therefore indistinguishable. Refuse to remap
-- PITSHOIST to the approved Hoist authority if any ambiguous stored rows exist;
-- they require a separate, explicitly reviewed data-authority decision.
do $$
begin
 if exists(select 1 from public.vehicle_work_items
           where public.workshop_normalize_identifier(work_key)='PITINSPECTION') then
  raise exception 'Ambiguous historical PITSHOIST/PITINSPECTION work items require separate adjudication'
   using errcode='23514';
 end if;
end $$;

-- Preserve the complete reviewed alias corpus and correct the approved Hoist
-- aliases without deleting retained business aliases.
insert into public.workshop_stage_aliases(alias_normalized,alias_value,stage_code)
select v.alias_normalized,v.alias_value,v.stage_code from (values
 ('BUS4X4','Bus 4x4','BUS_4X4'),('BUSFOURBYFOUR','Bus Four By Four','BUS_4X4'),('4X4BUS','4x4 Bus','BUS_4X4'),('DEPARTMENT138','Department 138','BUS_4X4'),('DEPT138','Dept 138','BUS_4X4'),
 ('TINT','Tint','TINT'),('TINTING','Tinting','TINT'),('WINDOWTINT','Window Tint','TINT'),
 ('HOIST','Hoist','HOIST'),('LIFTS','Lifts','HOIST'),('PITSHOIST','Pits Hoist','HOIST'),('PITHOIST','Pit Hoist','HOIST'),('EXPRESSHOIST','Express Hoist','HOIST'),
 ('FITTING','Fitting','FITTING'),('FITMENT','Fitment','FITTING'),('FITOUT','Fit Out','FITTING'),('EXPRESSFITOUT','Express Fit Out','FITTING'),
 ('FABRICATION','Fabrication','FABRICATION'),('FAB','Fab','FABRICATION'),('FABRICATING','Fabricating','FABRICATION'),
 ('ELECTRICAL','Electrical','ELECTRICAL'),('ELEC','Elec','ELECTRICAL'),('AUTOELECTRICAL','Auto Electrical','ELECTRICAL'),('AUTOELEC','Auto Elec','ELECTRICAL'),
 ('TYRE','Tyre','TYRE'),('TYRES','Tyres','TYRE'),('TYREBAY','Tyre Bay','TYRE'),('TIRE','Tire','TYRE'),('TIREBAY','Tire Bay','TYRE'),
 ('PITINSPECTION','Pit Inspection','PIT_INSPECTION'),('PIT','Pit','PIT_INSPECTION'),('PITS','Pits','PIT_INSPECTION'),('INSPECTION','Inspection','PIT_INSPECTION'),
 ('SUBLET','Sublet','SUBLET'),('OUTSOURCE','Outsource','SUBLET'),('OUTSOURCED','Outsourced','SUBLET'),('EXTERNAL','External','SUBLET')
) as v(alias_normalized,alias_value,stage_code)
on conflict(alias_normalized) do update set alias_value=excluded.alias_value,stage_code=excluded.stage_code;

create or replace function public.workshop_is_planner_operator()
returns boolean language sql stable security definer
set search_path=pg_catalog,public as $$
 select coalesce(public.current_pdc_user_role()::text,'') in ('operator','administrator')
$$;
revoke all on function public.workshop_is_planner_operator() from public,anon;
grant execute on function public.workshop_is_planner_operator() to authenticated;

create or replace function public.workshop_is_authorized_reader()
returns boolean language sql stable security definer
set search_path=pg_catalog,public as $$
 select coalesce(public.current_pdc_user_role()::text,'') in ('viewer','operator','administrator')
$$;
revoke all on function public.workshop_is_authorized_reader() from public,anon;
grant execute on function public.workshop_is_authorized_reader() to authenticated;

create or replace function public.workshop_require_authorized_reader()
returns void language plpgsql stable security definer
set search_path=pg_catalog,public as $$
begin
 if not public.workshop_is_authorized_reader() then
  raise exception 'Viewer, operator or administrator role required' using errcode='42501';
 end if;
end $$;
revoke all on function public.workshop_require_authorized_reader() from public,anon,authenticated;

create or replace function public.workshop_require_planner_operator()
returns void language plpgsql stable security definer
set search_path=pg_catalog,public as $$
begin
 if not public.workshop_is_planner_operator() then
  raise exception 'Operator or administrator role required' using errcode='42501';
 end if;
end $$;
revoke all on function public.workshop_require_planner_operator() from public,anon,authenticated;

-- Preserve the established cascade/completion behavior while replacing their
-- inherited importer gate in-place. pg_get_functiondef keeps this corrective
-- migration additive and repeatable without copying hundreds of legacy lines;
-- fail closed if the expected gate cannot be proven in the installed body.
do $$
declare v_signature regprocedure; v_definition text; v_patched text;
begin
 foreach v_signature in array array[
  'public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)'::regprocedure,
  'public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)'::regprocedure,
  'public.move_vehicle(uuid,integer,text,text,text,text,text)'::regprocedure,
  'public.mark_vehicle_deleted(uuid,integer,text)'::regprocedure,
  'public.qc_complete_vehicle(uuid,integer,text,text)'::regprocedure,
  'public.rft_transfer_vehicle(uuid,integer)'::regprocedure,
  'public.rft_collect_vehicle(uuid,integer)'::regprocedure,
  'public.restore_vehicle(uuid,integer,text)'::regprocedure,
  'public.edit_vehicle_master(uuid,integer,jsonb,text,text)'::regprocedure,
  'public.get_vehicle_core_snapshot()'::regprocedure,
  'public.resolve_vehicle_lifecycle_identity(text,text,text,text,text,text,text,text)'::regprocedure,
  'public.get_vehicle_intelligence_snapshot(uuid,text,integer)'::regprocedure,
  'public.append_vehicle_timeline_event(uuid,text,timestamptz,public.vehicle_timeline_source_kind,public.vehicle_timeline_event_state,text,text,jsonb,text,text,text,text,text,text,text,text,text,numeric,numeric,numeric,numeric,text,boolean,jsonb,jsonb,text,text,uuid,uuid,uuid,uuid,uuid)'::regprocedure,
  'public.create_ai_review_item(uuid,uuid,uuid,uuid[],uuid[],text,jsonb,jsonb)'::regprocedure,
  'public.list_ai_review_queue(text)'::regprocedure,
  'public.list_salespeople(boolean)'::regprocedure,
  'public.list_sublet_providers(boolean)'::regprocedure,
  'public.approve_ai_review_item(uuid,uuid,uuid[],text)'::regprocedure,
  'public.reject_ai_review_item(uuid,text,boolean)'::regprocedure
 ] loop
  select pg_get_functiondef(v_signature) into v_definition;
  v_patched:=replace(replace(replace(replace(replace(replace(v_definition,
    'perform public.require_pdc_role(''operator'');',
    'perform public.workshop_require_planner_operator();'),
    'perform public.require_pdc_role(''operator''::public.pdc_role);',
    'perform public.workshop_require_planner_operator();'),
    'perform public.require_pdc_role(''importer'');',
    'perform public.workshop_require_planner_operator();'),
    'perform public.require_pdc_role(''importer''::public.pdc_role);',
    'perform public.workshop_require_planner_operator();'),
    'public.is_pdc_role(''operator''::public.pdc_role)',
    'public.workshop_is_planner_operator()'),
    'public.is_pdc_role(''operator'')',
    'public.workshop_is_planner_operator()');
  v_patched:=replace(replace(v_patched,
    'public.is_pdc_role(''importer''::public.pdc_role)','false'),
    'public.is_pdc_role(''importer'')','false');
  v_patched:=replace(v_patched,
    'public.current_pdc_user_role() = ANY (ARRAY[''operator''::public.pdc_role, ''importer''::public.pdc_role, ''administrator''::public.pdc_role])',
    'public.workshop_is_planner_operator()');
  v_patched:=replace(v_patched,
    'if public.current_pdc_user_role() not in (''importer'', ''administrator'', ''operator'') then',
    'if not public.workshop_is_planner_operator() then');
  v_patched:=replace(v_patched,
    'if public.current_pdc_user_role() not in (''importer'', ''administrator'') then',
    'if not public.workshop_is_planner_operator() or not public.is_pdc_role(''administrator'') then');
  if v_signature='public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)'::regprocedure then
   v_patched:=replace(v_patched,
     'b.status = ''planned''',
     'b.status = ''planned'' and b.deleted_at is null');
   v_patched:=replace(v_patched,
     'and status = ''planned'';',
     'and status = ''planned'' and deleted_at is null;');
   v_patched:=replace(v_patched,
     E'and status = ''planned''\n',
     E'and status = ''planned'' and deleted_at is null\n');
   if position('b.status = ''planned'' and b.deleted_at is null' in v_patched)=0
      or position('status = ''planned'' and deleted_at is null' in v_patched)=0 then
    raise exception 'Could not install cascade soft-delete boundary' using errcode='42501';
   end if;
  end if;
  if position('public.workshop_require_planner_operator()' in v_patched)=0
     and position('public.workshop_is_planner_operator()' in v_patched)=0 then
   raise exception 'Could not install exact planner role guard for %',v_signature using errcode='42501';
  end if;
  if position('public.require_pdc_role(''operator''' in v_patched)>0
     or position('public.require_pdc_role(''importer''' in v_patched)>0
     or position('public.is_pdc_role(''operator''' in v_patched)>0
     or position('''importer''::public.pdc_role' in v_patched)>0
     or position('current_pdc_user_role() not in (''importer''' in v_patched)>0 then
   raise exception 'Could not close inherited importer gate for %',v_signature using errcode='42501';
  end if;
  execute v_patched;
 end loop;
end $$;

-- The retained restricted-pilot lifecycle projection is viewer-readable but
-- must not inherit importer through the historical role hierarchy.
do $$
declare v_signature regprocedure:='public.get_restricted_pilot_vehicle_snapshot(uuid)'::regprocedure;
        v_definition text; v_patched text;
begin
 select pg_get_functiondef(v_signature) into v_definition;
 v_patched:=replace(replace(v_definition,
   'perform public.require_pdc_role(''viewer'');',
   'perform public.workshop_require_authorized_reader();'),
   'perform public.require_pdc_role(''viewer''::public.pdc_role);',
   'perform public.workshop_require_authorized_reader();');
 if position('public.workshop_require_authorized_reader()' in v_patched)=0
    or position('public.require_pdc_role(''viewer''' in v_patched)>0 then
  raise exception 'Could not close inherited importer gate for %',v_signature using errcode='42501';
 end if;
 execute v_patched;
end $$;

-- Summary rebuilding is an internal primitive called by the approved narrow
-- ETA path and by guarded operator/admin intelligence mutations. It must not
-- remain directly executable by browser roles, including importer.
revoke all on function public.rebuild_vehicle_intelligence_summary(uuid) from public,anon,authenticated;
grant execute on function public.rebuild_vehicle_intelligence_summary(uuid) to service_role;

-- Vehicle rows carry workflow authority and are part of the Realtime
-- publication. Replace the inherited operator hierarchy so importers cannot
-- read that authority directly or through Realtime. Approved importer
-- maintenance remains available only through narrow SECURITY DEFINER RPCs.
drop policy if exists vehicles_select_approved on public.vehicles;
drop policy if exists vehicles_select_operator on public.vehicles;
drop policy if exists vehicles_planner_operator_select on public.vehicles;
create policy vehicles_planner_operator_select on public.vehicles
 for select to authenticated using(public.workshop_is_planner_operator());
grant select on public.vehicles to authenticated;

-- Retire the legacy combined snapshot: it serializes broad rows and is not
-- used by any reachable station route. Keep it service-role-only for rollback
-- diagnostics; browser roles must use the minimal station/eligibility DTOs.
revoke all on function public.get_workshop_snapshot(date,date) from public,anon,authenticated;
grant execute on function public.get_workshop_snapshot(date,date) to service_role;

-- Reference reads remain available to planner operators/admins, but no longer
-- inherit importer access through require_pdc_role('operator').
create or replace function public.get_workshop_configuration()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 perform public.workshop_require_planner_operator();
 return coalesce((select jsonb_object_agg(key,jsonb_build_object('value',value,'version',version,'updated_at',updated_at))
                  from public.workshop_settings),'{}'::jsonb);
end $$;
revoke all on function public.get_workshop_configuration() from public,anon;
grant execute on function public.get_workshop_configuration() to authenticated,service_role;

create or replace function public.list_workshop_bays(p_include_inactive boolean default false)
returns setof public.workshop_bays language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 perform public.workshop_require_planner_operator();
 if p_include_inactive then return query select * from public.workshop_bays order by bay_number;
 else return query select * from public.workshop_bays where is_active order by bay_number; end if;
end $$;
revoke all on function public.list_workshop_bays(boolean) from public,anon;
grant execute on function public.list_workshop_bays(boolean) to authenticated,service_role;

create or replace function public.list_technicians(p_include_inactive boolean default false)
returns setof public.workshop_technicians language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 perform public.workshop_require_planner_operator();
 if p_include_inactive then return query select * from public.workshop_technicians order by sort_order,name;
 else return query select * from public.workshop_technicians where active order by sort_order,name; end if;
end $$;
revoke all on function public.list_technicians(boolean) from public,anon;
grant execute on function public.list_technicians(boolean) to authenticated,service_role;

create or replace function public.workshop_current_revision()
returns bigint language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 perform public.workshop_require_planner_operator();
 return (select revision from public.workshop_revision where id=1);
end $$;
revoke all on function public.workshop_current_revision() from public,anon;
grant execute on function public.workshop_current_revision() to authenticated,service_role;

-- Replace the permissive hierarchical-role workshop read graph. Every direct
-- workshop table is operator/administrator only; importers retain their approved
-- SECURITY DEFINER Navision RPCs, not direct planner-table or Realtime access.
do $$
declare v_table text; v_policy record;
begin
 foreach v_table in array array[
  'vehicles','vehicle_aliases','vehicle_master_revision','vehicle_lifecycle_resolver_revision',
  'vehicle_master_source_records','vehicle_master_operation_receipts','vehicle_master_history','vehicle_master_identity_conflicts',
  'vehicle_movements','vehicle_parts_updates','vehicle_eta_history','vehicle_timeline_events',
  'vehicle_intelligence_revisions','vehicle_intelligence_summaries','vehicle_match_candidates','deleted_completed_vehicles',
  'vehicle_notifications','vehicle_work_items','workshop_bays','workshop_booking_assignments',
  'workshop_booking_history','workshop_bookings','workshop_parts_overrides',
  'workshop_revision','workshop_settings','workshop_stages',
  'workshop_technicians','workshop_station_revision','workshop_stage_aliases'
 ] loop
  for v_policy in select policyname from pg_policies
   where schemaname='public' and tablename=v_table
  loop execute format('drop policy if exists %I on public.%I',v_policy.policyname,v_table); end loop;
  execute format('create policy %I on public.%I for select to authenticated using (public.workshop_is_planner_operator())',
   v_table||'_planner_operator_select',v_table);
  execute format('grant select on public.%I to authenticated',v_table);
  execute format('revoke insert,update,delete on public.%I from public,anon,authenticated',v_table);
 end loop;
end $$;

-- AI intake/review, audit, reference and importer-backed source rows are
-- workflow authority, not importer scratch space. Preserve operator/admin
-- read/Realtime filtering while removing every direct importer read/write
-- policy; mutations remain available only through guarded narrow RPCs.
do $$
declare v_table text; v_policy record;
begin
 foreach v_table in array array[
  'ai_email_analysis_results','ai_email_attachments','ai_email_intake','ai_extracted_fields',
  'ai_intake_config','ai_mapping_rules','ai_proposed_actions','ai_review_items',
  'ai_trusted_senders','ai_undo_actions','ai_workshop_commands',
  'monitored_mailboxes','email_response_drafts','audit_events','import_runs','label_print_events',
  'salespeople','sublet_providers','navision_backend_revision','navision_import_batches',
  'navision_backend_records','navision_import_items','navision_operation_receipts',
  'navision_rollback_items','navision_backend_audit'
 ] loop
  for v_policy in select policyname from pg_policies
   where schemaname='public' and tablename=v_table
  loop execute format('drop policy if exists %I on public.%I',v_policy.policyname,v_table); end loop;
  execute format('create policy %I on public.%I for select to authenticated using (public.workshop_is_planner_operator())',
   v_table||'_planner_operator_select',v_table);
  execute format('grant select on public.%I to authenticated',v_table);
  execute format('revoke insert,update,delete on public.%I from public,anon,authenticated',v_table);
 end loop;
end $$;

-- Source email attachments are ingested by trusted backend code. Importer has
-- no direct storage-object read authority.
drop policy if exists pdc_email_attachments_read_importer on storage.objects;

-- Direct low-level booking operations must never bypass the audited high-level layer.
revoke execute on function public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_resize_booking(uuid,integer,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_reassign_booking(uuid,integer,uuid,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_start_booking(uuid,integer,timestamptz,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_record_stoppage(uuid,integer,text,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_resume_booking(uuid,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_return_booking_to_queue(uuid,integer,text,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_delete_booking(uuid,integer,text,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_restore_booking(uuid,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.workshop_complete_booking(uuid,integer,timestamptz,jsonb) from public,anon,authenticated;

-- Defence in depth for every current/legacy booking mutation path. The narrow
-- nested ETA-risk maintenance shape is retained for approved Navision ETA imports.
create or replace function public.workshop_require_planner_booking_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_stage_id uuid; v_stage_code text; v_planner_enabled boolean;
begin
 if auth.uid() is not null then
  if tg_op='UPDATE' and pg_trigger_depth()>1
     and (to_jsonb(new)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by'])
         is not distinct from
         (to_jsonb(old)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by']) then
   return new;
  end if;
  perform public.workshop_require_planner_operator();
 end if;
 v_stage_id:=case when tg_op='DELETE' then old.stage_id else new.stage_id end;
 select s.code,coalesce(s.planner_enabled,false) into v_stage_code,v_planner_enabled
 from public.workshop_stages s where s.id=v_stage_id;
 if coalesce(v_planner_enabled,false)=false then
  if tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed'
     and (to_jsonb(new)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version'])
         is not distinct from
         (to_jsonb(old)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version']) then
   return new;
  end if;
  raise exception 'planner_disabled stage=%',coalesce(v_stage_code,'unknown') using errcode='22023';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function public.workshop_require_planner_booking_mutation() from public,anon,authenticated;
drop trigger if exists workshop_bookings_require_planner_operator on public.workshop_bookings;
create trigger workshop_bookings_require_planner_operator before insert or update or delete on public.workshop_bookings
for each row execute function public.workshop_require_planner_booking_mutation();

create or replace function public.workshop_require_planner_assignment_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if auth.uid() is not null then perform public.workshop_require_planner_operator(); end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
revoke all on function public.workshop_require_planner_assignment_mutation() from public,anon,authenticated;
drop trigger if exists workshop_assignments_require_planner_operator on public.workshop_booking_assignments;
create trigger workshop_assignments_require_planner_operator before insert or update or delete on public.workshop_booking_assignments
for each row execute function public.workshop_require_planner_assignment_mutation();

-- YH schedules immediately. Only IT is ETA-gated, and the captured ETA fields
-- are scheduling metadata rather than vehicle authority.
create or replace function public.workshop_enforce_vehicle_eta()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare v_vehicle public.vehicles%rowtype; v_location text;
begin
 select * into v_vehicle from public.vehicles where id=new.vehicle_id;
 v_location:=upper(btrim(coalesce(v_vehicle.current_location,'')));
 if v_location='IT' then
  if v_vehicle.eta_to_kewdale is null then raise exception 'missing_or_invalid_eta' using errcode='23514'; end if;
  if (new.scheduled_start_at at time zone 'Australia/Perth')::date<v_vehicle.eta_to_kewdale then
   raise exception 'booking_before_eta earliest_permitted_date=%',v_vehicle.eta_to_kewdale using errcode='23514';
  end if;
  new.eta_at_booking:=v_vehicle.eta_to_kewdale; new.eta_risk_status:='none'; new.eta_risk_detected_at:=null;
 else
  new.eta_at_booking:=null; new.eta_risk_status:='none'; new.eta_risk_detected_at:=null;
 end if;
 return new;
end $$;
revoke all on function public.workshop_enforce_vehicle_eta() from public,anon,authenticated;
drop trigger if exists workshop_bookings_enforce_vehicle_eta on public.workshop_bookings;
create trigger workshop_bookings_enforce_vehicle_eta before insert or update of scheduled_start_at,vehicle_id
on public.workshop_bookings for each row execute function public.workshop_enforce_vehicle_eta();

-- Every scheduling-shape mutation (create, move, resize, bay change and
-- cascade shift) revalidates the same canonical eligibility boundary used by
-- snapshots. Status-only historical completion remains possible for Sublet.
create or replace function public.workshop_prevent_disabled_planner_booking_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_enabled boolean; v_mutating boolean; v_location text; v_eta date; v_stage text; v_eligible boolean;
begin
 if tg_op='UPDATE' and old.deleted_at is not null then
  if new.deleted_at is null and new.status='queued' and new.bay_id is null
     and new.stage_id=old.stage_id and new.vehicle_id=old.vehicle_id
     and new.scheduled_start_at is not distinct from old.scheduled_start_at
     and new.scheduled_end_at is not distinct from old.scheduled_end_at
     and new.default_duration_minutes is not distinct from old.default_duration_minutes then
   return new;
  end if;
  raise exception 'Soft-deleted Workshop Planner bookings cannot be scheduled or cascaded' using errcode='22023';
 end if;
 v_mutating:=tg_op='INSERT';
 if tg_op='UPDATE' then
  v_mutating:=old.stage_id is distinct from new.stage_id
   or old.bay_id is distinct from new.bay_id
   or old.scheduled_start_at is distinct from new.scheduled_start_at
   or old.scheduled_end_at is distinct from new.scheduled_end_at
   or old.default_duration_minutes is distinct from new.default_duration_minutes;
 end if;
 if v_mutating then
  select code,planner_enabled into v_stage,v_enabled from public.workshop_stages where id=new.stage_id and active;
  if not found or coalesce(v_enabled,false)=false then
   raise exception 'This work type does not have a Workshop Planner' using errcode='22023';
  end if;
  select upper(btrim(coalesce(current_location,''))),eta_to_kewdale into v_location,v_eta
  from public.vehicles where id=new.vehicle_id and lifecycle_state='active' and deleted_at is null;
  if not found then
   raise exception 'Active non-deleted vehicle is required for Workshop Planner scheduling' using errcode='22023';
  end if;
  if tg_op='UPDATE' and old.stage_id=new.stage_id and old.vehicle_id=new.vehicle_id
     and old.deleted_at is null and old.status in('queued','planned','started','stoppage') then
   v_eligible:=true;
  else
   select exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=new.vehicle_id
    and wi.required and not wi.completed and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage) into v_eligible;
  end if;
  if not coalesce(v_eligible,false) then
   raise exception 'Vehicle is not eligible for target Workshop Planner station' using errcode='22023';
  end if;
  if v_location not in('PMB','YH','IT') then
   raise exception 'Vehicle location is not eligible for Workshop Planner scheduling' using errcode='22023';
  end if;
  if v_location='IT' and v_eta is null then
   raise exception 'ETA to Kewdale is required before scheduling an in-transit vehicle' using errcode='22023';
  end if;
  if v_location='IT' and (new.scheduled_start_at at time zone 'Australia/Perth')::date<v_eta then
   raise exception 'In-transit vehicle cannot be scheduled before ETA to Kewdale' using errcode='22023';
  end if;
 end if;
 return new;
end $$;
revoke all on function public.workshop_prevent_disabled_planner_booking_mutation() from public,anon,authenticated;
drop trigger if exists workshop_bookings_planner_enabled_guard on public.workshop_bookings;
create trigger workshop_bookings_planner_enabled_guard before insert or update on public.workshop_bookings
for each row execute function public.workshop_prevent_disabled_planner_booking_mutation();

-- Rebuild the canonical relation so soft-deleted active-looking bookings can
-- never re-enter station or aggregate authority through migration-042 logic.
create or replace function public.workshop_station_eligibility(p_stage_code text)
returns table(vehicle_id uuid,stage_code text,work_key text,current_location text,
 eta_to_kewdale date,existing_booking boolean,schedule_enabled boolean,disabled_reason text)
language sql stable security definer set search_path=pg_catalog,public as $$
 with station as(
  select s.code,s.work_key from public.workshop_stages s
  where s.code=public.workshop_canonical_stage_code(p_stage_code) and s.active and s.planner_enabled
 ), outstanding as(
  select wi.vehicle_id,st.code,st.work_key from public.vehicle_work_items wi cross join station st
  where public.workshop_stage_code_for_work_key(wi.work_key)=st.code and wi.required and not wi.completed
  group by wi.vehicle_id,st.code,st.work_key
 ), active_booking as(
  select distinct b.vehicle_id,st.code,st.work_key from public.workshop_bookings b
  join public.workshop_stages s on s.id=b.stage_id join station st on st.code=s.code
  where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
 ), scoped as(select * from outstanding union select * from active_booking)
 select v.id,sc.code,sc.work_key,upper(btrim(coalesce(v.current_location,''))),v.eta_to_kewdale,
  (ab.vehicle_id is not null),
  case when upper(btrim(coalesce(v.current_location,''))) in('PMB','YH') then true
       when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is not null then true else false end,
  case when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is null then 'missing_eta'
       when upper(btrim(coalesce(v.current_location,''))) not in('PMB','YH','IT') and ab.vehicle_id is not null then 'existing_booking_location_review'
       when upper(btrim(coalesce(v.current_location,''))) not in('PMB','YH','IT') then 'location_ineligible' else null end
 from scoped sc join public.vehicles v on v.id=sc.vehicle_id
 left join active_booking ab on ab.vehicle_id=v.id and ab.code=sc.code
 where v.lifecycle_state='active' and v.deleted_at is null
  and(upper(btrim(coalesce(v.current_location,''))) in('PMB','YH','IT') or ab.vehicle_id is not null)
$$;
revoke all on function public.workshop_station_eligibility(text) from public,anon,authenticated;

-- Booking DTO: explicit reviewed projection only. No customer, notes, audit,
-- deletion reason, metadata, full rows or future columns can leak.
create or replace function public.workshop_planner_booking_dto(p_booking_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public as $$
 with aa as(
  select a.booking_id,a.technician_id,t.name technician_name,a.assignment_type
  from public.workshop_booking_assignments a join public.workshop_technicians t on t.id=a.technician_id
  where a.booking_id=p_booking_id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1)
 select jsonb_build_object(
  'booking_id',b.id,'vehicle_id',b.vehicle_id,
  'stage',jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key),
  'bay',case when bay.id is null then null else jsonb_build_object('id',bay.id,'bay_number',bay.bay_number,'code',bay.code,'display_name',bay.display_name) end,
  'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
  'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,
  'actual_end_at',b.actual_end_at,
  'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
  'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,'version',b.version,
  'assignment',case when aa.technician_id is null then null else jsonb_build_object(
    'technician_id',aa.technician_id,'technician_name',aa.technician_name,'assignment_type',aa.assignment_type) end)
 from public.workshop_bookings b
 join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
 join public.workshop_stages s on s.id=b.stage_id
 left join public.workshop_bays bay on bay.id=b.bay_id
 left join aa on aa.booking_id=b.id where b.id=p_booking_id and b.deleted_at is null
$$;
revoke all on function public.workshop_planner_booking_dto(uuid) from public,anon,authenticated;
comment on function public.workshop_planner_booking_dto(uuid) is
 'Minimal planner booking DTO. Explicit projection; excludes customer, notes, audit, metadata and deletion payloads.';

create or replace function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_ids uuid[];
begin
 perform public.workshop_require_planner_operator();
 v_stage:=public.workshop_canonical_stage_code(p_stage_code);
 select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
 if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
 if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then
  raise exception 'Invalid station planner date range' using errcode='22023'; end if;
 v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
 v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
 select coalesce(array_agg(distinct q.vehicle_id),'{}'::uuid[]) into v_ids from(
  select e.vehicle_id from public.workshop_station_eligibility(v_stage)e
   where exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=e.vehicle_id and wi.required and not wi.completed
    and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage)
  union
  select b.vehicle_id from public.workshop_bookings b
   join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and ((b.status in('queued','planned','started','stoppage') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))
 )q;
 return jsonb_build_object(
  'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
  'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
  'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,
   'is_physical',s.is_physical,'work_key',s.work_key)) from public.workshop_stages s where s.id=v_stage_id),
  'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,
   'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb)
   from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
  'bookings',(select coalesce(jsonb_agg(public.workshop_planner_booking_dto(b.id) order by b.scheduled_start_at,b.id),'[]'::jsonb)
   from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where b.stage_id=v_stage_id and b.vehicle_id=any(v_ids) and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and ((b.status in('queued','planned','started','stoppage') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
   'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
   'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
   'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,
   'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
   'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,
   'workshop_status',v.workshop_status,'version',v.version) order by v.stock_number nulls last,v.id),'[]'::jsonb)
   from public.vehicles v where v.id=any(v_ids) and v.lifecycle_state='active' and v.deleted_at is null),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
   'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.vehicle_id,wi.work_key),'[]'::jsonb)
   from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids)
    and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage)
 );
end $$;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated;
comment on function public.get_station_workshop_snapshot(text,date,date) is
 'Operator/admin-only minimal station DTO. Vehicle/work-item/booking collections share one active, non-deleted, station/date-scoped vehicle set. Sublet rejected.';

create or replace function public.get_workshop_eligibility_snapshot()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 perform public.workshop_require_planner_operator();
 return jsonb_build_object('generated_at',now(),
  'stages',(select coalesce(jsonb_agg(jsonb_build_object('code',s.code,'display_name',s.display_name,
   'work_key',s.work_key,'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
   'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb)
    from public.workshop_stage_aliases a where a.stage_code=s.code)) order by s.sort_order),'[]'::jsonb)
   from public.workshop_stages s where s.active and s.planner_enabled),
  'candidates',(select coalesce(jsonb_agg(jsonb_build_object('stage_code',e.stage_code,'work_key',e.work_key,
   'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
   'vehicle',jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
    'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'make',v.make,'model',v.model,
    'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,
    'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
    'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
   'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
    'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
    from public.vehicle_work_items wi where wi.vehicle_id=v.id
     and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code))
   order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
   from public.workshop_stages s cross join lateral public.workshop_station_eligibility(s.code)e
   join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where s.code=e.stage_code and s.active and s.planner_enabled));
end $$;
revoke all on function public.get_workshop_eligibility_snapshot() from public,anon,authenticated;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated;
comment on function public.get_workshop_eligibility_snapshot() is
 'Operator/admin-only minimal all-station eligibility DTO. Explicit vehicle/work-item projection; no customer or audit payloads.';

-- Scheduling wrappers below may change booking, booking history/audit and revision
-- records only. They never update vehicle location, pmb_stage, visibility,
-- workflow state or requirement completion.
create or replace function public.workshop_require_booking_active_vehicle(p_booking_id uuid,p_allow_deleted_booking boolean default false)
returns void language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 if not exists(select 1 from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
  where b.id=p_booking_id and (p_allow_deleted_booking or b.deleted_at is null)
   and v.lifecycle_state='active' and v.deleted_at is null) then
  raise exception 'Active non-deleted vehicle and authorized booking are required' using errcode='22023';
 end if;
end $$;
revoke all on function public.workshop_require_booking_active_vehicle(uuid,boolean) from public,anon,authenticated;

create or replace function public.workshop_require_booking_restore_eligibility(p_booking_id uuid)
returns void language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_vehicle_id uuid; v_stage_code text; v_location text; v_eta date;
begin
 select b.vehicle_id,s.code,upper(btrim(coalesce(v.current_location,''))),v.eta_to_kewdale
  into v_vehicle_id,v_stage_code,v_location,v_eta
 from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
 join public.workshop_stages s on s.id=b.stage_id
 where b.id=p_booking_id and b.deleted_at is not null
  and v.lifecycle_state='active' and v.deleted_at is null and s.active and s.planner_enabled;
 if not found then
  raise exception 'Deleted booking, active vehicle and enabled planner station are required for restore' using errcode='22023';
 end if;
 if not (v_location in('PMB','YH') or (v_location='IT' and v_eta is not null)) then
  raise exception 'Vehicle location is not eligible for Workshop Planner restore' using errcode='22023';
 end if;
 if not exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=v_vehicle_id
  and wi.required and not wi.completed and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage_code) then
  raise exception 'Outstanding station requirement is required for Workshop Planner restore' using errcode='22023';
 end if;
end $$;
revoke all on function public.workshop_require_booking_restore_eligibility(uuid) from public,anon,authenticated;

create or replace function public.workshop_require_booking_schedule_eligibility(p_booking_id uuid,p_target_stage_code text default null)
returns void language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_booking public.workshop_bookings%rowtype; v_current text; v_target text;
begin
 select b.* into v_booking from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id
  where b.id=p_booking_id and b.deleted_at is null and v.lifecycle_state='active' and v.deleted_at is null;
 if not found then raise exception 'Active non-deleted vehicle and booking are required for scheduling' using errcode='22023'; end if;
 select code into v_current from public.workshop_stages where id=v_booking.stage_id;
 v_target:=public.workshop_canonical_stage_code(coalesce(p_target_stage_code,v_current));
 if not exists(select 1 from public.workshop_stages where code=v_target and active and planner_enabled) then
  raise exception 'Unknown or planner-disabled workshop station' using errcode='22023';
 end if;
 if v_target is distinct from v_current and not exists(
  select 1 from public.vehicle_work_items wi where wi.vehicle_id=v_booking.vehicle_id and wi.required and not wi.completed
   and public.workshop_stage_code_for_work_key(wi.work_key)=v_target) then
  raise exception 'Vehicle is not eligible for target Workshop Planner station' using errcode='22023';
 end if;
end $$;
revoke all on function public.workshop_require_booking_schedule_eligibility(uuid,text) from public,anon,authenticated;

create or replace function public.schedule_vehicle_work(
 p_vehicle_id uuid,p_vehicle_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer default 180,p_technician_id uuid default null,
 p_override_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare v_vehicle public.vehicles%rowtype; v_stage public.workshop_stages%rowtype; v_result jsonb; v_override_id uuid; v_revision bigint; v_code text;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_vehicle_expected_version);
 select * into v_vehicle from public.vehicles where id=p_vehicle_id for update;
 if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
 if v_vehicle.version<>p_vehicle_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
 v_code:=public.workshop_canonical_stage_code(p_stage_code);
 select * into v_stage from public.workshop_stages where code=v_code and active and planner_enabled;
 if not found then raise exception 'Unknown or planner-disabled workshop station' using errcode='22023'; end if;
 if not exists(select 1 from public.workshop_station_eligibility(v_code)e where e.vehicle_id=p_vehicle_id) then
  return jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station');
 end if;
 if v_stage.is_physical and not public.workshop_parts_ready(p_vehicle_id) then
  if p_override_reason is null or btrim(p_override_reason)='' then return jsonb_build_object('ok',false,'error','parts_incomplete'); end if;
  perform public.require_pdc_role('administrator');
 end if;
 v_result:=public.workshop_create_booking(p_vehicle_id,v_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 if p_override_reason is not null and btrim(p_override_reason)<>'' then
  insert into public.workshop_parts_overrides(vehicle_id,booking_id,work_key,intended_stage_id,reason,previous_state,resulting_state,approved_by,approved_by_email)
  values(p_vehicle_id,(v_result->'booking'->>'booking_id')::uuid,'PARTS',v_stage.id,btrim(p_override_reason),
   jsonb_build_object('vehicle_id',p_vehicle_id,'version',v_vehicle.version),
   jsonb_build_object('vehicle_id',p_vehicle_id,'version',v_vehicle.version),auth.uid(),public.current_actor_email()) returning id into v_override_id;
 end if;
 v_revision:=public.workshop_bump_revision();
 return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end $$;

create or replace function public.move_workshop_booking(
 p_booking_id uuid,p_expected_version integer,p_stage_code text,p_bay_number integer,p_scheduled_start_at timestamptz,
 p_duration_minutes integer default null,p_override_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare v_before public.workshop_bookings%rowtype; v_stage public.workshop_stages%rowtype; v_result jsonb; v_override_id uuid; v_revision bigint; v_code text;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 select * into v_before from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 v_code:=public.workshop_canonical_stage_code(p_stage_code);
 perform public.workshop_require_booking_schedule_eligibility(p_booking_id,v_code);
 select * into v_stage from public.workshop_stages where code=v_code and active and planner_enabled;
 if not found then raise exception 'Unknown or planner-disabled workshop station' using errcode='22023'; end if;
 if v_stage.is_physical and not public.workshop_parts_ready(v_before.vehicle_id) then
  if p_override_reason is null or btrim(p_override_reason)='' then return jsonb_build_object('ok',false,'error','parts_incomplete'); end if;
  perform public.require_pdc_role('administrator');
 end if;
 v_result:=public.workshop_move_booking(p_booking_id,p_expected_version,v_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 if p_override_reason is not null and btrim(p_override_reason)<>'' then
  insert into public.workshop_parts_overrides(vehicle_id,booking_id,work_key,intended_stage_id,reason,previous_state,resulting_state,approved_by,approved_by_email)
  values(v_before.vehicle_id,p_booking_id,'PARTS',v_stage.id,btrim(p_override_reason),
   jsonb_build_object('booking_id',v_before.id,'version',v_before.version),v_result->'booking',auth.uid(),public.current_actor_email()) returning id into v_override_id;
 end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end $$;

create or replace function public.resize_workshop_booking(p_booking_id uuid,p_expected_version integer,p_duration_minutes integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_schedule_eligibility(p_booking_id,null);
 v_result:=public.workshop_resize_booking(p_booking_id,p_expected_version,p_duration_minutes,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.change_booking_bay(p_booking_id uuid,p_expected_version integer,p_bay_number integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_booking public.workshop_bookings%rowtype; v_code text; v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 select * into v_booking from public.workshop_bookings where id=p_booking_id;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 perform public.workshop_require_booking_schedule_eligibility(p_booking_id,null);
 select code into v_code from public.workshop_stages where id=v_booking.stage_id and planner_enabled;
 v_result:=public.workshop_move_booking(p_booking_id,p_expected_version,v_code,p_bay_number,v_booking.scheduled_start_at,v_booking.default_duration_minutes,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.assign_booking_technician(p_booking_id uuid,p_expected_version integer,p_technician_id uuid,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 v_result:=public.workshop_reassign_booking(p_booking_id,p_expected_version,p_technician_id,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.start_workshop_work(p_booking_id uuid,p_expected_version integer,p_actual_start_at timestamptz default now(),p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 v_result:=public.workshop_start_booking(p_booking_id,p_expected_version,p_actual_start_at,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.stop_workshop_work(p_booking_id uuid,p_expected_version integer,p_reason text,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 v_result:=public.workshop_record_stoppage(p_booking_id,p_expected_version,p_reason,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.complete_workshop_work(p_booking_id uuid,p_expected_version integer,p_work_key text default null,p_actual_end_at timestamptz default now(),p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_booking public.workshop_bookings%rowtype; v_stage_code text; v_requested_stage text; v_result jsonb; v_revision bigint;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 select code into v_stage_code from public.workshop_stages where id=v_booking.stage_id;
 if p_work_key is not null and btrim(p_work_key)<>'' then
  v_requested_stage:=public.workshop_stage_code_for_work_key(p_work_key);
  if v_requested_stage is distinct from v_stage_code then
   raise exception 'Completion work item does not match booking station' using errcode='22023';
  end if;
 end if;
 v_result:=public.workshop_complete_booking(p_booking_id,p_expected_version,p_actual_end_at,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision();
 return v_result||jsonb_build_object('revision',v_revision);
end $$;

create or replace function public.return_completed_work(p_booking_id uuid,p_expected_version integer,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 v_result:=public.workshop_return_booking_to_queue(p_booking_id,p_expected_version,p_reason,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.return_work_to_queue(p_booking_id uuid,p_expected_version integer,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 v_result:=public.workshop_return_booking_to_queue(p_booking_id,p_expected_version,p_reason,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.cancel_workshop_booking(p_booking_id uuid,p_expected_version integer,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 v_result:=public.workshop_delete_booking(p_booking_id,p_expected_version,p_reason,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

create or replace function public.restore_workshop_booking(p_booking_id uuid,p_expected_version integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_result jsonb; v_revision bigint; begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,true);
 perform public.workshop_require_booking_restore_eligibility(p_booking_id);
 v_result:=public.workshop_restore_booking(p_booking_id,p_expected_version,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision); end $$;

-- Resume retains conflict-safe rescheduling from migration 010 but never updates vehicles.
create or replace function public.resume_workshop_work(p_booking_id uuid,p_expected_version integer,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_booking public.workshop_bookings%rowtype; v_technician_id uuid; v_conflict_id uuid; v_now timestamptz:=now();
 v_new_start timestamptz; v_new_end timestamptz; v_remaining_minutes integer; v_elapsed_minutes integer; v_result jsonb; v_revision bigint;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
 select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 if v_booking.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
 if v_booking.status<>'stoppage' then return jsonb_build_object('ok',false,'error','not_stopped'); end if;
 v_elapsed_minutes:=greatest(0,floor(extract(epoch from(coalesce(v_booking.stoppage_started_at,v_now)-v_booking.scheduled_start_at))/60.0)::integer)-coalesce(v_booking.stoppage_accumulated_minutes,0);
 v_remaining_minutes:=greatest(15,v_booking.default_duration_minutes-greatest(0,v_elapsed_minutes));
 v_new_start:=public.workshop_normalize_start_date(v_now); v_new_end:=v_new_start+make_interval(mins=>v_remaining_minutes);
 select technician_id into v_technician_id from public.workshop_booking_assignments where booking_id=p_booking_id and released_at is null
 order by case when assignment_type='primary' then 0 else 1 end,assigned_at desc limit 1;
 perform public.workshop_lock_resources(v_booking.bay_id,v_technician_id);
 v_conflict_id:=public.workshop_find_bay_conflict(p_booking_id,v_booking.bay_id,v_new_start,v_new_end);
 if v_conflict_id is not null then return jsonb_build_object('ok',false,'error','bay_overlap','conflict',public.workshop_conflict_payload(v_conflict_id,'bay_overlap')); end if;
 if v_technician_id is not null then
  v_conflict_id:=public.workshop_find_technician_conflict(p_booking_id,v_technician_id,v_new_start,v_new_end);
  if v_conflict_id is not null then return jsonb_build_object('ok',false,'error','technician_overlap','conflict',public.workshop_conflict_payload(v_conflict_id,'technician_overlap')); end if;
 end if;
 update public.workshop_bookings set scheduled_start_at=v_new_start,scheduled_end_at=v_new_end,updated_by=auth.uid(),version=version+1 where id=p_booking_id;
 perform public.workshop_upsert_primary_assignment(p_booking_id,v_technician_id,v_new_start,v_new_end,'resume_rescheduled');
 v_result:=public.workshop_resume_booking(p_booking_id,v_booking.version+1,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('revision',v_revision);
end $$;

-- High-level browser RPCs remain callable by authenticated JWTs but enforce the
-- exact operator/admin role internally; importers/viewers/anonymous are denied.
do $$
declare v_sig regprocedure;
begin
 foreach v_sig in array array[
  'public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'::regprocedure,
  'public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure,
  'public.resize_workshop_booking(uuid,integer,integer,jsonb)'::regprocedure,
  'public.change_booking_bay(uuid,integer,integer,jsonb)'::regprocedure,
  'public.assign_booking_technician(uuid,integer,uuid,jsonb)'::regprocedure,
  'public.start_workshop_work(uuid,integer,timestamptz,jsonb)'::regprocedure,
  'public.stop_workshop_work(uuid,integer,text,jsonb)'::regprocedure,
  'public.resume_workshop_work(uuid,integer,jsonb)'::regprocedure,
  'public.return_completed_work(uuid,integer,text,jsonb)'::regprocedure,
  'public.return_work_to_queue(uuid,integer,text,jsonb)'::regprocedure,
  'public.cancel_workshop_booking(uuid,integer,text,jsonb)'::regprocedure,
  'public.restore_workshop_booking(uuid,integer,jsonb)'::regprocedure,
  'public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb)'::regprocedure,
  'public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)'::regprocedure
 ] loop execute format('revoke all on function %s from public,anon',v_sig); execute format('grant execute on function %s to authenticated',v_sig); end loop;
end $$;

-- Existing revision rows include a station being disabled/deleted; bump them
-- before adding new station rows so stale subscribers always refetch.
create or replace function public.workshop_bump_all_station_revisions()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 update public.workshop_station_revision set revision=revision+1,updated_at=now();
 insert into public.workshop_station_revision(stage_code,revision,updated_at)
 select code,1,now() from public.workshop_stages on conflict(stage_code) do nothing;
 return null;
end $$;
revoke all on function public.workshop_bump_all_station_revisions() from public,anon,authenticated;
do $$ declare v_table text; begin
 foreach v_table in array array['workshop_stages','workshop_stage_aliases','workshop_bays','workshop_technicians','workshop_settings'] loop
  execute format('drop trigger if exists %I on public.%I','workshop_all_station_revision_config',v_table);
  execute format('create trigger %I after insert or update or delete on public.%I for each statement execute function public.workshop_bump_all_station_revisions()','workshop_all_station_revision_config',v_table);
 end loop;
end $$;
select public.workshop_bump_revision();
insert into public.workshop_station_revision(stage_code,revision,updated_at)
select code,1,now() from public.workshop_stages where active and planner_enabled
on conflict(stage_code) do update set revision=public.workshop_station_revision.revision+1,updated_at=now();
