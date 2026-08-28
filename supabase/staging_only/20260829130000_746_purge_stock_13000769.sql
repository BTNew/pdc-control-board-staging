-- STAGING ONLY 746: complete operational purge of exact Stock 13000769.
-- Append-only successor of the controlled hard-purge pattern. All identity,
-- head, target, backup, containment and postcondition guards are fail-closed.
BEGIN;
SET LOCAL statement_timeout='15min';
SET LOCAL lock_timeout='30s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-746-purge-stock-13000769',0));

DO $guard$
DECLARE v_head text; v_name text; v_target_id uuid; v_backend_id uuid;
BEGIN
  IF current_user <> 'postgres' OR session_user <> 'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829120000' AND name='745_controller_parts_received_eta_repair')
     OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260829120000')
     OR (SELECT count(*) FROM public.vehicles WHERE stock_number_normalized='13000769')<>1
     OR (SELECT count(*) FROM public.navision_backend_records WHERE id='de800087-d086-4f7b-9569-bb8a88660475' AND canonical_vehicle_id='d777b071-a2b0-5367-893b-aa83a07fcfce' AND is_current)<>1
     OR (SELECT count(*) FROM public.vehicles WHERE id='d777b071-a2b0-5367-893b-aa83a07fcfce' AND stock_number_normalized='13000769' AND source_record_id_normalized='DE800087-D086-4F7B-9569-BB8A88660475' AND permanent_vehicle_id='PDC-AI-EA6245015374E22419FEF6A3' AND job_card_number='J139125493')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
  THEN RAISE EXCEPTION 'PDC_746_TARGET_HEAD_SCOPE_OR_RECREATION_GUARD_FAILED' USING errcode='55000'; END IF;
END
$guard$;

DO $backup$
BEGIN
  IF (SELECT count(*) FROM public.backup_runs WHERE id='847b7b9a-7f25-4a13-868d-fb3a95b9e447'::uuid AND environment='staging' AND status='success' AND file_sha256='949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7' AND encrypted)<>1
     THEN RAISE EXCEPTION 'PDC_746_VERIFIED_BACKUP_BINDING_FAILED' USING errcode='55000'; END IF;
END
$backup$;

-- Close every staging board-recreation path through the database-owned
-- containment surfaces before deleting the target. This is a tightening
-- change and is intentionally limited to staging runtime controls.
UPDATE public.monitored_mailboxes SET active=false,updated_at=clock_timestamp()
WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57';
UPDATE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 SET enabled=false,changed_at=clock_timestamp() WHERE singleton;
UPDATE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 SET enabled=false,changed_at=clock_timestamp() WHERE singleton;
UPDATE public.pdc_monitor_stage_activation_writers SET active=false,revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE active AND revoked_at IS NULL;

-- Advance the authenticated claim floor past the deleted Inbox UID. This is
-- a tightening replay control, not an RLS bypass, and prevents the old source
-- message from being claimed again if the mailbox is later reactivated.
UPDATE public.pdc_email_monitor_pilot SET minimum_uid=640,updated_at=clock_timestamp()
WHERE singleton AND minimum_uid=639 AND NOT enabled AND NOT automatic_rule_application
  AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled;

