-- r571 (F185) / sort 343 down. PREVIEW. This file is not applied.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Restores the r567 move body and the four unpinned drop functions. Pins stay 241.
-- Department 135 is not edited.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r571 down: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r571 down: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r571 down: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r571 down: department 135 move changed'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') IS DISTINCT FROM 'r571' THEN RAISE EXCEPTION 'r571 down: move pin is not r571'; END IF;
 IF to_regprocedure('public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean)') IS NULL THEN RAISE EXCEPTION 'r571 down: helper is missing'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='slot_between_571' AND fault_id='F185' AND sort_order=343 AND added_in='r571')<>1 THEN RAISE EXCEPTION 'r571 down: check missing'; END IF;
END $g$;

DO $mv$
DECLARE src text; old text; repl text; n integer;
BEGIN
 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'));
 old:=$old$exception when sqlstate '23P01' then
  return coalesce(public.workshop_exclusion_conflict_571(v_booking.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,60),p_stage_code,p_bay_number,p_metadata,false),
    jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
 when unique_violation then$old$;
 repl:=$new$exception when unique_violation then$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: administrator_move pair 1 found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$ if coalesce(p_cascade,false) then
  -- r571 (F185): a started or stoppage booking of this vehicle cannot be pushed. Ask to place this job after it.
  v_result:=public.workshop_exclusion_conflict_571(v_booking.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,60),p_stage_code,p_bay_number,p_metadata,true);
  if v_result is not null then return v_result; end if;
  v_push:=pdc_bay_seq_private.plan_for_move(p_booking_id,v_target_bay,p_scheduled_start_at);$old$;
 repl:=$new$ if coalesce(p_cascade,false) then
  v_push:=pdc_bay_seq_private.plan_for_move(p_booking_id,v_target_bay,p_scheduled_start_at);$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: administrator_move pair 0 found % times', n; END IF;
 src:=replace(src,old,repl);
 IF strpos(src,'workshop_exclusion_conflict_571')<>0 THEN RAISE EXCEPTION 'r571 down: administrator_move still calls the helper'; END IF;
EXECUTE 'CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $move571$'||src||'$move571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'));
 old:=$old$ v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
exception when sqlstate '23P01' then
 return coalesce(public.workshop_exclusion_conflict_571(v_before.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_before.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,false),
  jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
end$old$;
 repl:=$new$ v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: move_workshop_booking pair 1 found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$select * into v_before from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 v_result:=public.workshop_exclusion_conflict_571(v_before.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_before.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,true);
 if v_result is not null then return v_result; end if;$old$;
 repl:=$new$select * into v_before from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: move_workshop_booking pair 0 found % times', n; END IF;
 src:=replace(src,old,repl);
 IF strpos(src,'workshop_exclusion_conflict_571')<>0 THEN RAISE EXCEPTION 'r571 down: move_workshop_booking still calls the helper'; END IF;
EXECUTE 'CREATE OR REPLACE FUNCTION public.move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'', ''extensions'' AS $mv571$'||src||'$mv571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'));
 old:=$old$coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('qa_namespace',v_namespace,'qa_boundary_enforced',true));
exception when sqlstate '23P01' then
 return coalesce(public.workshop_exclusion_conflict_571(v_target.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_target.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,false),
  jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
end$old$;
 repl:=$new$coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('qa_namespace',v_namespace,'qa_boundary_enforced',true));
end$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_booking_move pair 2 found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$ select * into v_target from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 v_slot571:=public.workshop_exclusion_conflict_571(v_target.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_target.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,true);
 if v_slot571 is not null then return v_slot571; end if;$old$;
 repl:=$new$ select * into v_target from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_booking_move pair 1 found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$ v_violations uuid[]:='{}'::uuid[]; v_slot571 jsonb;$old$;
 repl:=$new$ v_violations uuid[]:='{}'::uuid[];$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_booking_move pair 0 found % times', n; END IF;
 src:=replace(src,old,repl);
 IF strpos(src,'workshop_exclusion_conflict_571')<>0 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_booking_move still calls the helper'; END IF;
