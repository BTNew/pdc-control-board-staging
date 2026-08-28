-- STAGING ONLY 748: repair the 747 recovered-identity guard so an
-- intentional QC recovery update checks the raw canonical stock value rather
-- than the generated column before PostgreSQL recomputes it.
BEGIN;
SET LOCAL lock_timeout='30s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-747-recover-stock-13000769',0));
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829140000' AND name='747_restore_stock_13000769_qc_retest')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260829140000')
  THEN RAISE EXCEPTION 'PDC_748_STAGING_OR_PREDECESSOR_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.pdc_protect_recovered_stock_13000769_747()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF OLD.id='d777b071-a2b0-5367-893b-aa83a07fcfce'::uuid THEN RAISE EXCEPTION 'PDC_747_RECOVERED_STOCK_DELETE_BLOCKED' USING errcode='55000'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.id='d777b071-a2b0-5367-893b-aa83a07fcfce'::uuid
     AND (NEW.deleted_at IS NOT NULL OR NEW.lifecycle_state::text='deleted' OR NEW.stock_number IS DISTINCT FROM '13000769') THEN
    RAISE EXCEPTION 'PDC_747_RECOVERED_STOCK_ARCHIVE_BLOCKED' USING errcode='55000';
  END IF;
  RETURN NEW;
END $$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260829141000','748_repair_recovery_identity_guard',ARRAY['Repair the recovered Stock 13000769 guard to check raw stock_number during BEFORE UPDATE because stock_number_normalized is generated after the trigger','Staging sentinel and Production exclusion retained']);
NOTIFY pgrst,'reload schema';
COMMIT;
