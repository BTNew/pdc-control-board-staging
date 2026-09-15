-- Staging-only read-only parity verification. No fixtures or operational/configuration writes.
BEGIN READ ONLY;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
SET LOCAL TIME ZONE 'Australia/Perth';
DO $test$
DECLARE
  actor uuid; actor_email text; v_snapshot jsonb; v_previous jsonb; v_configuration jsonb; v_calendar jsonb;
  expected jsonb; checks jsonb:='[]'; setting_key text; denied boolean; sample record; result boolean;
  week_start date:=date_trunc('week',now() AT TIME ZONE 'Australia/Perth')::date+14;
BEGIN
  IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING ONLY'; END IF;
  -- Select an existing approved operator solely for a read-only call under its authorization.
  SELECT r.auth_user_id,r.email INTO STRICT actor,actor_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
    WHERE r.role IN ('operator','administrator') AND r.active AND r.account_status='approved' ORDER BY r.auth_user_id LIMIT 1;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
  v_configuration:=public.get_workshop_configuration();
  v_snapshot:=public.get_workshop_eligibility_snapshot();

  declare
  v_now timestamptz:=now();
  v_month_start timestamptz:=date_trunc('month',now() at time zone 'Australia/Perth') at time zone 'Australia/Perth';
begin
  perform public.require_pdc_role('viewer');
  v_previous := (WITH eligibility AS MATERIALIZED (
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
      'bays',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'bay_id',b.bay_id,'stage_id',b.stage_id,'stage_code',b.stage_code,
        'stage_name',b.stage_name,'bay_number',b.bay_number,'display_name',b.display_name,
        'is_active',b.is_active,'efficiency_percent',b.efficiency_percent,
        'technician_name',b.technician_name
      ) ORDER BY b.sort_order,b.bay_number NULLS LAST,b.bay_id),'[]'::jsonb)
        FROM physical_bays b),
      'bookings',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'booking_id',b.id,'vehicle_id',b.vehicle_id,'stage_code',s.code,
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

  IF v_snapshot#-'{board,calendar}' IS DISTINCT FROM v_previous THEN RAISE EXCEPTION 'Preexisting board/candidate/pipeline fields changed'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Exact prior snapshot unchanged outside calendar','status','PASS'));
  v_calendar:=v_snapshot->'board'->'calendar';
  FOREACH setting_key IN ARRAY ARRAY['day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows'] LOOP
    expected:=v_configuration->setting_key->'value';
    IF NOT (v_calendar?setting_key) OR v_calendar->setting_key IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Configuration parity failed: %',setting_key; END IF;
    checks:=checks||jsonb_build_array(jsonb_build_object('name','Exact configuration value '||setting_key,'status','PASS'));
  END LOOP;
  IF (SELECT count(*) FROM jsonb_object_keys(v_calendar))<>6 THEN RAISE EXCEPTION 'Unexpected calendar configuration exposure'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Only the six calendar values exposed','status','PASS'));

  SELECT r.auth_user_id,r.email INTO STRICT actor,actor_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
    WHERE r.role='viewer' AND r.active AND r.account_status='approved' ORDER BY r.auth_user_id LIMIT 1;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
  v_snapshot:=public.get_workshop_eligibility_snapshot();
  IF v_snapshot->'board'->'calendar' IS DISTINCT FROM v_calendar THEN RAISE EXCEPTION 'Viewer/operator calendar mismatch'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Viewer/operator calendar parity','status','PASS'));
  denied:=false;
  BEGIN PERFORM public.get_workshop_configuration(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Full planner configuration became viewer accessible'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Full configuration remains operator-only','status','PASS'));
  PERFORM set_config('request.jwt.claims','{}',true);denied:=false;
  BEGIN PERFORM public.get_workshop_eligibility_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'No-role snapshot request accepted'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Unauthenticated snapshot denied','status','PASS'));
  IF has_function_privilege('anon','public.get_workshop_eligibility_snapshot()','EXECUTE') THEN RAISE EXCEPTION 'Anonymous execute granted'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Anonymous execute remains revoked','status','PASS'));

  -- Verify the current workshop boundary settings against the authoritative calendar.
  -- These assertions describe the requested live Monday-Friday07-17/Saturday08-12/Sundayclosed setup.
  IF v_calendar->>'day_start_time'<>'07:00' OR v_calendar->>'day_end_time'<>'17:00'
    OR NOT v_calendar->'working_week'@>'["saturday"]'::jsonb
    OR v_calendar->'working_week'@>'["sunday"]'::jsonb
    OR NOT v_calendar->'break_windows'@>'[{"scope":"saturday","start":"07:00","end":"08:00"},{"scope":"saturday","start":"12:00","end":"17:00"}]'::jsonb THEN
    RAISE EXCEPTION 'Current requested calendar changed; review dated boundary assertions';
  END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Current Saturday08-12 configuration preserved','status','PASS'));
  FOR sample IN SELECT * FROM (VALUES
    ('Weekday before opening',0,'06:59'::time,false),('Weekday opens',0,'07:00'::time,true),
    ('Weekday closes',0,'17:00'::time,false),('Saturday before opening',5,'07:59'::time,false),
    ('Saturday opens',5,'08:00'::time,true),('Saturday before closing',5,'11:59'::time,true),
    ('Saturday closes',5,'12:00'::time,false),('Sunday closed',6,'10:00'::time,false)
  ) x(label,day_offset,at_time,wanted) LOOP
    result:=public.workshop_calendar_minute_available((week_start+sample.day_offset+sample.at_time) AT TIME ZONE 'Australia/Perth');
    IF result IS DISTINCT FROM sample.wanted THEN RAISE EXCEPTION 'Calendar boundary mismatch: %',sample.label; END IF;
    checks:=checks||jsonb_build_array(jsonb_build_object('name',sample.label,'status','PASS'));
  END LOOP;
  IF current_setting('transaction_read_only')<>'on' THEN RAISE EXCEPTION 'Verification must remain read-only'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Read-only transaction protects current imports','status','PASS',
    'vehicles',(SELECT count(*) FROM public.vehicles),'bookings',(SELECT count(*) FROM public.workshop_bookings),'admin_blocks',(SELECT count(*) FROM public.workshop_admin_blocks)));
  PERFORM set_config('pdc.control_board_calendar_results',checks::text,true);
END $test$;
SELECT current_setting('pdc.control_board_calendar_results')::jsonb AS results;
ROLLBACK;
