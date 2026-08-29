-- STAGING ONLY 902: repair the exact Sublet ledger read dealer-binding cast.
-- No data or ACL mutation is performed; only the read RPC expression is
-- corrected from uuid=text to text=text.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-sublet-auditor-read-902',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$')<>'20260830091000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260830091000'
           AND name='sublet_auditor_read_ledger_volatility_repair')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260830092000')
     OR to_regprocedure('public.get_pdc_sublet_audit_ledgers(uuid,text,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_902_EXACT_STAGING_DEPENDENCY_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

DO $patch$
DECLARE
  v_definition text;
  v_patched text;
  v_anchor text:='r.id=v_vehicle.source_record_id';
BEGIN
  SELECT pg_get_functiondef('public.get_pdc_sublet_audit_ledgers(uuid,text,text)'::regprocedure)
    INTO v_definition;
  IF (length(v_definition)-length(replace(v_definition,v_anchor,'')))/length(v_anchor)<>1
     OR position('r.id::text=v_vehicle.source_record_id' in v_definition)>0
  THEN RAISE EXCEPTION 'PDC_902_READ_RPC_PATCH_ANCHOR_DRIFT' USING errcode='55000'; END IF;
  v_patched:=replace(v_definition,v_anchor,'r.id::text=v_vehicle.source_record_id');
  EXECUTE v_patched;
  SELECT pg_get_functiondef('public.get_pdc_sublet_audit_ledgers(uuid,text,text)'::regprocedure)
    INTO v_definition;
  IF position('r.id::text=v_vehicle.source_record_id' in v_definition)=0
     OR position(v_anchor in v_definition)>0
  THEN RAISE EXCEPTION 'PDC_902_READ_RPC_PATCH_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $patch$;

REVOKE ALL ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text)
  FROM public,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text)
  TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260830092000','sublet_auditor_read_ledger_uuid_text_cast_repair',ARRAY[
    'Exact staging successor after 20260830091000/sublet_auditor_read_ledger_volatility_repair',
    'Patch only the exact dealer-binding UUID/text comparison in the Sublet ledger read RPC',
    'Direct SELECT on immutable Sublet ledgers remains denied',
    'Projection-only closure; no repair RPC and no stored work-item mutation'
  ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
