-- Fitter progress is independent of QC inspection. All writes use planner authority.
CREATE SCHEMA IF NOT EXISTS pdc_fitter_private;
REVOKE ALL ON SCHEMA pdc_fitter_private FROM PUBLIC, anon, authenticated;

CREATE TABLE pdc_fitter_private.operation_progress (
 booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id),
 line_identity text NOT NULL,
 scope_hash text NOT NULL,
 completed boolean NOT NULL DEFAULT false,
 note text NOT NULL DEFAULT '' CHECK(length(note)<=2000),
 technician_id uuid NOT NULL REFERENCES public.workshop_technicians(id),
 updated_by uuid NOT NULL REFERENCES auth.users(id),
 updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(booking_id,line_identity)
);
CREATE TABLE pdc_fitter_private.command_receipts (
 actor_id uuid NOT NULL REFERENCES auth.users(id),
 request_id uuid NOT NULL,
 request_hash text NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(actor_id,request_id)
);
ALTER TABLE pdc_fitter_private.operation_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_fitter_private.command_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA pdc_fitter_private FROM PUBLIC,anon,authenticated;

CREATE FUNCTION pdc_fitter_private.assigned(p_booking_id uuid,p_technician_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
 SELECT EXISTS (
  SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays bay ON bay.id=b.bay_id
  JOIN public.workshop_technicians t ON t.id=p_technician_id AND t.active
  WHERE b.id=p_booking_id AND b.deleted_at IS NULL AND (
    EXISTS(SELECT 1 FROM public.workshop_booking_assignments a
      WHERE a.booking_id=b.id AND a.released_at IS NULL AND a.technician_id=t.id)
    OR (bay.default_technician_id=t.id AND NOT EXISTS(
      SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL))
  )
 )
$fn$;

-- Only work scope participates in the hash; QC changes must never reset fitter work.
CREATE FUNCTION pdc_fitter_private.lines(p_vehicle_id uuid,p_booking_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
 WITH source AS (
  SELECT l,md5(jsonb_build_array(l->>'line_identity',l->>'description',
    l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) scope_hash
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true)
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'line_identity',s.l->>'line_identity','description',s.l->>'description',
  'stage_code',s.l->>'stage_code','hours',s.l->'estimated_hours',
  'operation_no',s.l->'operation_no','source_note',s.l->>'review_note',
  'scope_hash',s.scope_hash,'completed',coalesce(p.completed AND p.scope_hash=s.scope_hash,false),
  'note',coalesce(p.note,''),'scope_changed',p.scope_hash IS NOT NULL AND p.scope_hash<>s.scope_hash,
  'updated_at',p.updated_at,'technician_id',p.technician_id
 ) ORDER BY s.l->>'stage_code',s.l->>'operation_no',s.l->>'line_identity'),'[]'::jsonb)
 FROM source s LEFT JOIN pdc_fitter_private.operation_progress p
   ON p.booking_id=p_booking_id AND p.line_identity=s.l->>'line_identity'
$fn$;

CREATE FUNCTION pdc_fitter_private.summary(p_lines jsonb,p_stage text)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 WITH lines AS (
  SELECT l, CASE WHEN jsonb_typeof(l->'hours')='number' THEN (l->>'hours')::numeric END hours
  FROM jsonb_array_elements(p_lines) l WHERE l->>'stage_code'=p_stage
 ), totals AS (
  SELECT count(*) total_lines,count(*) FILTER(WHERE (l->>'completed')::boolean) completed_lines,
   count(*) FILTER(WHERE hours IS NULL OR hours<=0) unknown_hours,
   coalesce(sum(greatest(hours,0)),0) total_hours,
   coalesce(sum(greatest(hours,0)) FILTER(WHERE (l->>'completed')::boolean),0) completed_hours FROM lines
 )
 SELECT jsonb_build_object('total_lines',total_lines,'completed_lines',completed_lines,
 'unknown_hours',unknown_hours,'total_hours',total_hours,'completed_hours',completed_hours,
 'percent',CASE WHEN total_hours>0 THEN least(CASE WHEN unknown_hours>0 THEN 99 ELSE 100 END,
 floor(100*completed_hours/total_hours)) ELSE 0 END,
 'can_complete',total_lines>0 AND total_lines=completed_lines AND unknown_hours=0) FROM totals
