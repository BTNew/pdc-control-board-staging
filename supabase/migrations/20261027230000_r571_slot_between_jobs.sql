-- r571 (F185) / sort 343. Go-live of #559.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Stacked on live #557 (r576 / F190 / sort 347, check cross_station_drop_576).
-- r571 / F185 / sort 343 is free. Pins stay 241. The move pin moves in place from r576.
-- Department 135 is not edited. The move body must be b6e8241730be349bdd79a295afba0a8a.
-- A timed drop pushes later jobs in that bay. A started or stoppage booking of the
-- same vehicle cannot move; the planner is asked to place this job after it.
-- A leftover exclusion error is returned as that booking, not a raw 23P01.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r571: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r571: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r571: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r571: department 135 move changed'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_job_pause_569' AND fault_id='F183' AND sort_order=340 AND added_in='r569') THEN RAISE EXCEPTION 'r571: r569 / F183 sort 340 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_576' AND fault_id='F190' AND sort_order=347 AND added_in='r576') THEN RAISE EXCEPTION 'r571: r576 cross-station drop is not present'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') IS DISTINCT FROM 'r576' THEN RAISE EXCEPTION 'r571: move pin is not r576'; END IF;
 IF strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),'r576 (F190)')=0 THEN RAISE EXCEPTION 'r571: r576 body is not present'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM 'b6e8241730be349bdd79a295afba0a8a' THEN RAISE EXCEPTION 'r571: move body is not the live r576 body'; END IF;
 IF to_regprocedure('public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean)') IS NOT NULL THEN RAISE EXCEPTION 'r571: helper already exists'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=343 OR fault_id='F185' OR check_name='slot_between_571' OR added_in='r571') THEN RAISE EXCEPTION 'r571: sort 343 or F185 is taken'; END IF;
END $g$;

