-- STAGING ONLY: successor for canonical cancellation of residual bookings on
-- a collected vehicle that is intentionally hidden from the active Board.
BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-external-completion-20260903135000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $repair$
DECLARE
  definition text;
  expected_hash constant text:='54b5463281b3b10a5a0fcde9ff56b359042f635540e8d5664d75bbde1688d553';
  marker constant text:='  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN(''completed'',''deleted'',''cancelled'') ORDER BY id FOR UPDATE LOOP';
  replacement constant text:='  IF EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text NOT IN(''completed'',''deleted'',''cancelled'')) AND NOT v.visible_on_board THEN
    UPDATE public.vehicles SET visible_on_board=true,version=version+1,updated_at=completed_at,updated_by=uid
    WHERE id=v.id AND version=v.version RETURNING * INTO v;
    IF NOT FOUND THEN RAISE EXCEPTION ''PDC_EXTERNAL_COMPLETION_TEMPORARY_ACTIVATION_DRIFT'' USING errcode=''40001''; END IF;
  END IF;
  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN(''completed'',''deleted'',''cancelled'') ORDER BY id FOR UPDATE LOOP';
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903134000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903134000' AND name='external_completion_review_repairs_20260903')<>1
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_BOOKING_REPAIR_HEAD_MISMATCH' USING errcode='55000'; END IF;
  definition:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
  IF encode(extensions.digest(convert_to(definition,'UTF8'),'sha256'),'hex')<>expected_hash
     OR (length(definition)-length(replace(definition,marker,'')))/length(marker)<>1
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_BOOKING_REPAIR_DEFINITION_MISMATCH' USING errcode='55000'; END IF;
  EXECUTE replace(definition,marker,replacement);
END $repair$;

REVOKE ALL ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) TO authenticated;

DO $post$
DECLARE d text:=pg_get_functiondef('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)'::regprocedure);
BEGIN
  IF position('PDC_EXTERNAL_COMPLETION_TEMPORARY_ACTIVATION_DRIFT' in d)=0
     OR position('SET visible_on_board=true,version=version+1' in d)=0
     OR NOT has_function_privilege('authenticated','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_function_privilege('anon','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_BOOKING_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903135000','external_completion_hidden_booking_cancel_20260903',ARRAY[
  'Temporarily reactivate a transaction-private collected vehicle only when residual bookings require canonical cancellation',
  'Preserve operator expected version while capturing cancellation deltas before the single completion increment',
  'Final committed vehicle remains hidden and completed; every booking retains canonical cancellation history'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