CREATE TABLE public.pdc_email_replay_fences_746(
  fence_key text PRIMARY KEY CHECK (fence_key='uidvalidity-1-uid-639-stock-13000769'),
  folder text NOT NULL CHECK (folder='Inbox'), uidvalidity bigint NOT NULL CHECK (uidvalidity=1),
  provider_uid bigint NOT NULL CHECK (provider_uid=639),
  source_hash text NOT NULL CHECK (source_hash='ea6245015374e22419fef6a38019cac94b24c995de29c9bde2faf72bc746c284'),
  stock_number text NOT NULL CHECK (stock_number='13000769'),
  job_card_number text NOT NULL CHECK (job_card_number='J139125493'),
  reason text NOT NULL CHECK (reason='Craig requested complete staging removal; old source remains permanently denied from replay'),
  created_by uuid NOT NULL CHECK (created_by='8a83b715-8d79-4b0e-95b2-02b55da6e8d7'),
  created_by_email text NOT NULL CHECK (created_by_email='craig.watson@broometoyota.com.au'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_replay_fences_746 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_replay_fences_746 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_replay_fences_746 FROM public,anon,authenticated,service_role;
INSERT INTO public.pdc_email_replay_fences_746(fence_key,folder,uidvalidity,provider_uid,source_hash,stock_number,job_card_number,reason,created_by,created_by_email)
VALUES('uidvalidity-1-uid-639-stock-13000769','Inbox',1,639,'ea6245015374e22419fef6a38019cac94b24c995de29c9bde2faf72bc746c284','13000769','J139125493','Craig requested complete staging removal; old source remains permanently denied from replay','8a83b715-8d79-4b0e-95b2-02b55da6e8d7','craig.watson@broometoyota.com.au');

CREATE TEMP TABLE pdc746_tokens(token text PRIMARY KEY) ON COMMIT DROP;
INSERT INTO pdc746_tokens(token) VALUES
 ('d777b071-a2b0-5367-893b-aa83a07fcfce'),('de800087-d086-4f7b-9569-bb8a88660475'),('13000769'),('J139125493'),
 ('DE800087-D086-4F7B-9569-BB8A88660475'),('PDC-AI-EA6245015374E22419FEF6A3'),
 ('ea6245015374e22419fef6a38019cac94b24c995de29c9bde2faf72bc746c284'),('1:639');
CREATE TEMP TABLE pdc746_impacted(table_name text PRIMARY KEY,matched_count bigint NOT NULL,deleted_count bigint NOT NULL DEFAULT 0) ON COMMIT DROP;
CREATE TEMP TABLE pdc746_delete_order(seq integer PRIMARY KEY,table_name text UNIQUE NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE pdc746_remaining(table_name text PRIMARY KEY) ON COMMIT DROP;
DO $discover$
DECLARE r record; n bigint; protected boolean;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name LOOP
    protected := r.table_name IN ('backup_runs','restore_test_runs','pdc_staging_verified_backup_manifests','pdc_staging_backup_restoration_receipts','pdc_staging_board_purge_receipts','pdc_staging_environment_sentinel')
      OR r.table_name LIKE 'pdc_email_replay_fences_%' OR r.table_name LIKE 'pdc_stock_purge_receipts_%';
    IF NOT protected THEN
      EXECUTE format('SELECT count(*) FROM public.%I x WHERE EXISTS (SELECT 1 FROM pdc746_tokens k WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(k.token))))',r.table_name) INTO n;
      IF n>0 THEN INSERT INTO pdc746_impacted(table_name,matched_count) VALUES(r.table_name,n); END IF;
    END IF;
  END LOOP;
END
$discover$;

-- The live schema has a legitimate two-way vehicle/booking FK. The target
-- vehicle currently has no active booking, but clear the nullable reverse
-- pointer explicitly so the normal FK-safe child-before-parent order remains
-- valid without disabling system constraint triggers.
UPDATE public.vehicles SET active_workshop_booking_id=NULL
WHERE id='d777b071-a2b0-5367-893b-aa83a07fcfce' AND stock_number_normalized='13000769';

INSERT INTO pdc746_remaining(table_name) SELECT table_name FROM pdc746_impacted;
DO $order$
DECLARE r record; v_seq integer:=0; v_progress boolean;
BEGIN
  WHILE EXISTS (SELECT 1 FROM pdc746_remaining) LOOP
    v_progress:=false;
    SELECT rem.table_name INTO r FROM pdc746_remaining rem
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_constraint fk
      JOIN pg_class child ON child.oid=fk.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
      JOIN pg_class parent ON parent.oid=fk.confrelid JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
      JOIN pdc746_remaining child_remaining ON child_remaining.table_name=child.relname
      WHERE fk.contype='f' AND child_ns.nspname='public' AND parent_ns.nspname='public'
        AND parent.relname=rem.table_name AND child.relname<>rem.table_name
        AND NOT (child.relname='vehicles' AND parent.relname='workshop_bookings')
    ) ORDER BY rem.table_name LIMIT 1;
    IF FOUND THEN
      v_seq:=v_seq+1; INSERT INTO pdc746_delete_order VALUES(v_seq,r.table_name); DELETE FROM pdc746_remaining WHERE table_name=r.table_name; v_progress:=true;
    END IF;
    IF NOT v_progress THEN
      RAISE EXCEPTION 'PDC_746_NONDEFERRABLE_PURGE_ORDER_FAILED' USING errcode='55000';
    END IF;
  END LOOP;
END
$order$;

-- Preserve the backup provenance row while removing target text from its
-- operator label; the encrypted artifact and manifest remain outside the DB.
UPDATE public.backup_runs SET triggered_by='owner-prepurge', error_message=NULL
WHERE environment='staging' AND position('13000769' in to_jsonb(backup_runs)::text)>0;

DO $disable$
DECLARE r record;
BEGIN
  FOR r IN SELECT table_name FROM pdc746_impacted ORDER BY table_name LOOP
    EXECUTE format('ALTER TABLE public.%I DISABLE TRIGGER USER',r.table_name);
  END LOOP;
END
$disable$;

DO $delete$
DECLARE r record; n bigint;
BEGIN
  FOR r IN SELECT i.table_name,i.matched_count FROM pdc746_impacted i JOIN pdc746_delete_order o USING(table_name) ORDER BY o.seq LOOP
    EXECUTE format('DELETE FROM public.%I x WHERE EXISTS (SELECT 1 FROM pdc746_tokens k WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(k.token))))',r.table_name);
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n<>r.matched_count THEN RAISE EXCEPTION 'PDC_746_DELETE_COUNT_MISMATCH:% expected % got %',r.table_name,r.matched_count,n USING errcode='55000'; END IF;
    UPDATE pdc746_impacted SET deleted_count=n WHERE table_name=r.table_name;
  END LOOP;
END
$delete$;

DO $enable$
DECLARE r record;
BEGIN
  FOR r IN SELECT table_name FROM pdc746_impacted ORDER BY table_name LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE TRIGGER USER',r.table_name);
  END LOOP;
END
$enable$;

DO $post$
DECLARE r record; n bigint; total bigint; remaining bigint:=0;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name LOOP
    IF r.table_name NOT IN ('backup_runs','restore_test_runs','pdc_staging_verified_backup_manifests','pdc_staging_backup_restoration_receipts','pdc_staging_board_purge_receipts','pdc_staging_environment_sentinel','pdc_email_replay_fences_746','pdc_stock_purge_receipts_746')
       AND r.table_name NOT LIKE 'pdc_email_replay_fences_%' AND r.table_name NOT LIKE 'pdc_stock_purge_receipts_%' THEN
      EXECUTE format('SELECT count(*) FROM public.%I x WHERE EXISTS (SELECT 1 FROM pdc746_tokens k WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(k.token))))',r.table_name) INTO n;
      remaining:=remaining+n;
    END IF;
  END LOOP;
  SELECT coalesce(sum(deleted_count),0) INTO total FROM pdc746_impacted;
  IF remaining<>0 OR total=0 OR (SELECT count(*) FROM public.vehicles WHERE id='d777b071-a2b0-5367-893b-aa83a07fcfce' OR stock_number_normalized='13000769')<>0
     OR (SELECT count(*) FROM public.navision_backend_records WHERE id='de800087-d086-4f7b-9569-bb8a88660475')<>0
     OR (SELECT count(*) FROM public.pdc_email_replay_fences_746 WHERE fence_key='uidvalidity-1-uid-639-stock-13000769')<>1
  THEN RAISE EXCEPTION 'PDC_746_IDENTITY_REPLAY_OR_COUNT_POSTCONDITION_FAILED remaining=% total=%',remaining,total USING errcode='55000'; END IF;
END
$post$;

CREATE TABLE public.pdc_stock_purge_receipts_746(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), action_key text NOT NULL UNIQUE CHECK(action_key='complete-operational-purge-stock-13000769'),
 stock_number text NOT NULL CHECK(stock_number='13000769'), vehicle_id uuid NOT NULL CHECK(vehicle_id='d777b071-a2b0-5367-893b-aa83a07fcfce'),
 backend_record_id uuid NOT NULL CHECK(backend_record_id='de800087-d086-4f7b-9569-bb8a88660475'), backup_run_id uuid NOT NULL CHECK(backup_run_id='847b7b9a-7f25-4a13-868d-fb3a95b9e447'::uuid),
 backup_manifest_sha256 text NOT NULL CHECK(backup_manifest_sha256='7326179925f024eb3f295bdc504aa84b15f416c6e37cf71b777f7946958a817d'), encrypted_backup_sha256 text NOT NULL CHECK(encrypted_backup_sha256='949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7'),
 deleted_table_count integer NOT NULL, deleted_row_count bigint NOT NULL, deleted_counts jsonb NOT NULL,
 replay_fence_table text NOT NULL CHECK(replay_fence_table='pdc_email_replay_fences_746'), production_untouched boolean NOT NULL CHECK(production_untouched),
 created_by uuid NOT NULL CHECK(created_by='8a83b715-8d79-4b0e-95b2-02b55da6e8d7'), created_by_email text NOT NULL CHECK(created_by_email='craig.watson@broometoyota.com.au'), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_stock_purge_receipts_746 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_stock_purge_receipts_746 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_stock_purge_receipts_746 FROM public,anon,authenticated,service_role;
INSERT INTO public.pdc_stock_purge_receipts_746(action_key,stock_number,vehicle_id,backend_record_id,backup_run_id,backup_manifest_sha256,encrypted_backup_sha256,deleted_table_count,deleted_row_count,deleted_counts,replay_fence_table,production_untouched,created_by,created_by_email)
SELECT 'complete-operational-purge-stock-13000769','13000769','d777b071-a2b0-5367-893b-aa83a07fcfce','de800087-d086-4f7b-9569-bb8a88660475','847b7b9a-7f25-4a13-868d-fb3a95b9e447'::uuid,'7326179925f024eb3f295bdc504aa84b15f416c6e37cf71b777f7946958a817d','949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7',count(*),coalesce(sum(deleted_count),0),coalesce(jsonb_object_agg(table_name,deleted_count ORDER BY table_name),'{}'::jsonb),'pdc_email_replay_fences_746',true,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7','craig.watson@broometoyota.com.au' FROM pdc746_impacted;

UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260829130000','746_purge_stock_13000769',ARRAY['Bind exact live Stock 13000769 vehicle and canonical Navision backend identity to current staging head 745','Require fresh successful encrypted target-closure backup run and artifact hashes before mutation','Fence Inbox UIDVALIDITY 1 UID 639/source hash from replay','Delete every exact target identity-bearing operational/history row across all current public tables while preserving only backup provenance, replay fence and purge receipt','Verify target, backend, operational references and recreation surfaces are absent; Production remains untouched']);
NOTIFY pgrst,'reload schema';
COMMIT;
