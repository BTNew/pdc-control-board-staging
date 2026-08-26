-- STAGING ONLY 462: repack every eligible planned booking using authoritative required-work duration.
BEGIN;SET LOCAL lock_timeout='10s';SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-462-authoritative-planned-repack',0));
DO $pre$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827011000' AND name='461_workshop_recovery_validation_containment')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827011000')
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')<>'d12b95b271f694aadf84cfeff6ce7073bd6811129b8d902056a606ec292de311'
 THEN RAISE EXCEPTION 'PDC_462_STAGING_HEAD_OR_FUNCTION_MISMATCH' USING errcode='55000';END IF;
END $pre$;

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
    coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id),b.default_duration_minutes),b.version
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
      SELECT max(b.scheduled_end_at) INTO v_fixed_end
      FROM public.workshop_bookings b
      WHERE b.bay_id=p_bay_id AND b.deleted_at IS NULL
        AND b.status::text IN ('queued','started','stoppage')
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
END $function$;
REVOKE ALL ON FUNCTION public.workshop_admin_repack_planned(uuid,timestamptz,jsonb) FROM public,anon,authenticated,service_role;
DO $post$ BEGIN
 IF pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure) NOT LIKE '%workshop_vehicle_stage_estimated_duration_minutes(b.vehicle_id,b.stage_id)%'
 OR pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure) NOT LIKE '%default_duration_minutes=v_item.duration_minutes%'
 OR pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure) NOT LIKE '%recover_overdue%' THEN
  RAISE EXCEPTION 'PDC_462_POSTCONDITION_FAILED' USING errcode='55000';
 END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260827012000','462_authoritative_planned_repack',ARRAY['Repack each eligible planned booking with its current authoritative required-work duration','Overdue planned rows remain eligible during recovery even after their stale end time','Started queued stoppage completed fixed and deleted history remain immutable; production untouched']);
NOTIFY pgrst,'reload schema';COMMIT;
