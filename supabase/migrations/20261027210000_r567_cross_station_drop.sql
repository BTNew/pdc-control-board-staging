-- r576 (F190) / sort 347. Go-live of #557.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- F181 / sort 338 / r567 is parts_stoppage_manual_567. Sort 341 / F184 / r570 is #544.
-- pmb_dept_ack_book_574 is F188 / sort 345. r571 / F185 / sort 343 stays unused for #559.
-- r575 / F189 / sort 346 is the live active-key guard (#562). This release moved off that triple.
-- Pins stay 241. The move pin is updated in place from 79f284b178ca2170bf8972c9cd83ce29 (r552).
-- Department 135 is not edited.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r576: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r576: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r576: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '79f284b178ca2170bf8972c9cd83ce29' THEN RAISE EXCEPTION 'r576: administrator_move_workshop_booking is not the r552 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r576: department 135 move changed'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563') THEN RAISE EXCEPTION 'r576: r563 / F177 sort 336 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='panel_line_completion_565' AND fault_id='F179' AND sort_order=337 AND added_in='r565') THEN RAISE EXCEPTION 'r576: r565 / F179 sort 337 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_dept_ack_book_574' AND fault_id='F188' AND sort_order=345 AND added_in='r574') THEN RAISE EXCEPTION 'r576: r574 / F188 sort 345 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='active_key_unique_575' AND fault_id='F189' AND sort_order=346 AND added_in='r575') THEN RAISE EXCEPTION 'r576: r575 / F189 sort 346 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=347 OR fault_id='F190' OR check_name='cross_station_drop_576' OR added_in='r576') THEN RAISE EXCEPTION 'r576: sort 347 or F190 is taken'; END IF;
END $g$;

