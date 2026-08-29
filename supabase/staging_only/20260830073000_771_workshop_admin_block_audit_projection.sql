-- Staging-only 771: narrow authenticated Workshop Admin-block audit projection.
-- This is read-only. It exposes one exact station/bay/date scope through a
-- SECURITY DEFINER RPC while leaving operational-table RLS and direct grants
-- unchanged. No repair, delete, restore or email path is included.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-771-workshop-admin-block-audit',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
  IF current_user <> 'postgres'
     OR session_user <> 'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FILTER (WHERE version~'^[0-9]{14}$')
         FROM supabase_migrations.schema_migrations) <> '20260830072000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260830072000' AND name='navision_import_preflight_contract') <> 1
     OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830073000')
     OR to_regprocedure('public.workshop_admin_block_snapshot(uuid)') IS NULL
     OR to_regprocedure('public.workshop_calendar_minute_available(timestamptz)') IS NULL
     OR to_regprocedure('public.workshop_operational_minutes_between(timestamptz,timestamptz)') IS NULL
     OR to_regclass('public.workshop_admin_blocks') IS NULL
     OR to_regclass('public.workshop_admin_block_history') IS NULL
     OR to_regclass('public.workshop_admin_block_receipts') IS NULL
     OR to_regclass('public.workshop_settings') IS NULL
     OR to_regclass('public.workshop_bookings') IS NULL
     OR to_regclass('public.workshop_booking_history') IS NULL
     OR to_regclass('public.workshop_revision') IS NULL
     OR to_regclass('public.workshop_station_revision') IS NULL
  THEN RAISE EXCEPTION 'PDC_771_EXACT_STAGING_HEAD_OR_WORKSHOP_DEPENDENCY_MISMATCH' USING errcode='55000'; END IF;
END
$pre$;

