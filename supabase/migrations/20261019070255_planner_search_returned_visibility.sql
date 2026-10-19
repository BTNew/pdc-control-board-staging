-- STAGING ONLY. Repair read projections; no bookings, roles or source records are changed.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(p_scope jsonb,p_vehicle_id uuid,p_requested_dealer text)
RETURNS boolean LANGUAGE sql STABLE SET search_path TO pg_catalog AS $function$
 SELECT coalesce(
 p_scope->>'environment'='staging' AND p_scope->>'role' IN('viewer','operator','administrator')
 AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450'
 AND NOT (p_scope ? 'department_scope')
 AND public.pdc_auditor_vehicle_dealer(p_vehicle_id) IS NULL
 AND EXISTS(
  SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
  WHERE v.id=p_vehicle_id AND v.source_system IN('tune_pmg','microsoft_navision')
   AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL
   AND nullif(btrim(v.stock_number),'') IS NOT NULL AND n.status='approved' AND n.approved_at IS NOT NULL
   AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL
    AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1'
    AND cardinality(j.departments)>0 AND j.departments <@ ARRAY['138','139']::text[] AND j.stock_number=v.stock_number)
   AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL
    AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1'
     OR coalesce(cardinality(j.departments),0)=0 OR NOT coalesce(j.departments <@ ARRAY['138','139']::text[],false)
     OR j.stock_number IS DISTINCT FROM v.stock_number))
   AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j
    ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL
    WHERE o.vehicle_id=v.id AND o.department='139' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
   AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id
    AND (o.department IS NULL OR o.department NOT IN('138','139') OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
 ),false);
$function$;
REVOKE ALL ON FUNCTION pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(jsonb,uuid,text) FROM PUBLIC,anon,authenticated,service_role;


DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('public.get_station_workshop_snapshot_pre_170(text,date,date)'::regprocedure),chr(13),'')) <> '989596eebf32ff187e481ad5d1c9db95' THEN RAISE EXCEPTION 'source_version_changed: get_station_workshop_snapshot_pre_170'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot_pre_170(p_stage_code text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_result jsonb;
begin
  perform public.require_pdc_role('viewer');
  v_stage:=public.workshop_canonical_stage_code(p_stage_code);
  select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
  if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
  if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then raise exception 'Invalid station planner date range' using errcode='22023'; end if;
  v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
  v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';

  with
  station as materialized(
    select s.id,s.code,s.display_name,s.is_physical,s.work_key
    from public.workshop_stages s where s.id=v_stage_id
  ),
  eligibility as materialized(
    select * from public.workshop_station_eligibility(v_stage)
  ),
  booking_seed as materialized(
    select b.*
    from public.workshop_bookings b
    join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
    where b.stage_id=v_stage_id and b.deleted_at is null
      and b.status in('queued','planned','started','stoppage','completed')
      and (
        (b.status='queued' and b.bay_id is null)
        or (b.status in('queued','planned') and b.scheduled_start_at<v_to)
        or (b.status in('started','stoppage') and b.scheduled_start_at<v_to)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to)
      )
  ),
  candidate_ids as materialized(
    select vehicle_id from eligibility union select vehicle_id from booking_seed
  ),
  effective_source_lines as materialized(
    select ol.vehicle_id,
      public.workshop_canonical_stage_code(coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))) stage_code,
      coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours
    from public.pdc_authenticated_email_operation_lines ol
    join public.pdc_authenticated_email_import_receipts r on r.receipt_id=ol.import_receipt_id
    join candidate_ids i on i.vehicle_id=ol.vehicle_id
    left join public.vehicle_workshop_line_adjustments a
      on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text and a.active
    union all
    select a.vehicle_id,public.workshop_canonical_stage_code(a.stage_code),a.estimated_hours
    from public.vehicle_workshop_line_adjustments a join candidate_ids i on i.vehicle_id=a.vehicle_id
    where a.active and a.source_kind='manual'
  ),
  hours as materialized(
    select vehicle_id,nullif(round(sum(estimated_hours)::numeric,2),0) estimated_hours
    from effective_source_lines where stage_code=v_stage and estimated_hours>0 group by vehicle_id
  ),
  booking_duration as materialized(
    select b.*,case when b.status in('queued','planned','started','stoppage')
      then coalesce(greatest(60,round(h.estimated_hours*60)::integer),b.default_duration_minutes)
      else b.default_duration_minutes end effective_duration
    from booking_seed b left join hours h on h.vehicle_id=b.vehicle_id
  ),
  selected_bookings as materialized(
    select b.*,case when b.status in('queued','planned','started','stoppage')
      then public.workshop_add_operational_minutes(b.scheduled_start_at,b.effective_duration)
      else b.scheduled_end_at end effective_end
    from booking_duration b
  ),
  selected_filtered as materialized(
    select * from selected_bookings b where
      (b.status='queued' and b.bay_id is null)
      or (b.status in('queued','planned') and b.scheduled_end_at>v_from)
      or b.status in('started','stoppage')
      or b.status='completed'
  ),
  selected_ids as materialized(
    select vehicle_id from eligibility union select vehicle_id from selected_filtered
  ),
  assignments as materialized(
    select distinct on(a.booking_id) a.booking_id,a.technician_id,t.name technician_name,a.assignment_type
    from public.workshop_booking_assignments a join public.workshop_technicians t on t.id=a.technician_id
    join selected_filtered b on b.id=a.booking_id
    where a.released_at is null
    order by a.booking_id,case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc
  ),
  requirement_rows as materialized(
    select wi.vehicle_id,jsonb_agg(jsonb_build_object(
      'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_at',wi.completed_at
    ) order by wi.work_key) requirements
    from public.vehicle_work_items wi join selected_ids i on i.vehicle_id=wi.vehicle_id
    where wi.required and not wi.completed group by wi.vehicle_id
  ),
  stage_work_items as materialized(
    select wi.* from public.vehicle_work_items wi join selected_ids i on i.vehicle_id=wi.vehicle_id
    where public.workshop_stage_code_for_work_key(wi.work_key)=v_stage
  )
  select jsonb_build_object(
    'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
    'semantics',jsonb_build_object(
      'outstanding_candidates','required canonical work items not completed and location-visible',
      'unscheduled_candidates','outstanding candidates without any active booking',
      'selected_date_bookings','scheduled rows intersecting the date plus started or stopped work carried forward until resolved'),
    'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
    'counts',jsonb_build_object(
      'outstanding_candidates',(select count(*) from eligibility),
      'unscheduled_candidates',(select count(*) from eligibility where not existing_booking),
      'selected_date_bookings',(select count(*) from selected_filtered where bay_id is not null)),
    'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key)) from station s),
    'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb) from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
    'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,
      'disabled_reason',e.disabled_reason,'estimated_hours',h.estimated_hours,
      'requirements',coalesce(rr.requirements,'[]'::jsonb)) order by e.vehicle_id),'[]'::jsonb)
      from eligibility e left join hours h on h.vehicle_id=e.vehicle_id left join requirement_rows rr on rr.vehicle_id=e.vehicle_id),
    'bookings',(select coalesce(jsonb_agg(jsonb_build_object(
      'booking_id',b.id,'vehicle_id',b.vehicle_id,
      'stage',jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key),
      'bay',case when bay.id is null then null else jsonb_build_object('id',bay.id,'bay_number',bay.bay_number,'code',bay.code,'display_name',bay.display_name) end,
      'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.effective_end,
      'default_duration_minutes',b.effective_duration,
      'estimated_operation_hours',case when b.status in('queued','planned','started','stoppage') then h.estimated_hours else null end,
      'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,'version',b.version,
      'assignment',case when aa.technician_id is null then null else jsonb_build_object('technician_id',aa.technician_id,'technician_name',aa.technician_name,'assignment_type',aa.assignment_type) end
    ) order by b.scheduled_start_at,b.id),'[]'::jsonb)
      from selected_filtered b join station s on true left join public.workshop_bays bay on bay.id=b.bay_id
      left join hours h on h.vehicle_id=b.vehicle_id left join assignments aa on aa.booking_id=b.id),
    'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
      'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
      'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
      'customer_name',v.customer_name,'make',v.make,'model',v.model,'registration',v.registration,
      'current_location',coalesce(nullif(v.location_override,''),v.current_location),
      'automatic_location',v.current_location,'location_override',v.location_override,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,
      'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
      'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,
      'version',v.version,'workshop_estimated_hours_by_stage',jsonb_build_object(v_stage,h.estimated_hours)
    ) order by v.stock_number nulls last,v.id),'[]'::jsonb)
      from public.vehicles v join selected_ids i on i.vehicle_id=v.id left join hours h on h.vehicle_id=v.id
      where v.lifecycle_state='active' and v.deleted_at is null),
    'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_at',wi.completed_at
    ) order by wi.vehicle_id,wi.work_key),'[]'::jsonb) from stage_work_items wi)
  ) into v_result;
  return v_result;