$fn$;

CREATE FUNCTION pdc_fitter_private.progress(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE b public.workshop_bookings; code text;
BEGIN
 -- Avoid rebuilding operation catalogues for the many bookings with no fitter work.
 IF NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=p_booking_id) THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 RETURN pdc_fitter_private.summary(pdc_fitter_private.lines(b.vehicle_id,b.id),code);
END $fn$;

CREATE FUNCTION public.get_fitter_roster()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 RETURN jsonb_build_object('ok',true,'technicians',(
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) ORDER BY name,id),'[]'::jsonb)
 FROM public.workshop_technicians WHERE active));
END $fn$;

CREATE FUNCTION public.get_fitter_jobs(p_technician_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians WHERE id=p_technician_id AND active)
 THEN RETURN jsonb_build_object('ok',false,'error','mechanic_unavailable'); END IF;
 RETURN jsonb_build_object('ok',true,'generated_at',now(),'technician_id',p_technician_id,
 'bays',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.display_name,
   'number',b.bay_number,'stage',s.display_name,'active',b.is_active) ORDER BY s.sort_order,b.bay_number),'[]'::jsonb)
   FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.default_technician_id=p_technician_id AND s.active AND s.is_physical AND NOT b.is_sublet_row),
 'jobs',(SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',b.id,'version',b.version,'status',b.status,'stage_code',s.code,'stage_name',s.display_name,
    'bay_id',bay.id,'bay_number',bay.bay_number,'bay_name',bay.display_name,'bay_active',bay.is_active,
    'start_at',b.scheduled_start_at,'end_at',b.scheduled_end_at,
    'stoppage_reason',b.stoppage_reason,'vehicle_id',v.id,'stock',v.stock_number,
    'job_card',v.job_card_number,'customer',v.customer_name,'vehicle',v.vehicle_description,
    'progress',pdc_fitter_private.progress(b.id)
  ) ORDER BY CASE b.status WHEN 'started' THEN 0 WHEN 'stoppage' THEN 1 ELSE 2 END,
   b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
  FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  JOIN public.workshop_bays bay ON bay.id=b.bay_id
  JOIN public.vehicles v ON v.id=b.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
  WHERE b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND s.is_physical AND NOT s.is_sublet AND pdc_fitter_private.assigned(b.id,p_technician_id)));
END $fn$;

CREATE FUNCTION public.get_fitter_job(p_technician_id uuid,p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE b public.workshop_bookings; code text; lines jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 lines:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'version',b.version,
   'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',pdc_fitter_private.summary(lines,code),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)));
END $fn$;