CREATE OR REPLACE FUNCTION public.get_workshop_admin_block_audit_771(
  p_stage_code text,
  p_bay_number integer,
  p_date_from date,
  p_date_to date,
  p_block_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $audit$
DECLARE
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_block public.workshop_admin_blocks%rowtype;
  v_day date;
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_range_start timestamptz;
  v_range_end timestamptz;
  v_minute timestamptz;
  v_run_start timestamptz;
  v_run_end timestamptz;
  v_windows jsonb;
  v_block_rows jsonb := '[]'::jsonb;
  v_block_ids uuid[] := '{}'::uuid[];
  v_response jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT (public.is_pdc_role('operator') OR public.is_pdc_role('administrator')) THEN
    RAISE EXCEPTION 'PDC_771_OPERATOR_OR_ADMINISTRATOR_REQUIRED' USING errcode='42501';
  END IF;
  IF p_stage_code IS NULL OR upper(btrim(p_stage_code)) !~ '^[A-Z0-9_]+$'
     OR p_bay_number IS NULL OR p_bay_number < 1
     OR p_date_from IS NULL OR p_date_to IS NULL
     OR p_date_to < p_date_from OR p_date_to > p_date_from + 31 THEN
    RAISE EXCEPTION 'PDC_771_INVALID_AUDIT_SCOPE' USING errcode='22023';
  END IF;

  SELECT * INTO v_stage FROM public.workshop_stages
  WHERE code=upper(btrim(p_stage_code)) AND active AND planner_enabled AND is_physical;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_771_STAGE_NOT_FOUND' USING errcode='22023'; END IF;
  SELECT * INTO v_bay FROM public.workshop_bays
  WHERE stage_id=v_stage.id AND bay_number=p_bay_number AND is_active AND NOT is_sublet_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_771_BAY_NOT_FOUND' USING errcode='22023'; END IF;

  v_range_start:=p_date_from::timestamp AT TIME ZONE 'Australia/Perth';
  v_range_end:=(p_date_to+1)::timestamp AT TIME ZONE 'Australia/Perth';

  FOR v_block IN
    SELECT a.* FROM public.workshop_admin_blocks a
    WHERE a.stage_id=v_stage.id AND a.bay_id=v_bay.id
      AND a.scheduled_start_at<v_range_end AND a.scheduled_end_at>v_range_start
      AND (p_block_id IS NULL OR a.id=p_block_id)
    ORDER BY a.scheduled_start_at,a.id
  LOOP
    v_block_ids:=array_append(v_block_ids,v_block.id);
    v_windows:='[]'::jsonb;
    FOR v_day IN SELECT generate_series(p_date_from,p_date_to,interval '1 day')::date LOOP
      v_day_start:=v_day::timestamp AT TIME ZONE 'Australia/Perth';
      v_day_end:=(v_day+1)::timestamp AT TIME ZONE 'Australia/Perth';
      v_run_start:=NULL; v_run_end:=NULL;
      FOR v_minute IN
        SELECT value FROM generate_series(
          greatest(v_day_start,v_block.scheduled_start_at),
          least(v_day_end,v_block.scheduled_end_at)-interval '1 minute',
          interval '1 minute'
        ) AS minutes(value)
      LOOP
        IF public.workshop_calendar_minute_available(v_minute) THEN
          IF v_run_start IS NULL THEN
            v_run_start:=v_minute; v_run_end:=v_minute+interval '1 minute';
          ELSIF v_minute=v_run_end THEN
            v_run_end:=v_minute+interval '1 minute';
          ELSE
            v_windows:=v_windows||jsonb_build_array(jsonb_build_object(
              'date',v_run_start AT TIME ZONE 'Australia/Perth',
              'start_at',v_run_start,'end_at',v_run_end,
              'minutes',extract(epoch FROM (v_run_end-v_run_start))/60
            ));
            v_run_start:=v_minute; v_run_end:=v_minute+interval '1 minute';
          END IF;
        END IF;
      END LOOP;
      IF v_run_start IS NOT NULL THEN
        v_windows:=v_windows||jsonb_build_array(jsonb_build_object(
          'date',v_run_start AT TIME ZONE 'Australia/Perth',
          'start_at',v_run_start,'end_at',v_run_end,
          'minutes',extract(epoch FROM (v_run_end-v_run_start))/60
        ));
      END IF;
    END LOOP;
    v_block_rows:=v_block_rows||jsonb_build_array(jsonb_build_object(
      'id',v_block.id,'version',v_block.version,'block_type',v_block.block_type,
      'label',v_block.label,'stage_id',v_block.stage_id,'stage_code',v_stage.code,
      'bay_id',v_block.bay_id,'bay_number',v_bay.bay_number,
      'scheduled_start_at',v_block.scheduled_start_at,'scheduled_end_at',v_block.scheduled_end_at,
      'duration_minutes',v_block.duration_minutes,
      'operational_minutes',public.workshop_operational_minutes_between(v_block.scheduled_start_at,v_block.scheduled_end_at),
      'deleted_at',v_block.deleted_at,'deleted_reason',v_block.deleted_reason,
      'created_at',v_block.created_at,'updated_at',v_block.updated_at,
      'continuation_windows',v_windows
    ));
  END LOOP;

  v_response:=jsonb_build_object(
    'ok',true,'contract','get_workshop_admin_block_audit_771',
    'environment','staging','scope',jsonb_build_object(
      'stage_code',v_stage.code,'bay_number',v_bay.bay_number,
      'date_from',p_date_from,'date_to',p_date_to,
      'block_id',p_block_id
    ),
    'blocks',v_block_rows,
    'block_count',jsonb_array_length(v_block_rows),
    'calendar',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'key',s.key,'value',s.value,'version',s.version,'updated_at',s.updated_at
      ) ORDER BY s.key),'[]'::jsonb)
      FROM public.workshop_settings s
      WHERE s.key IN ('working_week','day_start_time','day_end_time','scheduling_increment_minutes',
                      'closures','break_windows','overtime_windows','technician_leave',
                      'future_only_schedule_enforcement')
    ),
    'global_revision',(SELECT jsonb_build_object('id',r.id,'revision',r.revision,'updated_at',r.updated_at)
                       FROM public.workshop_revision r WHERE r.id=1),
    'station_revision',(SELECT jsonb_build_object('stage_code',r.stage_code,'revision',r.revision,'updated_at',r.updated_at)
                        FROM public.workshop_station_revision r WHERE r.stage_code=v_stage.code),
    'affected_planned_bookings',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id',b.id,'vehicle_id',b.vehicle_id,'status',b.status,
        'stage_id',b.stage_id,'bay_id',b.bay_id,'scheduled_start_at',b.scheduled_start_at,
        'scheduled_end_at',b.scheduled_end_at,'default_duration_minutes',b.default_duration_minutes,
        'version',b.version,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at
      ) ORDER BY b.scheduled_start_at,b.id),'[]'::jsonb)
      FROM public.workshop_bookings b
      WHERE b.bay_id=v_bay.id AND b.deleted_at IS NULL AND b.status='planned'
        AND b.scheduled_start_at<v_range_end AND b.scheduled_end_at>v_range_start
    ),
    'cascade_history',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id',h.id,'booking_id',h.booking_id,'event_type',h.event_type,
        'before_data',h.before_data,'after_data',h.after_data,
        'metadata',h.metadata,'created_at',h.created_at
      ) ORDER BY h.created_at,h.id),'[]'::jsonb)
      FROM public.workshop_booking_history h
      WHERE h.booking_id IN (
        SELECT b.id FROM public.workshop_bookings b
        WHERE b.bay_id=v_bay.id AND b.deleted_at IS NULL
          AND b.scheduled_start_at<v_range_end AND b.scheduled_end_at>v_range_start
      ) AND (h.metadata ? 'admin_block_cascade' OR h.metadata ? 'admin_block_id')
    ),
    'history',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id',h.id,'block_id',h.block_id,'event_type',h.event_type,
        'block_version',h.block_version,'before_data',h.before_data,'after_data',h.after_data,
        'metadata',h.metadata,'created_at',h.created_at
      ) ORDER BY h.created_at,h.id),'[]'::jsonb)
      FROM public.workshop_admin_block_history h
      WHERE h.block_id=ANY(v_block_ids)
    ),
    'receipts',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'receipt_id',r.receipt_id,'block_id',r.block_id,'mutation_type',r.mutation_type,
        'expected_version',r.expected_version,'resulting_version',r.resulting_version,
        'response',r.response,'metadata',r.metadata,'created_at',r.created_at,
        'idempotency_key',r.idempotency_key,'request_hash',r.request_hash
      ) ORDER BY r.created_at,r.receipt_id),'[]'::jsonb)
      FROM public.workshop_admin_block_receipts r
      WHERE r.block_id=ANY(v_block_ids)
    ),
    'undo',jsonb_build_object(
      'available',false,
      'reason','No undo mutation is exposed by the read-only 771 contract; existing immutable receipts/history remain the recovery evidence.'
    )
  );
  RETURN v_response||jsonb_build_object(
    'response_sha256',encode(extensions.digest(convert_to(v_response::text,'UTF8'),'sha256'),'hex')
  );
END
$audit$;

REVOKE ALL ON FUNCTION public.get_workshop_admin_block_audit_771(text,integer,date,date,uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_workshop_admin_block_audit_771(text,integer,date,date,uuid) TO authenticated;
COMMENT ON FUNCTION public.get_workshop_admin_block_audit_771(text,integer,date,date,uuid) IS
  'Staging-only operator/administrator read projection for one exact Workshop station/bay/date scope. Returns persisted Admin-block interval, configured calendar, derived continuation windows, affected planned rows, immutable cascade history, receipts and revisions. No generic table access or mutation.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260830073000','771_workshop_admin_block_audit_projection',ARRAY[
  'Require exact staging predecessor 20260830072000 and reject production sentinel',
  'Expose only an authenticated operator/administrator exact station/bay/date Admin-block audit projection',
  'Return persisted start/end/duration/version, configured calendar, minute-derived continuation windows, revisions, affected planned bookings and immutable cascade/history/receipt evidence',
  'Do not grant generic table access and expose no repair, restore, undo, delete, service-role or email path',
  'Preserve existing Admin-block mutation idempotency, planned-only cascade and started/stoppage/completed history'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
