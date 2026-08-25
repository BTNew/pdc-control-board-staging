-- Staging-only 393: future-only recovery for unstarted planned Workshop work.
-- Started, stoppage, completed, cancelled and deleted rows remain truthful history.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-393-future-only-workshop-recovery',0));

DO $pre$
BEGIN
  IF current_user <> 'postgres'
     OR session_user <> 'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826090000' AND name='392_workshop_admin_block_atomic_cascade')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826090000')
     OR to_regprocedure('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)') IS NULL
     OR to_regprocedure('public.workshop_calendar_minute_available(timestamptz)') IS NULL
     OR to_regprocedure('public.workshop_add_operational_minutes(timestamptz,integer)') IS NULL
     OR to_regprocedure('public.workshop_bump_revision()') IS NULL THEN
    RAISE EXCEPTION 'PDC_393_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

INSERT INTO public.workshop_settings(key,value)
VALUES('future_only_schedule_enforcement','true'::jsonb)
ON CONFLICT(key) DO NOTHING;

DO $repack_patch$
DECLARE
  v_definition text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure) INTO v_definition;
  v_patched:=replace(v_definition,
    'AND a.scheduled_end_at>p_from',
    'AND (a.scheduled_end_at>p_from or (coalesce((p_metadata->>''recover_overdue'')::boolean,false) and a.scheduled_start_at<p_from))');
  IF v_patched=v_definition OR position('recover_overdue' in v_patched)=0 THEN
    RAISE EXCEPTION 'PDC_393_REPACK_PATCH_ANCHOR_MISSING' USING errcode='55000';
  END IF;
  EXECUTE v_patched;
END $repack_patch$;