end $function$;

DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)'::regprocedure),chr(13),'')) <> '2409e7ff60763284b9812e8d0270b35f' THEN RAISE EXCEPTION 'source_version_changed: workshop_read_vehicle_allowed_20261013'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ SELECT coalesce((public.pdc_workshop_actor_vehicle_allowed(p_scope,p_vehicle_id,p_requested_dealer)
 OR pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(p_scope,p_vehicle_id,p_requested_dealer))
 AND (NOT (p_scope ? 'department_scope') OR
   (p_scope->>'department_scope'='138' AND p_scope->>'environment'='staging' AND p_scope->>'role' IN ('viewer','operator','administrator') AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450' AND EXISTS (
SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
WHERE v.id=p_vehicle_id AND v.source_system='tune_pmg' AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR j.departments IS DISTINCT FROM ARRAY['138']::text[] OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND (o.department IS DISTINCT FROM '138' OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
))),false); $function$;

DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure),chr(13),'')) <> 'de33246c9d04b8bdaf63ce5b0ca3a67d' THEN RAISE EXCEPTION 'source_version_changed: get_vehicle_workshop_detail_scoped'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid, p_dealer_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_scope jsonb; v_dealer text; v_vehicle_dealer text;
BEGIN
  v_scope:=pdc_codex_intake_private.workshop_read_actor_scope_20261013();
  v_dealer:=btrim(coalesce(p_dealer_code,''));
  IF NOT pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied','data',jsonb_build_object('environment','staging','dealer_code',v_dealer));
  END IF;
  SELECT public.pdc_auditor_vehicle_dealer(v.id) INTO v_vehicle_dealer
  FROM public.vehicles v
  WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active';
  IF v_vehicle_dealer IS DISTINCT FROM v_dealer AND NOT pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(v_scope,p_vehicle_id,v_dealer)
 AND NOT pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(v_scope,p_vehicle_id,v_dealer) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_dealer_scope','data',jsonb_build_object('vehicle_id',p_vehicle_id,'dealer_code',v_dealer));
  END IF;
  RETURN public.get_vehicle_workshop_detail(p_vehicle_id) || jsonb_build_object('imported_additions',
  (SELECT coalesce(jsonb_agg(jsonb_build_object('change_id',q.change_id,'description',q.proposed_source->>'operation_description',
    'department',q.proposed_source->>'department','job_card',q.repair_order_number,'line_number',q.original_line_number,
    'source_hours',q.proposed_source->'source_estimated_hours','status',coalesce(q.automation_result->>'code','classification_pending')) ORDER BY q.created_at),'[]')
   FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=p_vehicle_id AND q.status='pending'));
 