CREATE FUNCTION public.fitter_job_command(p_technician_id uuid,p_booking_id uuid,
 p_expected_version integer,p_catalog_hash text,p_request_id uuid,p_action text,
 p_line_identity text DEFAULT NULL,p_completed boolean DEFAULT NULL,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $fn$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action NOT IN('start','line','stop','resume','complete')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp();
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false));
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 RETURN r;
END $fn$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_fitter_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.get_fitter_roster(),public.get_fitter_jobs(uuid),
 public.get_fitter_job(uuid,uuid),public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_fitter_roster(),public.get_fitter_jobs(uuid),
 public.get_fitter_job(uuid,uuid),public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.workshop_overlay_canonical_booking_fields_397(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_bookings jsonb;
BEGIN
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot->'bookings') IS DISTINCT FROM 'array' THEN
    RETURN p_snapshot;
  END IF;

  SELECT coalesce(jsonb_agg(
    CASE WHEN b.id IS NULL THEN item.booking ELSE item.booking||jsonb_build_object(
      'scheduled_start_at',b.scheduled_start_at,
      'scheduled_end_at',b.scheduled_end_at,
      'default_duration_minutes',b.default_duration_minutes,
      'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
    'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
    'capacity_estimate_minutes',b.capacity_estimate_minutes,
      'fitter_progress',pdc_fitter_private.progress(b.id),
      'status',b.status,
      'version',b.version,
      'actual_start_at',b.actual_start_at,
      'actual_end_at',b.actual_end_at,
      'stoppage_reason',b.stoppage_reason,
      'stoppage_started_at',b.stoppage_started_at,
      'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes
    ) END ORDER BY item.ordinality),'[]'::jsonb)
  INTO v_bookings
  FROM jsonb_array_elements(p_snapshot->'bookings') WITH ORDINALITY AS item(booking,ordinality)
  LEFT JOIN public.workshop_bookings b
    ON b.id=CASE
      WHEN coalesce(item.booking->>'booking_id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'booking_id')::uuid
      WHEN coalesce(item.booking->>'id','')~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN (item.booking->>'id')::uuid
    END;

  RETURN jsonb_set(p_snapshot,'{bookings}',v_bookings,true);
END $function$
;
CREATE OR REPLACE FUNCTION public.get_workshop_eligibility_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_now timestamptz:=now();
  v_month_start timestamptz:=date_trunc('month',now() at time zone 'Australia/Perth') at time zone 'Australia/Perth';
begin
  perform public.require_pdc_role('viewer');
  return (WITH eligibility AS MATERIALIZED (
    SELECT e.* FROM public.workshop_stages s
    CROSS JOIN LATERAL public.workshop_station_eligibility(s.code) e
    WHERE s.active AND s.planner_enabled AND s.code=e.stage_code
  ), physical_stages AS MATERIALIZED (
    SELECT s.id,s.code,s.display_name,s.sort_order
    FROM public.workshop_stages s
    WHERE s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet
  ), physical_bays AS MATERIALIZED (
    SELECT b.id AS bay_id,b.stage_id,s.code AS stage_code,s.display_name AS stage_name,
      s.sort_order,b.bay_number,b.display_name,b.is_active,b.efficiency_percent,
      t.name AS technician_name
    FROM public.workshop_bays b
    JOIN physical_stages s ON s.id=b.stage_id
    LEFT JOIN public.workshop_technicians t ON t.id=b.default_technician_id
    WHERE NOT b.is_sublet_row
  ) SELECT jsonb_build_object(
    'generated_at',v_now,
    'semantics',jsonb_build_object(
      'count_label','Outstanding requirements',
      'candidate_authority','required canonical work item with completed=false; PMB or Yard Hold, or IT with Kewdale ETA',
      'legacy_pmb_stage_authority',false,
      'pipeline_authority','canonical station eligibility plus authoritative workshop bookings'
    ),
    'stages',(select coalesce(jsonb_agg(jsonb_build_object(
      'code',s.code,'display_name',s.display_name,'work_key',s.work_key,
      'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
      'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb)
        from public.workshop_stage_aliases a where a.stage_code=s.code)
    ) order by s.sort_order),'[]'::jsonb)
      from public.workshop_stages s where s.active and s.planner_enabled),
    'candidates',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',e.stage_code,'work_key',e.work_key,
      'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
      'vehicle',jsonb_build_object(
        'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
        'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'key_number',v.key_number,
        'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,
        'registration',v.registration,'current_location',coalesce(nullif(v.location_override,''),v.current_location),
      'automatic_location',v.current_location,'location_override',v.location_override,'pmb_stage',v.pmb_stage,
        'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
        'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
      'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
        'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
        from public.vehicle_work_items wi where wi.vehicle_id=v.id
          and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code)
    ) order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
      from public.workshop_stages s
      join eligibility e on e.stage_code=s.code
      join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where s.code=e.stage_code and s.active and s.planner_enabled),
    'board',jsonb_build_object(
      'calendar',(SELECT coalesce(jsonb_object_agg(ws.key,ws.value),'{}'::jsonb)
        FROM public.workshop_settings ws
        WHERE ws.key IN ('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows')),
      'bays',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'bay_id',b.bay_id,'stage_id',b.stage_id,'stage_code',b.stage_code,
        'stage_name',b.stage_name,'bay_number',b.bay_number,'display_name',b.display_name,
        'is_active',b.is_active,'efficiency_percent',b.efficiency_percent,
        'technician_name',b.technician_name
      ) ORDER BY b.sort_order,b.bay_number NULLS LAST,b.bay_id),'[]'::jsonb)
        FROM physical_bays b),
      'bookings',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'booking_id',b.id,'vehicle_id',b.vehicle_id,'stage_code',s.code,
        'fitter_progress',pdc_fitter_private.progress(b.id),
        'bay_id',b.bay_id,'bay_number',pb.bay_number,'status',b.status,
        'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
        'version',b.version,
        'vehicle',jsonb_build_object(
          'id',v.id,'stock_number',v.stock_number,'key_number',v.key_number,
          'job_card_number',v.job_card_number,'customer_name',v.customer_name,
          'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,
          'current_location',coalesce(nullif(v.location_override,''),v.current_location)
        )
      ) ORDER BY s.sort_order,pb.bay_number NULLS LAST,b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
        FROM public.workshop_bookings b
        JOIN physical_stages s ON s.id=b.stage_id
        JOIN public.vehicles v ON v.id=b.vehicle_id
          AND v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
        LEFT JOIN physical_bays pb ON pb.bay_id=b.bay_id AND pb.stage_id=b.stage_id
        WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage')
          AND (b.bay_id IS NULL OR pb.bay_id IS NOT NULL)),
      'admin_blocks',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'block_id',a.id,'stage_code',pb.stage_code,'bay_id',a.bay_id,'bay_number',pb.bay_number,
        'block_type',a.block_type,'label',a.label,'scheduled_start_at',a.scheduled_start_at,
        'scheduled_end_at',a.scheduled_end_at,'version',a.version
      ) ORDER BY pb.sort_order,pb.bay_number NULLS LAST,a.scheduled_start_at,a.id),'[]'::jsonb)
        FROM public.workshop_admin_blocks a
        JOIN physical_bays pb ON pb.bay_id=a.bay_id AND pb.stage_id=a.stage_id
        WHERE a.deleted_at IS NULL AND a.scheduled_end_at>v_now)
    ),
    'pipeline',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',s.code,
      'it',(select count(*) from eligibility e
        join public.vehicles v on v.id=e.vehicle_id
        where e.stage_code=s.code and e.current_location='IT'),
      'pmb_waiting',(select count(*) from eligibility e
        join public.vehicles v on v.id=e.vehicle_id
        where e.stage_code=s.code and e.current_location='PMB'
          and not exists(
            select 1 from public.workshop_bookings b
            where b.vehicle_id=v.id and b.stage_id=s.id and b.deleted_at is null
              and b.status in ('started','stoppage'))),
      'yard_hold_waiting',(select count(*) from eligibility e
        where e.stage_code=s.code and e.current_location='YH'
          and not exists(select 1 from public.workshop_bookings b
            where b.vehicle_id=e.vehicle_id and b.stage_id=s.id and b.deleted_at is null
              and b.status in ('started','stoppage'))),
      'in_bays',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='started' and b.bay_id is not null
          and v.lifecycle_state='active' and v.deleted_at is null),
      'average_bay_hours',(select coalesce(round(avg(greatest(0,
          extract(epoch from(v_now-coalesce(b.actual_start_at,b.scheduled_start_at)))/3600.0
          -coalesce(b.stoppage_accumulated_minutes,0)/60.0))::numeric,1),0)
        from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='started' and b.bay_id is not null
          and v.lifecycle_state='active' and v.deleted_at is null),
      'stoppage',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='stoppage'
          and v.lifecycle_state='active' and v.deleted_at is null),
      'completed_mtd',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='completed'
          and b.actual_end_at>=v_month_start and b.actual_end_at<=v_now and v.deleted_at is null)
    ) order by s.sort_order),'[]'::jsonb)
      from public.workshop_stages s where s.active and s.planner_enabled)
  ));
end;
$function$
;
