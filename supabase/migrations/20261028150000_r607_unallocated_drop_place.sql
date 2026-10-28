-- r607 (F221) / sort 376. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026 11:35 AWST, Workshop Planner PMB (139) Hoist: dragging Key 448 (stock 13016924)
-- from Unallocated onto Jason Ranoco's bay kept failing with "That bay is already occupied during this
-- time" and "Jason Ranoco is already booked on stock 13073120 ... No booking was saved".
--
-- Root cause, two parts:
-- 1. A new booking from Unallocated (administrator_schedule_workshop_vehicle, cascade insert) only pushed
--    planned jobs that START at or after the drop point. A drop onto the running job (Key 460) or into
--    the middle of a planned job left that job where it was, so the new booking overlapped it and the
--    whole drop was refused (bay_overlap, or technician_overlap when the bay mechanic was checked first).
--    A moved booking already handles both cases (r592 / r598 place-after, and the overlap chain), the
--    Unallocated drop did not.
-- 2. Craig shortened running Key 460 to end 15:04 at 11:34:53. The chip moved, but the trigger
--    workshop_capture_capacity_basis keeps a running job's capacity fixed, so the server still held the
--    bay until 16:19. Dropping into the free-looking space after 15:04 was refused.
--
-- Fix:
-- 1. administrator_schedule_workshop_vehicle (cascade drops only): a drop that overlaps a running or
--    stopped job is placed at that job's real end (pdc_ops.place_after_live_bay_592, same as a move).
--    A drop inside a planned job takes that job's start, and that job and the ones behind it move back
--    in the same step. The result says where it went (requested_start_at, placed_start_at, placement).
--    Best slot (cascade false) is unchanged.
-- 2. workshop_capture_capacity_basis: a deliberate resize of a running or stopped job (resize_workshop_booking
--    sets pdc.workshop_capacity_manual for that booking, version and length) sets the job's real length to
--    the new length. Nothing else changes for running jobs. Key 460 is repaired to its 225-minute resize.
--
-- Pin count stays 241: both functions are already pinned (r417, r415) and are re-pinned as r607.
-- Department 135 (karratha135_pdc) is not edited.
-- Undo: supabase/rollbacks/20261028150000_r607_unallocated_drop_place.down.sql

SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '60s';

DO $g607$
DECLARE awst time;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF (awst >= time '06:50' AND awst < time '07:30')
     OR (awst >= time '12:15' AND awst < time '12:45')
     OR (awst >= time '17:50' AND awst < time '18:10') THEN
    RAISE EXCEPTION 'r607: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r607: run between :02 and :45 (the clock tick runs at :00)';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r607: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r607: pin count is not 241'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=376 OR fault_id='F221' OR added_in='r607' OR check_name='unallocated_drop_place_607') THEN
    RAISE EXCEPTION 'r607: sort 376 / F221 is taken';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'))
     IS DISTINCT FROM '50c3c198c6ccd360390442043e18ce72' THEN RAISE EXCEPTION 'r607: schedule wrapper is not the r417 body'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_capture_capacity_basis()'))
     IS DISTINCT FROM '7dcc9b114f5484722febaa769253d54b' THEN RAISE EXCEPTION 'r607: capacity trigger is not the r415 body'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_ops.place_after_live_bay_592(uuid,uuid,timestamptz,timestamptz,integer,jsonb)'))
     IS DISTINCT FROM 'fdb2b641534c4bafaacd5ee35b59b6ba' THEN RAISE EXCEPTION 'r607: place-after helper is not the r598 body'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_resize_booking(uuid,integer,integer,jsonb)'))
     IS DISTINCT FROM '81b1f4829a0c59cfd91a39665aadeb58' THEN RAISE EXCEPTION 'r607: resize body changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
     IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r607: department 135 changed'; END IF;
END $g607$;

-- 1. The Unallocated drop places itself like a move does.
DO $p607a$
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
  IF (length(def)-length(replace(def,old_decl,'')))/length(old_decl)<>1 THEN RAISE EXCEPTION 'r607: declare anchor'; END IF;
  IF (length(def)-length(replace(def,old_lock,'')))/length(old_lock)<>1 THEN RAISE EXCEPTION 'r607: lock anchor'; END IF;
  IF (length(def)-length(replace(def,old_res,'')))/length(old_res)<>1 THEN RAISE EXCEPTION 'r607: result anchor'; END IF;
  def := replace(replace(replace(def,old_decl,new_decl),old_lock,new_lock),old_res,new_res);
  EXECUTE def;
  IF (SELECT strpos(prosrc,'r607 (F221)')>0 AND strpos(prosrc,'pdc_ops.place_after_live_bay_592(null,v_bay')>0
       AND strpos(prosrc,'pdc_bay_rules_private.warning(v_rules)')>0 FROM pg_proc WHERE oid=sig) IS NOT TRUE THEN
    RAISE EXCEPTION 'r607: wrapper patch not in place';
  END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid=sig) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN
    RAISE EXCEPTION 'r607: wrapper grants changed';
  END IF;
END $p607a$;

-- 2. A resize of a running or stopped job sets its real length.
DO $p607b$
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
  IF (length(def)-length(replace(def,old_live,'')))/length(old_live)<>1 THEN RAISE EXCEPTION 'r607: trigger anchor'; END IF;
  EXECUTE replace(def,old_live,new_live);
  IF (SELECT strpos(prosrc,'r607 (F221)')>0 AND strpos(prosrc,'pdc.workshop_resume_415')>0 FROM pg_proc WHERE oid=sig) IS NOT TRUE THEN
    RAISE EXCEPTION 'r607: trigger patch not in place';
  END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid=sig) IS DISTINCT FROM '{postgres=X/postgres}' THEN
    RAISE EXCEPTION 'r607: trigger grants changed';
  END IF;