DO $mv$
DECLARE src text; newsrc text; old text; repl text;
BEGIN
 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'));
 IF md5(src) IS DISTINCT FROM '79f284b178ca2170bf8972c9cd83ce29' THEN RAISE EXCEPTION 'r576: move body changed before the patch'; END IF;
 newsrc:=src;

 old:=$old$ v_stopped boolean:=false; v_push jsonb; v_push_apply jsonb; v_push_receipt uuid;$old$;
 repl:=$new$ v_stopped boolean:=false; v_push jsonb; v_push_apply jsonb; v_push_receipt uuid; v_minutes integer; v_cross jsonb:='[]'::jsonb; v_block uuid; v_plan_hash text; v_park timestamptz; v_slot timestamptz; v_row record; v_n integer; v_bay_pushes integer:=0;$new$;
 IF length(old)=0 OR (length(newsrc)-length(replace(newsrc,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'r576: declare line was not found once'; END IF;
 newsrc:=replace(newsrc,old,repl);

 old:=$old$ end if;
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move($old$;
 repl:=$new$ end if;
 -- r576 (F190): a cascade drop still pushes later jobs in this bay. The same vehicle
 -- already booked in another bay, or queued with no bay, is a real double-booking.
 -- Ask before pushing those. A started or stoppage booking is named and not pushed.
 if coalesce(p_cascade,false) then
  v_push:=pdc_bay_seq_private.plan_for_move(p_booking_id,v_target_bay,p_scheduled_start_at);
  if coalesce((v_push->>'ok')::boolean,false) is not true then v_result:=v_push; raise exception 'r576: cross-station plan failed' using errcode='P0415'; end if;
  v_minutes:=public.workshop_booking_capacity_duration_minutes(p_booking_id,v_booking.vehicle_id,v_target_stage,v_target_bay);
  if coalesce(v_minutes,0)>0 then
   update pg_temp.r424_p set dur=v_minutes, new_start=p_scheduled_start_at, new_end=pdc_bay_seq_private.end_at(p_scheduled_start_at,v_minutes,bay_id), changed=false, loaded=false
    where id=p_booking_id and kind='pin';
  end if;
  update pg_temp.r424_p set new_start=cur_start, new_end=cur_end, changed=false
   where id is distinct from p_booking_id and cur_start is not null;
  insert into pg_temp.r424_p(id,vehicle_id,stage_id,bay_id,cur_bay,status,kind,prio,cur_start,cur_end,new_start,new_end,dur,version)
  select b.id,b.vehicle_id,b.stage_id,b.bay_id,b.bay_id,b.status::text,'move',2,
    b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),
    b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id),
    coalesce(public.workshop_booking_capacity_duration_minutes(b.id,b.vehicle_id,b.stage_id,b.bay_id),b.default_duration_minutes),b.version
  from public.workshop_bookings b
  where b.vehicle_id=v_booking.vehicle_id and b.id<>p_booking_id and b.deleted_at is null and b.status='queued' and b.bay_id is null
    and public.workshop_booking_effective_end_at(b.id)>clock_timestamp()
    and coalesce(public.workshop_booking_capacity_duration_minutes(b.id,b.vehicle_id,b.stage_id,b.bay_id),b.default_duration_minutes) is not null
  on conflict (id) do nothing;
  v_push:=pdc_bay_seq_private.p_close();
  if coalesce((v_push->>'ok')::boolean,false) is not true then v_result:=v_push; raise exception 'r576: cross-station plan failed' using errcode='P0415'; end if;
  if exists(select 1 from pg_temp.r424_p where id=p_booking_id and kind='pin' and new_start is distinct from p_scheduled_start_at) then
   select b.id into v_block from public.workshop_bookings b
    where b.vehicle_id=v_booking.vehicle_id and b.id<>p_booking_id and b.deleted_at is null and b.status in ('queued','planned','started','stoppage')
     and b.bay_id is distinct from v_target_bay
     and b.scheduled_start_at < pdc_bay_seq_private.end_at(pdc_bay_seq_private.end_at(p_scheduled_start_at,coalesce(v_minutes,60),v_target_bay),60,b.bay_id)
     and p_scheduled_start_at < public.workshop_booking_effective_end_at(b.id)
    order by case when b.status in ('started','stoppage') then 0 else 1 end, b.scheduled_start_at limit 1;
   if v_block is null then v_result:=jsonb_build_object('ok',false,'error','vehicle_overlap'); raise exception 'r576: cross-station overlap not pushed' using errcode='P0415'; end if;
  else
   select p.id into v_block from pg_temp.r424_p pin
    join pg_temp.r424_p p on p.vehicle_id=pin.vehicle_id and p.id<>pin.id
    where pin.id=p_booking_id and pin.kind='pin' and p.kind='fixed' and p.bay_id is distinct from v_target_bay
     and ((p.new_start < pdc_bay_seq_private.end_at(pin.new_end,60,p.bay_id) and pin.new_start < p.new_end)
       or (pin.new_start < pdc_bay_seq_private.end_at(p.new_end,60,pin.bay_id) and p.new_start < pin.new_end))
    order by p.new_start limit 1;
  end if;
  if v_block is not null then
   select jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',b.id,
     'conflict',jsonb_build_object('conflict_type','vehicle_overlap','existing_booking',jsonb_build_object(
       'booking_id',b.id,'vehicle_id',v.id,'status',b.status,'scheduled_start_at',b.scheduled_start_at,
       'scheduled_end_at',public.workshop_booking_effective_end_at(b.id),
       'vehicle',jsonb_build_object('id',v.id,'stock_number',v.stock_number,'key_number',v.key_number,'customer_name',v.customer_name),
       'stage',jsonb_build_object('code',s.code,'display_name',s.display_name),
       'bay',jsonb_build_object('bay_number',bay.bay_number,'display_name',coalesce(bay.display_name,'Unallocated')))))
    into v_result
    from public.workshop_bookings b
    join public.vehicles v on v.id=b.vehicle_id
    join public.workshop_stages s on s.id=b.stage_id
    left join public.workshop_bays bay on bay.id=b.bay_id
    where b.id=v_block;
   raise exception 'r576: cross-station overlap not pushed' using errcode='P0415';
  end if;
  v_plan_hash:=pdc_bay_seq_private.p_hash(p_booking_id);
  select coalesce(jsonb_agg(jsonb_build_object('booking_id',p.id,'vehicle_id',p.vehicle_id,'key_number',v.key_number,
     'stock_number',v.stock_number,'customer_name',v.customer_name,'work_category',b.work_category,'stage_code',s.code,
     'stage_name',s.display_name,'bay_number',bay.bay_number,'bay_display_name',coalesce(bay.display_name,'Unallocated'),
     'status',b.status,'from_start',p.cur_start,'from_end',p.cur_end,'to_start',p.new_start,'to_end',p.new_end)
     order by p.cur_start,p.id),'[]'::jsonb) into v_cross
   from pg_temp.r424_p p
   join public.workshop_bookings b on b.id=p.id
   join public.vehicles v on v.id=p.vehicle_id
   left join public.workshop_bays bay on bay.id=p.bay_id
   left join public.workshop_stages s on s.id=coalesce(bay.stage_id,p.stage_id)
   where p.changed and p.id is distinct from p_booking_id and p.bay_id is distinct from v_target_bay;
  select count(*) into v_bay_pushes from pg_temp.r424_p
   where changed and id is distinct from p_booking_id and bay_id is not distinct from v_target_bay;
  if coalesce(jsonb_array_length(v_cross),0)>0 then
   if coalesce(p_metadata->'push_later_confirm'->>'plan_hash','') is distinct from v_plan_hash then
    v_result:=jsonb_build_object('ok',false,'warning',true,'requires_confirmation',true,'error','later_bookings_warning',
      'booking_id',p_booking_id,'pushes',v_cross,'plan_hash',v_plan_hash,'bay_push_count',v_bay_pushes,
      'message','This drop would book this vehicle in two places at once. Push the other station back so an hour stays clear'
        ||case when coalesce(v_bay_pushes,0)>0 then ', and later jobs in this bay move back too' else '' end||'.');
    raise exception 'r576: cross-station push not confirmed' using errcode='P0415';
   end if;
   update pg_temp.r424_p set want_start=new_start
    where changed and id is distinct from p_booking_id and bay_id is distinct from v_target_bay;
   select greatest(clock_timestamp(),coalesce(max(public.workshop_booking_effective_end_at(b.id)),clock_timestamp()))+interval '30 days' into v_park
    from public.workshop_bookings b
    where b.deleted_at is null and b.vehicle_id=v_booking.vehicle_id and b.status in ('queued','planned','started','stoppage');
   for v_row in select id,bay_id,dur from pg_temp.r424_p
     where want_start is not null and id is distinct from p_booking_id and bay_id is distinct from v_target_bay
     order by want_start,id
   loop
    select coalesce(max(public.workshop_booking_effective_end_at(b.id)),v_park) into v_slot
     from public.workshop_bookings b
     where b.deleted_at is null and b.bay_id is not distinct from v_row.bay_id and b.status in ('queued','planned','started','stoppage');
    v_slot:=pdc_bay_seq_private.next_start(greatest(v_park,coalesce(v_slot,v_park)+interval '1 day'),v_row.bay_id);
    update pg_temp.r424_p set new_start=v_slot, new_end=pdc_bay_seq_private.end_at(v_slot,dur,bay_id), changed=true where id=v_row.id;
    v_park:=pdc_bay_seq_private.end_at(v_slot,v_row.dur,v_row.bay_id)+interval '1 day';
   end loop;
   update pg_temp.r424_p set changed=false where id=p_booking_id or bay_id is not distinct from v_target_bay;
   select count(*) into v_n from pg_temp.r424_p where changed and bay_id is null and kind='move';
   update public.workshop_bookings b set scheduled_start_at=p.new_start, scheduled_end_at=p.new_end, version=b.version+1, updated_by=v_actor, updated_at=clock_timestamp()
    from pg_temp.r424_p p
    where b.id=p.id and p.changed and p.bay_id is null and p.kind='move' and b.deleted_at is null and b.status='queued' and b.bay_id is null and b.version=p.version;
   if (select count(*) from public.workshop_bookings b join pg_temp.r424_p p on p.id=b.id where p.bay_id is null and p.kind='move' and p.changed and b.scheduled_start_at is not distinct from p.new_start) is distinct from v_n then
    v_result:=jsonb_build_object('ok',false,'error','concurrent_queue_change'); raise exception 'r576: cross-station push not applied' using errcode='P0415'; end if;
   update pg_temp.r424_p p set version=b.version, cur_start=b.scheduled_start_at, cur_end=b.scheduled_end_at, changed=false
    from public.workshop_bookings b where b.id=p.id and p.bay_id is null and p.want_start is not null;
   if exists(select 1 from pg_temp.r424_p where changed) then
    v_push_apply:=pdc_bay_seq_private.p_apply(coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'pushed_for_booking_id',p_booking_id,'release','r576'),'cross_station_park_575');
    if coalesce((v_push_apply->>'ok')::boolean,false) is not true then v_result:=v_push_apply; raise exception 'r576: cross-station push not applied' using errcode='P0415'; end if;
   end if;
   insert into pdc_bay_seq_private.receipts(request_id,actor_id,actor_email,operation,bay_id,booking_id,mode,plan_hash,changes,before_rows,after_rows,result)
   values(p_request_id,v_actor,public.current_actor_email(),'push_later',v_target_bay,p_booking_id,'push_later',v_plan_hash,v_cross,
     coalesce(v_push_apply->'before_rows','[]'::jsonb),coalesce(v_push_apply->'after_rows','[]'::jsonb),jsonb_build_object('ok',true,'changes',v_cross,'release','r576'))
    returning receipt_id into v_push_receipt;
   v_push:=jsonb_build_object('ok',true,'changes',v_cross,'plan_hash',v_plan_hash);
  end if;
 end if;
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move($new$;
 IF length(old)=0 OR (length(newsrc)-length(replace(newsrc,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'r576: cascade call was not found once'; END IF;
 newsrc:=replace(newsrc,old,repl);

 old:=$old$ if (v_resumable or v_push_receipt is not null) and coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'r415: move refused; resume rolled back' using errcode='P0415'; end if;$old$;
 repl:=$new$ if v_push_receipt is not null and coalesce((v_result->>'ok')::boolean,false) then
  update pg_temp.r424_p p set version=b.version, new_start=p.want_start, new_end=pdc_bay_seq_private.end_at(p.want_start,p.dur,p.bay_id), changed=true
   from public.workshop_bookings b
   where b.id=p.id and p.want_start is not null and p.id is distinct from p_booking_id and p.bay_id is not null and p.bay_id is distinct from v_target_bay;
  update pg_temp.r424_p p set version=b.version, new_start=p.want_start, new_end=pdc_bay_seq_private.end_at(p.want_start,p.dur,null), changed=true
   from public.workshop_bookings b
   where b.id=p.id and p.want_start is not null and p.bay_id is null;
  select count(*) into v_n from pg_temp.r424_p where changed and bay_id is null and kind='move';
  update public.workshop_bookings b set scheduled_start_at=p.new_start, scheduled_end_at=p.new_end, version=b.version+1, updated_by=v_actor, updated_at=clock_timestamp()
   from pg_temp.r424_p p
   where b.id=p.id and p.changed and p.bay_id is null and p.kind='move' and b.deleted_at is null and b.status='queued' and b.bay_id is null and b.version=p.version;
  if (select count(*) from public.workshop_bookings b join pg_temp.r424_p p on p.id=b.id where p.changed and p.bay_id is null and b.scheduled_start_at is not distinct from p.new_start) is distinct from v_n then
   v_result:=jsonb_build_object('ok',false,'error','concurrent_queue_change'); raise exception 'r576: cross-station push not applied' using errcode='P0415'; end if;
  update pg_temp.r424_p set changed=false where bay_id is null or id=p_booking_id or bay_id is not distinct from v_target_bay;
  if exists(select 1 from pg_temp.r424_p where changed) then
   v_push_apply:=pdc_bay_seq_private.p_apply(coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'pushed_for_booking_id',p_booking_id,'release','r576'),'cross_station_push_575');
   if coalesce((v_push_apply->>'ok')::boolean,false) is not true then v_result:=v_push_apply; raise exception 'r576: cross-station push not applied' using errcode='P0415'; end if;
  end if;
  v_push:=jsonb_build_object('ok',true,'changes',v_cross,'plan_hash',v_plan_hash);
 end if;
 if (v_resumable or v_push_receipt is not null) and coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'r415: move refused; resume rolled back' using errcode='P0415'; end if;$new$;
 IF length(old)=0 OR (length(newsrc)-length(replace(newsrc,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'r576: rollback guard was not found once'; END IF;
 newsrc:=replace(newsrc,old,repl);

 IF newsrc IS NOT DISTINCT FROM src THEN RAISE EXCEPTION 'r576: move body was not changed'; END IF;
 IF strpos(newsrc,'r576 (F190)')=0 OR strpos(newsrc,'cross-station push not confirmed')=0 OR strpos(newsrc,'if not coalesce(p_cascade,false) then')=0 THEN RAISE EXCEPTION 'r576: patched body is missing a marker'; END IF;
 IF (length(newsrc)-length(replace(newsrc,'r576 (F190)','')))/length('r576 (F190)')<>1 THEN RAISE EXCEPTION 'r576: marker was not unique'; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $move575$'||newsrc||'$move575$';
END $mv$;

UPDATE pdc_ops.expected_function_md5 SET
 prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),
 release='r576',
 note='r576: a cascade drop names and can push the same vehicle in another station (was 79f284b178ca2170bf8972c9cd83ce29, r552)',
 updated_at=now()
 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'
   AND prosrc_md5='79f284b178ca2170bf8972c9cd83ce29' AND release='r552';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('cross_station_drop_576','F190',
 'A cascade drop pushes later jobs in that bay. The same vehicle booked in another bay, or queued with no bay, is not saved on top of that time. The planner is asked, and the booking is named, before those rows are pushed. A started or stoppage booking is not pushed. Craig, 27 Oct 2026 09:44 AWST, dropped unallocated fitting 676d6c62 onto Thanh bay. The save was rejected by tint b6a0c4c7 in Tint Bay 01 and by queued hoist 5012775c, which has no bay. Key 338 in the destination bay is the bay cascade, not the refusal. The non-cascade push path stays. Department 135 is not edited. The check does not require those rows to stay in conflict.',
 $chk575$
SELECT
  pg_catalog.strpos(s.mv, 'r576 (F190)') > 0
  AND pg_catalog.strpos(s.mv, 'cross-station push not confirmed') > 0
  AND pg_catalog.strpos(s.mv, 'if not coalesce(p_cascade,false) then') > 0
  AND pg_catalog.md5(s.mv) = s.pin_md5
  AND s.pin_release = 'r576'
  AND s.r576_pins = 1
  AND s.k_md5 = '4eb5baf999b849d174880a1e261fcbf2'
  AND pg_catalog.strpos(s.k_src, 'r576') = 0
  AS ok,
  'move '||coalesce(pg_catalog.md5(s.mv), 'missing')||' pin '||coalesce(s.pin_md5, 'missing')||' k135 '||coalesce(s.k_md5, 'missing') AS detail
FROM (
 SELECT
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'administrator_move_workshop_booking'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean') AS mv,
  (SELECT e.prosrc_md5 FROM pdc_ops.expected_function_md5 e
    WHERE e.signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') AS pin_md5,
  (SELECT e.release FROM pdc_ops.expected_function_md5 e
    WHERE e.signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') AS pin_release,
  (SELECT count(*) FROM pdc_ops.expected_function_md5 e WHERE e.release = 'r576') AS r576_pins,
  (SELECT p.prosrc FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'k135_administrator_move_workshop_booking'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean') AS k_src,
  (SELECT pg_catalog.md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'k135_administrator_move_workshop_booking'
     AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean') AS k_md5
) s
$chk575$,
true, 347, 'r576');

DO $post$
DECLARE y record; acl text; cfg text;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r576: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r576')<>1 THEN RAISE EXCEPTION 'r576: expected one pin to move'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)' AND prosrc_md5='79f284b178ca2170bf8972c9cd83ce29') THEN RAISE EXCEPTION 'r576: move pin was not updated'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'))
    IS NOT DISTINCT FROM '79f284b178ca2170bf8972c9cd83ce29' THEN RAISE EXCEPTION 'r576: move body did not change'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)' AND release='r576')
    IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) THEN RAISE EXCEPTION 'r576: pin md5 does not match the body'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS NOT TRUE THEN RAISE EXCEPTION 'r576: move is not security definer'; END IF;
 SELECT proconfig::text, proacl::text INTO cfg, acl FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)');
 IF cfg IS DISTINCT FROM '{search_path=pg_catalog, public}' THEN RAISE EXCEPTION 'r576: search_path changed (%)', cfg; END IF;
 IF acl IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r576: grants changed (%)', acl; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r576: department 135 move changed'; END IF;
 IF strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),'r576')<>0 THEN RAISE EXCEPTION 'r576: department 135 body was edited'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_576' AND fault_id='F190' AND sort_order=347 AND added_in='r576' AND enabled)<>1 THEN RAISE EXCEPTION 'r576: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_576' AND fault_id='F190' AND sort_order=347 AND added_in='r576') INTO y;
 IF coalesce(y.ok,false) IS NOT TRUE THEN RAISE EXCEPTION 'r576: check failed: %', y.detail; END IF;
END $post$;
