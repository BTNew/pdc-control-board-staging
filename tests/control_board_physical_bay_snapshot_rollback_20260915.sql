-- STAGING ONLY. All actors, bays, vehicles, bookings, source evidence and history roll back.
-- Run in one connection after applying the additive Control Board migration.
BEGIN;
SET LOCAL statement_timeout='120s';
SET LOCAL lock_timeout='5s';
SET LOCAL TIME ZONE 'Australia/Perth';
DO $test$
DECLARE
  actor uuid:=gen_random_uuid(); actor_email text; batch uuid:=gen_random_uuid();
  vid uuid; bid uuid; bay uuid; stage uuid; evidence uuid; operation_id uuid; wk text; stock text;
  fixture_name text; stage_code text; state public.workshop_booking_status; payload jsonb;
  refs jsonb:='{}'; checks jsonb:='[]'; v_snapshot jsonb; v_previous jsonb; v_old jsonb;
  v_bay jsonb; v_booking jsonb; row_item record; i integer:=0; expected integer;
  start_at timestamptz:=(date_trunc('week',clock_timestamp() AT TIME ZONE 'Australia/Perth')::date+21+time '07:00') AT TIME ZONE 'Australia/Perth';
  before_role_count integer; before_bays jsonb; before_bookings jsonb; before_vehicles jsonb;
  denied boolean; empty_snapshot jsonb; block_id uuid:=gen_random_uuid(); deleted_block uuid:=gen_random_uuid(); expired_block uuid:=gen_random_uuid();