CREATE FUNCTION public.workshop_exclusion_conflict_571(p_vehicle_id uuid, p_exclude uuid, p_start timestamptz, p_minutes integer, p_stage_code text, p_bay_number integer, p_metadata jsonb, p_running_only boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $fn$
declare
 v_bay uuid; v_end timestamptz; v_after timestamptz; v_minutes integer; v_pushes integer; v_row record;
begin
 -- r571 (F185): name the booking the exclusion constraint would reject.
 if p_vehicle_id is null or p_start is null then return null; end if;
 select bay.id into v_bay from public.workshop_bays bay
  join public.workshop_stages s on s.id=bay.stage_id
  where s.code=p_stage_code and bay.bay_number=p_bay_number
  limit 1;
 v_minutes:=greatest(coalesce(p_minutes,60),1);
 if v_bay is not null then v_end:=pdc_bay_seq_private.end_at(p_start,v_minutes,v_bay); end if;
 if v_end is null or v_end<=p_start then v_end:=p_start + make_interval(mins=>v_minutes); end if;
 select b.id, b.status, b.scheduled_start_at, b.scheduled_end_at, b.vehicle_id,
   v.key_number, v.stock_number, v.customer_name, s.display_name as stage_name, s.code as stage_code,
   bay.bay_number, bay.display_name as bay_name
  into v_row
  from public.workshop_bookings b
  join public.vehicles v on v.id=b.vehicle_id
  left join public.workshop_stages s on s.id=b.stage_id
  left join public.workshop_bays bay on bay.id=b.bay_id
  where b.vehicle_id=p_vehicle_id and b.id is distinct from p_exclude and b.deleted_at is null
   and not b.legacy_ambiguity_quarantined
   and b.status in ('queued','planned','started','stoppage')
   and not (b.status='queued' and b.bay_id is null)
   and (not coalesce(p_running_only,true) or b.status in ('started','stoppage'))
   and tstzrange(b.scheduled_start_at, b.scheduled_end_at, '[)') && tstzrange(p_start, v_end, '[)')
  order by case when b.status in ('started','stoppage') then 0 else 1 end, b.scheduled_start_at
  limit 1;
 if v_row.id is null then return null; end if;
 if v_row.status in ('started','stoppage') then
  if v_bay is not null then v_after:=pdc_bay_seq_private.end_at(v_row.scheduled_end_at,60,v_bay); end if;
  if v_after is null or v_after<=v_row.scheduled_end_at then v_after:=v_row.scheduled_end_at + interval '60 minutes'; end if;
  select count(*) into v_pushes from public.workshop_bookings o
   where o.deleted_at is null and v_bay is not null and o.bay_id=v_bay and o.id is distinct from p_exclude
    and o.status in ('queued','planned') and o.scheduled_start_at>=v_after and o.scheduled_start_at<v_after + interval '1 day';
  return jsonb_build_object('ok',false,'warning',true,'requires_confirmation',true,'error','place_after_running',
    'plan_hash', md5(v_row.id::text||'|'||v_after::text), 'place_after', v_after, 'bay_push_count', coalesce(v_pushes,0),
    'message', 'Key '||coalesce(v_row.key_number,'')||', stock '||coalesce(v_row.stock_number,'')||', '||coalesce(v_row.customer_name,'')
      ||' is '||case when v_row.status='started' then 'already running' else 'on stoppage' end
      ||' in '||coalesce(v_row.stage_name,'another station')||', '||coalesce(v_row.bay_name,'Unallocated')
      ||', until '||to_char(v_row.scheduled_end_at at time zone 'Australia/Perth','Dy DD Mon HH24:MI')
      ||'. That booking cannot move. Place this job right after it'
      ||case when coalesce(v_pushes,0)>0 then '. Later jobs in this bay move back too' else '' end||'.',
    'held', jsonb_build_object('booking_id',v_row.id,'key_number',v_row.key_number,'stock_number',v_row.stock_number,
      'customer_name',v_row.customer_name,'stage_name',v_row.stage_name,'bay_display_name',coalesce(v_row.bay_name,'Unallocated'),
      'bay_number',v_row.bay_number,'status',v_row.status,'from_start',v_row.scheduled_start_at,'to_end',v_row.scheduled_end_at),
    'conflict_booking_id', v_row.id,
    'conflict', jsonb_build_object('conflict_type','vehicle_overlap','existing_booking', jsonb_build_object(
      'booking_id',v_row.id,'vehicle_id',v_row.vehicle_id,'status',v_row.status,
      'scheduled_start_at',v_row.scheduled_start_at,'scheduled_end_at',v_row.scheduled_end_at,
      'vehicle', jsonb_build_object('id',v_row.vehicle_id,'stock_number',v_row.stock_number,'key_number',v_row.key_number,'customer_name',v_row.customer_name),
      'stage', jsonb_build_object('code',v_row.stage_code,'display_name',v_row.stage_name),
      'bay', jsonb_build_object('bay_number',v_row.bay_number,'display_name',coalesce(v_row.bay_name,'Unallocated')))));
 end if;
 return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_row.id,
  'conflict', jsonb_build_object('conflict_type','vehicle_overlap','existing_booking', jsonb_build_object(
    'booking_id',v_row.id,'vehicle_id',v_row.vehicle_id,'status',v_row.status,
    'scheduled_start_at',v_row.scheduled_start_at,'scheduled_end_at',v_row.scheduled_end_at,
    'vehicle', jsonb_build_object('id',v_row.vehicle_id,'stock_number',v_row.stock_number,'key_number',v_row.key_number,'customer_name',v_row.customer_name),
    'stage', jsonb_build_object('code',v_row.stage_code,'display_name',v_row.stage_name),
    'bay', jsonb_build_object('bay_number',v_row.bay_number,'display_name',coalesce(v_row.bay_name,'Unallocated')))));
end
$fn$;

REVOKE ALL ON FUNCTION public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean) FROM PUBLIC, anon, authenticated;

