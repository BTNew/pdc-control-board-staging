-- Staging-only 394: compact released Admin capacity and preserve exact duration.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-394-admin-compaction',0));

DO $pre$
BEGIN
  IF current_user <> 'postgres'
     OR session_user <> 'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826093000' AND name='393_future_only_workshop_recovery')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826093000')
     OR to_regprocedure('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)') IS NULL THEN
    RAISE EXCEPTION 'PDC_394_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

DO $repack_patch$
DECLARE
  v_definition text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure) INTO v_definition;
  v_patched:=replace(v_definition,
    'v_start:=greatest(v_item.original_start,v_cursor);',
    'v_start:=case when coalesce((p_metadata->>''compact_released'')::boolean,false) then v_cursor else greatest(v_item.original_start,v_cursor) end;');
  v_patched:=replace(v_patched,
    'SELECT scheduled_start_at,scheduled_end_at INTO v_anchor_start,v_anchor_end',
    'SELECT scheduled_start_at,scheduled_end_at INTO v_anchor_start,v_anchor_end');
  v_patched:=replace(v_patched,
    'FROM public.workshop_admin_blocks WHERE id=v_anchor_id AND deleted_at IS NULL;',
    'FROM public.workshop_admin_blocks WHERE id=v_anchor_id AND deleted_at IS NULL;
  IF coalesce((p_metadata->>''compact_released'')::boolean,false) AND v_anchor_end IS NOT NULL THEN v_cursor:=greatest(v_cursor,v_anchor_end); END IF;');
  IF v_patched=v_definition OR position('compact_released' in v_patched)=0 THEN
    RAISE EXCEPTION 'PDC_394_REPACK_PATCH_ANCHOR_MISSING' USING errcode='55000';
  END IF;
  EXECUTE v_patched;
END $repack_patch$;

CREATE OR REPLACE FUNCTION public.workshop_admin_next_operational_minute(p_from timestamptz)
RETURNS timestamptz LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $next$
DECLARE
  v_increment integer;
  v_candidate timestamptz:=date_trunc('minute',p_from);
BEGIN
  SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
  v_increment:=greatest(1,coalesce(v_increment,15));
  FOR i IN 0..(60*24*14) LOOP
    IF public.workshop_calendar_minute_available(v_candidate) THEN RETURN v_candidate; END IF;
    v_candidate:=v_candidate+((v_increment::text||' minutes')::interval);
  END LOOP;
  RETURN NULL;
END $next$;
REVOKE ALL ON FUNCTION public.workshop_admin_next_operational_minute(timestamptz) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.delete_workshop_admin_block(
  p_block_id uuid,p_expected_version integer,p_reason text DEFAULT NULL,p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $delete$
DECLARE
  v_block public.workshop_admin_blocks%rowtype;
  v_before jsonb; v_after jsonb; v_response jsonb; v_repack jsonb;
  v_revision bigint; v_receipt uuid; v_stage text; v_from timestamptz;
BEGIN
  PERFORM public.require_pdc_role('administrator');
  SELECT * INTO v_block FROM public.workshop_admin_blocks WHERE id=p_block_id FOR UPDATE;
  IF NOT FOUND OR v_block.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','admin_block_not_found'); END IF;
  IF v_block.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
  PERFORM public.workshop_admin_lock_physical_bays(v_block.bay_id,NULL);
  SELECT code INTO v_stage FROM public.workshop_stages WHERE id=v_block.stage_id;
  v_before:=public.workshop_admin_block_snapshot(p_block_id);
  UPDATE public.workshop_admin_blocks
  SET deleted_at=clock_timestamp(),deleted_reason=nullif(btrim(coalesce(p_reason,'')),''),updated_by=auth.uid(),updated_at=clock_timestamp(),version=version+1
  WHERE id=p_block_id;
  v_from:=public.workshop_admin_next_operational_minute(greatest(v_block.scheduled_start_at,date_trunc('minute',clock_timestamp())));
  IF v_from IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_future_operational_minute','no_partial_save',true); END IF;
  v_repack:=public.workshop_admin_repack_planned(v_block.bay_id,v_from,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('admin_block_id',p_block_id,'compact_released',true));
  v_after:=public.workshop_admin_block_snapshot(p_block_id);
  v_revision:=public.workshop_bump_revision(); PERFORM public.workshop_bump_station_revision(v_stage);
  v_response:=jsonb_build_object('ok',true,'code','admin_block_deleted','admin_block',v_after,'revision',v_revision,'repack',v_repack,'cascade',v_repack,'notification_delta',0);
  v_receipt:=public.workshop_admin_write_evidence(p_block_id,'deleted',p_expected_version,v_before,v_after,v_response,p_metadata);
  RETURN v_response||jsonb_build_object('receipt_id',v_receipt);
END $delete$;

DO $resize_patch$
DECLARE v_definition text; v_patched text;
BEGIN
 SELECT pg_get_functiondef('public.resize_workshop_admin_block(uuid,integer,integer,jsonb)'::regprocedure) INTO v_definition;
 v_patched:=replace(v_definition,
   'coalesce(p_metadata,''{}''::jsonb)||jsonb_build_object(''admin_block_id'',p_block_id)',
   'coalesce(p_metadata,''{}''::jsonb)||jsonb_build_object(''admin_block_id'',p_block_id,''compact_released'',p_duration_minutes<v_block.duration_minutes)');
 IF v_patched=v_definition OR position('compact_released' in v_patched)=0 THEN RAISE EXCEPTION 'PDC_394_RESIZE_PATCH_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE v_patched;
END $resize_patch$;

REVOKE ALL ON FUNCTION public.delete_workshop_admin_block(uuid,integer,text,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.delete_workshop_admin_block(uuid,integer,text,jsonb) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826100000','394_admin_compaction_and_duration_bounds',ARRAY[
  'shorten/delete compacts eligible future planned vehicle/Admin rows toward the next valid operational minute',
  'fixed/live, started, stoppage, completed, cancelled/deleted and cross-bay rows remain untouched',
  'exact multi-day operational durations and one receipt/revision/readback contract are preserved'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
