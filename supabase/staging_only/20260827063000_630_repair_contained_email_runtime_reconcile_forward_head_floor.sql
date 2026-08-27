-- STAGING ONLY 630: remove the exact-head self-loop from the repaired
-- reconciliation function while retaining an exact installed-lineage floor.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-630-contained-email-runtime-reconcile-forward-head-floor',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827061000' AND name='610_repair_contained_email_runtime_reconcile_replay_head')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827063000')<>0
     OR to_regprocedure('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_630_RECONCILE_FORWARD_HEAD_FLOOR_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

DO $repair$
DECLARE
  v_definition text;
  v_repaired text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)'::regprocedure)
    INTO v_definition;
  IF position('PDC_600_EXACT_LEDGER_HEAD_REQUIRED' IN v_definition)=0
     OR position('20260827060000' IN v_definition)=0
  THEN RAISE EXCEPTION 'PDC_630_RECONCILE_FORWARD_SOURCE_DRIFT' USING errcode='55000'; END IF;
  v_repaired:=replace(v_definition,'20260827060000','20260827061000');
  v_repaired:=replace(v_repaired,
    $old$max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827061000'$old$,
    $new$max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<'20260827061000'$new$);
  EXECUTE v_repaired;
END
$repair$;

REVOKE ALL ON FUNCTION public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text) TO authenticated;

DO $post$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)'::regprocedure)
    INTO v_definition;
  IF position('20260827061000' IN v_definition)=0
     OR position('20260827060000' IN v_definition)<>0
     OR position($floor$max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<'20260827061000'$floor$ IN v_definition)=0
     OR NOT has_function_privilege('authenticated','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('anon','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
     OR has_function_privilege('service_role','public.reconcile_pdc_monitor_contained_binding_504(uuid,text,text,text,text,text,text)','EXECUTE')
  THEN RAISE EXCEPTION 'PDC_630_RECONCILE_FORWARD_HEAD_FLOOR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827063000','630_repair_contained_email_runtime_reconcile_forward_head_floor',ARRAY[
  'Replace the 600 exact-head equality with an installed 610 lineage floor so the authenticated replay remains valid after forward successor application',
  'Preserve the exact .44 canonical binding, 580 projection proof, immutable reconciliation history and idempotent receipt',
  'Preserve authenticated-only execution and fail-closed contained runtime state',
  'Production, mailbox, monitor, planner, scheduler, email and vehicle writes remain untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
