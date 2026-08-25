-- Staging-only 392: atomic Admin block insertion with exact planned/Admin cascade.
-- The request is evaluated against the locked bay, station, revision and row
-- versions at drop time. Production is structurally excluded by the guard.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-392-workshop-admin-atomic-cascade',0));

DO $pre$
BEGIN
  IF current_user <> 'postgres'
     OR session_user <> 'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825235000' AND name='391_detail_stale_receipt_repair')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825235000')
     OR to_regclass('public.workshop_admin_blocks') IS NULL
     OR to_regclass('public.workshop_admin_block_receipts') IS NULL
     OR to_regprocedure('public.workshop_lock_resources(uuid,uuid)') IS NULL
     OR to_regprocedure('public.workshop_add_operational_minutes(timestamptz,integer)') IS NULL
     OR to_regprocedure('public.workshop_operational_minutes_between(timestamptz,timestamptz)') IS NULL
     OR to_regprocedure('public.workshop_calendar_minute_available(timestamptz)') IS NULL
     OR to_regprocedure('public.workshop_bump_revision()') IS NULL
     OR to_regprocedure('public.workshop_bump_station_revision(text)') IS NULL
     OR to_regprocedure('public.workshop_write_history(uuid,text,jsonb,jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'PDC_392_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

ALTER TABLE public.workshop_admin_block_receipts
  ADD COLUMN IF NOT EXISTS idempotency_key text,
  ADD COLUMN IF NOT EXISTS request_hash text;
CREATE UNIQUE INDEX IF NOT EXISTS workshop_admin_block_receipts_actor_request_uidx
  ON public.workshop_admin_block_receipts(actor_user_id,idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.workshop_admin_nearest_available_slot(
  p_bay_id uuid,
  p_requested_start_at timestamptz,
  p_duration_minutes integer
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $slot$
DECLARE
  v_increment integer;
  v_candidate timestamptz;
  v_end timestamptz;
  v_fixed record;
  v_requested timestamptz := date_trunc('minute',p_requested_start_at);
BEGIN
  SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment
  FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
  v_increment:=greatest(1,coalesce(v_increment,15));
  IF v_requested IS NULL OR p_duration_minutes IS NULL OR p_duration_minutes<=0 THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  END IF;
  FOR v_candidate IN
    SELECT v_requested + (((n * v_increment)::text || ' minutes')::interval)
    FROM generate_series(0,60*24*45) n
  LOOP
    IF NOT public.workshop_calendar_minute_available(v_candidate) THEN CONTINUE; END IF;
    v_end:=public.workshop_add_operational_minutes(v_candidate,p_duration_minutes);
    IF v_end IS NULL OR v_end<=v_candidate
       OR public.workshop_operational_minutes_between(v_candidate,v_end)<>p_duration_minutes THEN CONTINUE; END IF;
    SELECT b.id,b.status::text status,b.vehicle_id,b.stage_id,b.scheduled_start_at,b.scheduled_end_at
      INTO v_fixed
    FROM public.workshop_bookings b
    WHERE b.bay_id=p_bay_id AND b.deleted_at IS NULL
      AND b.status::text IN ('queued','started','stoppage','completed')
      AND b.scheduled_start_at<v_end AND b.scheduled_end_at>v_candidate
    ORDER BY b.scheduled_start_at,b.id LIMIT 1;
    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'ok',true,
        'scheduled_start_at',v_candidate,
        'scheduled_end_at',v_end,
        'duration_minutes',p_duration_minutes,
        'distance_minutes',public.workshop_operational_minutes_between(v_requested,v_candidate)
      );
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok',false,'error','no_available_slot');
END $slot$;

-- Planned vehicle bookings and active Admin rows are virtualised first and
-- written in reverse order. That makes a forward cascade safe against the
-- existing overlap triggers: later rows move out of the way before earlier
-- rows take their exact final positions. Started, stoppage, completed and
-- queued/fixed rows are never UPDATE targets.
CREATE OR REPLACE FUNCTION public.workshop_admin_repack_planned(
  p_bay_id uuid,
  p_from timestamptz,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $repack$
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
    AND a.scheduled_end_at>p_from
  ORDER BY a.scheduled_start_at,a.id
  FOR UPDATE;
  INSERT INTO workshop_admin_repack_items(kind,id,original_start,original_end,duration_minutes,row_version)
  SELECT 'booking',b.id,b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.version
  FROM public.workshop_bookings b
  WHERE b.bay_id=p_bay_id AND b.status='planned' AND b.deleted_at IS NULL
    AND b.scheduled_end_at>p_from
  ORDER BY b.scheduled_start_at,b.id
  FOR UPDATE;

  FOR v_item IN
    SELECT * FROM workshop_admin_repack_items ORDER BY original_start,kind,id
  LOOP
    v_start:=greatest(v_item.original_start,v_cursor);
    v_guard:=0;
    LOOP
      v_guard:=v_guard+1;
      IF v_guard>1000 THEN RAISE EXCEPTION 'Workshop Admin cascade guard exceeded' USING errcode='54000'; END IF;
      v_end:=public.workshop_add_operational_minutes(v_start,v_item.duration_minutes);
      SELECT max(b.scheduled_end_at) INTO v_fixed_end
      FROM public.workshop_bookings b
      WHERE b.bay_id=p_bay_id AND b.deleted_at IS NULL
        AND b.status::text IN ('queued','started','stoppage','completed')
        AND b.scheduled_start_at<v_end AND b.scheduled_end_at>v_start;
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

  -- Reverse order is essential: it vacates later rows before earlier rows are
  -- written. Every row was locked and its original version is checked again.
  FOR v_item IN
    SELECT * FROM workshop_admin_repack_items
    WHERE final_start IS DISTINCT FROM original_start
    ORDER BY original_start DESC,kind DESC,id DESC
  LOOP
    IF v_item.kind='booking' THEN
      v_before:=public.workshop_booking_snapshot(v_item.id);
      UPDATE public.workshop_bookings
      SET scheduled_start_at=v_item.final_start,scheduled_end_at=v_item.final_end,
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
END $repack$;

CREATE OR REPLACE FUNCTION public.create_workshop_admin_block(
  p_expected_revision bigint,
  p_stage_code text,
  p_bay_number integer,
  p_block_type text,
  p_label text,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $create$
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
  SELECT b.id,b.status::text status,b.vehicle_id,b.stage_id,b.scheduled_start_at,b.scheduled_end_at
    INTO v_fixed
  FROM public.workshop_bookings b
  WHERE b.bay_id=(v_valid->>'bay_id')::uuid AND b.deleted_at IS NULL
    AND b.status::text IN ('queued','started','stoppage','completed')
    AND b.scheduled_start_at<v_end AND b.scheduled_end_at>p_scheduled_start_at
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
END $create$;

REVOKE ALL ON FUNCTION public.workshop_admin_nearest_available_slot(uuid,timestamptz,integer) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.workshop_admin_repack_planned(uuid,timestamptz,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb) TO authenticated;

COMMENT ON FUNCTION public.create_workshop_admin_block(bigint,text,integer,text,text,timestamptz,integer,jsonb) IS
  'Administrator-only atomic Admin block insertion. Fixed/live conflicts return blocker and nearest exact slot; planned vehicle and Admin rows cascade through configured workdays with idempotent receipt and no notifications.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826090000','392_workshop_admin_block_atomic_cascade',ARRAY[
  'drop-time exact station/bay/date/time and row-version locking',
  'atomic planned vehicle/Admin cascade through operational minutes and later workdays',
  'fixed/live blocker with nearest exact slot and no partial save',
  'administrator idempotency, receipt/audit, revision bump, authoritative readback contract, no notifications'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
