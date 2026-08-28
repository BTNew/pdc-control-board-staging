-- STAGING ONLY: exact, reversible Phase 1 reset for Stocks 13080534 and
-- 13017855. This migration is intentionally fail-closed and leaves the mailbox
-- and storage objects untouched for a one-time canonical importer replay.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='15min';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-exact-stock-reset-13080534-13017855-phase1',0));
LOCK TABLE supabase_migrations.schema_migrations IN ROW EXCLUSIVE MODE;

DO $guard$
DECLARE newest uuid[];
BEGIN
  IF current_user <> 'postgres' OR session_user <> 'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829151000' AND name='752_reactivate_exact_email_monitor_after_751')
     OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260829151000')
     OR to_regclass('public.pdc_exact_stock_reset_receipts_20260828') IS NOT NULL
     OR to_regclass('public.pdc_exact_email_reimport_authorizations_20260828') IS NOT NULL
     OR (SELECT count(*) FROM public.navision_backend_records WHERE id='5721cafa-2b60-4d45-b69c-ab907eaf178e' AND source_record_id_normalized='NAVISION-13080534' AND normalized_data->>'batch'='13080534' AND is_current AND record_status='current')<>1
     OR (SELECT count(*) FROM public.navision_backend_records WHERE id='e39eb741-cf03-44f2-8a75-54362ecc8a26' AND source_record_id_normalized='NAVISION-13017855' AND normalized_data->>'batch'='13017855' AND canonical_vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33' AND is_current AND record_status='current')<>1
     OR (SELECT count(*) FROM public.vehicles WHERE stock_number_normalized='13080534')<>0
     OR (SELECT count(*) FROM public.vehicles WHERE id='7fe33693-f519-5152-bbe0-9cc799c4ae33' AND stock_number_normalized='13017855' AND vin_normalized='MR0MABAV902402464' AND job_card_number='J139125422' AND lifecycle_state='active' AND visible_on_board)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE id='6836f01c-080f-4289-90a4-df8667a49ac9' AND subject='13080534' AND lower(sender_email)='craig.watson@broometoyota.com.au' AND provider_uid='imap_uid:681' AND source_hash='f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916' AND internet_message_id=E'\r\n <ME3P282MB1762651B0CB12077BBE64EA9CFAC2@ME3P282MB1762.AUSP282.PROD.OUTLOOK.COM>')<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE id='d89a3bbd-590b-493b-84a8-ce557bbfe512' AND subject='13017855' AND lower(sender_email)='craig.watson@broometoyota.com.au' AND provider_uid='imap_uid:680' AND source_hash='d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493' AND internet_message_id=E'\r\n <ME3P282MB17624D09C1024DA27B4AB754CFAC2@ME3P282MB1762.AUSP282.PROD.OUTLOOK.COM>')<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE lower(sender_email)='craig.watson@broometoyota.com.au' AND id IN ('6836f01c-080f-4289-90a4-df8667a49ac9','d89a3bbd-590b-493b-84a8-ce557bbfe512'))<>2
     OR (SELECT array_agg(id ORDER BY received_at DESC NULLS LAST,id DESC) FROM (SELECT id,received_at FROM public.ai_email_intake WHERE lower(sender_email)='craig.watson@broometoyota.com.au' ORDER BY received_at DESC NULLS LAST,id DESC LIMIT 2) q) <> ARRAY['6836f01c-080f-4289-90a4-df8667a49ac9'::uuid,'d89a3bbd-590b-493b-84a8-ce557bbfe512'::uuid]
     OR (SELECT count(*) FROM public.ai_email_attachments WHERE intake_id IN ('6836f01c-080f-4289-90a4-df8667a49ac9','d89a3bbd-590b-493b-84a8-ce557bbfe512'))<>6
     OR (SELECT count(*) FROM public.pdc_authenticated_email_import_receipts WHERE vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33' AND stock_number='13017855' AND source_hash='812c2291fe80a143e8fe8a55e34f9869476926d69d6bbddd345b61a6a5448a8a' AND source_uid='1:640')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
  THEN RAISE EXCEPTION 'PDC_EXACT_RESET_20260828_PREFLIGHT_BINDING_FAILED' USING errcode='55000';
  END IF;
END
$guard$;

DO $backup$
BEGIN
  IF (SELECT count(*) FROM public.backup_runs WHERE id='7f1c3315-ac42-46fb-99ed-70b43ef89f80'::uuid AND environment='staging' AND status='success' AND encrypted AND file_sha256='6887bad60ba612c83584cb628829b70dcb0f2e6c8a08de64e46b2c7de3a77518')<>1
  THEN RAISE EXCEPTION 'PDC_EXACT_RESET_20260828_SNAPSHOT_BINDING_FAILED' USING errcode='55000'; END IF;
END
$backup$;

CREATE TEMP TABLE pdc_exact_reset_tokens(token text PRIMARY KEY) ON COMMIT DROP;
INSERT INTO pdc_exact_reset_tokens(token) VALUES
 ('13080534'),('13017855'),('5721cafa-2b60-4d45-b69c-ab907eaf178e'),
 ('e39eb741-cf03-44f2-8a75-54362ecc8a26'),('7fe33693-f519-5152-bbe0-9cc799c4ae33'),
 ('J139125422'),('MR0MABAV902402464'),('1:680'),('1:640'),('imap_uid:680'),('imap_uid:681'),
 ('f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916'),
 ('d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493'),
 ('812c2291fe80a143e8fe8a55e34f9869476926d69d6bbddd345b61a6a5448a8a'),
 ('0f190df5-09df-4df6-a111-66f658318d57'),('3415271f-e6df-4d1e-a763-3341f9b066f4'),('91eadf28-e8d6-482a-9dd9-b3b6b7862489'),
 ('5d907dc4-c2c3-4eb1-b028-a771b8d447d7'),('842405e4-5209-45f5-9729-0d22327daeaa'),('c3786a12-18a0-4c88-8636-8b09800aed56'),
 ('6836f01c-080f-4289-90a4-df8667a49ac9'),('d89a3bbd-590b-493b-84a8-ce557bbfe512'),
 (E'\r\n <ME3P282MB1762651B0CB12077BBE64EA9CFAC2@ME3P282MB1762.AUSP282.PROD.OUTLOOK.COM>'),
 (E'\r\n <ME3P282MB17624D09C1024DA27B4AB754CFAC2@ME3P282MB1762.AUSP282.PROD.OUTLOOK.COM>');

CREATE TEMP TABLE pdc_exact_reset_untouched(table_name text PRIMARY KEY, row_count bigint NOT NULL, rows_sha256 text NOT NULL) ON COMMIT DROP;
DO $before_13000769$
DECLARE r record; n bigint; h text;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name LOOP
    EXECUTE format('SELECT count(*),coalesce(encode(extensions.digest(string_agg(to_jsonb(x)::text,E''\\n'' order by to_jsonb(x)::text),''sha256''),''hex''),'''') FROM public.%I x WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(%L::text)))',r.table_name,'13000769') INTO n,h;
    IF n>0 THEN INSERT INTO pdc_exact_reset_untouched VALUES(r.table_name,n,h); END IF;
  END LOOP;
END
$before_13000769$;

CREATE TEMP TABLE pdc_exact_reset_impacted(table_name text PRIMARY KEY, matched_count bigint NOT NULL, deleted_count bigint NOT NULL DEFAULT 0) ON COMMIT DROP;
CREATE TEMP TABLE pdc_exact_reset_delete_order(seq integer PRIMARY KEY, table_name text UNIQUE NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE pdc_exact_reset_remaining(table_name text PRIMARY KEY) ON COMMIT DROP;

DO $discover$
DECLARE table_name text; n bigint;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['ai_email_attachments','ai_email_intake','audit_events','navision_backend_records','navision_board_activations','navision_import_items','pdc_ai_intake_history','pdc_ai_intake_proposals','pdc_authenticated_email_import_receipts','pdc_authenticated_email_operation_lines','pdc_authenticated_parts_received_receipts_751','pdc_email_monitor_requeue_receipts_735','pdc_email_monitor_requeue_targets_735','pdc_email_monitor_storage_reconciliations_735','pdc_email_source_claims','pdc_exact_email_import_receipts_501','pdc_parts_order_receipts_377','pdc_qc_operation_completion_history_379','pdc_qc_operation_completion_receipts_379','pdc_qc_operation_completions_379','pdc_vehicle_detail_edit_history_388','pdc_vehicle_detail_edit_receipts_388','vehicle_master_history','vehicle_movements','vehicle_parts_updates','vehicle_work_items','vehicle_workshop_line_adjustments','vehicles','workshop_booking_history','workshop_booking_move_receipts','workshop_bookings'] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I x WHERE EXISTS (SELECT 1 FROM pdc_exact_reset_tokens k WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(k.token))))',table_name) INTO n;
    IF n>0 THEN INSERT INTO pdc_exact_reset_impacted(table_name,matched_count) VALUES(table_name,n); END IF;
  END LOOP;
END
$discover$;

-- Break the only known live two-way operational FK before the child-first
-- delete order. No booking is created or changed by this reset.
UPDATE public.vehicles SET active_workshop_booking_id=NULL
WHERE id='7fe33693-f519-5152-bbe0-9cc799c4ae33' AND stock_number_normalized='13017855';

INSERT INTO pdc_exact_reset_remaining(table_name) SELECT table_name FROM pdc_exact_reset_impacted;
DO $order$
DECLARE r record; v_seq integer:=0; progress boolean;
BEGIN
  WHILE EXISTS (SELECT 1 FROM pdc_exact_reset_remaining) LOOP
    progress:=false;
    SELECT rem.table_name INTO r FROM pdc_exact_reset_remaining rem
    WHERE NOT EXISTS (
      SELECT 1 FROM pg_constraint fk
      JOIN pg_class child ON child.oid=fk.conrelid JOIN pg_namespace child_ns ON child_ns.oid=child.relnamespace
      JOIN pg_class parent ON parent.oid=fk.confrelid JOIN pg_namespace parent_ns ON parent_ns.oid=parent.relnamespace
      JOIN pdc_exact_reset_remaining child_rem ON child_rem.table_name=child.relname
      WHERE fk.contype='f' AND child_ns.nspname='public' AND parent_ns.nspname='public'
        AND parent.relname=rem.table_name AND child.relname<>rem.table_name
        AND NOT (child.relname='vehicles' AND parent.relname='workshop_bookings')
    ) ORDER BY rem.table_name LIMIT 1;
    IF FOUND THEN
      v_seq:=v_seq+1; INSERT INTO pdc_exact_reset_delete_order VALUES(v_seq,r.table_name); DELETE FROM pdc_exact_reset_remaining WHERE table_name=r.table_name; progress:=true;
    END IF;
    IF NOT progress THEN RAISE EXCEPTION 'PDC_EXACT_RESET_NONDEFERRABLE_DELETE_ORDER_FAILED' USING errcode='55000'; END IF;
  END LOOP;
END
$order$;

DO $disable$
DECLARE r record;
BEGIN
  FOR r IN SELECT table_name FROM pdc_exact_reset_impacted ORDER BY table_name LOOP
    EXECUTE format('ALTER TABLE public.%I DISABLE TRIGGER USER',r.table_name);
  END LOOP;
END
$disable$;

DO $delete$
DECLARE r record; n bigint;
BEGIN
  FOR r IN SELECT i.table_name,i.matched_count FROM pdc_exact_reset_impacted i JOIN pdc_exact_reset_delete_order o USING(table_name) ORDER BY o.seq LOOP
    EXECUTE format('DELETE FROM public.%I x WHERE EXISTS (SELECT 1 FROM pdc_exact_reset_tokens k WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(k.token))))',r.table_name);
    GET DIAGNOSTICS n=ROW_COUNT;
    IF n<>r.matched_count THEN RAISE EXCEPTION 'PDC_EXACT_RESET_DELETE_COUNT_MISMATCH:% expected % got %',r.table_name,r.matched_count,n USING errcode='55000'; END IF;
    UPDATE pdc_exact_reset_impacted SET deleted_count=n WHERE table_name=r.table_name;
  END LOOP;
END
$delete$;

DO $enable$
DECLARE r record;
BEGIN
  FOR r IN SELECT table_name FROM pdc_exact_reset_impacted ORDER BY table_name LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE TRIGGER USER',r.table_name);
  END LOOP;
END
$enable$;

DO $post$
DECLARE r record; n bigint; remaining bigint:=0; total bigint;
BEGIN
  FOR r IN SELECT table_name FROM pdc_exact_reset_impacted ORDER BY table_name LOOP
    EXECUTE format('SELECT count(*) FROM public.%I x WHERE EXISTS (SELECT 1 FROM pdc_exact_reset_tokens k WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(k.token))))',r.table_name) INTO n;
    remaining:=remaining+n;
  END LOOP;
  SELECT coalesce(sum(deleted_count),0) INTO total FROM pdc_exact_reset_impacted;
  IF remaining<>0 OR total=0
     OR (SELECT count(*) FROM public.vehicles WHERE stock_number_normalized IN ('13080534','13017855'))<>0
     OR (SELECT count(*) FROM public.navision_backend_records WHERE id IN ('5721cafa-2b60-4d45-b69c-ab907eaf178e','e39eb741-cf03-44f2-8a75-54362ecc8a26'))<>0
     OR (SELECT count(*) FROM public.navision_board_activations WHERE backend_record_id IN ('5721cafa-2b60-4d45-b69c-ab907eaf178e','e39eb741-cf03-44f2-8a75-54362ecc8a26') OR canonical_vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33')<>0
     OR (SELECT count(*) FROM public.pdc_authenticated_email_operation_lines WHERE source_uid IN ('1:640','1:680','1:681') OR vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33')<>0
  THEN RAISE EXCEPTION 'PDC_EXACT_RESET_IDENTITY_OR_POSTCONDITION_FAILED remaining=% total=%',remaining,total USING errcode='55000'; END IF;
END
$post$;

DO $unchanged_13000769$
DECLARE r record; n bigint; h text; prior_count bigint; prior_hash text;
BEGIN
  FOR r IN SELECT * FROM pdc_exact_reset_untouched LOOP
    EXECUTE format('SELECT count(*),coalesce(encode(extensions.digest(string_agg(to_jsonb(x)::text,E''\\n'' order by to_jsonb(x)::text),''sha256''),''hex''),'''') FROM public.%I x WHERE jsonb_path_exists(to_jsonb(x), ''$.** ? (@ == $token)'', jsonb_build_object(''token'',to_jsonb(%L::text)))',r.table_name,'13000769') INTO n,h;
    IF n<>r.row_count OR h<>r.rows_sha256 THEN RAISE EXCEPTION 'PDC_EXACT_RESET_13000769_CHANGED:%',r.table_name USING errcode='55000'; END IF;
  END LOOP;
END
$unchanged_13000769$;

CREATE TABLE public.pdc_exact_stock_reset_receipts_20260828(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 action_key text NOT NULL UNIQUE CHECK(action_key='phase1-exact-stock-reset-13080534-13017855'),
 environment text NOT NULL CHECK(environment='staging'), project_ref text NOT NULL CHECK(project_ref='cdsmnqxtyyoeoznmbidd'),
 expected_predecessor_head text NOT NULL CHECK(expected_predecessor_head='20260829151000/752_reactivate_exact_email_monitor_after_751'),
 snapshot_backup_run_id uuid NOT NULL, snapshot_artifact_sha256 text NOT NULL CHECK(snapshot_artifact_sha256='6887bad60ba612c83584cb628829b70dcb0f2e6c8a08de64e46b2c7de3a77518'), snapshot_manifest_sha256 text NOT NULL CHECK(snapshot_manifest_sha256='8de3b4cb413006d6850838a83ca1648215e0e589f1f61f7e01cb9339fc4bb018'),
 target_bindings jsonb NOT NULL, target_token_set_sha256 text NOT NULL CHECK(target_token_set_sha256~'^[a-f0-9]{64}$'),
 deleted_table_count integer NOT NULL, deleted_row_count bigint NOT NULL, deleted_counts jsonb NOT NULL,
 forced_rls boolean NOT NULL CHECK(forced_rls), trigger_reset_restored boolean NOT NULL CHECK(trigger_reset_restored), production_untouched boolean NOT NULL CHECK(production_untouched),
 rollback_contract text NOT NULL CHECK(length(rollback_contract)>80), created_by uuid NOT NULL CHECK(created_by='8a83b715-8d79-4b0e-95b2-02b55da6e8d7'), created_by_email text NOT NULL CHECK(created_by_email='craig.watson@broometoyota.com.au'), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_exact_stock_reset_receipts_20260828 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_exact_stock_reset_receipts_20260828 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_exact_stock_reset_receipts_20260828 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_exact_email_reimport_authorizations_20260828(
 authorization_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 reset_receipt_id uuid NOT NULL REFERENCES public.pdc_exact_stock_reset_receipts_20260828(receipt_id) ON DELETE RESTRICT,
 stock_number text NOT NULL UNIQUE CHECK(stock_number IN ('13080534','13017855')),
 intake_id uuid NOT NULL UNIQUE, source_uid text NOT NULL UNIQUE, sender_email text NOT NULL CHECK(sender_email='craig.watson@broometoyota.com.au'),
 internet_message_id text NOT NULL UNIQUE, parent_source_hash text NOT NULL UNIQUE CHECK(parent_source_hash~'^[a-f0-9]{64}$'), attachment_manifest jsonb NOT NULL,
 expected_backend_record_id uuid NOT NULL, expected_canonical_vehicle_id uuid, expected_job_card_number text, expected_head text NOT NULL CHECK(expected_head='20260829151000/752_reactivate_exact_email_monitor_after_751'),
 status text NOT NULL CHECK(status='authorized'), one_time boolean NOT NULL CHECK(one_time), consumed boolean NOT NULL DEFAULT false CHECK(NOT consumed), mailbox_preserved boolean NOT NULL CHECK(mailbox_preserved), attachment_bytes_preserved boolean NOT NULL CHECK(attachment_bytes_preserved), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_exact_email_reimport_authorizations_20260828 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_exact_email_reimport_authorizations_20260828 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_exact_email_reimport_authorizations_20260828 FROM public,anon,authenticated,service_role;

INSERT INTO public.pdc_exact_stock_reset_receipts_20260828(action_key,environment,project_ref,expected_predecessor_head,snapshot_backup_run_id,snapshot_artifact_sha256,snapshot_manifest_sha256,target_bindings,target_token_set_sha256,deleted_table_count,deleted_row_count,deleted_counts,forced_rls,trigger_reset_restored,production_untouched,rollback_contract,created_by,created_by_email)
SELECT 'phase1-exact-stock-reset-13080534-13017855','staging','cdsmnqxtyyoeoznmbidd','20260829151000/752_reactivate_exact_email_monitor_after_751','7f1c3315-ac42-46fb-99ed-70b43ef89f80'::uuid,'6887bad60ba612c83584cb628829b70dcb0f2e6c8a08de64e46b2c7de3a77518','8de3b4cb413006d6850838a83ca1648215e0e589f1f61f7e01cb9339fc4bb018',jsonb_build_object('13080534',jsonb_build_object('backend_record_id','5721cafa-2b60-4d45-b69c-ab907eaf178e','canonical_vehicle_id',null,'job_card_number',null),'13017855',jsonb_build_object('backend_record_id','e39eb741-cf03-44f2-8a75-54362ecc8a26','canonical_vehicle_id','7fe33693-f519-5152-bbe0-9cc799c4ae33','job_card_number','J139125422','vin','MR0MABAV902402464')),encode(extensions.digest((SELECT string_agg(token,'|' ORDER BY token) FROM pdc_exact_reset_tokens),'sha256'),'hex'),count(*),coalesce(sum(deleted_count),0),coalesce(jsonb_object_agg(table_name,deleted_count ORDER BY table_name),'{}'::jsonb),true,true,true,'Rollback is a separate guarded staging-only restore using the encrypted closure artifact, exact receipt, predecessor identity bindings, advisory lock, empty-target preflight and transaction rollback on any mismatch; never restore to Production or bypass the canonical importer.', '8a83b715-8d79-4b0e-95b2-02b55da6e8d7','craig.watson@broometoyota.com.au'
FROM pdc_exact_reset_impacted;

INSERT INTO public.pdc_exact_email_reimport_authorizations_20260828(reset_receipt_id,stock_number,intake_id,source_uid,sender_email,internet_message_id,parent_source_hash,attachment_manifest,expected_backend_record_id,expected_canonical_vehicle_id,expected_job_card_number,expected_head,status,one_time,consumed,mailbox_preserved,attachment_bytes_preserved)
SELECT r.receipt_id,'13080534','6836f01c-080f-4289-90a4-df8667a49ac9'::uuid,'imap_uid:681','craig.watson@broometoyota.com.au',E'\r\n <ME3P282MB1762651B0CB12077BBE64EA9CFAC2@ME3P282MB1762.AUSP282.PROD.OUTLOOK.COM>','f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916',jsonb_build_array(jsonb_build_object('attachment_id','0f190df5-09df-4df6-a111-66f658318d57','file_name','13080534.pdf','source_hash','090749692e975cec1b490f42d07af95e9693edadbf42c7399947f7ebaf7bfc34'),jsonb_build_object('attachment_id','3415271f-e6df-4d1e-a763-3341f9b066f4','file_name','image.png','source_hash','64e39069be7b13b3a478ad5e2386cbe3978e59d27a25b06595fc8f7a226fbaa3'),jsonb_build_object('attachment_id','91eadf28-e8d6-482a-9dd9-b3b6b7862489','file_name','image.png','source_hash','ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3')),'5721cafa-2b60-4d45-b69c-ab907eaf178e'::uuid,null,null,'20260829151000/752_reactivate_exact_email_monitor_after_751','authorized',true,false,true,true FROM public.pdc_exact_stock_reset_receipts_20260828 r
UNION ALL
SELECT r.receipt_id,'13017855','d89a3bbd-590b-493b-84a8-ce557bbfe512'::uuid,'imap_uid:680','craig.watson@broometoyota.com.au',E'\r\n <ME3P282MB17624D09C1024DA27B4AB754CFAC2@ME3P282MB1762.AUSP282.PROD.OUTLOOK.COM>','d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493',jsonb_build_array(jsonb_build_object('attachment_id','5d907dc4-c2c3-4eb1-b028-a771b8d447d7','file_name','image.png','source_hash','64e39069be7b13b3a478ad5e2386cbe3978e59d27a25b06595fc8f7a226fbaa3'),jsonb_build_object('attachment_id','842405e4-5209-45f5-9729-0d22327daeaa','file_name','13017855.pdf','source_hash','23416bd8de1ef1fa6bb40b3b81b3613d969fdb3bd897dc090f0d6747b7b1831f'),jsonb_build_object('attachment_id','c3786a12-18a0-4c88-8636-8b09800aed56','file_name','image.png','source_hash','ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3')),'e39eb741-cf03-44f2-8a75-54362ecc8a26'::uuid,'7fe33693-f519-5152-bbe0-9cc799c4ae33'::uuid,'J139125422','20260829151000/752_reactivate_exact_email_monitor_after_751','authorized',true,false,true,true FROM public.pdc_exact_stock_reset_receipts_20260828 r;

CREATE FUNCTION public.pdc_exact_stock_reset_20260828_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_EXACT_STOCK_RESET_RECEIPT_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_exact_stock_reset_20260828_immutable() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_exact_stock_reset_receipt_immutable BEFORE UPDATE OR DELETE ON public.pdc_exact_stock_reset_receipts_20260828 FOR EACH ROW EXECUTE FUNCTION public.pdc_exact_stock_reset_20260828_immutable();
CREATE TRIGGER pdc_exact_email_reimport_authorization_immutable BEFORE UPDATE OR DELETE ON public.pdc_exact_email_reimport_authorizations_20260828 FOR EACH ROW EXECUTE FUNCTION public.pdc_exact_stock_reset_20260828_immutable();

INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
SELECT 'delete','pdc_exact_stock_reset_receipts_20260828',receipt_id,'8a83b715-8d79-4b0e-95b2-02b55da6e8d7'::uuid,'craig.watson@broometoyota.com.au',target_bindings,jsonb_build_object('status','phase1_reset_applied','stocks',jsonb_build_array('13080534','13017855')),
 jsonb_build_object('event_type','pdc_exact_stock_reset_phase1','dashboard_session','20260828_191153_4fb787','source_uids',jsonb_build_array('imap_uid:681','imap_uid:680'),'production_untouched',true,'mailbox_preserved',true) FROM public.pdc_exact_stock_reset_receipts_20260828;

DO $final$
BEGIN
 IF (SELECT count(*) FROM public.pdc_exact_stock_reset_receipts_20260828 WHERE action_key='phase1-exact-stock-reset-13080534-13017855' AND forced_rls AND trigger_reset_restored AND production_untouched)<>1
 OR (SELECT count(*) FROM public.pdc_exact_email_reimport_authorizations_20260828 WHERE status='authorized' AND one_time AND NOT consumed AND mailbox_preserved AND attachment_bytes_preserved)<>2
 OR (SELECT count(DISTINCT stock_number) FROM public.pdc_exact_email_reimport_authorizations_20260828)<>2
 OR (SELECT count(*) FROM public.ai_email_intake WHERE id IN ('6836f01c-080f-4289-90a4-df8667a49ac9','d89a3bbd-590b-493b-84a8-ce557bbfe512'))<>0
 THEN RAISE EXCEPTION 'PDC_EXACT_RESET_FINAL_RECEIPT_OR_HANDOFF_FAILED' USING errcode='55000'; END IF;
END
$final$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260829163000','exact_stock_reset_13080534_13017855_phase1',ARRAY['Bind exact live Navision/backend/vehicle/job-card identities and the two newest Craig-sender message IDs plus attachment hashes','Require fresh encrypted staging closure snapshot and artifact/manifest hashes','Acquire exact advisory and migration locks; preserve 13000769 row digests','Delete only the recursively proven exact target closure, restore user triggers, force RLS on immutable reset receipt and handoff tables','Leave exactly two one-time fresh-import authorizations; mailbox messages and storage bytes remain preserved; Production untouched','Rollback is a separate exact encrypted-artifact restore contract with fail-closed identity and postcondition guards']);
NOTIFY pgrst,'reload schema';
COMMIT;
