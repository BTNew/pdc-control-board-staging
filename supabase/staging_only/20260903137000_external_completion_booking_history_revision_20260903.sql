-- STAGING ONLY: canonical residual-booking history/revision successor and
-- explicit validation of the already-applied 132000 milestone repair.
BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-external-completion-20260903137000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $repair$
DECLARE
  definition text;
  milestone_definition text;
  expected_hash constant text:='c9fe7c0e9a0e9e6ec07bc8e9024716d00c2950f5844396de699517115b4a8864';
  old_block constant text:='  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN(''completed'',''deleted'',''cancelled'') ORDER BY id FOR UPDATE LOOP
    UPDATE public.workshop_bookings SET
      status=''deleted'',deleted_at=coalesce(deleted_at,completed_at),
      deleted_reason=''External/non-Navision vehicle completed after recorded collection'',
      version=version+1,updated_at=completed_at,updated_by=uid
    WHERE id=b.id AND version=b.version;
    IF NOT FOUND THEN RAISE EXCEPTION ''PDC_EXTERNAL_COMPLETION_BOOKING_SOFT_DELETE_DRIFT'' USING errcode=''40001''; END IF;
    cancelled:=cancelled+1;
  END LOOP;';
  new_block constant text:='  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN(''completed'',''deleted'',''cancelled'') ORDER BY id FOR UPDATE LOOP
    booking_result:=public.workshop_delete_booking(b.id,b.version,''External/non-Navision vehicle completed after recorded collection'',jsonb_build_object(''source'',''complete_external_rft_collection_20260903'',''physical_delivery_asserted'',false));
    IF NOT coalesce((booking_result->>''ok'')::boolean,false) THEN
      RAISE EXCEPTION ''PDC_EXTERNAL_COMPLETION_BOOKING_DELETE_FAILED:%'',coalesce(booking_result->>''error'',''unknown'') USING errcode=''40001'';
    END IF;
    cancelled:=cancelled+1;
  END LOOP;
  IF cancelled>0 THEN PERFORM public.workshop_bump_revision(); END IF;';
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903136000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903132000' AND name='external_completion_delivery_milestone_scope_20260903')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903136000' AND name='external_completion_residual_booking_soft_delete_20260903')<>1
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_HISTORY_REPAIR_HEAD_MISMATCH' USING errcode='55000'; END IF;

  -- 132000 is immutable after deployment. Validate its exact ledger identity and
  -- prove its broad marker-only exception has been superseded by receipt auth.
  milestone_definition:=pg_get_functiondef('public.pdc_vehicle_first_milestones()'::regprocedure);
  IF position('pdc_external_completion_authorizations_20260903' in milestone_definition)=0
     OR position('v_external_collected_completion' in milestone_definition)>0
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_132000_NOT_SUPERSEDED' USING errcode='55000'; END IF;

  definition:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
  IF encode(extensions.digest(convert_to(definition,'UTF8'),'sha256'),'hex')<>expected_hash
     OR (length(definition)-length(replace(definition,old_block,'')))/length(old_block)<>1
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_HISTORY_REPAIR_DEFINITION_MISMATCH' USING errcode='55000'; END IF;
  EXECUTE replace(definition,old_block,new_block);
END $repair$;

REVOKE ALL ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) TO authenticated;

DO $post$
DECLARE d text:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
BEGIN
  IF position('public.workshop_delete_booking' in d)=0
     OR position('public.workshop_bump_revision' in d)=0
     OR position('PDC_EXTERNAL_COMPLETION_BOOKING_DELETE_FAILED' in d)=0
     OR position('UPDATE public.workshop_bookings SET' in d)>0
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_HISTORY_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903137000','external_completion_booking_history_revision_20260903',ARRAY[
  'Residual bookings use workshop_delete_booking so before/after snapshots, assignments and workshop_booking_history remain canonical',
  'Workshop revision is bumped once after the completion batch',
  'Applied 132000 identity is validated and its marker-only trigger scope is proven superseded by receipt-backed authorization'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
