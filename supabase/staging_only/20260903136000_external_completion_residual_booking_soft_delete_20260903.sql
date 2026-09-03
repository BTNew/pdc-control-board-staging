-- STAGING ONLY: use the durable soft-delete mutation for residual bookings.
-- The legacy cancel RPC rejects every non-active lifecycle, including collected
-- RFT vehicles, before it can preserve the booking history.
BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-external-completion-20260903136000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $repair$
DECLARE
  definition text;
  expected_hash constant text:='e2dc32f8ffbae85883f55fb496871948d0ee5f8f67bc94a6b7b2fbbdcb28d2b7';
  old_block constant text:='  IF EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text NOT IN(''completed'',''deleted'',''cancelled'')) AND NOT v.visible_on_board THEN
    UPDATE public.vehicles SET visible_on_board=true,version=version+1,updated_at=completed_at,updated_by=uid
    WHERE id=v.id AND version=v.version RETURNING * INTO v;
    IF NOT FOUND THEN RAISE EXCEPTION ''PDC_EXTERNAL_COMPLETION_TEMPORARY_ACTIVATION_DRIFT'' USING errcode=''40001''; END IF;
  END IF;
  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN(''completed'',''deleted'',''cancelled'') ORDER BY id FOR UPDATE LOOP
    booking_result:=public.cancel_workshop_booking(b.id,b.version,''External/non-Navision vehicle completed after recorded collection'',jsonb_build_object(''source'',''complete_external_rft_collection_20260903''));
    IF NOT coalesce((booking_result->>''ok'')::boolean,false) THEN RAISE EXCEPTION ''PDC_EXTERNAL_COMPLETION_BOOKING_CANCEL_FAILED:%'',coalesce(booking_result->>''error'',booking_result->>''code'',''unknown'') USING errcode=''40001''; END IF;
    cancelled:=cancelled+1;
  END LOOP;';
  new_block constant text:='  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN(''completed'',''deleted'',''cancelled'') ORDER BY id FOR UPDATE LOOP
    UPDATE public.workshop_bookings SET
      status=''deleted'',deleted_at=coalesce(deleted_at,completed_at),
      deleted_reason=''External/non-Navision vehicle completed after recorded collection'',
      version=version+1,updated_at=completed_at,updated_by=uid
    WHERE id=b.id AND version=b.version;
    IF NOT FOUND THEN RAISE EXCEPTION ''PDC_EXTERNAL_COMPLETION_BOOKING_SOFT_DELETE_DRIFT'' USING errcode=''40001''; END IF;
    cancelled:=cancelled+1;
  END LOOP;';
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903135000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903135000' AND name='external_completion_hidden_booking_cancel_20260903')<>1
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_SOFT_DELETE_HEAD_MISMATCH' USING errcode='55000'; END IF;
  definition:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
  IF encode(extensions.digest(convert_to(definition,'UTF8'),'sha256'),'hex')<>expected_hash
     OR (length(definition)-length(replace(definition,old_block,'')))/length(old_block)<>1
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_SOFT_DELETE_DEFINITION_MISMATCH' USING errcode='55000'; END IF;
  EXECUTE replace(definition,old_block,new_block);
END $repair$;

REVOKE ALL ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) TO authenticated;

DO $post$
DECLARE d text:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
BEGIN
  IF position('PDC_EXTERNAL_COMPLETION_BOOKING_SOFT_DELETE_DRIFT' in d)=0
     OR position('deleted_reason=''External/non-Navision vehicle completed after recorded collection''' in d)=0
     OR position('PDC_EXTERNAL_COMPLETION_TEMPORARY_ACTIVATION_DRIFT' in d)>0
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_SOFT_DELETE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903136000','external_completion_residual_booking_soft_delete_20260903',ARRAY[
  'Collected RFT vehicles retain non-active lifecycle while residual bookings are soft-deleted with versioned history',
  'No transient Board reactivation or lifecycle fiction is introduced',
  'Completion still fails atomically on booking version drift and retains all postconditions'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
