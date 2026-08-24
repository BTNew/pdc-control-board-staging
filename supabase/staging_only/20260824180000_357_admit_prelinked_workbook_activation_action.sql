-- Staging-only successor: admit the exact prelinked workbook activation action
-- into the existing immutable Manager approval and pair receipt contracts.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-357-prelinked-action-contract',0));
DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824170000' AND name='356_activate_prelinked_workbook_vehicle_navision')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824170000' AND version~'^[0-9]{14}$') THEN
  RAISE EXCEPTION 'PDC_357_STAGING_TARGET_OR_HEAD_MISMATCH';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_verified_backup_manifests WHERE backup_manifest_sha256='0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0') THEN
  RAISE EXCEPTION 'PDC_357_VERIFIED_BACKUP_MISSING';
 END IF;
END $guard$;

ALTER TABLE public.pdc_pmb_canonical_manager_approvals
 DROP CONSTRAINT pdc_pmb_canonical_manager_approvals_action_check,
 DROP CONSTRAINT pdc_pmb_canonical_manager_approvals_check,
 ADD CONSTRAINT pdc_pmb_canonical_manager_approvals_action_check CHECK(action IN('create_canonical_vehicle','reactivate_complete_board_purge','activate_exact_prelinked_workbook_vehicle')),
 ADD CONSTRAINT pdc_pmb_canonical_manager_approvals_check CHECK(
  (action='create_canonical_vehicle' AND target_vehicle_id IS NULL AND target_vehicle_version IS NULL)
  OR (action IN('reactivate_complete_board_purge','activate_exact_prelinked_workbook_vehicle') AND target_vehicle_id IS NOT NULL AND target_vehicle_version IS NOT NULL)
 );
ALTER TABLE public.pdc_pmb_canonical_pair_receipts
 DROP CONSTRAINT pdc_pmb_canonical_pair_receipts_action_check,
 ADD CONSTRAINT pdc_pmb_canonical_pair_receipts_action_check CHECK(action IN('create_canonical_vehicle','reactivate_complete_board_purge','activate_exact_prelinked_workbook_vehicle'));

DO $post$
DECLARE a text;b text;c text;
BEGIN
 SELECT pg_get_constraintdef(oid,true) INTO a FROM pg_constraint WHERE conrelid='public.pdc_pmb_canonical_manager_approvals'::regclass AND conname='pdc_pmb_canonical_manager_approvals_action_check';
 SELECT pg_get_constraintdef(oid,true) INTO b FROM pg_constraint WHERE conrelid='public.pdc_pmb_canonical_manager_approvals'::regclass AND conname='pdc_pmb_canonical_manager_approvals_check';
 SELECT pg_get_constraintdef(oid,true) INTO c FROM pg_constraint WHERE conrelid='public.pdc_pmb_canonical_pair_receipts'::regclass AND conname='pdc_pmb_canonical_pair_receipts_action_check';
 IF position('activate_exact_prelinked_workbook_vehicle' IN a)=0 OR position('activate_exact_prelinked_workbook_vehicle' IN b)=0
   OR position('activate_exact_prelinked_workbook_vehicle' IN c)=0 THEN RAISE EXCEPTION 'PDC_357_ACTION_CONTRACT_POSTCONDITION_FAILED'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260824180000','357_admit_prelinked_workbook_activation_action',array[
 'Require exact staging sentinel, verified backup and migration 356 head',
 'Extend only the immutable canonical Manager approval and pair receipt action checks for exact prelinked workbook activation',
 'Keep target vehicle/version mandatory and preserve Manager, independent Administrator and canonical Apply controls',
 'Grant no generic DML, Monitor, mailbox, writer or Production authority'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
