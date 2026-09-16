-- Keep Admin preflight and repacking consistent with the existing fixed-booking trigger.
DO $$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'STAGING only'; END IF; END $$;
CREATE OR REPLACE FUNCTION public.move_workshop_admin_block(p_block_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_block public.workshop_admin_blocks%rowtype; v_valid jsonb; v_before jsonb; v_after jsonb; v_repack jsonb; v_response jsonb; v_revision bigint; v_receipt uuid; v_old_stage text;
begin
  perform public.require_pdc_role('administrator');
  select * into v_block from public.workshop_admin_blocks where id=p_block_id for update;
  if not found or v_block.deleted_at is not null then return jsonb_build_object('ok',false,'error','admin_block_not_found'); end if;
  if v_block.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
  v_valid:=public.workshop_admin_validate_interval(p_stage_code,p_bay_number,p_scheduled_start_at,v_block.duration_minutes);
  if not coalesce((v_valid->>'ok')::boolean,false) then return v_valid; end if;
  perform public.workshop_admin_lock_physical_bays(v_block.bay_id,(v_valid->>'bay_id')::uuid);
  select code into v_old_stage from public.workshop_stages where id=v_block.stage_id;
  if exists(select 1 from public.workshop_admin_blocks a where a.id<>p_block_id and a.bay_id=(v_valid->>'bay_id')::uuid and a.deleted_at is null and a.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and a.scheduled_end_at>p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','admin_block_conflict');
  end if;
  if exists(select 1 from public.workshop_bookings b where b.bay_id=(v_valid->>'bay_id')::uuid and b.deleted_at is null and b.status in ('queued','started','stoppage') and b.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at) then
    return jsonb_build_object('ok',false,'error','fixed_booking_conflict');
  end if;
  v_before:=public.workshop_admin_block_snapshot(p_block_id);
  update public.workshop_admin_blocks set stage_id=(v_valid->>'stage_id')::uuid,bay_id=(v_valid->>'bay_id')::uuid,
    scheduled_start_at=p_scheduled_start_at,scheduled_end_at=(v_valid->>'scheduled_end_at')::timestamptz,
    updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1 where id=p_block_id;
  v_repack:=public.workshop_admin_repack_planned((v_valid->>'bay_id')::uuid,p_scheduled_start_at,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_id',p_block_id));
  v_after:=public.workshop_admin_block_snapshot(p_block_id);
  v_revision:=public.workshop_bump_revision();
  perform public.workshop_bump_station_revision(v_old_stage);
  if v_old_stage is distinct from (v_valid->>'stage_code') then perform public.workshop_bump_station_revision(v_valid->>'stage_code'); end if;
  v_response:=jsonb_build_object('ok',true,'admin_block',v_after,'revision',v_revision,'repack',v_repack);
  v_receipt:=public.workshop_admin_write_evidence(p_block_id,'moved',p_expected_version,v_before,v_after,v_response,p_metadata);
  return v_response||jsonb_build_object('receipt_id',v_receipt);
end $function$
;

CREATE OR REPLACE FUNCTION public.create_workshop_admin_block(p_expected_revision bigint, p_stage_code text, p_bay_number integer, p_block_type text, p_label text, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(coalesce(p_metadata->>'request_id','')),'');
  v_valid jsonb;
  v_id uuid;
  v_end timestamptz;
  v_repack jsonb;
  v_after jsonb;
  v_response jsonb;
  v_revision bigint;
  v_receipt uuid:=gen_random_uuid();
  v_request_hash text;
  v_existing public.workshop_admin_block_receipts%rowtype;
  v_fixed record;
  v_nearest jsonb;
BEGIN
  PERFORM public.require_pdc_role('administrator');
  IF v_actor IS NULL OR v_key IS NULL OR v_key !~ '^[A-Za-z0-9:_-]{8,160}$' THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_idempotency_key','no_partial_save',true);
  END IF;
  IF lower(btrim(coalesce(p_block_type,''))) NOT IN ('training','sick','admin') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_admin_block_type','no_partial_save',true);
  END IF;
  IF nullif(btrim(coalesce(p_label,'')),'') IS NOT NULL AND length(btrim(p_label))>120 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_label','no_partial_save',true);
  END IF;
  v_request_hash:=md5(jsonb_build_object(
    'stage_code',upper(btrim(coalesce(p_stage_code,''))),'bay_number',p_bay_number,
    'block_type',lower(btrim(coalesce(p_block_type,''))),'label',nullif(btrim(coalesce(p_label,'')),''),
    'scheduled_start_at',p_scheduled_start_at,'duration_minutes',p_duration_minutes
  )::text);
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-admin-request:'||v_actor::text||':'||v_key,0));
  SELECT * INTO v_existing FROM public.workshop_admin_block_receipts
  WHERE actor_user_id=v_actor AND idempotency_key=v_key LIMIT 1;
  IF FOUND THEN
    IF v_existing.request_hash IS DISTINCT FROM v_request_hash THEN
      RETURN jsonb_build_object('ok',false,'error','idempotency_conflict','no_partial_save',true);
    END IF;
    RETURN v_existing.response||jsonb_build_object('replay',true);
  END IF;
  v_valid:=public.workshop_admin_validate_interval(p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes);
  IF NOT coalesce((v_valid->>'ok')::boolean,false) THEN RETURN v_valid||jsonb_build_object('no_partial_save',true); END IF;
  PERFORM public.workshop_admin_lock_physical_bays((v_valid->>'bay_id')::uuid,NULL);
  PERFORM 1 FROM public.workshop_revision WHERE id=1 FOR UPDATE;
  IF public.workshop_current_revision()<>p_expected_revision THEN
    RETURN jsonb_build_object('ok',false,'error','version_conflict','current_revision',public.workshop_current_revision(),'no_partial_save',true);
  END IF;
  v_end:=(v_valid->>'scheduled_end_at')::timestamptz;
  SELECT b.id,b.status::text status,b.vehicle_id,b.stage_id,b.scheduled_start_at,public.workshop_booking_effective_end_at(b.id) AS scheduled_end_at
    INTO v_fixed
  FROM public.workshop_bookings b
  WHERE b.bay_id=(v_valid->>'bay_id')::uuid AND b.deleted_at IS NULL
    AND b.status::text IN ('queued','started','stoppage')
    AND b.scheduled_start_at<v_end AND public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at
  ORDER BY b.scheduled_start_at,b.id LIMIT 1;
  IF FOUND THEN
    v_nearest:=public.workshop_admin_nearest_available_slot((v_valid->>'bay_id')::uuid,p_scheduled_start_at,p_duration_minutes);
    RETURN jsonb_build_object(
      'ok',false,'error','fixed_booking_conflict','code','fixed_booking_conflict',
      'blocker',jsonb_build_object('booking_id',v_fixed.id,'status',v_fixed.status,'vehicle_id',v_fixed.vehicle_id,
        'stage_id',v_fixed.stage_id,'scheduled_start_at',v_fixed.scheduled_start_at,'scheduled_end_at',v_fixed.scheduled_end_at),
      'nearest_available_slot',v_nearest,'no_partial_save',true,'notification_delta',0
    );
  END IF;
  INSERT INTO public.workshop_admin_blocks(
    stage_id,bay_id,block_type,label,scheduled_start_at,scheduled_end_at,duration_minutes,created_by,updated_by
  ) VALUES(
    (v_valid->>'stage_id')::uuid,(v_valid->>'bay_id')::uuid,lower(btrim(p_block_type)),
    nullif(btrim(coalesce(p_label,'')),''),p_scheduled_start_at,v_end,p_duration_minutes,v_actor,v_actor
  ) RETURNING id INTO v_id;
  v_repack:=public.workshop_admin_repack_planned((v_valid->>'bay_id')::uuid,p_scheduled_start_at,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_id',v_id));
  v_after:=public.workshop_admin_block_snapshot(v_id);
  v_revision:=public.workshop_bump_revision();
  PERFORM public.workshop_bump_station_revision(v_valid->>'stage_code');
  v_response:=jsonb_build_object(
    'ok',true,'code','admin_block_created','admin_block',v_after,'revision',v_revision,
    'repack',v_repack,'cascade',v_repack,'receipt_id',v_receipt,'replay',false,
    'notification_delta',0,'no_partial_save',false
  );
  INSERT INTO public.workshop_admin_block_history(
    block_id,event_type,block_version,before_data,after_data,metadata,actor_user_id,actor_email
  ) VALUES(v_id,'created',1,NULL,v_after,coalesce(p_metadata,'{}'::jsonb),v_actor,public.current_actor_email());
  INSERT INTO public.workshop_admin_block_receipts(
    receipt_id,block_id,mutation_type,expected_version,resulting_version,response,metadata,actor_user_id,actor_email,idempotency_key,request_hash
  ) VALUES(v_receipt,v_id,'create',p_expected_revision,1,v_response,coalesce(p_metadata,'{}'::jsonb),v_actor,public.current_actor_email(),v_key,v_request_hash);
  RETURN v_response;
END $function$
;

CREATE OR REPLACE FUNCTION public.resize_workshop_admin_block(p_block_id uuid, p_expected_version integer, p_duration_minutes integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_block public.workshop_admin_blocks%rowtype; v_stage text; v_bay_number integer; v_valid jsonb; v_before jsonb; v_after jsonb; v_repack jsonb; v_response jsonb; v_revision bigint; v_receipt uuid;
begin
  perform public.require_pdc_role('administrator');
  select * into v_block from public.workshop_admin_blocks where id=p_block_id for update;
  if not found or v_block.deleted_at is not null then return jsonb_build_object('ok',false,'error','admin_block_not_found'); end if;
  if v_block.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
  select s.code,b.bay_number into v_stage,v_bay_number from public.workshop_stages s join public.workshop_bays b on b.stage_id=s.id where s.id=v_block.stage_id and b.id=v_block.bay_id;
  v_valid:=public.workshop_admin_validate_interval(v_stage,v_bay_number,v_block.scheduled_start_at,p_duration_minutes);
  if not coalesce((v_valid->>'ok')::boolean,false) then return v_valid; end if;
  perform public.workshop_admin_lock_physical_bays(v_block.bay_id,null);
  if exists(select 1 from public.workshop_admin_blocks a where a.id<>p_block_id and a.bay_id=v_block.bay_id and a.deleted_at is null and a.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and a.scheduled_end_at>v_block.scheduled_start_at) then return jsonb_build_object('ok',false,'error','admin_block_conflict'); end if;
  if exists(select 1 from public.workshop_bookings b where b.bay_id=v_block.bay_id and b.deleted_at is null and b.status in ('queued','started','stoppage') and b.scheduled_start_at<(v_valid->>'scheduled_end_at')::timestamptz and public.workshop_booking_effective_end_at(b.id)>v_block.scheduled_start_at) then return jsonb_build_object('ok',false,'error','fixed_booking_conflict'); end if;
  v_before:=public.workshop_admin_block_snapshot(p_block_id);
  update public.workshop_admin_blocks set scheduled_end_at=(v_valid->>'scheduled_end_at')::timestamptz,duration_minutes=p_duration_minutes,updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1 where id=p_block_id;
  v_repack:=public.workshop_admin_repack_planned(v_block.bay_id,v_block.scheduled_start_at,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_id',p_block_id,'compact_released',p_duration_minutes<v_block.duration_minutes));
  v_after:=public.workshop_admin_block_snapshot(p_block_id);
  v_revision:=public.workshop_bump_revision(); perform public.workshop_bump_station_revision(v_stage);
  v_response:=jsonb_build_object('ok',true,'admin_block',v_after,'revision',v_revision,'repack',v_repack);
  v_receipt:=public.workshop_admin_write_evidence(p_block_id,'resized',p_expected_version,v_before,v_after,v_response,p_metadata);
  return v_response||jsonb_build_object('receipt_id',v_receipt);
end $function$
;

CREATE OR REPLACE FUNCTION public.workshop_admin_repack_planned(p_bay_id uuid, p_from timestamp with time zone, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_item record;
  v_start timestamptz;
  v_end timestamptz;
  v_cursor timestamptz:=p_from;
  v_block_end timestamptz;
  v_fixed_end timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_technician uuid;
  v_shifted jsonb:='[]'::jsonb;
  v_anchor_id uuid;
  v_anchor_start timestamptz;
  v_anchor_end timestamptz;
  v_guard integer;
BEGIN
  v_anchor_id:=CASE WHEN coalesce(p_metadata->>'admin_block_id','')~*'^[0-9a-f-]{36}$' THEN (p_metadata->>'admin_block_id')::uuid END;
  SELECT scheduled_start_at,scheduled_end_at INTO v_anchor_start,v_anchor_end
  FROM public.workshop_admin_blocks WHERE id=v_anchor_id AND deleted_at IS NULL;

  IF coalesce((p_metadata->>'compact_released')::boolean,false) AND v_anchor_end IS NOT NULL THEN v_cursor:=greatest(v_cursor,v_anchor_end); END IF;

  DROP TABLE IF EXISTS pg_temp.workshop_admin_repack_items;
  CREATE TEMP TABLE workshop_admin_repack_items(
    kind text NOT NULL,
    id uuid NOT NULL,
    original_start timestamptz NOT NULL,
    original_end timestamptz NOT NULL,
    duration_minutes integer NOT NULL,
    row_version integer NOT NULL,
    final_start timestamptz,
    final_end timestamptz,
    PRIMARY KEY(kind,id)
  ) ON COMMIT DROP;

  INSERT INTO workshop_admin_repack_items(kind,id,original_start,original_end,duration_minutes,row_version)
  SELECT 'admin',a.id,a.scheduled_start_at,a.scheduled_end_at,a.duration_minutes,a.version
  FROM public.workshop_admin_blocks a
  WHERE a.bay_id=p_bay_id AND a.deleted_at IS NULL AND a.id IS DISTINCT FROM v_anchor_id
    AND (a.scheduled_end_at>p_from or (coalesce((p_metadata->>'recover_overdue')::boolean,false) and a.scheduled_start_at<p_from))
  ORDER BY a.scheduled_start_at,a.id
  FOR UPDATE;
  INSERT INTO workshop_admin_repack_items(kind,id,original_start,original_end,duration_minutes,row_version)
  SELECT 'booking',b.id,b.scheduled_start_at,b.scheduled_end_at,
    coalesce(public.workshop_booking_capacity_duration_minutes(b.id,b.vehicle_id,b.stage_id,b.bay_id),b.default_duration_minutes),b.version
  FROM public.workshop_bookings b
  WHERE b.bay_id=p_bay_id AND b.status='planned' AND b.deleted_at IS NULL
    AND (b.scheduled_end_at>p_from OR (coalesce((p_metadata->>'recover_overdue')::boolean,false) AND b.scheduled_start_at<p_from))
  ORDER BY b.scheduled_start_at,b.id
  FOR UPDATE;

  FOR v_item IN
    SELECT * FROM workshop_admin_repack_items ORDER BY original_start,kind,id
  LOOP
    v_start:=case when coalesce((p_metadata->>'compact_released')::boolean,false) then v_cursor else greatest(v_item.original_start,v_cursor) end;
    v_guard:=0;
    LOOP
      v_guard:=v_guard+1;
      IF v_guard>1000 THEN RAISE EXCEPTION 'Workshop Admin cascade guard exceeded' USING errcode='54000'; END IF;
      v_end:=public.workshop_add_operational_minutes(v_start,v_item.duration_minutes);
      SELECT max(public.workshop_booking_effective_end_at(b.id)) INTO v_fixed_end
      FROM public.workshop_bookings b
      WHERE b.bay_id=p_bay_id AND b.deleted_at IS NULL
        AND b.status::text IN ('queued','started','stoppage')
        AND b.scheduled_start_at<v_end AND public.workshop_booking_effective_end_at(b.id)>v_start;
      SELECT max(o.obstacle_end) INTO v_block_end
      FROM (
        SELECT v_anchor_end obstacle_end,v_anchor_start obstacle_start
        WHERE v_anchor_id IS NOT NULL AND v_anchor_end IS NOT NULL
        UNION ALL
        SELECT x.final_end,x.final_start
        FROM workshop_admin_repack_items x
        WHERE x.kind='admin' AND x.final_start IS NOT NULL
      ) o
      WHERE o.obstacle_start<v_end AND o.obstacle_end>v_start;
      EXIT WHEN v_fixed_end IS NULL AND v_block_end IS NULL;
      v_start:=greatest(v_start,coalesce(v_fixed_end,v_start),coalesce(v_block_end,v_start));
    END LOOP;
    UPDATE workshop_admin_repack_items
    SET final_start=v_start,final_end=v_end
    WHERE kind=v_item.kind AND id=v_item.id;
    v_cursor:=greatest(v_cursor,v_end);
  END LOOP;

  -- Rightward moves vacate from the back; leftward moves vacate from the front. Rows are
  -- written. Every row was locked and its original version is checked again.
  FOR v_item IN
    SELECT * FROM workshop_admin_repack_items
    WHERE final_start IS DISTINCT FROM original_start OR final_end IS DISTINCT FROM original_end
    ORDER BY CASE WHEN final_start<original_start THEN 0 ELSE 1 END,
    CASE WHEN final_start<original_start THEN original_start END ASC,
    CASE WHEN final_start>=original_start THEN original_start END DESC,kind,id
  LOOP
    IF v_item.kind='booking' THEN
      v_before:=public.workshop_booking_snapshot(v_item.id);
      UPDATE public.workshop_bookings
      SET scheduled_start_at=v_item.final_start,scheduled_end_at=v_item.final_end,
          default_duration_minutes=v_item.duration_minutes,
          updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1
      WHERE id=v_item.id AND status='planned' AND deleted_at IS NULL AND version=v_item.row_version;
      IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent planned booking version changed' USING errcode='40001'; END IF;
      SELECT a.technician_id INTO v_technician
      FROM public.workshop_booking_assignments a
      WHERE a.booking_id=v_item.id AND a.released_at IS NULL
      ORDER BY case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at DESC LIMIT 1;
      PERFORM public.workshop_upsert_primary_assignment(v_item.id,v_technician,v_item.final_start,v_item.final_end,'admin_block_cascaded');
      v_after:=public.workshop_booking_snapshot(v_item.id);
      PERFORM public.workshop_write_history(v_item.id,'admin_block_cascaded',v_before,v_after,
        coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_cascade',true));
    ELSE
      v_before:=public.workshop_admin_block_snapshot(v_item.id);
      UPDATE public.workshop_admin_blocks
      SET scheduled_start_at=v_item.final_start,scheduled_end_at=v_item.final_end,
          updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1
      WHERE id=v_item.id AND deleted_at IS NULL AND version=v_item.row_version;
      IF NOT FOUND THEN RAISE EXCEPTION 'Concurrent Admin block version changed' USING errcode='40001'; END IF;
      v_after:=public.workshop_admin_block_snapshot(v_item.id);
      INSERT INTO public.workshop_admin_block_history(
        block_id,event_type,block_version,before_data,after_data,metadata,actor_user_id,actor_email
      ) VALUES(v_item.id,'moved',(v_after->>'version')::integer,v_before,v_after,
        coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_cascade',true),auth.uid(),public.current_actor_email());
    END IF;
    v_shifted:=v_shifted||jsonb_build_array(jsonb_build_object(
      'kind',v_item.kind,'id',v_item.id,'from',v_item.original_start,'to',v_item.final_start,
      'duration_minutes',v_item.duration_minutes,'version_before',v_item.row_version,
      'version_after',v_item.row_version+1
    ));
  END LOOP;
  RETURN jsonb_build_object(
    'shifted_items',v_shifted,
    'shifted_count',jsonb_array_length(v_shifted),
    'shifted_booking_ids',coalesce((SELECT jsonb_agg(id) FROM jsonb_to_recordset(v_shifted) AS x(kind text,id uuid) WHERE kind='booking'),'[]'::jsonb),
    'shifted_admin_block_ids',coalesce((SELECT jsonb_agg(id) FROM jsonb_to_recordset(v_shifted) AS x(kind text,id uuid) WHERE kind='admin'),'[]'::jsonb)
  );
END $function$
;

CREATE OR REPLACE FUNCTION public.workshop_admin_nearest_available_slot(p_bay_id uuid, p_requested_start_at timestamp with time zone, p_duration_minutes integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_increment integer;
  v_candidate timestamptz;
  v_end timestamptz;
  v_fixed_end timestamptz;
  v_limit timestamptz;
  v_requested timestamptz := date_trunc('minute',p_requested_start_at);
BEGIN
  SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment
  FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
  v_increment:=greatest(1,coalesce(v_increment,15));
  IF v_requested IS NULL OR p_duration_minutes IS NULL OR p_duration_minutes<=0 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  END IF;
  v_candidate:=public.workshop_admin_next_operational_minute(v_requested);
  v_limit:=v_requested+interval '45 days';
  WHILE v_candidate IS NOT NULL AND v_candidate<v_limit LOOP
    v_end:=public.workshop_add_operational_minutes(v_candidate,p_duration_minutes);
    IF v_end IS NULL OR v_end<=v_candidate
       OR public.workshop_operational_minutes_between(v_candidate,v_end)<>p_duration_minutes THEN RETURN jsonb_build_object('ok',false,'error','invalid_schedule_interval'); END IF;
    SELECT max(public.workshop_booking_effective_end_at(b.id))
      INTO v_fixed_end
    FROM public.workshop_bookings b
    WHERE b.bay_id=p_bay_id AND b.deleted_at IS NULL
      AND b.status::text IN ('queued','started','stoppage')
      AND b.scheduled_start_at<v_end AND public.workshop_booking_effective_end_at(b.id)>v_candidate
;
    IF v_fixed_end IS NULL THEN
      RETURN jsonb_build_object(
        'ok',true,
        'scheduled_start_at',v_candidate,
        'scheduled_end_at',v_end,
        'duration_minutes',p_duration_minutes,
        'distance_minutes',public.workshop_operational_minutes_between(v_requested,v_candidate)
      );
    END IF;
    -- Jump past the blocker instead of probing every 15-minute slot.
    v_candidate:=public.workshop_admin_next_operational_minute(greatest(v_fixed_end,v_candidate+interval '1 minute'));
  END LOOP;
  RETURN jsonb_build_object('ok',false,'error','no_available_slot');
END $function$
;