CREATE TABLE public.workshop_schedule_recovery_receipts(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL,
  request_hash text NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_user_id,idempotency_key)
);
ALTER TABLE public.workshop_schedule_recovery_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.workshop_schedule_recovery_receipts FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.workshop_future_only_schedule_enabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT coalesce((SELECT (value#>>'{}')::boolean FROM public.workshop_settings WHERE key='future_only_schedule_enforcement'),true)
$$;

CREATE OR REPLACE FUNCTION public.workshop_reject_overdue_planned_booking()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $guard$
BEGIN
  IF public.workshop_future_only_schedule_enabled()
     AND new.deleted_at IS NULL
     AND new.status::text='planned'
     AND new.scheduled_start_at < date_trunc('minute',clock_timestamp()) THEN
    RAISE EXCEPTION '%',jsonb_build_object('error','overdue_planned_booking','next_recovery','run_recover_overdue_planned_workshop_bookings')::text USING errcode='22023';
  END IF;
  RETURN new;
END $guard$;
DROP TRIGGER IF EXISTS workshop_bookings_reject_overdue_planned ON public.workshop_bookings;
CREATE TRIGGER workshop_bookings_reject_overdue_planned
BEFORE INSERT OR UPDATE OF status,scheduled_start_at,deleted_at
ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION public.workshop_reject_overdue_planned_booking();
REVOKE ALL ON FUNCTION public.workshop_reject_overdue_planned_booking() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.recover_overdue_planned_workshop_bookings(
  p_idempotency_key text,
  p_as_of timestamptz DEFAULT clock_timestamp()
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $recover$
DECLARE
  v_actor uuid:=auth.uid();
  v_key text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_as_of timestamptz:=coalesce(p_as_of,clock_timestamp());
  v_start timestamptz:=date_trunc('minute',v_as_of);
  v_increment integer;
  v_bay record;
  v_stage text;
  v_repack jsonb;
  v_moved jsonb:='[]'::jsonb;
  v_count integer:=0;
  v_hash text;
  v_existing public.workshop_schedule_recovery_receipts%rowtype;
  v_response jsonb;
BEGIN
  PERFORM public.workshop_require_planner_operator();
  IF v_actor IS NULL OR v_key IS NULL OR v_key !~ '^[A-Za-z0-9:_-]{8,160}$' THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_idempotency_key','no_partial_save',true);
  END IF;
  IF NOT public.workshop_future_only_schedule_enabled() THEN
    RETURN jsonb_build_object('ok',true,'code','future_only_disabled','moved_count',0,'notification_delta',0);
  END IF;
  v_hash:=md5(jsonb_build_object('as_of',v_as_of,'contract_version',1)::text);
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-recovery-request:'||v_actor::text||':'||v_key,0));
  SELECT * INTO v_existing FROM public.workshop_schedule_recovery_receipts
  WHERE actor_user_id=v_actor AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_existing.request_hash IS DISTINCT FROM v_hash THEN
      RETURN jsonb_build_object('ok',false,'error','idempotency_conflict','no_partial_save',true);
    END IF;
    RETURN v_existing.response||jsonb_build_object('replay',true);
  END IF;
  SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
  v_increment:=greatest(1,coalesce(v_increment,15));
  WHILE NOT public.workshop_calendar_minute_available(v_start) LOOP
    v_start:=v_start+((v_increment::text||' minutes')::interval);
    IF v_start>v_as_of+interval '14 days' THEN
      RETURN jsonb_build_object('ok',false,'error','no_future_operational_minute','no_partial_save',true);
    END IF;
  END LOOP;
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-future-only-recovery',0));
  FOR v_bay IN
    SELECT DISTINCT b.bay_id
    FROM public.workshop_bookings b
    WHERE b.bay_id IS NOT NULL AND b.deleted_at IS NULL AND b.status::text='planned'
      AND b.scheduled_start_at<v_as_of
    ORDER BY b.bay_id
  LOOP
    PERFORM public.workshop_lock_resources(v_bay.bay_id,NULL);
    v_repack:=public.workshop_admin_repack_planned(v_bay.bay_id,v_start,jsonb_build_object(
      'source','future_only_recovery','recover_overdue',true,'recovery_as_of',v_as_of,'request_id',v_key));
    v_count:=v_count+coalesce((v_repack->>'shifted_count')::integer,0);
    v_moved:=v_moved||coalesce(v_repack->'shifted_items','[]'::jsonb);
    SELECT s.code INTO v_stage FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=v_bay.bay_id;
    IF v_stage IS NOT NULL THEN PERFORM public.workshop_bump_station_revision(v_stage); END IF;
  END LOOP;
  IF v_count>0 THEN PERFORM public.workshop_bump_revision(); END IF;
  v_response:=jsonb_build_object('ok',true,'code','overdue_planned_recovered','replay',false,
    'as_of',v_as_of,'recovery_start',v_start,'moved_count',v_count,'moved_items',v_moved,
    'notification_delta',0,'no_partial_save',false);
  INSERT INTO public.workshop_schedule_recovery_receipts(actor_user_id,idempotency_key,request_hash,response)
  VALUES(v_actor,v_key,v_hash,v_response);
  RETURN v_response;
END $recover$;
REVOKE ALL ON FUNCTION public.workshop_future_only_schedule_enabled() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.recover_overdue_planned_workshop_bookings(text,timestamptz) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recover_overdue_planned_workshop_bookings(text,timestamptz) TO authenticated;

-- Every authenticated station snapshot performs the same idempotent recovery
-- before it is trusted. Revision-derived keys avoid receipt churn while still
-- rerunning after a mutation creates a new overdue row.
CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot(
  p_stage_code text,p_date_from date,p_date_to date
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE
  v_snapshot jsonb;
  v_stage text;
  v_from timestamptz;
  v_to timestamptz;
BEGIN
  PERFORM public.workshop_require_planner_operator();
  PERFORM public.recover_overdue_planned_workshop_bookings(
    'snapshot-'||auth.uid()::text||'-'||public.workshop_current_revision()::text,
    date_trunc('minute',clock_timestamp())
  );
  v_snapshot:=public.get_station_workshop_snapshot_pre_170(p_stage_code,p_date_from,p_date_to);
  v_stage:=v_snapshot#>>'{scope,stage_code}';
  v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
  v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
  RETURN v_snapshot||jsonb_build_object('admin_blocks',(
    SELECT coalesce(jsonb_agg(public.workshop_admin_block_snapshot(a.id) order by a.scheduled_start_at,a.id),'[]'::jsonb)
    FROM public.workshop_admin_blocks a
    JOIN public.workshop_stages s ON s.id=a.stage_id
    WHERE a.deleted_at IS NULL AND s.code=v_stage
      AND a.scheduled_start_at<v_to AND a.scheduled_end_at>v_from
  ));
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_station_workshop_snapshot(text,date,date) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_station_workshop_snapshot(text,date,date) TO authenticated,service_role;
COMMENT ON FUNCTION public.get_station_workshop_snapshot(text,date,date) IS
  'Authoritative station snapshot with idempotent future-only recovery before readback; no planned booking is returned in elapsed time.';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826093000','393_future_only_workshop_recovery',ARRAY[
  'future-only enforcement rejects new or moved overdue planned rows',
  'administrator/operator recovery repacks every overdue planned row by physical bay with exact duration and history/version preservation',
  'idempotent recovery receipt, revision/station invalidation and zero notifications',
  'staging-only rollback switch future_only_schedule_enforcement'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