EXECUTE 'CREATE OR REPLACE FUNCTION public.cascade_workshop_booking_move(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $cs571$'||src||'$cs571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'));
 old:=$old$exception when sqlstate '23P01' then
  perform set_config('pdc.work_category',coalesce(previous_context,''),true);
  result:=coalesce(public.workshop_exclusion_conflict_571(p_vehicle_id,null,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,false),
    jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
  return result;
 when others then$old$;
 repl:=$new$exception when others then$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: schedule_vehicle_work pair 1 found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$result:=public.workshop_exclusion_conflict_571(p_vehicle_id,null,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,true);
 if result is not null then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return result; end if;
 result:=public.schedule_vehicle_work_pre345($old$;
 repl:=$new$result:=public.schedule_vehicle_work_pre345($new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: schedule_vehicle_work pair 0 found % times', n; END IF;
 src:=replace(src,old,repl);
 IF strpos(src,'workshop_exclusion_conflict_571')<>0 THEN RAISE EXCEPTION 'r571 down: schedule_vehicle_work still calls the helper'; END IF;
EXECUTE 'CREATE OR REPLACE FUNCTION public.schedule_vehicle_work(p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'', ''extensions'' AS $sv571$'||src||'$sv571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)'));
 old:=$old$EXCEPTION WHEN sqlstate '23P01' THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
 v_slot571:=public.workshop_exclusion_conflict_571(v_vehicle_id,case when lower(btrim(coalesce(p_operation,'')))='extend' then p_target_id else null end,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,false);
 return coalesce(v_slot571, jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true); RAISE;$old$;
 repl:=$new$EXCEPTION WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true); RAISE;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_schedule pair 2 found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$    v_vehicle_id:=p_target_id;
  end if;
  v_slot571:=public.workshop_exclusion_conflict_571(v_vehicle_id,case when lower(btrim(coalesce(p_operation,'')))='extend' then p_target_id else null end,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,true);
  if v_slot571 is not null then return v_slot571; end if;$old$;
 repl:=$new$    v_vehicle_id:=p_target_id;
  end if;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_schedule pair 1 found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$declare v_vehicle_id uuid; v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true); v_capacity_result jsonb; v_slot571 jsonb;$old$;
 repl:=$new$declare v_vehicle_id uuid; v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true); v_capacity_result jsonb;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_schedule pair 0 found % times', n; END IF;
 src:=replace(src,old,repl);
 IF strpos(src,'workshop_exclusion_conflict_571')<>0 THEN RAISE EXCEPTION 'r571 down: cascade_workshop_schedule still calls the helper'; END IF;
EXECUTE 'CREATE OR REPLACE FUNCTION public.cascade_workshop_schedule(p_operation text, p_target_id uuid, p_target_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_shift_minutes integer, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $csch571$'||src||'$csch571$';
END $mv$;

DROP FUNCTION public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean);

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(replace(check_sql, 's.pin_release = ''r571''', 's.pin_release = ''r567'''), 'WHERE e.release = ''r571''', 'WHERE e.release = ''r567''')
 WHERE check_name='cross_station_drop_567' AND fault_id='F181' AND sort_order=341 AND added_in='r567';

UPDATE pdc_ops.expected_function_md5 SET
 prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),
 release='r567',
 note='r567: a cascade drop names and can push the same vehicle in another station (was 79f284b178ca2170bf8972c9cd83ce29, r552)',
 updated_at=now()
 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'
   AND release='r571';

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='slot_between_571' AND fault_id='F185' AND sort_order=343 AND added_in='r571';

NOTIFY pgrst, 'reload schema';

DO $post$
DECLARE y record; acl text; cfg text;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r571 down: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r571')<>0 THEN RAISE EXCEPTION 'r571 down: r571 pin remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r567')<>1 THEN RAISE EXCEPTION 'r571 down: r567 pin missing'; END IF;
 IF to_regprocedure('public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r571 down: helper remains'; END IF;
 IF strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),'r571')<>0 THEN RAISE EXCEPTION 'r571 down: move body still names r571'; END IF;
 IF strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),'r567 (F181)')=0 THEN RAISE EXCEPTION 'r571 down: r567 marker missing'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS NOT TRUE THEN RAISE EXCEPTION 'r571 down: move is not security definer'; END IF;
 SELECT proconfig::text, proacl::text INTO cfg, acl FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)');
 IF cfg IS DISTINCT FROM '{search_path=pg_catalog, public}' THEN RAISE EXCEPTION 'r571 down: search_path changed (%)', cfg; END IF;
 IF acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r571 down: grants changed (%)', acl; END IF;
 IF (SELECT proconfig::text FROM pg_proc WHERE oid=to_regprocedure('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) IS DISTINCT FROM '{search_path=pg_catalog, public, extensions}' THEN RAISE EXCEPTION 'r571 down: move_workshop_booking search_path changed'; END IF;
 IF (SELECT proconfig::text FROM pg_proc WHERE oid=to_regprocedure('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)')) IS DISTINCT FROM '{search_path=pg_catalog, public, extensions}' THEN RAISE EXCEPTION 'r571 down: schedule_vehicle_work search_path changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r571 down: department 135 move changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='slot_between_571')<>0 THEN RAISE EXCEPTION 'r571 down: check remains'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_567' AND fault_id='F181' AND sort_order=341 AND added_in='r567') INTO y;
 IF coalesce(y.ok,false) IS NOT TRUE THEN RAISE EXCEPTION 'r571 down: r567 check failed: %', y.detail; END IF;
END $post$;