BEGIN
  IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING ONLY'; END IF;
  SELECT count(*) INTO before_role_count FROM public.pdc_user_roles;
  SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') INTO before_bays FROM public.workshop_bays b;
  SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]') INTO before_bookings FROM public.workshop_bookings b;
  SELECT coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]') INTO before_vehicles FROM public.vehicles v;
  IF before_bookings<>'[]'::jsonb OR before_vehicles<>'[]'::jsonb THEN RAISE EXCEPTION 'This isolated fixture expects the staging wipe to remain empty'; END IF;

  actor_email:='control-board-'||actor||'@example.invalid';
  INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES(actor,'authenticated','authenticated',actor_email,clock_timestamp(),'{"provider":"email","providers":["email"]}','{"full_name":"Control board rollback fixture"}',clock_timestamp(),clock_timestamp());
  UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
    WHERE auth_user_id=actor AND email=actor_email;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);

  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
    source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,response,created_by,created_actor)
  VALUES(batch,'pilbara_service_open_jobcards_v1',encode(extensions.digest(batch::text,'sha256'),'hex'),repeat('b',64),'control-board-'||batch,'apply',12,12,0,12,0,0,'{}',actor,actor_email);

  FOR row_item IN SELECT * FROM (VALUES
    ('planned','FITTING','planned'),('started','TINT','started'),('stoppage','HOIST','stoppage'),
    ('queued','ELECTRICAL','queued'),('inactive_bay','FABRICATION','planned'),('changed_location','BUS_4X4','planned'),
    ('completed_booking','TYRE','completed'),('deleted_booking','FITTING','deleted'),
    ('hidden_vehicle','FITTING','planned'),('inactive_vehicle','FITTING','planned'),
    ('deleted_vehicle','FITTING','planned'),('no_requirement','FITTING','planned')
  ) x(fixture,stage_name,booking_state)
  LOOP
    i:=i+1;fixture_name:=row_item.fixture;stage_code:=row_item.stage_name;state:=row_item.booking_state::public.workshop_booking_status;
    vid:=gen_random_uuid();bid:=gen_random_uuid();bay:=gen_random_uuid();evidence:=gen_random_uuid();operation_id:=gen_random_uuid();stock:='CB-'||substr(vid::text,1,8);
    SELECT id,work_key INTO STRICT stage,wk FROM public.workshop_stages WHERE code=stage_code;
    INSERT INTO public.workshop_bays(id,stage_id,bay_number,code,display_name,is_active,efficiency_percent)
    VALUES(bay,stage,900+i,'CB-'||bay,'Fixture '||fixture_name,true,100);
    INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,key_number,job_card_number,customer_name,vehicle_description,make,model,current_location,
      visible_on_board,source_system,source_record_id,source_payload,created_by,updated_by)
    VALUES(vid,'control-board-rollback-'||vid,stock,'KEY-'||i,'CB-JC-'||i,'Fixture customer '||i,'Complete vehicle description '||i,'Fixture make','Fixture model','PMB',
      true,'control_board_rollback_20260915',vid::text,'{"rollback_fixture":true}',actor,actor);
    INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,first_job_card,approved_at,approved_by)
    VALUES(vid,'approved','CB-JC-'||i,clock_timestamp(),actor);
    payload:=jsonb_build_object('stock_number',stock,'repair_order_number','CB-JC-'||i,'original_line_number',1,'source_order',1,
      'department','139','operation_description','Control board fixture operation','source_estimated_hours',1,'effective_estimated_hours',1,
      'proposed_station',stage_code,'hours_provenance','source_explicit','semantic_hash',repeat('c',64),'parts_on_backorder_raw','');
    INSERT INTO public.pdc_pilbara_service_import_rows(evidence_id,batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,
      semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
    VALUES(evidence,batch,'pilbara_service_open_jobcards_v1',i,stock,'CB-JC-'||i,1,repeat('c',64),payload,'{}','insert','rollback_fixture',vid);
    INSERT INTO public.pdc_pilbara_service_operations(operation_id,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,
      operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_semantics,classification,semantic_hash,raw_evidence_id,department,proposed_station)
    VALUES(operation_id,'pilbara_service_open_jobcards_v1',stock,'CB-JC-'||i,1,1,vid,'Control board fixture operation',1,1,'source_explicit','review','Review',repeat('c',64),evidence,'139',stage_code);
    INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed) VALUES(vid,wk,true,false)
      ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true;
    INSERT INTO public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,
      actual_start_at,actual_end_at,stoppage_reason,stoppage_started_at,deleted_at,source,created_by,updated_by,metadata)
    VALUES(bid,vid,stage,CASE WHEN fixture_name='queued' THEN NULL ELSE bay END,state,
      start_at,start_at+interval '1h',60,
      CASE WHEN state IN ('started','stoppage') THEN start_at END,CASE WHEN state='completed' THEN start_at+interval '1h' END,
      CASE WHEN state='stoppage' THEN 'Fixture stop' END,CASE WHEN state='stoppage' THEN start_at END,
      CASE WHEN state='deleted' THEN clock_timestamp() END,'planner',actor,actor,'{"rollback_fixture":true}');
    IF fixture_name='inactive_bay' THEN UPDATE public.workshop_bays SET is_active=false WHERE id=bay; END IF;
    IF fixture_name='changed_location' THEN UPDATE public.vehicles SET current_location='Other' WHERE id=vid; END IF;
    IF fixture_name='hidden_vehicle' THEN UPDATE public.vehicles SET visible_on_board=false WHERE id=vid; END IF;
    IF fixture_name='inactive_vehicle' THEN UPDATE public.vehicles SET lifecycle_state='completed' WHERE id=vid; END IF;
    IF fixture_name='deleted_vehicle' THEN UPDATE public.vehicles SET deleted_at=clock_timestamp(),deleted_reason='Rollback fixture' WHERE id=vid; END IF;
    IF fixture_name='no_requirement' THEN UPDATE public.vehicle_work_items SET required=false WHERE vehicle_id=vid; END IF;
    refs:=refs||jsonb_build_object(fixture_name,jsonb_build_object('vehicle',vid,'booking',bid,'bay',bay));
  END LOOP;

  -- An active physical stage's sublet-marked row must never become a physical bay.
  SELECT id INTO stage FROM public.workshop_stages WHERE code='FITTING';
  bay:=gen_random_uuid();
  INSERT INTO public.workshop_bays(id,stage_id,bay_number,code,display_name,is_active,is_sublet_row)
  VALUES(bay,stage,999,'CB-'||bay,'Not a physical bay',true,true);
  refs:=refs||jsonb_build_object('sublet_row',jsonb_build_object('bay',bay));

  -- Current and deleted administrative reservations, entirely on a fixture bay.
  bay:=(refs->'planned'->>'bay')::uuid;
  INSERT INTO public.workshop_admin_blocks(id,stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
  VALUES(block_id,stage,bay,'admin','Fixture reserved',start_at+interval '2h',start_at+interval '3h',60,actor,actor);
  INSERT INTO public.workshop_admin_blocks(id,stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,deleted_at,created_by,updated_by)
  VALUES(deleted_block,stage,bay,'admin','Deleted fixture',start_at+interval '4h',start_at+interval '5h',60,clock_timestamp(),actor,actor);
  INSERT INTO public.workshop_admin_blocks(id,stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by)
  VALUES(expired_block,stage,bay,'admin','Expired fixture',now()-interval '2h',now()-interval '1h',60,actor,actor);

  -- The existing viewer, rather than a planner operator, can read the same RPC.
  UPDATE public.pdc_user_roles SET role='viewer' WHERE auth_user_id=actor;
  v_snapshot:=public.get_workshop_eligibility_snapshot();

  -- Exact pre-migration JSON computation on the same transaction and fixtures.
  declare
  v_now timestamptz:=now();
  v_month_start timestamptz:=date_trunc('month',now() at time zone 'Australia/Perth') at time zone 'Australia/Perth';
begin
  perform public.require_pdc_role('viewer');
  v_previous := (WITH eligibility AS MATERIALIZED (
    SELECT e.* FROM public.workshop_stages s
    CROSS JOIN LATERAL public.workshop_station_eligibility(s.code) e
    WHERE s.active AND s.planner_enabled AND s.code=e.stage_code
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
        'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
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

  v_old:=jsonb_set(v_snapshot-'board','{candidates}',coalesce((SELECT jsonb_agg(jsonb_set(x,'{vehicle}',(x->'vehicle')-'key_number') ORDER BY ordinal) FROM jsonb_array_elements(v_snapshot->'candidates') WITH ORDINALITY t(x,ordinal)),'[]'::jsonb));
  IF v_old IS DISTINCT FROM v_previous THEN RAISE EXCEPTION 'Existing stages, candidates, pipeline or semantics changed'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Exact original snapshot fields unchanged','status','PASS'));
  IF jsonb_typeof(v_snapshot->'board'->'bays')<>'array' OR jsonb_typeof(v_snapshot->'board'->'bookings')<>'array' OR jsonb_typeof(v_snapshot->'board'->'admin_blocks')<>'array' THEN RAISE EXCEPTION 'Board arrays absent'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Viewer gets additive board arrays','status','PASS'));
  FOR row_item IN SELECT s.code,count(b.id) AS count FROM public.workshop_stages s JOIN public.workshop_bays b ON b.stage_id=s.id
    WHERE s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet AND NOT b.is_sublet_row GROUP BY s.code
  LOOP
    SELECT count(*) INTO expected FROM jsonb_array_elements(v_snapshot->'board'->'bays')x WHERE x->>'stage_code'=row_item.code;
    IF expected<>row_item.count THEN RAISE EXCEPTION 'Bay count mismatch for %',row_item.code; END IF;
    checks:=checks||jsonb_build_array(jsonb_build_object('name','All configured bays for '||row_item.code,'status','PASS','count',expected));
  END LOOP;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_snapshot->'board'->'bays')x WHERE x->>'stage_code' IN ('SUBLET','PARTS','PIT_INSPECTION') OR x->>'bay_id'=refs->'sublet_row'->>'bay') THEN RAISE EXCEPTION 'Excluded stage/row leaked into board'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Disabled planners and nonphysical/Sublet rows excluded','status','PASS'));
  FOR fixture_name IN SELECT unnest(ARRAY['planned','started','stoppage','queued','inactive_bay','changed_location','no_requirement'])
  LOOP
    SELECT x INTO v_booking FROM jsonb_array_elements(v_snapshot->'board'->'bookings')x WHERE x->>'booking_id'=refs->fixture_name->>'booking';
    IF v_booking IS NULL THEN RAISE EXCEPTION 'Expected booking missing: %',fixture_name; END IF;
    IF v_booking->>'vehicle_id' IS DISTINCT FROM refs->fixture_name->>'vehicle'
      OR v_booking->'vehicle'->>'id' IS DISTINCT FROM refs->fixture_name->>'vehicle'
      OR v_booking->'vehicle'->>'key_number' IS NULL OR v_booking->'vehicle'->>'vehicle_description' NOT LIKE 'Complete vehicle description %'
      OR v_booking->'vehicle'->>'job_card_number' IS NULL THEN RAISE EXCEPTION 'Compact identity fields incomplete: %',fixture_name; END IF;
    IF fixture_name='queued' AND v_booking->'bay_id'<>'null'::jsonb THEN RAISE EXCEPTION 'Queued job falsely allocated'; END IF;
    IF fixture_name<>'queued' AND v_booking->>'bay_id' IS DISTINCT FROM refs->fixture_name->>'bay' THEN RAISE EXCEPTION 'Booking bay identity mismatch'; END IF;
    checks:=checks||jsonb_build_array(jsonb_build_object('name','Visible canonical booking '||fixture_name,'status','PASS'));
  END LOOP;
  FOR fixture_name IN SELECT unnest(ARRAY['completed_booking','deleted_booking','hidden_vehicle','inactive_vehicle','deleted_vehicle'])
  LOOP
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_snapshot->'board'->'bookings')x WHERE x->>'booking_id'=refs->fixture_name->>'booking') THEN RAISE EXCEPTION 'Hidden/history booking exposed: %',fixture_name; END IF;
    checks:=checks||jsonb_build_array(jsonb_build_object('name','Excluded '||fixture_name,'status','PASS'));
  END LOOP;
  SELECT x INTO v_bay FROM jsonb_array_elements(v_snapshot->'board'->'bays')x WHERE x->>'bay_id'=refs->'inactive_bay'->>'bay';
  IF v_bay->>'is_active' IS DISTINCT FROM 'false' OR v_bay->>'efficiency_percent' IS DISTINCT FROM '100' THEN RAISE EXCEPTION 'Inactive bay context missing'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Inactive bay and existing booking retained with correct context','status','PASS'));
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_snapshot->'board'->'admin_blocks')x WHERE x->>'block_id'=block_id::text AND x->>'label'='Fixture reserved')
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_snapshot->'board'->'admin_blocks')x WHERE x->>'block_id' IN (deleted_block::text,expired_block::text)) THEN RAISE EXCEPTION 'Administrative reservation projection wrong'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Active administrative reservations only','status','PASS'));
  IF EXISTS(SELECT 1 FROM public.workshop_bays b WHERE b.code NOT LIKE 'CB-%' AND NOT before_bays@>jsonb_build_array(to_jsonb(b))) THEN RAISE EXCEPTION 'Existing bay configuration modified'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Existing bay configuration unchanged','status','PASS'));

  PERFORM set_config('request.jwt.claims','{}',true);denied:=false;
  BEGIN PERFORM public.get_workshop_eligibility_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Unauthenticated invocation accepted'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Unauthenticated caller denied','status','PASS'));
  UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE auth_user_id=actor;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);denied:=false;
  BEGIN PERFORM public.get_workshop_eligibility_snapshot(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Inactive viewer accepted'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Inactive account denied','status','PASS'));
  IF has_function_privilege('anon','public.get_workshop_eligibility_snapshot()','EXECUTE')
    OR has_function_privilege('authenticated','public.get_workshop_snapshot(date,date)','EXECUTE') THEN RAISE EXCEPTION 'Broader read access was granted'; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('name','Existing ACL boundaries unchanged','status','PASS'));
  PERFORM set_config('pdc.control_board_test_results',checks::text,true);
END $test$;
SELECT current_setting('pdc.control_board_test_results')::jsonb AS results;
ROLLBACK;