END $p607b$;

-- 3. Re-pin both functions. Pin count stays 241.
DO $pin607$
DECLARE n integer;
BEGIN
  UPDATE pdc_ops.expected_function_md5 e
  SET prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(e.signature)), release='r607',
      note='r607 (F221): '||CASE WHEN e.signature LIKE '%capture_capacity_basis%'
        THEN 'a resize of a running or stopped job sets its real length'
        ELSE 'an Unallocated drop is placed after a running job or before the planned job it lands in' END,
      updated_at=now()
  WHERE e.signature IN ('public.workshop_capture_capacity_basis()',
    'public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamp with time zone,integer,uuid,jsonb,uuid,boolean)');
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>2 THEN RAISE EXCEPTION 'r607: re-pin touched % rows', n; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r607: pin count moved'; END IF;
END $pin607$;

-- 4. Repair Key 460 (booking 0b48d8ac, running in Jason Ranoco's Hoist bay). Craig resized it to
-- 225 minutes at 11:34:53 AWST; the server kept 300. Only this row, only if it is still exactly that.
DO $fix607$
DECLARE
  v_id uuid := '0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd';
  v_before jsonb; v_after jsonb; v_version integer; n integer;
BEGIN
  SELECT version INTO v_version FROM public.workshop_bookings
  WHERE id=v_id AND deleted_at IS NULL AND status='started' AND default_duration_minutes=225
    AND public.workshop_booking_effective_duration_minutes(id)<>225;
  IF v_version IS NULL THEN
    RAISE NOTICE 'r607: Key 460 no longer needs the repair; skipped';
    RETURN;
  END IF;
  -- Recorded as Craig, who asked for this fix and made the 225-minute resize.
  PERFORM set_config('request.jwt.claims', jsonb_build_object('sub','8a83b715-8d79-4b0e-95b2-02b55da6e8d7',
    'role','authenticated','email','craig.watson@broometoyota.com.au')::text, true);
  v_before := public.workshop_booking_snapshot(v_id);
  PERFORM set_config('pdc.workshop_capacity_manual',
    jsonb_build_object('actor',auth.uid(),'booking',v_id,'version',v_version,'duration',225)::text,true);
  UPDATE public.workshop_bookings SET version=version+1
  WHERE id=v_id AND version=v_version AND status='started' AND default_duration_minutes=225;
  GET DIAGNOSTICS n=ROW_COUNT;
  PERFORM set_config('pdc.workshop_capacity_manual','',true);
  IF n<>1 THEN RAISE EXCEPTION 'r607: Key 460 repair touched % rows', n; END IF;
  IF public.workshop_booking_effective_duration_minutes(v_id)<>225 THEN RAISE EXCEPTION 'r607: Key 460 real length is not 225'; END IF;
  v_after := public.workshop_booking_snapshot(v_id);
  PERFORM public.workshop_write_history(v_id,'capacity_repaired',v_before,v_after,
    jsonb_build_object('release','r607','fault','F221','reason','running resize to 225 minutes at 11:34:53 AWST was not applied to the real length'));
  PERFORM set_config('request.jwt.claims', '', true);
END $fix607$;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('unallocated_drop_place_607', 'F221',
 'A drop from Unallocated onto a bay is placed after a running or stopped job, or before the planned job it lands in, instead of being refused (r607). A resize of a running or stopped job sets its real length, so no running job ends later on the server than its chip after a resize.',
$chk$
SELECT
  strpos(w.prosrc,'r607 (F221)')>0
  AND strpos(w.prosrc,'pdc_ops.place_after_live_bay_592(null,v_bay')>0
  AND strpos(w.prosrc,'before_planned')>0
  AND strpos(w.prosrc,'pdc_bay_rules_private.warning(v_rules)')>0
  AND strpos(t.prosrc,'r607 (F221)')>0
  AND strpos(t.prosrc,'pdc.workshop_resume_415')>0
  AND md5(w.prosrc)=(SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamp with time zone,integer,uuid,jsonb,uuid,boolean)' AND release='r607')
  AND md5(t.prosrc)=(SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_capture_capacity_basis()' AND release='r607')
  AND stale.n=0
  AS ok,
  'drop placement '||CASE WHEN strpos(w.prosrc,'r607 (F221)')>0 THEN 'on' ELSE 'MISSING' END
  ||'; running resize '||CASE WHEN strpos(t.prosrc,'r607 (F221)')>0 THEN 'on' ELSE 'MISSING' END
  ||'; running jobs resized since r607 whose real length is not the resize: '||stale.n AS detail
FROM pg_proc w
CROSS JOIN (SELECT prosrc FROM pg_proc WHERE oid='public.workshop_capture_capacity_basis()'::regprocedure) t
CROSS JOIN (
  SELECT count(*) AS n
  FROM public.workshop_bookings b
  WHERE b.deleted_at IS NULL AND b.status IN ('started','stoppage')
    AND public.workshop_booking_effective_duration_minutes(b.id)<>b.default_duration_minutes
    AND EXISTS (SELECT 1 FROM public.workshop_booking_history h
                WHERE h.booking_id=b.id AND h.event_type='resized' AND h.created_at>'2026-10-28 07:00:00+00'
                  AND (h.after_data->>'status') IN ('started','stoppage')
                  AND (h.after_data->>'default_duration_minutes')::integer=b.default_duration_minutes)
) stale
WHERE w.oid='public.administrator_schedule_workshop_vehicle(uuid,integer,text,integer,timestamptz,integer,uuid,jsonb,uuid,boolean)'::regprocedure
$chk$,
true, 376, 'r607');
