-- r607 (F221) undo. Staging cdsmnqxtyyoeoznmbidd only.
-- Puts administrator_schedule_workshop_vehicle back to the r417 body and workshop_capture_capacity_basis back
-- to the r415 body, restores both pins and removes the F221 check. It does not rewrite booking rows:
-- Key 460 keeps the 225-minute length Craig set (r607 only made the server honour it).

SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '60s';

DO $g$ BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r607 undo: staging only'; END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r607 undo: run between :02 and :45'; END IF;
END $g$;

DO $u607a$
DECLARE
  def text;
  sig regprocedure := 'public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure;
  old_decl text := $o$ v_rules jsonb:='[]'::jsonb;
begin$o$;
  new_decl text := $n$ v_rules jsonb:='[]'::jsonb;
 v607_requested timestamptz:=p_scheduled_start_at; v607_placement text:='as_dropped'; v607_live jsonb; v607_end timestamptz; v607_under timestamptz;
begin$n$;
  old_lock text := $o$ perform 1 from public.vehicles where id=p_vehicle_id for update;
 if p_cascade then
 select coalesce(array_agg$o$;
  new_lock text := $n$ perform 1 from public.vehicles where id=p_vehicle_id for update;
 -- r607 (F221): a drop from Unallocated is placed where it can be kept, the same way a moved job is.
 -- Over a running or stopped job it goes right after that job's real end (r592 / r598 helper).
 -- Inside a planned job it takes that job's start; that job and the ones behind it move back below.
 if p_cascade then
   v607_end:=pdc_cascade_private.target_end_469(p_vehicle_id,v_bay,p_scheduled_start_at,p_duration_minutes);
   if v607_end is not null and v607_end>p_scheduled_start_at then
     v607_live:=pdc_ops.place_after_live_bay_592(null,v_bay,p_scheduled_start_at,v607_end,p_duration_minutes,coalesce(p_metadata,'{}'::jsonb));
     if v607_live->>'action'='fail' then
       perform set_config('pdc.work_category',coalesce(previous_context,''),true);
       return pdc_bay_rules_private.finish(v_rules,null,v607_live->'body');
     elsif v607_live->>'action'='snap' then
       p_scheduled_start_at:=(v607_live->>'start_at')::timestamptz;
       v607_placement:='after_running';
     end if;
   end if;
   select min(b.scheduled_start_at) into v607_under from public.workshop_bookings b
   where b.deleted_at is null and b.status='planned' and b.bay_id=v_bay
     and b.scheduled_start_at<p_scheduled_start_at
     and b.scheduled_start_at>=date_trunc('minute',statement_timestamp())
     and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at;
   if v607_under is not null then
     p_scheduled_start_at:=v607_under;
     v607_placement:='before_planned';
   end if;
 end if;
 if p_cascade then
 select coalesce(array_agg$n$;
  old_res text := $o$ v_result:=v_result||jsonb_build_object('booking_id',v_booking_id,'booking_version',v_booking_version,'operation_type','create');$o$;
  new_res text := $n$ v_result:=v_result||jsonb_build_object('booking_id',v_booking_id,'booking_version',v_booking_version,'operation_type','create',
   'requested_start_at',v607_requested,'placed_start_at',p_scheduled_start_at,'placement',v607_placement);$n$;
BEGIN
  def := pg_get_functiondef(sig);
  IF strpos(def,'r607 (F221)')=0 THEN RAISE EXCEPTION 'r607 undo: wrapper is not the r607 body'; END IF;
  def := replace(replace(replace(def,new_res,old_res),new_lock,old_lock),new_decl,old_decl);
  EXECUTE def;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=sig) IS DISTINCT FROM '50c3c198c6ccd360390442043e18ce72' THEN RAISE EXCEPTION 'r607 undo: wrapper checksum'; END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid=sig) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r607 undo: wrapper grants'; END IF;
END $u607a$;

DO $u607b$
DECLARE
  def text;
  sig regprocedure := 'public.workshop_capture_capacity_basis()'::regprocedure;
  old_live text := $o$ -- Completed/live history and its applied duration stay fixed.
 IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN('queued','planned') THEN$o$;
  new_live text := $n$ -- r607 (F221): a deliberate resize of a running or stopped job sets its real length to the new length,
 -- so the bay frees up where the chip now ends. Only resize_workshop_booking sets this context, for one
 -- booking, its version and the new length, in the same transaction.
 IF TG_OP='UPDATE' AND NEW.deleted_at IS NULL AND NEW.status IN('started','stoppage') AND OLD.status=NEW.status
  AND NEW.default_duration_minutes>=1
  AND coalesce(nullif(current_setting('pdc.workshop_capacity_manual',true),''),'{}')::jsonb
      @> jsonb_build_object('booking',NEW.id,'version',OLD.version,'duration',NEW.default_duration_minutes)
  AND (coalesce(nullif(current_setting('pdc.workshop_capacity_manual',true),''),'{}')::jsonb->>'actor') IS NOT DISTINCT FROM auth.uid()::text THEN
  NEW.capacity_efficiency_percent:=coalesce(OLD.capacity_efficiency_percent,100);
  NEW.capacity_base_minutes:=NEW.default_duration_minutes::numeric*NEW.capacity_efficiency_percent/100;
  NEW.capacity_estimate_minutes:=pdc_work_categories_private.minutes(NEW.id,NEW.vehicle_id,NEW.stage_id);
  RETURN NEW;
 END IF;
 -- Completed/live history and its applied duration stay fixed.
 IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN('queued','planned') THEN$n$;
BEGIN
  def := pg_get_functiondef(sig);
  IF strpos(def,'r607 (F221)')=0 THEN RAISE EXCEPTION 'r607 undo: trigger is not the r607 body'; END IF;
  EXECUTE replace(def,new_live,old_live);
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=sig) IS DISTINCT FROM '7dcc9b114f5484722febaa769253d54b' THEN RAISE EXCEPTION 'r607 undo: trigger checksum'; END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid=sig) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r607 undo: trigger grants'; END IF;
END $u607b$;

DO $pin$
DECLARE n integer;
BEGIN
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='50c3c198c6ccd360390442043e18ce72', release='r417', note='F32: bay rule mismatch warns; confirmed overrides are logged', updated_at=now()
  WHERE signature='public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamp with time zone,integer,uuid,jsonb,uuid,boolean)' AND release='r607';
  GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'r607 undo: wrapper pin'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='7dcc9b114f5484722febaa769253d54b', release='r415', note='F31: started-then-returned jobs resume for re-planning', updated_at=now()
  WHERE signature='public.workshop_capture_capacity_basis()' AND release='r607';
  GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'r607 undo: trigger pin'; END IF;
  DELETE FROM pdc_ops.regression_checks WHERE check_name='unallocated_drop_place_607' AND fault_id='F221' AND added_in='r607';
  GET DIAGNOSTICS n=ROW_COUNT; IF n<>1 THEN RAISE EXCEPTION 'r607 undo: check not removed'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r607 undo: pin count'; END IF;
END $pin$;
