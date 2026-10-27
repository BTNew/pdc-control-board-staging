-- Undo r567 (F181) / sort 341. PREVIEW. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target. Restores the r552 move body
-- md5 79f284b178ca2170bf8972c9cd83ce29 and removes cross_station_drop_567.
-- Department 135 is not edited. Pin count stays 241.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r567 down: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r567 down: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r567 down: pin count is not 241'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') IS DISTINCT FROM 'r567' THEN RAISE EXCEPTION 'r567 down: move pin is not r567'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)')
    IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) THEN RAISE EXCEPTION 'r567 down: pin does not match the body'; END IF;
 IF strpos((SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),'r567 (F181)')=0 THEN RAISE EXCEPTION 'r567 down: marker missing'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r567 down: department 135 move changed'; END IF;
END $g$;

DO $mv$
DECLARE src text; newsrc text; old text; repl text;
BEGIN
 src:=(SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'));
 IF strpos(src,'r567 (F181)')=0 THEN RAISE EXCEPTION 'r567 down: body is not the r567 body'; END IF;
 newsrc:=src;

 old:=$old$ if v_push_receipt is not null and coalesce((v_result->>'ok')::boolean,false) then
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
   v_result:=jsonb_build_object('ok',false,'error','concurrent_queue_change'); raise exception 'r567: cross-station push not applied' using errcode='P0415'; end if;
  update pg_temp.r424_p set changed=false where bay_id is null or id=p_booking_id or bay_id is not distinct from v_target_bay;
  if exists(select 1 from pg_temp.r424_p where changed) then
   v_push_apply:=pdc_bay_seq_private.p_apply(coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'pushed_for_booking_id',p_booking_id,'release','r567'),'cross_station_push_567');
   if coalesce((v_push_apply->>'ok')::boolean,false) is not true then v_result:=v_push_apply; raise exception 'r567: cross-station push not applied' using errcode='P0415'; end if;
  end if;
  v_push:=jsonb_build_object('ok',true,'changes',v_cross,'plan_hash',v_plan_hash);
 end if;
 if (v_resumable or v_push_receipt is not null) and coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'r415: move refused; resume rolled back' using errcode='P0415'; end if;$old$;
 repl:=$new$ if (v_resumable or v_push_receipt is not null) and coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'r415: move refused; resume rolled back' using errcode='P0415'; end if;$new$;
 IF length(old)=0 OR (length(newsrc)-length(replace(newsrc,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'r567 down: patch 1 was not found once'; END IF;
 newsrc:=replace(newsrc,old,repl);

 old:=$old$ end if;
 -- r567 (F181): a cascade drop still pushes later jobs in this bay. The same vehicle
 -- already booked in another bay, or queued with no bay, is a real double-booking.
 -- Ask before pushing those. A started or stoppage booking is named and not pushed.
 if coalesce(p_cascade,false) then
  v_push:=pdc_bay_seq_private.plan_for_move(p_booking_id,v_target_bay,p_scheduled_start_at);
  if coalesce((v_push->>'ok')::boolean,false) is not true then v_result:=v_push; raise exception 'r567: cross-station plan failed' using errcode='P0415'; end if;
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
  if coalesce((v_push->>'ok')::boolean,false) is not true then v_result:=v_push; raise exception 'r567: cross-station plan failed' using errcode='P0415'; end if;
  if exists(select 1 from pg_temp.r424_p where id=p_booking_id and kind='pin' and new_start is distinct from p_scheduled_start_at) then
   select b.id into v_block from public.workshop_bookings b
    where b.vehicle_id=v_booking.vehicle_id and b.id<>p_booking_id and b.deleted_at is null and b.status in ('queued','planned','started','stoppage')
     and b.bay_id is distinct from v_target_bay
     and b.scheduled_start_at < pdc_bay_seq_private.end_at(pdc_bay_seq_private.end_at(p_scheduled_start_at,coalesce(v_minutes,60),v_target_bay),60,b.bay_id)
     and p_scheduled_start_at < public.workshop_booking_effective_end_at(b.id)
    order by case when b.status in ('started','stoppage') then 0 else 1 end, b.scheduled_start_at limit 1;
   if v_block is null then v_result:=jsonb_build_object('ok',false,'error','vehicle_overlap'); raise exception 'r567: cross-station overlap not pushed' using errcode='P0415'; end if;
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
   raise exception 'r567: cross-station overlap not pushed' using errcode='P0415';
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
    raise exception 'r567: cross-station push not confirmed' using errcode='P0415';
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
    v_result:=jsonb_build_object('ok',false,'error','concurrent_queue_change'); raise exception 'r567: cross-station push not applied' using errcode='P0415'; end if;
   update pg_temp.r424_p p set version=b.version, cur_start=b.scheduled_start_at, cur_end=b.scheduled_end_at, changed=false
    from public.workshop_bookings b where b.id=p.id and p.bay_id is null and p.want_start is not null;
   if exists(select 1 from pg_temp.r424_p where changed) then
    v_push_apply:=pdc_bay_seq_private.p_apply(coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'pushed_for_booking_id',p_booking_id,'release','r567'),'cross_station_park_567');
    if coalesce((v_push_apply->>'ok')::boolean,false) is not true then v_result:=v_push_apply; raise exception 'r567: cross-station push not applied' using errcode='P0415'; end if;
   end if;
   insert into pdc_bay_seq_private.receipts(request_id,actor_id,actor_email,operation,bay_id,booking_id,mode,plan_hash,changes,before_rows,after_rows,result)
   values(p_request_id,v_actor,public.current_actor_email(),'push_later',v_target_bay,p_booking_id,'push_later',v_plan_hash,v_cross,
     coalesce(v_push_apply->'before_rows','[]'::jsonb),coalesce(v_push_apply->'after_rows','[]'::jsonb),jsonb_build_object('ok',true,'changes',v_cross,'release','r567'))
    returning receipt_id into v_push_receipt;
   v_push:=jsonb_build_object('ok',true,'changes',v_cross,'plan_hash',v_plan_hash);
  end if;
 end if;
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move($old$;
 repl:=$new$ end if;
 if p_cascade then
   v_result:=public.cascade_workshop_booking_move($new$;
 IF length(old)=0 OR (length(newsrc)-length(replace(newsrc,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'r567 down: patch 2 was not found once'; END IF;
 newsrc:=replace(newsrc,old,repl);

 old:=$old$ v_stopped boolean:=false; v_push jsonb; v_push_apply jsonb; v_push_receipt uuid; v_minutes integer; v_cross jsonb:='[]'::jsonb; v_block uuid; v_plan_hash text; v_park timestamptz; v_slot timestamptz; v_row record; v_n integer; v_bay_pushes integer:=0;$old$;
 repl:=$new$ v_stopped boolean:=false; v_push jsonb; v_push_apply jsonb; v_push_receipt uuid;$new$;
 IF length(old)=0 OR (length(newsrc)-length(replace(newsrc,old,'')))/length(old)<>1 THEN RAISE EXCEPTION 'r567 down: patch 3 was not found once'; END IF;
 newsrc:=replace(newsrc,old,repl);

 IF strpos(newsrc,'r567 (F181)')<>0 OR strpos(newsrc,'cross-station push not confirmed')<>0 THEN RAISE EXCEPTION 'r567 down: r567 text remains'; END IF;
 IF strpos(newsrc,'if not coalesce(p_cascade,false) then')=0 THEN RAISE EXCEPTION 'r567 down: the non-cascade push path is missing'; END IF;
 IF md5(newsrc) IS DISTINCT FROM '79f284b178ca2170bf8972c9cd83ce29' THEN RAISE EXCEPTION 'r567 down: restored body is not the r552 body'; END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION public.administrator_move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT false)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public'' AS $move567$'||newsrc||'$move567$';
END $mv$;

UPDATE pdc_ops.expected_function_md5 SET
 prosrc_md5='79f284b178ca2170bf8972c9cd83ce29',
 release='r552',
 note='r552: a clock version bump with the same bay window does not reject a drag (was 1c11423631f21d520b9c2d457df8bfe1, r424)',
 updated_at=now()
 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'
   AND release='r567';

DELETE FROM pdc_ops.regression_checks
 WHERE check_name='cross_station_drop_567' AND fault_id='F181' AND sort_order=341 AND added_in='r567';

NOTIFY pgrst, 'reload schema';

DO $post$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r567 down: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r567')<>0 THEN RAISE EXCEPTION 'r567 down: an r567 pin remains'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '79f284b178ca2170bf8972c9cd83ce29' THEN RAISE EXCEPTION 'r567 down: move body was not restored'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') IS DISTINCT FROM '79f284b178ca2170bf8972c9cd83ce29' THEN RAISE EXCEPTION 'r567 down: pin md5 was not restored'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') IS DISTINCT FROM 'r552' THEN RAISE EXCEPTION 'r567 down: pin release was not restored'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='cross_station_drop_567' OR fault_id='F181' OR added_in='r567' OR sort_order=341) THEN RAISE EXCEPTION 'r567 down: check remains'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.k135_administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '4eb5baf999b849d174880a1e261fcbf2' THEN RAISE EXCEPTION 'r567 down: department 135 move changed'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS NOT TRUE THEN RAISE EXCEPTION 'r567 down: move is not security definer'; END IF;
END $post$;
