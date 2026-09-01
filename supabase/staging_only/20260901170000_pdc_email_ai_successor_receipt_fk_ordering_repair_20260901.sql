-- STAGING ONLY 20260901170000: defer the successor action receipt FK
-- so the existing receipt-first transaction functions may insert their parent
-- transaction receipt after collecting action rows in the same transaction.
-- No receipt data, function body, ACL, RLS or business state is rewritten.
-- The migration records production_writes=false, mailbox_contacted=false and
-- outbound_email=false as part of its immutable release metadata.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901170000-successor-receipt-fk-ordering',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  fk_def text;
  old_deferrable boolean;
  old_deferred boolean;
BEGIN
  SELECT pg_get_constraintdef(oid), condeferrable, condeferred
    INTO fk_def, old_deferrable, old_deferred
  FROM pg_constraint
  WHERE conrelid='public.pdc_email_ai_successor_action_receipts'::regclass
    AND conname='pdc_email_ai_successor_action_receipts_transaction_id_fkey'
    AND contype='f';
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]+$')<>20260901160000
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901170000')
     OR fk_def IS NULL
     OR fk_def NOT ILIKE 'FOREIGN KEY (transaction_id) REFERENCES pdc_email_ai_successor_transaction_receipts(transaction_id)%'
     OR old_deferrable
     OR old_deferred
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts WHERE transaction_id='205f0c13-ef4b-4ac0-8128-3563a4d8d61a')<>1
  THEN RAISE EXCEPTION 'PDC_20260901170000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

ALTER TABLE public.pdc_email_ai_successor_action_receipts
  DROP CONSTRAINT pdc_email_ai_successor_action_receipts_transaction_id_fkey;
ALTER TABLE public.pdc_email_ai_successor_action_receipts
  ADD CONSTRAINT pdc_email_ai_successor_action_receipts_transaction_id_fkey
  FOREIGN KEY(transaction_id)
  REFERENCES public.pdc_email_ai_successor_transaction_receipts(transaction_id)
  ON DELETE RESTRICT
  DEFERRABLE INITIALLY DEFERRED;

DO $post$
DECLARE
  is_deferrable boolean;
  is_deferred boolean;
  fk_def text;
BEGIN
  SELECT condeferrable, condeferred, pg_get_constraintdef(oid)
    INTO is_deferrable, is_deferred, fk_def
  FROM pg_constraint
  WHERE conrelid='public.pdc_email_ai_successor_action_receipts'::regclass
    AND conname='pdc_email_ai_successor_action_receipts_transaction_id_fkey'
    AND contype='f';
  IF NOT is_deferrable OR NOT is_deferred
     OR fk_def NOT ILIKE 'FOREIGN KEY (transaction_id) REFERENCES pdc_email_ai_successor_transaction_receipts(transaction_id)%'
     OR (SELECT count(*) FROM public.pdc_email_ai_successor_transaction_receipts WHERE transaction_id='205f0c13-ef4b-4ac0-8128-3563a4d8d61a')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901170000_FK_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901170000','pdc_email_ai_successor_receipt_fk_ordering_repair_20260901',ARRAY[
  'Replace only the immediate transaction_id foreign key with the same ON DELETE RESTRICT relationship as DEFERRABLE INITIALLY DEFERRED',
  'Permit the existing strict v2 executor and non-dispatch receipt paths to insert action rows before their parent transaction row within one transaction',
  'Preserve receipt 205f0c13-ef4b-4ac0-8128-3563a4d8d61a, failed-attempt evidence, function bodies, ACL, FORCE RLS, outbound-disabled and Production isolation boundaries'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