END
$function$;

DO $guard$ BEGIN IF md5(replace(pg_get_functiondef('public.get_workshop_booking_search_scoped(jsonb)'::regprocedure),chr(13),'')) <> '5e819aff0c838264664ba8c886cab609' THEN RAISE EXCEPTION 'source_version_changed: get_workshop_booking_search_scoped'; END IF; END $guard$;

CREATE OR REPLACE FUNCTION public.get_workshop_booking_search_scoped(p_vehicles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '15s'
AS $function$
DECLARE actor_scope jsonb; results jsonb;
BEGIN
 -- Actual signed-in identity plus the existing role check are required.
 -- The private read helper applies only the owner-authorised Department138 delegation.
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 PERFORM public.require_pdc_role('viewer');
 actor_scope:=pdc_codex_intake_private.workshop_read_actor_scope_20261013();
 IF jsonb_typeof(p_vehicles) IS DISTINCT FROM 'array' THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF jsonb_array_length(p_vehicles) NOT BETWEEN 1 AND 25 THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_vehicles) x WHERE jsonb_typeof(x) IS DISTINCT FROM 'object'
   OR jsonb_typeof(x->'vehicle_id') IS DISTINCT FROM 'string'
   OR coalesce(x->>'vehicle_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   OR jsonb_typeof(x->'dealer_code') IS DISTINCT FROM 'string'
   OR length(btrim(coalesce(x->>'dealer_code',''))) NOT BETWEEN 1 AND 80)
 OR (SELECT count(DISTINCT lower(x->>'vehicle_id')) FROM jsonb_array_elements(p_vehicles) x)<>jsonb_array_length(p_vehicles) THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;

 WITH requested AS MATERIALIZED (
  SELECT (x->>'vehicle_id')::uuid vehicle_id,btrim(x->>'dealer_code') dealer_code,ordinal
  FROM jsonb_array_elements(p_vehicles) WITH ORDINALITY q(x,ordinal)
 ), authorized AS MATERIALIZED (
  SELECT r.*,CASE
   WHEN pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(actor_scope,r.vehicle_id,r.dealer_code) IS NOT TRUE THEN 'dealer_scope_denied'
   WHEN NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=r.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
     AND (public.pdc_auditor_vehicle_dealer(v.id)=r.dealer_code OR pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(actor_scope,v.id,r.dealer_code)
      OR pdc_codex_intake_private.workshop_approved_pmg_read_allowed_20261019(actor_scope,v.id,r.dealer_code))) THEN 'vehicle_not_in_dealer_scope'
   ELSE NULL END error
  FROM requested r
 ), booking_rows AS (
  SELECT a.vehicle_id,jsonb_agg(jsonb_build_object(
   'booking_id',b.id,'booking_version',b.version,'work_category',b.work_category,'stage_code',s.code,'stage_name',s.display_name,
   'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',b.status,
   'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
   'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at)
   ORDER BY s.sort_order,b.scheduled_start_at,b.id) bookings
  FROM authorized a JOIN public.workshop_bookings b ON b.vehicle_id=a.vehicle_id AND a.error IS NULL
  JOIN public.workshop_stages s ON s.id=b.stage_id LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
  GROUP BY a.vehicle_id
 )
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',a.vehicle_id,'dealer_code',a.dealer_code,'ok',a.error IS NULL)
  ||CASE WHEN a.error IS NULL THEN jsonb_build_object('bookings',coalesce(b.bookings,'[]'::jsonb))
    ELSE jsonb_build_object('error',a.error) END ORDER BY a.ordinal)
 INTO results FROM authorized a LEFT JOIN booking_rows b ON b.vehicle_id=a.vehicle_id;
 RETURN jsonb_build_object('ok',true,'results',results);
END $function$;

NOTIFY pgrst, 'reload schema';