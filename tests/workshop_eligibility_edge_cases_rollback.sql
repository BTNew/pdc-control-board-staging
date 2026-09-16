-- STAGING ONLY. Synthetic eligibility edge cases and complete output parity.
-- Existing operational rows stay unchanged; actor and all fixtures roll back.
BEGIN;
SET LOCAL statement_timeout='90s';
SET LOCAL lock_timeout='15s';
DO $guard$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: rollback verification is STAGING only';
 END IF;
END $guard$;

-- APPLY CANDIDATE MIGRATION HERE FOR PRE-DEPLOYMENT VERIFICATION.

CREATE TEMP TABLE snap_results(name text PRIMARY KEY,status text,evidence jsonb) ON COMMIT DROP;
CREATE TEMP TABLE snap_bench(variant text,iteration int,ms numeric) ON COMMIT DROP;
CREATE TEMP TABLE snap_original_vehicles AS SELECT id,to_jsonb(v) row_data FROM public.vehicles v;
CREATE TEMP TABLE snap_original_bookings AS SELECT id,to_jsonb(b) row_data FROM public.workshop_bookings b;
CREATE TEMP TABLE snap_original_progress AS SELECT booking_id,line_identity,to_jsonb(p) row_data FROM pdc_fitter_private.operation_progress p;
CREATE TEMP TABLE snap_context(actor uuid,email text) ON COMMIT DROP;
CREATE TEMP TABLE snap_refs(name text PRIMARY KEY,id uuid) ON COMMIT DROP;
CREATE FUNCTION pg_temp.snap_assert(pass boolean,label text,evidence jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 IF pass IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL %: %',label,evidence; END IF;
 INSERT INTO snap_results VALUES(label,'PASS',evidence);
END $f$;

DO $setup$ DECLARE a uuid:=gen_random_uuid(); email text;
BEGIN
 email:='snapshot-perf-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',email,now(),'{"provider":"email","providers":["email"]}','{"full_name":"Snapshot performance rollback fixture"}',now(),now());
 UPDATE public.pdc_user_roles SET role='viewer',active=true,account_status='approved',approved_at=now() WHERE auth_user_id=a;
 INSERT INTO snap_context VALUES(a,email);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',email,'role','authenticated')::text,true);
 PERFORM public.require_pdc_role('viewer');
END $setup$;

-- Frozen prior implementation gives a real before/after comparison even after
-- deployment, without creating a public API or widening grants.
CREATE OR REPLACE FUNCTION pg_temp.station_before_optimization(p_stage_code text)
 RETURNS TABLE(vehicle_id uuid, stage_code text, work_key text, current_location text, eta_to_kewdale date, existing_booking boolean, schedule_enabled boolean, disabled_reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH station AS(
  SELECT s.id,s.code,s.work_key FROM public.workshop_stages s
  WHERE s.code=public.workshop_canonical_stage_code(p_stage_code) AND s.active AND s.planner_enabled
 ),outstanding AS(
  SELECT wi.vehicle_id,st.id stage_id,st.code,st.work_key
  FROM public.vehicle_work_items wi CROSS JOIN station st
  WHERE public.workshop_stage_code_for_work_key(wi.work_key)=st.code AND wi.required AND NOT wi.completed
  GROUP BY wi.vehicle_id,st.id,st.code,st.work_key
 ),active_booking AS(
  SELECT DISTINCT b.vehicle_id,st.code FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id JOIN station st ON st.code=s.code
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
 ),eligible AS MATERIALIZED (
 SELECT v.id,o.code,o.work_key,public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) current_location,v.eta_to_kewdale,
  (ab.vehicle_id IS NOT NULL) existing_booking,o.stage_id
 FROM outstanding o JOIN public.vehicles v ON v.id=o.vehicle_id
 LEFT JOIN active_booking ab ON ab.vehicle_id=v.id AND ab.code=o.code
 WHERE v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
   AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN('PMB','YH','IT')
   AND (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' OR v.eta_to_kewdale IS NOT NULL)
 ),estimated AS MATERIALIZED (
 SELECT e.*,public.workshop_vehicle_stage_estimated_duration_minutes(e.id,e.stage_id) duration_minutes
 FROM eligible e
 )
 SELECT e.id,e.code,e.work_key,e.current_location,e.eta_to_kewdale,e.existing_booking,
   e.duration_minutes IS NOT NULL,
   CASE WHEN e.duration_minutes IS NULL THEN 'estimated_duration_missing' ELSE NULL::text END
 FROM estimated e
$function$
;
CREATE OR REPLACE FUNCTION pg_temp.snapshot_before_optimization()
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
    CROSS JOIN LATERAL pg_temp.station_before_optimization(s.code) e
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

CREATE FUNCTION pg_temp.snap_vehicle(tag text,location text,hours numeric,expected_visible boolean DEFAULT true,
 override_location text DEFAULT NULL,eta date DEFAULT NULL,completed boolean DEFAULT false,required boolean DEFAULT true,shown boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE v uuid:=gen_random_uuid(); actor_id uuid; stock text:='PERF-'||substr(v::text,1,8); v_required boolean:=required; v_completed boolean:=completed;
BEGIN
 SELECT actor INTO actor_id FROM snap_context;
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,customer_name,vehicle_description,current_location,
 location_override,eta_to_kewdale,visible_on_board,source_system,source_record_id,source_payload,created_by,updated_by)
 VALUES(v,'snapshot-rollback-'||v,stock,'PERF-JC-'||substr(v::text,1,8),'Snapshot rollback '||tag,'Synthetic vehicle',location,
 override_location,eta,shown,'snapshot_rollback',v::text,'{"rollback_fixture":true}',actor_id,actor_id);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
 VALUES(v,'fitting',required,completed);
 INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,created_by,updated_by)
 VALUES(v,'manual:perf-'||v,'manual','FITTING','Synthetic fitting operation',hours,actor_id,actor_id);
 -- Creating a manual line deliberately reconciles the required-work projection.
 -- Set the synthetic edge-state after that reconciliation, never a real vehicle.
 UPDATE public.vehicle_work_items SET required=(public.workshop_stage_code_for_work_key(work_key)='FITTING' AND v_required),completed=v_completed WHERE vehicle_id=v;
 INSERT INTO snap_refs VALUES(tag,v);
 PERFORM pg_temp.snap_assert(EXISTS(SELECT 1 FROM public.workshop_station_eligibility('Fitting') e WHERE e.vehicle_id=v)=expected_visible,
  'Eligibility fixture - '||tag);
 IF expected_visible THEN
  PERFORM pg_temp.snap_assert(
    (SELECT e.schedule_enabled FROM public.workshop_station_eligibility('fitting') e WHERE e.vehicle_id=v)=(hours>0),
    'Approved hours availability - '||tag);
 END IF;
 RETURN v;