DO $mv$
DECLARE src text; newsrc text; old text; repl text; n integer;
BEGIN
 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'));
 newsrc:=src;
 old:=$old$ if coalesce(p_cascade,false) then
  v_push:=pdc_bay_seq_private.plan_for_move(p_booking_id,v_target_bay,p_scheduled_start_at);$old$;
 repl:=$new$ if coalesce(p_cascade,false) then
  -- r571 (F185): a started or stoppage booking of this vehicle cannot be pushed. Ask to place this job after it.
  v_result:=public.workshop_exclusion_conflict_571(v_booking.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,60),p_stage_code,p_bay_number,p_metadata,true);
  if v_result is not null then return v_result; end if;
  v_push:=pdc_bay_seq_private.plan_for_move(p_booking_id,v_target_bay,p_scheduled_start_at);$new$;
 n:=(length(newsrc)-length(replace(newsrc,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: cascade pre-check anchor found % times', n; END IF;
 newsrc:=replace(newsrc,old,repl);
 old:=$old$exception when unique_violation then$old$;
 repl:=$new$exception when sqlstate '23P01' then
  return coalesce(public.workshop_exclusion_conflict_571(v_booking.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,60),p_stage_code,p_bay_number,p_metadata,false),
    jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
 when unique_violation then$new$;
 n:=(length(newsrc)-length(replace(newsrc,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: move exception anchor found % times', n; END IF;
 newsrc:=replace(newsrc,old,repl);
 IF strpos(newsrc,'r571 (F185)')=0 OR strpos(newsrc,'r576 (F190)')=0 THEN RAISE EXCEPTION 'r571: move markers missing'; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $move571$'||newsrc||'$move571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'));
 old:=$old$select * into v_before from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;$old$;
 repl:=$new$select * into v_before from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 v_result:=public.workshop_exclusion_conflict_571(v_before.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_before.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,true);
 if v_result is not null then return v_result; end if;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: move_workshop_booking anchor found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$ v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end$old$;
 repl:=$new$ v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
exception when sqlstate '23P01' then
 return coalesce(public.workshop_exclusion_conflict_571(v_before.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_before.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,false),
  jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
end$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: move_workshop_booking exception anchor found % times', n; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'', ''extensions'' AS $mv571$'||replace(src,old,repl)||'$mv571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'));
 old:=$old$ v_violations uuid[]:='{}'::uuid[];$old$;
 repl:=$new$ v_violations uuid[]:='{}'::uuid[]; v_slot571 jsonb;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: cascade declare anchor found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$ select * into v_target from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;$old$;
 repl:=$new$ select * into v_target from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 v_slot571:=public.workshop_exclusion_conflict_571(v_target.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_target.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,true);
 if v_slot571 is not null then return v_slot571; end if;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: cascade load anchor found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('qa_namespace',v_namespace,'qa_boundary_enforced',true));
end$old$;
 repl:=$new$coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('qa_namespace',v_namespace,'qa_boundary_enforced',true));
exception when sqlstate '23P01' then
 return coalesce(public.workshop_exclusion_conflict_571(v_target.vehicle_id,p_booking_id,p_scheduled_start_at,coalesce(p_duration_minutes,v_target.default_duration_minutes),p_stage_code,p_bay_number,p_metadata,false),
  jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
end$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: cascade exception anchor found % times', n; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.cascade_workshop_booking_move(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $cs571$'||replace(src,old,repl)||'$cs571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)'));
 old:=$old$result:=public.schedule_vehicle_work_pre345($old$;
 repl:=$new$result:=public.workshop_exclusion_conflict_571(p_vehicle_id,null,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,true);
 if result is not null then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return result; end if;
 result:=public.schedule_vehicle_work_pre345($new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: schedule anchor found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$exception when others then$old$;
 repl:=$new$exception when sqlstate '23P01' then
  perform set_config('pdc.work_category',coalesce(previous_context,''),true);
  result:=coalesce(public.workshop_exclusion_conflict_571(p_vehicle_id,null,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,false),
    jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
  return result;
 when others then$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: schedule exception anchor found % times', n; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.schedule_vehicle_work(p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'', ''extensions'' AS $sv571$'||replace(src,old,repl)||'$sv571$';

 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)'));
 old:=$old$declare v_vehicle_id uuid; v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true); v_capacity_result jsonb;$old$;
 repl:=$new$declare v_vehicle_id uuid; v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true); v_capacity_result jsonb; v_slot571 jsonb;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: cascade schedule declare anchor found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$    v_vehicle_id:=p_target_id;
  end if;$old$;
 repl:=$new$    v_vehicle_id:=p_target_id;
  end if;
  v_slot571:=public.workshop_exclusion_conflict_571(v_vehicle_id,case when lower(btrim(coalesce(p_operation,'')))='extend' then p_target_id else null end,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,true);
  if v_slot571 is not null then return v_slot571; end if;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: cascade schedule vehicle anchor found % times', n; END IF;
 src:=replace(src,old,repl);
 old:=$old$EXCEPTION WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true); RAISE;$old$;
 repl:=$new$EXCEPTION WHEN sqlstate '23P01' THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
 v_slot571:=public.workshop_exclusion_conflict_571(v_vehicle_id,case when lower(btrim(coalesce(p_operation,'')))='extend' then p_target_id else null end,p_scheduled_start_at,p_duration_minutes,p_stage_code,p_bay_number,p_metadata,false);
 return coalesce(v_slot571, jsonb_build_object('ok',false,'error','vehicle_overlap','message','This vehicle is already booked at that time. No update was saved.'));
WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true); RAISE;$new$;
 n:=(length(src)-length(replace(src,old,'')))/length(old);
 IF n<>1 THEN RAISE EXCEPTION 'r571: cascade schedule exception anchor found % times', n; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.cascade_workshop_schedule(p_operation text, p_target_id uuid, p_target_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_shift_minutes integer, p_override_reason text, p_metadata jsonb)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $csch571$'||replace(src,old,repl)||'$csch571$';
