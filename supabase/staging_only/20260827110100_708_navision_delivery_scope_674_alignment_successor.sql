-- STAGING ONLY 708: align the effective 707 delivery gate with the
-- currently active canonical authenticated Monitor/import binding. The 707
-- objects, receipt chain, ACLs and all 700-706 lifecycle history remain
-- append-only; this successor only repairs the stale 673 scope reference.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-708-navision-delivery-scope-674-alignment',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827110000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827109000' AND name='675_authenticated_monitor_enqueue_trigger_compatibility')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827110000' AND name='676_authenticated_monitor_rollback_control_repair')<>1
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827109100' AND name='707_navision_delivery_monitor_identity_security_successor')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827110000')
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record_pre707(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_674(text)') IS NULL
  THEN
    RAISE EXCEPTION 'PDC_708_EXACT_707_STAGING_PRESTATE_REQUIRED' USING errcode='55000';
  END IF;
END $pre$;

DO $repair$
DECLARE
  v_delivery text;
  v_wrapper text;
  v_old text:='pdc_monitor_authenticated_active_scope_673';
  v_new text:='pdc_monitor_authenticated_active_scope_674';
BEGIN
  SELECT pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure) INTO v_delivery;
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure) INTO v_wrapper;
  IF length(v_delivery)-length(replace(v_delivery,v_old,''))<>length(v_old)
     OR length(v_wrapper)-length(replace(v_wrapper,v_old,''))<>length(v_old)
     OR position(v_new in v_delivery)>0
     OR position(v_new in v_wrapper)>0 THEN
    RAISE EXCEPTION 'PDC_708_STALE_SCOPE_ANCHOR_MISSING_OR_AMBIGUOUS' USING errcode='55000';
  END IF;
  EXECUTE replace(v_delivery,v_old,v_new);
  EXECUTE replace(v_wrapper,v_old,v_new);
END $repair$;

DO $post$
DECLARE
  v_delivery text;
  v_wrapper text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure) INTO v_delivery;
  SELECT pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure) INTO v_wrapper;
  IF position('pdc_monitor_authenticated_active_scope_674(NULL)' in v_delivery)=0
     OR position('pdc_monitor_authenticated_active_scope_673' in v_delivery)>0
     OR position('pdc_monitor_authenticated_active_scope_674(NULL)' in v_wrapper)=0
     OR position('pdc_monitor_authenticated_active_scope_673' in v_wrapper)>0
     OR NOT has_function_privilege('authenticated','public.reconcile_navision_delivery_700(uuid)','execute')
     OR has_function_privilege('anon','public.reconcile_navision_delivery_700(uuid)','execute')
     OR has_function_privilege('service_role','public.reconcile_navision_delivery_700(uuid)','execute')
     OR has_function_privilege('pdc_email_monitor','public.reconcile_navision_delivery_700(uuid)','execute')
     OR has_function_privilege('authenticated','public.reconcile_navision_delivery_700_pre707(uuid,uuid,text)','execute')
     OR NOT has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('service_role','public.reconcile_navision_operational_record(uuid,uuid,text)','execute')
     OR has_function_privilege('pdc_email_monitor','public.reconcile_navision_operational_record(uuid,uuid,text)','execute') THEN
    RAISE EXCEPTION 'PDC_708_SECURITY_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827110100','708_navision_delivery_scope_674_alignment_successor',ARRAY[
  'Require exact live 676 ledger head with 675 monitor binding and applied 707 successor; preserve 707 and 700-706 without rewrite or reapply',
  'Replace only the stale 673 scope reference in the effective one-argument delivery RPC and guarded operational wrapper with the active 674 canonical Monitor/import scope',
  'Preserve server-derived auth.uid()/auth.jwt() actor identity, exact Delivered - At Dealer matching, locks, idempotency, timer, audit/history, RLS and outbound interception',
  'Retain authenticated-only gated execution and deny anon, service_role, pdc_email_monitor database role and private predecessor execution; Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
