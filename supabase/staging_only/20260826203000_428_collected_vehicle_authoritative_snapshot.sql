-- STAGING ONLY 428: retain receipt-backed collected vehicles in the authoritative snapshot.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-428-collected-snapshot',0));
DO $repair$ DECLARE d text; h text; repaired text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826202000' AND name='427_hidden_parts_stoppage_acceptance')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826202000') THEN RAISE EXCEPTION 'PDC_428_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure),encode(extensions.digest(convert_to(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,h;
 IF h<>'8e214bde7a1fc8706452526d34abadada708696386bed0c3cb4602466c62ec19' THEN RAISE EXCEPTION 'PDC_428_EXACT_FUNCTION_MISMATCH' USING errcode='55000'; END IF;
 repaired:=replace(d,'v.lifecycle_state IN(''active'',''rft'') AND v.visible_on_board','((v.lifecycle_state IN(''active'',''rft'') AND v.visible_on_board) OR (v.lifecycle_state=''completed'' AND v.rft_collected_at IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_action_receipts_412 handover WHERE handover.vehicle_id=v.id AND handover.action=''collected'')))');
 IF repaired=d OR position('v.lifecycle_state=''completed'' AND v.rft_collected_at IS NOT NULL' in repaired)=0 OR position('handover.action=''collected''' in repaired)=0 THEN RAISE EXCEPTION 'PDC_428_REPAIR_NOT_EXACT' USING errcode='55000'; END IF;
 EXECUTE repaired;
END $repair$;
DO $post$ DECLARE d text; BEGIN SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure) INTO d;
 IF position('v.lifecycle_state=''completed'' AND v.rft_collected_at IS NOT NULL' in d)=0 OR position('handover.action=''collected''' in d)=0 THEN RAISE EXCEPTION 'PDC_428_POSTCONDITION' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826203000','428_collected_vehicle_authoritative_snapshot',ARRAY[
 'Exact-SHA shared snapshot retains hidden completed vehicles only when collection has a non-null timestamp and an immutable 412 collected receipt',
 'Collected vehicles remain absent from active/RFT/bay views but survive authoritative reconciliation for Completed Vehicles history'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