END $mv$;

UPDATE pdc_ops.expected_function_md5 SET
 prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),
 release='r571',
 note='r571: a drop between jobs pushes that bay; a running booking of the same vehicle offers a start after it (was r576)',
 updated_at=now()
 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'
   AND release='r576';

UPDATE pdc_ops.regression_checks
 SET check_sql=replace(replace(check_sql, 's.pin_release = ''r576''', 's.pin_release = ''r571'''), 'WHERE e.release = ''r576''', 'WHERE e.release = ''r571''')
 WHERE check_name='cross_station_drop_576' AND fault_id='F190' AND sort_order=347 AND added_in='r576';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('slot_between_571','F185',
 'A timed drop pushes later jobs in that bay, on a station bay and on a shared bay. A started or stoppage booking of the same vehicle is not pushed. The planner is asked to place this job after that booking. A leftover vehicle exclusion is returned with the vehicle, the bay and the time. Craig, 27 Oct 2026 11:46 AWST, dropped Key 112 tint acd1a2d7 onto Tint Bay 01. The exclusion workshop_bookings_active_vehicle_no_overlap fired on fitting stoppage 6d92ccca, which has no bay and still occupies 27 Oct 08:28 to 28 Oct 07:08 Perth. Department 135 is not edited. The check does not require those rows to stay in conflict.',
 $chk571$
SELECT
  pg_catalog.strpos(s.mv, 'r571 (F185)') > 0
  AND pg_catalog.strpos(s.mv, 'r576 (F190)') > 0
  AND pg_catalog.strpos(s.mv, 'place_after_running') = 0
  AND pg_catalog.strpos(s.helper, 'place_after_running') > 0
  AND pg_catalog.strpos(s.helper, 'r571 (F185)') > 0
  AND pg_catalog.strpos(s.cs, 'workshop_exclusion_conflict_571') > 0
  AND pg_catalog.strpos(s.mvb, 'workshop_exclusion_conflict_571') > 0
  AND pg_catalog.strpos(s.sv, 'workshop_exclusion_conflict_571') > 0
  AND pg_catalog.strpos(s.csch, 'workshop_exclusion_conflict_571') > 0
  AND pg_catalog.strpos(s.mv, 'sqlstate ''23P01''') > 0
  AND pg_catalog.strpos(s.cs, 'sqlstate ''23P01''') > 0
  AND pg_catalog.strpos(s.mvb, 'sqlstate ''23P01''') > 0
  AND pg_catalog.strpos(s.sv, 'sqlstate ''23P01''') > 0
  AND pg_catalog.strpos(s.csch, 'sqlstate ''23P01''') > 0
  AND pg_catalog.md5(s.mv) = s.pin_md5
  AND s.pin_release = 'r571'
  AND s.r571_pins = 1
  AND s.k_md5 = '4eb5baf999b849d174880a1e261fcbf2'
  AND pg_catalog.strpos(s.k_src, 'r571') = 0
  AS ok,
  'move '||coalesce(pg_catalog.md5(s.mv), 'missing')||' pin '||coalesce(s.pin_md5, 'missing') AS detail
FROM (
 SELECT
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'administrator_move_workshop_booking'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean') AS mv,
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'workshop_exclusion_conflict_571') AS helper,
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'cascade_workshop_booking_move'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb') AS cs,
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'move_workshop_booking'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb') AS mvb,
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'schedule_vehicle_work'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_override_reason text, p_metadata jsonb') AS sv,
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'cascade_workshop_schedule'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_operation text, p_target_id uuid, p_target_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_shift_minutes integer, p_override_reason text, p_metadata jsonb') AS csch,
  (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e
    WHERE e.signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') AS pin_md5,
  (SELECT e.release FROM pdc_ops.expected_function_md5 e
    WHERE e.signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') AS pin_release,
  (SELECT count(*) FROM pdc_ops.expected_function_md5 e WHERE e.release = 'r571') AS r571_pins,
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'k135_administrator_move_workshop_booking'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean') AS k_src,
  (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'k135_administrator_move_workshop_booking'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean') AS k_md5
) s
$chk571$,
true, 343, 'r571');

NOTIFY pgrst, 'reload schema';

DO $post$
DECLARE y record; acl text; cfg text;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r571: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r571')<>1 THEN RAISE EXCEPTION 'r571: expected one pin to move'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r576')<>0 THEN RAISE EXCEPTION 'r571: r576 pin remains'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS NOT TRUE THEN RAISE EXCEPTION 'r571: move is not security definer'; END IF;
 SELECT proconfig::text, proacl::text INTO cfg, acl FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)');
 IF cfg NOT IN ('{"search_path=pg_catalog, public"}', '{search_path=pg_catalog, public}') THEN RAISE EXCEPTION 'r571: search_path changed (%)', cfg; END IF;
 IF acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r571: grants changed (%)', acl; END IF;
 IF (SELECT proconfig::text FROM pg_proc WHERE oid=to_regprocedure('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) NOT IN ('{"search_path=pg_catalog, public, extensions"}', '{search_path=pg_catalog, public, extensions}') THEN RAISE EXCEPTION 'r571: move_workshop_booking search_path changed'; END IF;
 IF (SELECT proconfig::text FROM pg_proc WHERE oid=to_regprocedure('public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)')) NOT IN ('{"search_path=pg_catalog, public, extensions"}', '{search_path=pg_catalog, public, extensions}') THEN RAISE EXCEPTION 'r571: schedule_vehicle_work search_path changed'; END IF;
 IF (SELECT proconfig::text FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)')) NOT IN ('{"search_path=pg_catalog, public"}', '{search_path=pg_catalog, public}') THEN RAISE EXCEPTION 'r571: cascade move search_path changed'; END IF;
 IF (SELECT proconfig::text FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)')) NOT IN ('{"search_path=pg_catalog, public"}', '{search_path=pg_catalog, public}') THEN RAISE EXCEPTION 'r571: cascade schedule search_path changed'; END IF;
 IF has_function_privilege('authenticated', 'public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean)', 'EXECUTE') THEN RAISE EXCEPTION 'r571: helper is executable by authenticated'; END IF;
 IF has_function_privilege('anon', 'public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean)', 'EXECUTE') THEN RAISE EXCEPTION 'r571: helper is executable by anon'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r571: department 135 move changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='slot_between_571' AND fault_id='F185' AND sort_order=343 AND added_in='r571' AND enabled)<>1 THEN RAISE EXCEPTION 'r571: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='slot_between_571' AND fault_id='F185' AND sort_order=343 AND added_in='r571') INTO y;
 IF coalesce(y.ok,false) IS NOT TRUE THEN RAISE EXCEPTION 'r571: check failed: %', y.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_576' AND fault_id='F190' AND sort_order=347 AND added_in='r576') INTO y;
 IF coalesce(y.ok,false) IS NOT TRUE THEN RAISE EXCEPTION 'r571: r576 check failed after the pin moved: %', y.detail; END IF;
END $post$;
