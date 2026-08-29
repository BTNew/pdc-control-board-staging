-- STAGING ONLY 784: complete Stage-A projections and bounded history.
-- Workflow events are returned in a deterministic bounded page of 500, with
-- completeness metadata; VIN, top-level Job Card and canonical Sublet instance
-- evidence are explicit confirmed/unknown projections. No inference or writes.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-784-stage-a-integrity-projection',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830180000,783_historical_observation_digest_repair)'
    OR to_regprocedure('public.get_pdc_auditor_snapshot(uuid,integer)') IS NULL
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830181000')
 THEN RAISE EXCEPTION 'PDC_784_CURRENT_HEAD_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;
create or replace function public.get_pdc_auditor_snapshot(
  p_after_vehicle_id uuid default null,
  p_page_size integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $snapshot$
declare
  v_scope jsonb := public.pdc_auditor_actor_scope();
  v_dealer text := v_scope->>'dealer_code';
  v_limit integer;
  v_items jsonb;
  v_has_more boolean;
  v_next uuid;
  v_workshop_revision bigint;
  v_email_revision bigint;
  v_auditor_revision bigint;
  v_relation_revision bigint;
  v_config_revision bigint;
  v_operational_revision text;
  v_rule_set_hash text;
  v_response_revision text;
  v_configs jsonb;
  v_calendar_config jsonb;
  v_resources jsonb;
  v_total_vehicle_count integer;
  v_page_item_count integer;
begin
  if p_page_size is null or p_page_size < 1 or p_page_size > 100 then
    raise exception 'pdc_auditor_invalid_page_size' using errcode='22023';
  end if;
  v_limit := p_page_size;

  select coalesce(revision,0) into v_workshop_revision from public.workshop_revision where id=1;
  select coalesce(revision,0) into v_email_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(max(revision_id),0) into v_auditor_revision
    from public.pdc_auditor_revision where dealer_code=v_dealer and environment='staging';
  select coalesce((('x'||substr(encode(extensions.digest(convert_to(coalesce(string_agg(
      concat_ws(':',relation_id::text,booking_id::text,work_item_id::text,relation_kind,relation_action,
        source_revision::text,extract(epoch from source_recorded_at)::text,active::text,coalesce(supersedes_relation_id::text,'')),
      '|' order by relation_id),''),'UTF8'),'sha256'),'hex'),1,13))::bit(52)::bigint),0)
    into v_relation_revision
  from public.pdc_auditor_booking_work_relations where dealer_code=v_dealer and environment='staging';
  select coalesce(max(config_version),0) into v_config_revision
    from public.pdc_auditor_rule_config where dealer_code=v_dealer and environment='staging';
  v_operational_revision := public.pdc_auditor_operational_revision(v_dealer);
  select md5('pdc-auditor-rules-v1a|'||coalesce(string_agg(c.rule_key||':'||c.config_version||':'||md5(c.config::text),'|' order by c.rule_key,c.config_version),''))
      ||md5('pdc-auditor-rules-v1b|'||coalesce(string_agg(c.rule_key||':'||c.config_version||':'||md5(c.config::text),'|' order by c.rule_key,c.config_version),''))
    into v_rule_set_hash
  from public.pdc_auditor_rule_config c
  where c.dealer_code=v_dealer and c.environment='staging'
    and c.effective_from<=statement_timestamp()
    and (c.effective_to is null or c.effective_to>statement_timestamp());
  v_response_revision := md5(concat_ws('|','pdc-auditor-snapshot-v2a',v_dealer,
    v_workshop_revision,v_email_revision,v_auditor_revision,v_relation_revision,v_config_revision,v_operational_revision,v_rule_set_hash)) ||
    md5(concat_ws('|','pdc-auditor-snapshot-v2b',v_dealer,
    v_workshop_revision,v_email_revision,v_auditor_revision,v_relation_revision,v_config_revision,v_operational_revision,v_rule_set_hash));

  select coalesce(jsonb_agg(jsonb_build_object(
    'rule_key',c.rule_key,'config_version',c.config_version,'provisional',c.provisional,
    'effective_from',c.effective_from,'classification','confirmed',
    'parameters',case c.rule_key
      when 'station_compatibility' then jsonb_build_object(
        'mode',c.config->'mode','unknown_station_action',c.config->'unknown_station_action',
        'booking_work_link_policy',c.config->'booking_work_link_policy',
        'allowed_pairs',coalesce(c.config->'allowed_pairs','[]'::jsonb))
      when 'department_mismatch_thresholds' then jsonb_build_object(
        'status',c.config->'status','minimum_sample_size',c.config->'minimum_sample_size',
        'warning_ratio',c.config->'warning_ratio','high_ratio',c.config->'high_ratio','action',c.config->'action')
      when 'risk_weights' then jsonb_build_object('versioned',true)
      when 'working_calendar' then jsonb_build_object('versioned',true)
      else '{}'::jsonb end
  ) order by c.rule_key),'[]'::jsonb) into v_configs
  from public.pdc_auditor_rule_config c
  where c.dealer_code=v_dealer and c.environment='staging'
    and c.effective_from<=statement_timestamp()
    and (c.effective_to is null or c.effective_to>statement_timestamp())
    and not exists(select 1 from public.pdc_auditor_rule_config newer
      where newer.dealer_code=c.dealer_code and newer.environment=c.environment
        and newer.rule_key=c.rule_key and newer.effective_from<=statement_timestamp()
        and (newer.effective_to is null or newer.effective_to>statement_timestamp())
        and (newer.config_version,newer.rule_config_id)>(c.config_version,c.rule_config_id));

  select c.config into v_calendar_config
  from public.pdc_auditor_rule_config c
  where c.dealer_code=v_dealer and c.environment='staging' and c.rule_key='working_calendar'
    and c.effective_from<=statement_timestamp()
    and (c.effective_to is null or c.effective_to>statement_timestamp())
  order by c.config_version desc,c.rule_config_id desc limit 1;

  select coalesce(jsonb_agg(resource order by resource->>'resource_type',resource->>'code'),'[]'::jsonb)
    into v_resources
  from (
    (select jsonb_build_object('resource_type','stage','resource_id',s.id,'code',left(s.code,40),
      'active',s.active,'is_physical',s.is_physical,'is_sublet',s.is_sublet,'classification','confirmed') resource
     from public.workshop_stages s order by s.code limit 100)
    union all
    (select jsonb_build_object('resource_type','bay','resource_id',b.id,'code',left(b.code,40),
      'stage_id',b.stage_id,'active',b.is_active,'is_sublet',b.is_sublet_row,'classification','confirmed')
     from public.workshop_bays b order by b.code limit 100)
    union all
    (select jsonb_build_object('resource_type','technician','resource_id',t.id,'code',t.id::text,
      'active',t.active,'role_type',left(t.role_type,32),'compatible_stage_codes',to_jsonb(t.can_fit_stages),
      'classification','confirmed')
     from public.workshop_technicians t order by t.id limit 100)
  ) resources;
  select count(*) into v_total_vehicle_count from public.vehicles v
  where v.deleted_at is null and public.pdc_auditor_vehicle_dealer(v.id)=v_dealer;

  with selected_vehicles as materialized (
    select v.id,v.version,v.key_number,v.stock_number,v.vin,v.job_card_number,
      coalesce(v.vehicle_description,v.model,v.make) model_label,
      v.current_location,v.pmb_stage,v.pmb_bay_stage,v.pmb_bay_number,v.eta_to_kewdale,
      v.lifecycle_state::text lifecycle_state,v.visible_on_board,v.workshop_status,
      v.workshop_status_updated_at,v.qc_completed_at,v.rft_transferred_at,v.rft_collected_at,
      v.active_workshop_booking_id,v.created_at,v.updated_at
    from public.vehicles v
    where public.pdc_auditor_vehicle_dealer(v.id)=v_dealer
      and v.deleted_at is null and (p_after_vehicle_id is null or v.id>p_after_vehicle_id)
    order by v.id limit v_limit+1
  ), page as materialized (select * from selected_vehicles order by id limit v_limit)
  select coalesce(jsonb_agg(jsonb_build_object(
    'vehicle_id',p.id,'dealer_code',v_dealer,
    'key_number',left(coalesce(p.key_number,''),80),'stock_number',left(coalesce(p.stock_number,''),80),
    'vin',jsonb_build_object('value',left(coalesce(p.vin,''),32),'classification',case when nullif(btrim(p.vin),'') is null then 'unknown' else 'confirmed' end),
    'job_card_number',jsonb_build_object('value',left(coalesce(p.job_card_number,''),80),'classification',case when nullif(btrim(p.job_card_number),'') is null then 'unknown' else 'confirmed' end),
    'model',left(coalesce(p.model_label,''),160),'vehicle_version',p.version,
    'lifecycle',jsonb_build_object(
      'state',p.lifecycle_state,'visible_on_board',p.visible_on_board,
      'created_at',p.created_at,'updated_at',p.updated_at,'classification','confirmed'),
    'workshop',jsonb_build_object(
      'status',p.workshop_status,'status_updated_at',p.workshop_status_updated_at,
      'stage_code',left(coalesce(p.pmb_stage,''),40),'bay_stage_code',left(coalesce(p.pmb_bay_stage,''),40),
      'bay_number',left(coalesce(p.pmb_bay_number,''),20),
      'active_booking_id',p.active_workshop_booking_id,'classification','confirmed'),
    'quality',jsonb_build_object(
      'qc_completed_at',p.qc_completed_at,'rft_transferred_at',p.rft_transferred_at,
      'rft_collected_at',p.rft_collected_at,
      'qc_state',case when p.qc_completed_at is null then 'incomplete' else 'completed' end,
      'rft_state',case when p.rft_collected_at is not null then 'collected'
        when p.rft_transferred_at is not null then 'transferred' else 'not_transferred' end,
      'classification','confirmed'),
    'location',jsonb_build_object('code',left(coalesce(p.current_location,''),40),'classification','confirmed'),
    'eta',jsonb_build_object('eta_to_kewdale',p.eta_to_kewdale,
      'classification',case when p.eta_to_kewdale is null then 'unknown' else 'confirmed' end),
    'work_items',coalesce((select jsonb_agg(jsonb_build_object(
      'work_item_id',wi.id,'work_key',left(wi.work_key,64),'required',wi.required,'completed',wi.completed,
      'inactive',not wi.required,'completed_at',wi.completed_at,'updated_at',wi.updated_at,
      'status',case when wi.completed then 'completed' when not wi.required then 'inactive' else 'required' end,
      'hours',jsonb_build_object(
        'confirmed_hours',coalesce(h.confirmed_hours,0),'estimated_hours',coalesce(h.estimated_hours,0),
        'unknown_hours_line_count',coalesce(h.unknown_count,0),'line_count',coalesce(h.line_count,0),
        'provenance',case when coalesce(h.line_count,0)=0 then 'unknown'
          when coalesce(h.unknown_count,0)>0 then 'mixed_or_unknown'
          when coalesce(h.estimated_hours,0)>0 and coalesce(h.confirmed_hours,0)>0 then 'mixed'
          when coalesce(h.confirmed_hours,0)>0 then 'job_card' else 'ai_estimate' end,
        'classification',case when coalesce(h.confirmed_hours,0)>0 then 'confirmed'
          when coalesce(h.estimated_hours,0)>0 then 'estimated' else 'unknown' end)
    ) order by wi.work_key,wi.id)
    from (select * from public.vehicle_work_items wi0 where wi0.vehicle_id=p.id order by wi0.work_key,wi0.id limit 100) wi
    left join lateral (select
      sum(ol.estimated_hours) filter(where ol.estimated_hours_source='job_card') confirmed_hours,
      sum(ol.estimated_hours) filter(where ol.estimated_hours_source='ai_estimate') estimated_hours,
      count(*) filter(where ol.estimated_hours is null or ol.estimated_hours_source is null) unknown_count,
      count(*) line_count
      from public.pdc_authenticated_email_operation_lines ol
      where ol.vehicle_id=wi.vehicle_id and ol.work_key=wi.work_key) h on true
    ),'[]'::jsonb),
    'bookings',coalesce((select jsonb_agg(jsonb_build_object(
      'booking_id',q.booking_id,'stage_code',q.stage_code,'status',q.status,
      'scheduled_start_at',q.scheduled_start_at,'scheduled_end_at',q.scheduled_end_at,
      'actual_start_at',q.actual_start_at,'actual_end_at',q.actual_end_at,
      'duration_minutes',q.duration_minutes,'actual_duration_minutes',q.actual_duration_minutes,
      'scheduled_duration_minutes',case when q.scheduled_start_at is null or q.scheduled_end_at is null then null else floor(extract(epoch from (q.scheduled_end_at-q.scheduled_start_at))/60)::integer end,
      'duration_semantics',case when q.actual_start_at is null or q.actual_end_at is null then 'scheduled_only' when q.actual_duration_minutes is not distinct from floor(extract(epoch from (q.actual_end_at-q.actual_start_at))/60)::integer then 'actual_matches_physical_interval' else 'source_contradiction_review' end,
      'bay_id',q.bay_id,'booking_version',q.version,
      'stoppage',jsonb_build_object('active',q.status='stoppage','started_at',q.stoppage_started_at,
        'accumulated_minutes',q.stoppage_accumulated_minutes,'classification','confirmed'),
      'assignments',q.assignments,
      'linked_work_item_id',case when q.valid_relation_count=1 and q.all_relation_count=1
          then q.work_item_id else null end,
      'relation_kind',case when q.valid_relation_count=1 and q.all_relation_count=1 then q.relation_kind else null end,
      'relation_source_revision',case when q.valid_relation_count=1 and q.all_relation_count=1 then q.source_revision else null end,
      'relationship_status',case
        when q.revoked_relation_count=1 and q.valid_relation_count=0 and q.all_relation_count=1 then 'revoked_authoritative_relation_unlinked'
        when q.all_relation_count<>q.valid_relation_count or q.valid_relation_count>1 then 'corrupt_or_ambiguous_relation_unlinked'
        when q.valid_relation_count=0 then 'legacy_no_relation_unlinked'
        when q.status not in ('queued','planned','started','stoppage') or not q.work_required or q.work_completed then 'linked_completed_or_inactive'
        when q.active_booking_count_for_work>1 then 'multiple_active_bookings_for_work_item'
        when q.relation_kind='explicit_fk' then 'explicit_linked_active'
        when q.relation_kind='authoritative_relation' then 'exact_authoritative_linked_active'
        else 'corrupt_or_ambiguous_relation_unlinked' end,
      'classification',case when q.valid_relation_count=1 and q.all_relation_count=1 then 'confirmed' else 'unknown' end
    ) order by q.scheduled_start_at,q.booking_id) from (
      select b.id booking_id,s.code stage_code,b.status::text status,b.scheduled_start_at,b.scheduled_end_at,
        b.actual_start_at,b.actual_end_at,b.default_duration_minutes duration_minutes,b.actual_duration_minutes,b.bay_id,b.version,
        b.stoppage_started_at,b.stoppage_accumulated_minutes,
        coalesce((select jsonb_agg(jsonb_build_object(
          'assignment_id',a.id,'technician_id',a.technician_id,'assignment_type',a.assignment_type,
          'scheduled_start_at',a.scheduled_start_at,'scheduled_end_at',a.scheduled_end_at,
          'released_at',a.released_at,'authority_state',case when a.released_at is null then 'active' else 'released' end,
          'classification','confirmed') order by a.scheduled_start_at,a.id)
          from (select * from public.workshop_booking_assignments a0 where a0.booking_id=b.id
            order by a0.scheduled_start_at,a0.id limit 100) a),'[]'::jsonb) assignments,
        rel.all_relation_count,rel.valid_relation_count,rel.revoked_relation_count,rel.work_item_id,rel.relation_kind,rel.source_revision,
        coalesce(rel.work_required,false) work_required,coalesce(rel.work_completed,false) work_completed,
        coalesce(multi.active_booking_count_for_work,0) active_booking_count_for_work
      from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
      left join lateral (
        select count(*) all_relation_count,
          count(*) filter(where r.relation_action='revoked') revoked_relation_count,
          count(*) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and rv.id=wi.vehicle_id and r.dealer_code=v_dealer and r.environment='staging') valid_relation_count,
          (min(wi.id::text) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging'))::uuid work_item_id,
          min(r.relation_kind) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') relation_kind,
          max(r.source_revision) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') source_revision,
          bool_and(wi.required) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') work_required,
          bool_or(wi.completed) filter(where r.relation_action='asserted' and wi.vehicle_id=b.vehicle_id and public.pdc_auditor_vehicle_dealer(rv.id)=v_dealer
            and r.dealer_code=v_dealer and r.environment='staging') work_completed
        from public.pdc_auditor_booking_work_relations r
        join public.vehicle_work_items wi on wi.id=r.work_item_id
        join public.vehicles rv on rv.id=wi.vehicle_id
        where r.booking_id=b.id and r.active
          and not exists(select 1 from public.pdc_auditor_booking_work_relations successor
            where successor.supersedes_relation_id=r.relation_id)
      ) rel on true
      left join lateral (
        select count(*) active_booking_count_for_work
        from public.pdc_auditor_booking_work_relations r2
        join public.workshop_bookings b2 on b2.id=r2.booking_id
        where rel.valid_relation_count=1 and r2.active and r2.relation_action='asserted' and r2.work_item_id=rel.work_item_id
          and not exists(select 1 from public.pdc_auditor_booking_work_relations successor2
            where successor2.supersedes_relation_id=r2.relation_id)
          and r2.dealer_code=v_dealer and r2.environment='staging'
          and b2.deleted_at is null and b2.status::text in ('queued','planned','started','stoppage')
      ) multi on true
      where b.vehicle_id=p.id and b.deleted_at is null
      order by b.scheduled_start_at desc,b.id desc limit 100
    ) q),'[]'::jsonb),
    'parts',coalesce((select jsonb_build_object(
      'scope','vehicle_level','job_specific',false,'vehicle_level',true,'inferred',false,'work_item_id',null,
      'parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,'parts_received',pu.parts_received,
      'parts_stoppage',pu.parts_stoppage,'eta_at',pu.worst_eta,'updated_at',pu.updated_at,
      'classification','confirmed')
      from public.vehicle_parts_updates pu where pu.vehicle_id=p.id order by pu.updated_at desc,pu.id desc limit 1),
      jsonb_build_object('scope','unknown','job_specific',false,'vehicle_level',false,'inferred',false,
        'work_item_id',null,'classification','unknown')),
    'operation_lines',coalesce((select jsonb_agg(jsonb_build_object(
      'operation_line_id',ol.operation_line_id,'operation_no',left(ol.operation_no,8),
      'work_key',left(ol.work_key,64),'estimated_hours',ol.estimated_hours,
      'hours_provenance',coalesce(ol.estimated_hours_source,'unknown'),
      'classification',case when ol.estimated_hours_source='job_card' then 'confirmed'
        when ol.estimated_hours_source='ai_estimate' then 'estimated' else 'unknown' end,
      'created_at',ol.created_at) order by ol.created_at desc,ol.operation_line_id)
      from (select * from public.pdc_authenticated_email_operation_lines ol0 where ol0.vehicle_id=p.id
        order by ol0.created_at desc,ol0.operation_line_id limit 100) ol),'[]'::jsonb),
    'line_adjustments',coalesce((select jsonb_agg(jsonb_build_object(
      'adjustment_id',a.adjustment_id,'source_kind',a.source_kind,'stage_code',a.stage_code,
      'estimated_hours',a.estimated_hours,'active',a.active,'version',a.version,
      'classification','confirmed','created_at',a.created_at,'updated_at',a.updated_at)
      order by a.updated_at desc,a.adjustment_id)
      from (select * from public.vehicle_workshop_line_adjustments a0 where a0.vehicle_id=p.id
        order by a0.updated_at desc,a0.adjustment_id limit 100) a),'[]'::jsonb),
    'sublet',coalesce((select jsonb_build_object(
      'provider_ids',coalesce((select jsonb_agg(vsp.provider_id order by vsp.provider_id)
        from (select * from public.vehicle_sublet_providers vsp0 where vsp0.vehicle_id=p.id
          order by vsp0.provider_id limit 20) vsp),'[]'::jsonb),
      'provider_names',coalesce((select jsonb_agg(left(vsp.canonical_name,120) order by vsp.canonical_name)
        from (select * from public.vehicle_sublet_providers vsp0 where vsp0.vehicle_id=p.id
          order by vsp0.canonical_name limit 20) vsp),'[]'::jsonb),
      'status',case when sb.actual_return_date is not null then 'returned'
        when sb.booking_date is not null then 'booked' when sb.po_sent_date is not null then 'po_sent' else 'unbooked' end,
      'booking_date',sb.booking_date,'expected_return_date',sb.expected_return_date,
      'actual_return_date',sb.actual_return_date,'version',sb.version,'updated_at',sb.updated_at,
      'classification','confirmed') from public.pdc_sublet_bookings sb where sb.vehicle_id=p.id),
      jsonb_build_object('status','unknown','provider_ids','[]'::jsonb,'provider_names','[]'::jsonb,'classification','unknown')),
    'movement_events',coalesce((select jsonb_agg(jsonb_build_object(
      'event_id',m.id,'event_type','movement','occurred_at',m.moved_at,'classification','confirmed')
      order by m.moved_at desc,m.id)
      from (select id,moved_at from public.vehicle_movements m0 where m0.vehicle_id=p.id
        order by m0.moved_at desc,m0.id limit 25) m),'[]'::jsonb),
    'sublet_authority',coalesce((select jsonb_build_object('status',case when si.status='active' then 'active' when si.status='returned' then 'returned' else 'unknown' end,'booking_id',si.booking_id,'provider_id',si.provider_id,'provider_name',left(si.provider_name,120),'provider_email',left(si.provider_email,180),'out_date',si.out_date,'expected_return_date',si.expected_return_date,'returned_at',si.returned_at,'version',si.version,'classification','confirmed') from public.pdc_sublet_booking_instances si where si.vehicle_id=p.id and si.status<>'cancelled' order by case when si.status='active' then 0 else 1 end,si.out_date desc,si.booking_id desc limit 1),jsonb_build_object('status','unknown','booking_id',null,'provider_id',null,'provider_name',null,'provider_email',null,'out_date',null,'expected_return_date',null,'returned_at',null,'version',null,'classification','unknown')),
    'workflow_events',coalesce((select jsonb_agg(jsonb_build_object(
      'event_id',e.id,'event_type',left(e.action::text,32),'entity_type',left(coalesce(e.table_name,''),48),
      'occurred_at',e.created_at,'classification','confirmed') order by e.created_at desc,e.id)
      from (select id,action,table_name,created_at from public.audit_events e0 where e0.vehicle_id=p.id
        order by e0.created_at desc,e0.id limit 500) e),'[]'::jsonb),
    'collection_completeness',jsonb_build_object(
      'work_items',jsonb_build_object('returned',least((select count(*) from public.vehicle_work_items wi where wi.vehicle_id=p.id),100),'total',(select count(*) from public.vehicle_work_items wi where wi.vehicle_id=p.id),'limit',100,'complete',(select count(*) from public.vehicle_work_items wi where wi.vehicle_id=p.id)<=100),
      'bookings',jsonb_build_object('returned',least((select count(*) from public.workshop_bookings b where b.vehicle_id=p.id and b.deleted_at is null),100),'total',(select count(*) from public.workshop_bookings b where b.vehicle_id=p.id and b.deleted_at is null),'limit',100,'complete',(select count(*) from public.workshop_bookings b where b.vehicle_id=p.id and b.deleted_at is null)<=100),
      'operation_lines',jsonb_build_object('returned',least((select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=p.id),100),'total',(select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=p.id),'limit',100,'complete',(select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=p.id)<=100),
      'line_adjustments',jsonb_build_object('returned',least((select count(*) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p.id),100),'total',(select count(*) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p.id),'limit',100,'complete',(select count(*) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p.id)<=100),
      'movement_events',jsonb_build_object('returned',least((select count(*) from public.vehicle_movements m where m.vehicle_id=p.id),25),'total',(select count(*) from public.vehicle_movements m where m.vehicle_id=p.id),'limit',25,'complete',(select count(*) from public.vehicle_movements m where m.vehicle_id=p.id)<=25),
      'workflow_events',jsonb_build_object('returned',least((select count(*) from public.audit_events e where e.vehicle_id=p.id),500),'total',(select count(*) from public.audit_events e where e.vehicle_id=p.id),'limit',500,'complete',(select count(*) from public.audit_events e where e.vehicle_id=p.id)<=500))
  ) order by p.id),'[]'::jsonb) into v_items from page p;

  v_page_item_count := jsonb_array_length(v_items);

  select count(*)>v_limit into v_has_more from (
    select v.id from public.vehicles v
    where public.pdc_auditor_vehicle_dealer(v.id)=v_dealer
      and v.deleted_at is null and (p_after_vehicle_id is null or v.id>p_after_vehicle_id)
    order by v.id limit v_limit+1
  ) bounded;
  if v_has_more then
    select (item->>'vehicle_id')::uuid into v_next from jsonb_array_elements(v_items) item
      order by item->>'vehicle_id' desc limit 1;
  end if;
  return jsonb_build_object(
    'ok',true,'code','pdc_auditor_snapshot','snapshot_contract_version','stage-a-v2',
    'environment','staging','dealer_code',v_dealer,'generated_at',clock_timestamp(),
    'response_revision',v_response_revision,'operational_revision',v_operational_revision,
    'rule_set_hash',v_rule_set_hash,
    'source_revisions',jsonb_build_object(
      'workshop_revision',v_workshop_revision,'pdc_email_vehicle_revision',v_email_revision,
      'auditor_revision',v_auditor_revision,'auditor_relation_revision',v_relation_revision,
      'auditor_config_revision',v_config_revision),
    'working_calendar',jsonb_build_object(
      'timezone','Australia/Perth','working_days',jsonb_build_array('monday','tuesday','wednesday','thursday','friday'),
      'day_start','08:00','day_end','16:00','closures','[]'::jsonb,'breaks','[]'::jsonb,
      'overtime_windows','[]'::jsonb,'source',case when v_calendar_config is null then 'missing_holiday_configuration' else 'auditor_rule_config' end,
      'holiday_configuration_status',case when v_calendar_config is null then 'missing' else 'confirmed' end,
      'classification',case when v_calendar_config is null then 'unknown' else 'confirmed' end)
      || case when v_calendar_config is null then '{}'::jsonb
        else jsonb_build_object('public_holidays',v_calendar_config->'public_holidays') end,
    'active_rule_configs',v_configs,
    'station_compatibility',coalesce((select c->'parameters'->'allowed_pairs' from jsonb_array_elements(v_configs) c where c->>'rule_key'='station_compatibility' limit 1),'[]'::jsonb),
    'resources',v_resources,
    'page_manifest',jsonb_build_object('after_vehicle_id',p_after_vehicle_id,'returned_count',v_page_item_count,
      'total_scoped_vehicle_count',v_total_vehicle_count,'page_limit',v_limit,'has_more',v_has_more,
      'next_vehicle_id',v_next,'response_revision',v_response_revision,'operational_revision',v_operational_revision),
    'page_size',v_limit,'has_more',v_has_more,
    'next_vehicle_id',v_next,'items',v_items,
    'relationship_semantics','Only one active exact auditor relation with same dealer and vehicle may link; all legacy, inactive, duplicate, cross-vehicle or cross-dealer cases are unlinked and fail closed.'
  );
end;
$snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_auditor_snapshot(uuid,integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_auditor_snapshot(uuid,integer) TO authenticated;
DO $verify$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.get_pdc_auditor_snapshot(uuid,integer)'::regprocedure) INTO d;
 IF position('p.vin' in d)=0 OR position('p.job_card_number' in d)=0 OR position('pdc_sublet_booking_instances' in d)=0 OR position('limit 500) e' in d)=0 OR position('actual_duration_minutes' in d)=0 OR position('source_contradiction_review' in d)=0 THEN RAISE EXCEPTION 'PDC_784_PROJECTION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 IF NOT has_function_privilege('authenticated','public.get_pdc_auditor_snapshot(uuid,integer)','execute') OR has_function_privilege('anon','public.get_pdc_auditor_snapshot(uuid,integer)','execute') OR has_function_privilege('service_role','public.get_pdc_auditor_snapshot(uuid,integer)','execute') OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_784_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830181000','784_stage_a_integrity_projection',ARRAY[
 'Return VIN and top-level Job Card as direct confirmed/unknown projections without inference',
 'Return canonical Sublet instance authority with explicit Unknown when absent',
 'Return up to 500 workflow events in deterministic created_at/id order with matching completeness metadata so 13017855 114-event history is complete',
 'Preserve dealer scope, forced-RLS source tables, authenticated-only execution and read-only behavior'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