END $f$;

DO $fixtures$
BEGIN
 PERFORM pg_temp.snap_vehicle('PMB positive','PMB',1.25);
 PERFORM pg_temp.snap_vehicle('Sub-minute positive','PMB',0.01);
 PERFORM pg_temp.snap_vehicle('Zero hours','PMB',0);
 -- NULL hours is covered below because SQL NULL needs explicit expected=false.
 PERFORM pg_temp.snap_vehicle('Yard Hold alias','Yard Hold',2);
 PERFORM pg_temp.snap_vehicle('IT with ETA','IT',2,true,NULL,current_date+7);
 PERFORM pg_temp.snap_vehicle('IT missing ETA','IT',2,false);
 PERFORM pg_temp.snap_vehicle('QC excluded','QC',2,false);
 PERFORM pg_temp.snap_vehicle('PMB override','YH',2,true,'PMB');
 PERFORM pg_temp.snap_vehicle('QC override excluded','PMB',2,false,'QC');
 PERFORM pg_temp.snap_vehicle('Completed excluded','PMB',2,false,NULL,NULL,true);
 PERFORM pg_temp.snap_vehicle('Not required excluded','PMB',2,false,NULL,NULL,false,false);
 PERFORM pg_temp.snap_vehicle('Hidden excluded','PMB',2,false,NULL,NULL,false,true,false);
END $fixtures$;

DO $edge$ DECLARE missing uuid; alias text; prior jsonb; current jsonb; s record;
BEGIN
 SELECT id INTO missing FROM snap_refs WHERE name='Zero hours';
 UPDATE public.vehicle_workshop_line_adjustments SET estimated_hours=NULL WHERE vehicle_id=missing;
 PERFORM pg_temp.snap_assert(
  (SELECT NOT schedule_enabled AND disabled_reason='estimated_duration_missing' FROM public.workshop_station_eligibility('fitting') WHERE vehicle_id=missing),
  'Missing hours remain disabled with existing reason');
 PERFORM pg_temp.snap_assert(pg_temp.snapshot_before_optimization()=public.get_workshop_eligibility_snapshot(),
  'Snapshot parity includes all synthetic eligibility cases');

 PERFORM set_config('request.jwt.claims','{}',true);
 BEGIN
  PERFORM public.get_workshop_eligibility_snapshot();
  RAISE EXCEPTION 'Unauthenticated snapshot unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN
  PERFORM pg_temp.snap_assert(true,'Unauthenticated snapshot remains denied');
 END;
 SELECT jsonb_build_object('sub',actor,'email',email,'role','authenticated') INTO current FROM snap_context;
 PERFORM set_config('request.jwt.claims',current::text,true);
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE auth_user_id=(SELECT actor FROM snap_context);
 BEGIN
  PERFORM public.get_workshop_eligibility_snapshot();
  RAISE EXCEPTION 'Inactive account snapshot unexpectedly succeeded';
 EXCEPTION WHEN insufficient_privilege THEN
  PERFORM pg_temp.snap_assert(true,'Inactive account remains denied');
 END;

 PERFORM pg_temp.snap_assert(NOT EXISTS(
  SELECT 1 FROM snap_original_bookings o FULL JOIN public.workshop_bookings b ON b.id=o.id
   WHERE o.id IS NULL OR b.id IS NULL OR o.row_data<>to_jsonb(b)),
  'Existing bookings unchanged');
 PERFORM pg_temp.snap_assert(NOT EXISTS(
  SELECT 1 FROM snap_original_vehicles o LEFT JOIN public.vehicles v ON v.id=o.id WHERE v.id IS NULL OR o.row_data<>to_jsonb(v)),
  'Existing vehicles unchanged');
 PERFORM pg_temp.snap_assert(NOT EXISTS(
  SELECT 1 FROM snap_original_progress o FULL JOIN pdc_fitter_private.operation_progress p ON p.booking_id=o.booking_id AND p.line_identity=o.line_identity
   WHERE o.booking_id IS NULL OR p.booking_id IS NULL OR o.row_data<>to_jsonb(p)),
  'Fitter completion data unchanged');
END $edge$;

SELECT jsonb_build_object(
 'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY r.name) FROM snap_results r),
 'timings',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.variant,t.iteration) FROM snap_bench t),
 'average_ms',(SELECT jsonb_object_agg(variant,ms) FROM(SELECT variant,round(avg(ms),2) ms FROM snap_bench GROUP BY variant) q)
) AS verification;
ROLLBACK;
