-- STAGING ONLY 677: exact retained UID514 recovery enqueue successor.
-- This is an append-only repair for the missing canonical intake/authorization
-- only. It does not lower the generic UID floor, edit sealed .44, contact the
-- mailbox, claim/import UID514, mutate vehicles, delete evidence, enable a task,
-- send email or touch Production.
-- Wrong actor, wrong gateway, wrong role, anon and service_role fail closed.
--
-- Exact predecessor/runtime anchors:
--   676 trigger p.prosrc: 9fe5f8bb31e15b9047a6c6d9304af2cfab19f9d33ec6161dcf31fbcf92367b43
--   674 active scope p.prosrc: 4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629
--   674 runtime helper p.prosrc: de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351
--   674 migration at authoritative commit: d6c57dd8f0215cff71e479b4b50e40de10dea2113216534ccc2edd9048db3bcb
--   sealed .44 runner: 52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd
--   external adapter: a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036
--   enqueue p.prosrc: eb91ff09afac2c66d2abf461b57dd9c8d1c6fc5aac13843d74c0ce192b8dd88a
--   UID514 authorize p.prosrc: ef925445ee7ccfd3dbfeba4c2e437e4c49e477269137ac5bbd1e744d9cf56962
--   UID514 claim p.prosrc: 937a18081480543436e790469c4b62351f6c0e758badf1d5d1213cf0377b375b

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-677-uid514-exact-recovery-successor',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_trigger_hash text;
  v_scope_hash text;
  v_runtime_hash text;
  v_enqueue_hash text;
  v_authorize_hash text;
  v_claim_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_trigger_hash
    FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash
    FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_active_scope_674(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_runtime_hash
    FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_runtime_authorized_502(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_enqueue_hash
    FROM pg_proc p WHERE p.oid='public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_authorize_hash
    FROM pg_proc p WHERE p.oid='public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_claim_hash
    FROM pg_proc p WHERE p.oid='public.claim_pdc_uid514_recovery_257(text,integer)'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827110000' AND name='676_authenticated_monitor_rollback_control_repair')<>1
     OR to_regclass('public.pdc_uid514_recovery_controls_677') IS NOT NULL
     OR to_regclass('public.pdc_uid514_recovery_history_677') IS NOT NULL
     OR to_regclass('public.pdc_uid514_recovery_enqueue_capabilities_677') IS NOT NULL
     OR to_regprocedure('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)') IS NOT NULL
     OR to_regprocedure('public.admin_rollback_pdc_uid514_recovery_677(text)') IS NOT NULL
     OR v_trigger_hash<>'9fe5f8bb31e15b9047a6c6d9304af2cfab19f9d33ec6161dcf31fbcf92367b43'
     OR v_scope_hash<>'4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629'
     OR v_runtime_hash<>'de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351'
     OR v_enqueue_hash<>'eb91ff09afac2c66d2abf461b57dd9c8d1c6fc5aac13843d74c0ce192b8dd88a'
     OR v_authorize_hash<>'ef925445ee7ccfd3dbfeba4c2e437e4c49e477269137ac5bbd1e744d9cf56962'
     OR v_claim_hash<>'937a18081480543436e790469c4b62351f6c0e758badf1d5d1213cf0377b375b'
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND active AND test_mode)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
  THEN RAISE EXCEPTION 'PDC_677_EXACT_676_PREDECESSOR_OR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_uid514_recovery_controls_677(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true,
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  server_application_role text NOT NULL CHECK(server_application_role='importer'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  mailbox_key text NOT NULL CHECK(mailbox_key='pdc_pmb_email'),
  mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'),
  provider text NOT NULL CHECK(provider='gmail'),
  mailbox_folder text NOT NULL CHECK(mailbox_folder='Inbox'),
  mailbox_uidvalidity bigint NOT NULL CHECK(mailbox_uidvalidity=1),
  mailbox_uid bigint NOT NULL CHECK(mailbox_uid=514),
  recovery_event_id integer NOT NULL UNIQUE CHECK(recovery_event_id=25751401),
  parent_source_hash text NOT NULL UNIQUE CHECK(parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280'),
  all_attachment_hashes text[] NOT NULL CHECK(cardinality(all_attachment_hashes)=7),
  pdf_hashes text[] NOT NULL CHECK(cardinality(pdf_hashes)=4),
  job_card_sha256 text NOT NULL CHECK(job_card_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4),
  all_mime_parts_retained boolean NOT NULL CHECK(all_mime_parts_retained),
  task_enabled boolean NOT NULL DEFAULT false CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL DEFAULT false CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_uid514_recovery_controls_677 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_recovery_controls_677 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_recovery_controls_677 FROM public,anon,authenticated,service_role,pdc_email_monitor;
INSERT INTO public.pdc_uid514_recovery_controls_677(
 actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,
 planner_sha256,trust_receipt_sha256,mailbox_id,mailbox_key,mailbox_address,provider,mailbox_folder,mailbox_uidvalidity,mailbox_uid,recovery_event_id,
 parent_source_hash,all_attachment_hashes,pdf_hashes,job_card_sha256,observed_mime_part_count,retained_authenticated_attachment_count,all_mime_parts_retained)
VALUES(
 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer',
 'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b',
 'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348',
 'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227','12fe383d-5c1e-5801-96e4-f67cf3e3bb57','pdc_pmb_email','pmbcontroller@gmail.com','gmail','Inbox',1,514,25751401,
 '440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280',
 ARRAY['7bc4e2dec9b1c405098f1ca7b4c646bf3262158e328f9f548abb855b8ef2f21a','ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3','c60dae99a28cdccdee51f5bdffa43382d9b7eb31af690c31caedcc8d4f66cf40','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','66b790ba3a72760e00a034bf7f5cf5a7e1defe5d6947373216f8c8dc4ed8acff','b297f4f9070f6c78c88aae099630b78bb5157c3094c45a30b5cfef0f263ac3b1','ea248634b8610f757907c519ea2f7ba243fb1602c8114cbde947707aff8407ae'],
 ARRAY['9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','66b790ba3a72760e00a034bf7f5cf5a7e1defe5d6947373216f8c8dc4ed8acff','b297f4f9070f6c78c88aae099630b78bb5157c3094c45a30b5cfef0f263ac3b1','ea248634b8610f757907c519ea2f7ba243fb1602c8114cbde947707aff8407ae'],
 '9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4',7,4,true);

CREATE TABLE public.pdc_uid514_recovery_enqueue_capabilities_677(
  capability_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash text NOT NULL UNIQUE CHECK(token_hash~'^[a-f0-9]{64}$'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  recovery_event_id integer NOT NULL CHECK(recovery_event_id=25751401),
  mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  consumed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_uid514_recovery_enqueue_capabilities_677 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_recovery_enqueue_capabilities_677 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_recovery_enqueue_capabilities_677 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE TABLE public.pdc_uid514_recovery_history_677(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('forward_uid514_recovery','rollback')),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827110000'),
  successor_head text NOT NULL CHECK(successor_head='20260827111000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  server_application_role text NOT NULL CHECK(server_application_role='importer'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  mailbox_key text NOT NULL CHECK(mailbox_key='pdc_pmb_email'),
  mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'),
  mailbox_folder text NOT NULL CHECK(mailbox_folder='Inbox'),
  mailbox_uidvalidity bigint NOT NULL CHECK(mailbox_uidvalidity=1),
  mailbox_uid bigint NOT NULL CHECK(mailbox_uid=514),
  recovery_event_id integer NOT NULL CHECK(recovery_event_id=25751401),
  parent_source_hash text NOT NULL CHECK(parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280'),
  all_attachment_hashes text[] NOT NULL CHECK(cardinality(all_attachment_hashes)=7),
  pdf_hashes text[] NOT NULL CHECK(cardinality(pdf_hashes)=4),
  job_card_sha256 text NOT NULL CHECK(job_card_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4),
  all_mime_parts_retained boolean NOT NULL CHECK(all_mime_parts_retained),
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL,
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  performed_by uuid,
  performed_by_email text,
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_uid514_recovery_history_immutable_677()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_677_UID514_RECOVERY_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_uid514_recovery_history_immutable_677
BEFORE UPDATE OR DELETE ON public.pdc_uid514_recovery_history_677
FOR EACH ROW EXECUTE FUNCTION public.pdc_uid514_recovery_history_immutable_677();
ALTER TABLE public.pdc_uid514_recovery_history_677 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_recovery_history_677 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_recovery_history_677 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.pdc_uid514_recovery_payload_valid_677(p_message jsonb,p_attachments jsonb,p_recovery_event_id integer)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $payload$
DECLARE
  v_control public.pdc_uid514_recovery_controls_677%rowtype;
  v_auth jsonb;
  v_match integer;
BEGIN
  SELECT * INTO v_control FROM public.pdc_uid514_recovery_controls_677 WHERE singleton AND enabled;
  IF NOT FOUND OR p_recovery_event_id<>25751401 OR NOT public.pdc_monitor_authenticated_active_scope_674(NULL)
     OR jsonb_typeof(p_message) IS DISTINCT FROM 'object' OR jsonb_typeof(p_attachments) IS DISTINCT FROM 'array'
     OR p_message->>'provider_uid'<>'imap_uid:514'
     OR p_message->>'source_hash'<>'440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280'
     OR p_message->>'subject'<>'Re: New vehicle order for 13016925 - PMG Build'
     OR lower(btrim(coalesce(p_message->>'sender_email','')))<>'oleg.borodavkin@pmgwa.com.au'
     OR lower(btrim(coalesce(p_message->>'recipient_mailbox','')))<>'pmbcontroller@gmail.com'
     OR lower(btrim(coalesce(p_message->>'provider_authserv_id','')))<>'mx.google.com'
     OR coalesce(p_message->>'graph_message_id','')='' OR p_message->>'graph_message_id' NOT LIKE 'imap:%'
     OR jsonb_array_length(p_attachments)<>7 THEN RETURN false; END IF;
  v_auth:=coalesce(p_message->'provider_authentication','null'::jsonb);
  IF jsonb_typeof(v_auth) IS DISTINCT FROM 'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth) k) IS DISTINCT FROM array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb
     OR v_auth->>'sender_domain' IS DISTINCT FROM 'pmgwa.com.au'
     OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb) THEN RETURN false; END IF;
  SELECT count(*) INTO v_match
  FROM jsonb_array_elements(p_attachments) WITH ORDINALITY supplied(value,ord)
  JOIN (VALUES
    (1,'image001.jpg','image/jpeg',161949,'7bc4e2dec9b1c405098f1ca7b4c646bf3262158e328f9f548abb855b8ef2f21a'),
    (2,'image002.png','image/png',119426,'ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3'),
    (3,'image.png','image/png',220912,'c60dae99a28cdccdee51f5bdffa43382d9b7eb31af690c31caedcc8d4f66cf40'),
    (4,'J139125482 - _13016925.pdf','application/pdf',72551,'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
    (5,'131 Parts Order - 13016925 - Hilux SCC WM - HERMAL Pty Ltd.pdf','application/pdf',50134,'66b790ba3a72760e00a034bf7f5cf5a7e1defe5d6947373216f8c8dc4ed8acff'),
    (6,'PMG Sublet Order - 13016925 - Hilux SCC WM - HERMAL Pty Ltd.pdf','application/pdf',49944,'b297f4f9070f6c78c88aae099630b78bb5157c3094c45a30b5cfef0f263ac3b1'),
    (7,'PD Document 48298_PDCheckform.pdf','application/pdf',17398,'ea248634b8610f757907c519ea2f7ba243fb1602c8114cbde947707aff8407ae')
  ) expected(ord,file_name,content_type,size_bytes,source_hash) ON expected.ord=supplied.ord
  WHERE (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(supplied.value) k) IS NOT DISTINCT FROM array['content_type','file_name','reported_content_type','size_bytes','source_hash','storage_path','validation_error','validation_status']::text[]
    AND supplied.value->>'file_name'=expected.file_name AND supplied.value->>'content_type'=expected.content_type
    AND supplied.value->>'reported_content_type'=expected.content_type AND supplied.value->>'size_bytes'=expected.size_bytes::text
    AND lower(supplied.value->>'source_hash')=expected.source_hash AND supplied.value->>'validation_status'='verified'
    AND supplied.value->>'validation_error'='' AND supplied.value->>'storage_path' LIKE 'pdc-email-intake-private/%';
  RETURN v_match=7;
END
$payload$;
REVOKE ALL ON FUNCTION public.pdc_uid514_recovery_payload_valid_677(jsonb,jsonb,integer) FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.pdc_uid514_recovery_enqueue_capability_677(p_mailbox_id uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $capability$
DECLARE
  v_token text:=current_setting('pdc.uid514.recovery_token',true);
  v_row public.pdc_uid514_recovery_enqueue_capabilities_677%rowtype;
BEGIN
  IF NOT public.pdc_monitor_authenticated_active_scope_674(NULL) OR p_mailbox_id<>'12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid OR v_token='' THEN RETURN false; END IF;
  SELECT * INTO v_row FROM public.pdc_uid514_recovery_enqueue_capabilities_677
   WHERE token_hash=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex')
     AND actor_id=auth.uid() AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND recovery_event_id=25751401
     AND mailbox_id=p_mailbox_id AND consumed_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  UPDATE public.pdc_uid514_recovery_enqueue_capabilities_677 SET consumed_at=clock_timestamp() WHERE capability_id=v_row.capability_id;
  RETURN true;
END
$capability$;
REVOKE ALL ON FUNCTION public.pdc_uid514_recovery_enqueue_capability_677(uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $trigger$
DECLARE
  v_before text;
  v_after text;
  v_needle text:=E'  if coalesce(new.provider_uid,'''')!~''^imap_uid:[0-9]+$'' or substring(new.provider_uid from ''^imap_uid:([0-9]+)$'')::bigint<515 then raise exception ''pdc_monitor_uid_before_active_floor'' using errcode=''42501''; end if;';
  v_insertion text:=E'  if new.provider_uid=''imap_uid:514'' then\n    if not public.pdc_uid514_recovery_enqueue_capability_677(new.monitored_mailbox_id) then raise exception ''PDC_677_UID514_RECOVERY_CAPABILITY_MISSING'' using errcode=''42501''; end if;\n    return new;\n  end if;\n';
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure) INTO v_before;
  IF position('pdc_monitor_uid_before_active_floor' IN v_before)=0 OR position(v_needle IN v_before)=0 THEN RAISE EXCEPTION 'PDC_677_TRIGGER_SOURCE_DRIFT' USING errcode='55000'; END IF;
  v_after:=replace(v_before,v_needle,v_insertion||v_needle);
  EXECUTE v_after;
END
$trigger$;

CREATE FUNCTION public.enqueue_pdc_uid514_recovery_677(p_message jsonb,p_attachments jsonb,p_recovery_event_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $enqueue$
DECLARE
  v_token text;
  v_normalized jsonb;
  v_enqueue jsonb;
  v_authorization jsonb;
  v_history public.pdc_uid514_recovery_history_677%rowtype;
  v_control public.pdc_uid514_recovery_controls_677%rowtype;
  v_intake_id uuid;
  v_event_key text;
  v_existing boolean;
BEGIN
  IF p_recovery_event_id<>25751401 THEN RAISE EXCEPTION 'PDC_677_UID514_RECOVERY_SCOPE_INVALID' USING errcode='22023'; END IF;
  IF NOT public.pdc_uid514_recovery_payload_valid_677(p_message,p_attachments,p_recovery_event_id) THEN
    RAISE EXCEPTION 'PDC_677_UID514_RECOVERY_PAYLOAD_INVALID' USING errcode='42501';
  END IF;
  SELECT * INTO v_control FROM public.pdc_uid514_recovery_controls_677 WHERE singleton AND enabled FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_677_UID514_RECOVERY_DISABLED' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-uid514-recovery-257',0));
  SELECT EXISTS(SELECT 1 FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401) INTO v_existing;
  SELECT coalesce(jsonb_agg(value || jsonb_build_object('graph_attachment_id','imap_uid:514:part:'||lpad(ord::text,2,'0')) ORDER BY ord),'[]'::jsonb)
    INTO v_normalized FROM jsonb_array_elements(p_attachments) WITH ORDINALITY parts(value,ord);
  v_token:=gen_random_uuid()::text;
  IF NOT v_existing THEN
    INSERT INTO public.pdc_uid514_recovery_enqueue_capabilities_677(token_hash,actor_id,gateway_instance_id,recovery_event_id,mailbox_id)
    VALUES(encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex'),auth.uid(),'pdc-monitor-staging-sales-uid509-v1',25751401,'12fe383d-5c1e-5801-96e4-f67cf3e3bb57');
    PERFORM set_config('pdc.uid514.recovery_token',v_token,true);
  END IF;
  v_enqueue:=public.enqueue_pdc_email_intake(p_message,v_normalized);
  v_intake_id:=(v_enqueue->>'intake_id')::uuid;
  IF v_intake_id IS NULL THEN RAISE EXCEPTION 'PDC_677_UID514_RECOVERY_INTAKE_ID_MISSING' USING errcode='55000'; END IF;
  UPDATE public.pdc_uid514_recovery_enqueue_capabilities_677
    SET consumed_at=coalesce(consumed_at,clock_timestamp())
    WHERE token_hash=encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex') AND consumed_at IS NULL;
  v_authorization:=public.authorize_pdc_uid514_retained_intake_257(v_intake_id,25751401);
  IF coalesce(v_authorization->>'ok','false')<>'true' THEN RAISE EXCEPTION 'PDC_677_UID514_RECOVERY_AUTHORIZATION_FAILED' USING errcode='55000'; END IF;
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-677-uid514-exact-recovery-successor|forward|25751401','UTF8'),'sha256'),'hex');
  SELECT * INTO v_history FROM public.pdc_uid514_recovery_history_677 WHERE event_key=v_event_key;
  IF FOUND THEN
    RETURN jsonb_build_object('ok',true,'code','uid514_recovery_replayed','idempotent',true,'intake_id',v_intake_id,'recovery_event_id',25751401,'parent_source_hash',v_control.parent_source_hash,'all_mime_parts_retained',true,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'job_card_sha256',v_control.job_card_sha256);
  END IF;
  INSERT INTO public.pdc_uid514_recovery_history_677(
    event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,
    mailbox_id,mailbox_key,mailbox_address,mailbox_folder,mailbox_uidvalidity,mailbox_uid,recovery_event_id,parent_source_hash,all_attachment_hashes,pdf_hashes,job_card_sha256,observed_mime_part_count,retained_authenticated_attachment_count,all_mime_parts_retained,
    before_state,after_state,task_enabled,mailbox_contacted,uid514_processed,production_writes,rollback_contract)
  VALUES(
    v_event_key,'forward_uid514_recovery','20260827110000','20260827111000',v_control.actor_id,v_control.actor_email,v_control.jwt_role,v_control.server_application_role,v_control.gateway_instance_id,v_control.release_name,v_control.source_sha,v_control.manifest_sha256,v_control.planner_sha256,v_control.trust_receipt_sha256,
    v_control.mailbox_id,v_control.mailbox_key,v_control.mailbox_address,v_control.mailbox_folder,v_control.mailbox_uidvalidity,v_control.mailbox_uid,25751401,v_control.parent_source_hash,v_control.all_attachment_hashes,v_control.pdf_hashes,v_control.job_card_sha256,7,4,true,
    jsonb_build_object('enqueue',v_enqueue,'authorization',v_authorization,'intake_id',v_intake_id,'reviewed_typed_path',true,'canonical_intake_created',not v_existing),
    jsonb_build_object('intake_id',v_intake_id,'authorization_code',v_authorization->>'code','canonical_attachment_count',7,'qualifying_pdf_count',4,'all_mime_parts_retained',true),false,false,false,false,
    'Exact UIDVALIDITY 1 Inbox UID514 only; rollback disables future enqueue/claim and preserves every canonical intake, attachment, authorization, selection and history row');
  RETURN jsonb_build_object('ok',true,'code','uid514_recovery_enqueued','idempotent',false,'intake_id',v_intake_id,'recovery_event_id',25751401,'parent_source_hash',v_control.parent_source_hash,'all_mime_parts_retained',true,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'job_card_sha256',v_control.job_card_sha256);
END
$enqueue$;
REVOKE ALL ON FUNCTION public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer) TO authenticated;

CREATE FUNCTION public.pdc_uid514_recovery_claim_enabled_677()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $claim_gate$
SELECT public.pdc_monitor_authenticated_active_scope_674(NULL)
 AND EXISTS(SELECT 1 FROM public.pdc_uid514_recovery_controls_677 c WHERE c.singleton AND c.enabled AND c.actor_id=auth.uid() AND c.actor_email='sales@broometoyota.com.au' AND c.jwt_role='authenticated' AND c.server_application_role='importer' AND c.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND c.release_name='pdc-monitor-staging-m502-2026.08.44' AND c.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND c.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND c.parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND c.mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND c.mailbox_uidvalidity=1 AND c.mailbox_uid=514 AND c.recovery_event_id=25751401 AND NOT c.task_enabled AND NOT c.mailbox_contacted AND NOT c.uid514_processed AND NOT c.production_writes);
$claim_gate$;
REVOKE ALL ON FUNCTION public.pdc_uid514_recovery_claim_enabled_677() FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $claim_repair$
DECLARE
  v_before text;
  v_after text;
  v_needle text:=E' if p_recovery_event_id<>25751401 then raise exception ''PDC_261_UID514_SCOPE_INVALID'' using errcode=''22023'';end if;';
  v_insertion text:=E' if not public.pdc_uid514_recovery_claim_enabled_677() then raise exception ''PDC_677_UID514_RECOVERY_DISABLED'' using errcode=''42501'';end if;\n';
BEGIN
  SELECT pg_get_functiondef('public.claim_pdc_uid514_recovery_257(text,integer)'::regprocedure) INTO v_before;
  IF position('pdc_261_uid514_scope_invalid' IN lower(v_before))=0 OR position(v_needle IN v_before)=0 THEN RAISE EXCEPTION 'PDC_677_CLAIM_SOURCE_DRIFT' USING errcode='55000'; END IF;
  v_after:=replace(v_before,v_needle,v_insertion||v_needle);
  EXECUTE v_after;
END
$claim_repair$;

CREATE FUNCTION public.admin_rollback_pdc_uid514_recovery_677(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $rollback$
DECLARE
  v_admin uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_count integer;
  v_control public.pdc_uid514_recovery_controls_677%rowtype; v_existing public.pdc_uid514_recovery_history_677%rowtype;
  v_before jsonb; v_after jsonb; v_event_key text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_admin IS NULL OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_677_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  SELECT count(*) INTO v_count FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id AND lower(u.email)=v_email
   WHERE r.auth_user_id=v_admin AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF v_count<>1 THEN RAISE EXCEPTION 'PDC_677_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-677-uid514-exact-recovery-successor',0));
  SELECT * INTO v_control FROM public.pdc_uid514_recovery_controls_677 WHERE singleton FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_677_CONTROL_MISSING' USING errcode='55000'; END IF;
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-677-uid514-exact-recovery-successor|rollback|25751401','UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing FROM public.pdc_uid514_recovery_history_677 WHERE event_key=v_event_key;
  IF FOUND THEN
    IF v_control.enabled THEN RAISE EXCEPTION 'PDC_677_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_uid514_recovery_rolled_back_677','idempotent',true,'uid514_processed',false,'production_writes',false);
  END IF;
  IF NOT v_control.enabled THEN RAISE EXCEPTION 'PDC_677_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
  v_before:=to_jsonb(v_control);
  UPDATE public.pdc_uid514_recovery_controls_677 SET enabled=false,changed_at=clock_timestamp() WHERE singleton RETURNING * INTO v_control;
  v_after:=to_jsonb(v_control);
  INSERT INTO public.pdc_uid514_recovery_history_677(
    event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,
    mailbox_id,mailbox_key,mailbox_address,mailbox_folder,mailbox_uidvalidity,mailbox_uid,recovery_event_id,parent_source_hash,all_attachment_hashes,pdf_hashes,job_card_sha256,observed_mime_part_count,retained_authenticated_attachment_count,all_mime_parts_retained,
    before_state,after_state,task_enabled,mailbox_contacted,uid514_processed,production_writes,performed_by,performed_by_email,rollback_contract)
  VALUES(v_event_key,'rollback','20260827110000','20260827111000',v_control.actor_id,v_control.actor_email,v_control.jwt_role,v_control.server_application_role,v_control.gateway_instance_id,v_control.release_name,v_control.source_sha,v_control.manifest_sha256,v_control.planner_sha256,v_control.trust_receipt_sha256,
    v_control.mailbox_id,v_control.mailbox_key,v_control.mailbox_address,v_control.mailbox_folder,v_control.mailbox_uidvalidity,v_control.mailbox_uid,25751401,v_control.parent_source_hash,v_control.all_attachment_hashes,v_control.pdf_hashes,v_control.job_card_sha256,7,4,true,
    v_before,v_after,false,false,false,false,v_admin,v_email,'Disable future exact UID514 enqueue/claim only; retain all immutable intake, attachment, authorization, selection and prior successor evidence without deletion');
  RETURN jsonb_build_object('ok',true,'code','pdc_uid514_recovery_rolled_back_677','idempotent',false,'uid514_processed',false,'production_writes',false,'rollback_available',true);
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_uid514_recovery_677(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_uid514_recovery_677(text) TO authenticated;

DO $history$
BEGIN
  INSERT INTO public.pdc_uid514_recovery_history_677(
    event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,
    mailbox_id,mailbox_key,mailbox_address,mailbox_folder,mailbox_uidvalidity,mailbox_uid,recovery_event_id,parent_source_hash,all_attachment_hashes,pdf_hashes,job_card_sha256,observed_mime_part_count,retained_authenticated_attachment_count,all_mime_parts_retained,
    before_state,after_state,task_enabled,mailbox_contacted,uid514_processed,production_writes,rollback_contract)
  SELECT encode(extensions.digest(convert_to('pdc-staging-677-uid514-exact-recovery-successor|forward|25751401','UTF8'),'sha256'),'hex'),'forward_uid514_recovery','20260827110000','20260827111000',actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,
    mailbox_id,mailbox_key,mailbox_address,mailbox_folder,mailbox_uidvalidity,mailbox_uid,recovery_event_id,parent_source_hash,all_attachment_hashes,pdf_hashes,job_card_sha256,7,4,true,
    jsonb_build_object('forward_control_installed',true,'canonical_intake_created',false,'authorization_created',false,'claim_import_performed',false,'reviewed_typed_path','enqueue_pdc_uid514_recovery_677'),
    jsonb_build_object('enabled',enabled,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false),false,false,false,false,
    'Forward control only; exact retained evidence is created later by the authenticated pdc-emails typed recovery call; no UID514 or vehicle action occurs during migration'
  FROM public.pdc_uid514_recovery_controls_677 WHERE singleton;
END
$history$;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_uid514_recovery_controls_677 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND jwt_role='authenticated' AND server_application_role='importer' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_uidvalidity=1 AND mailbox_uid=514 AND recovery_event_id=25751401 AND parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_history_677 WHERE event_kind='forward_uid514_recovery')<>1
     OR NOT has_function_privilege('authenticated','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute')
     OR NOT has_function_privilege('authenticated','public.admin_rollback_pdc_uid514_recovery_677(text)','execute')
     OR NOT has_function_privilege('authenticated','public.claim_pdc_uid514_recovery_257(text,integer)','execute')
     OR has_function_privilege('anon','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute')
     OR has_function_privilege('service_role','public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)','execute')
     OR has_function_privilege('anon','public.claim_pdc_uid514_recovery_257(text,integer)','execute')
     OR has_function_privilege('service_role','public.claim_pdc_uid514_recovery_257(text,integer)','execute')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_uid514_recovery_history_677'::regclass) IS DISTINCT FROM true
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_uid514_recovery_controls_677'::regclass) IS DISTINCT FROM true
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_uid514_recovery_enqueue_capabilities_677'::regclass) IS DISTINCT FROM true
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
     OR (SELECT count(*) FROM public.pdc_uid514_attachment_selection_673 WHERE recovery_event_id=25751401)<>0
     OR (SELECT count(*) FROM public.vehicles WHERE stock_number='13016925')<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR position('pdc_uid514_recovery_enqueue_capability_677' IN pg_get_functiondef('public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure))=0
     OR position('pdc_uid514_recovery_claim_enabled_677' IN pg_get_functiondef('public.claim_pdc_uid514_recovery_257(text,integer)'::regprocedure))=0
  THEN RAISE EXCEPTION 'PDC_677_UID514_RECOVERY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827111000','677_uid514_exact_recovery_successor',ARRAY[
 'Require exact applied 676 predecessor plus exact 674 scope/runtime, enqueue, authorize and claim function hashes and absent Production sentinel',
 'Bind only actor df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b, authenticated JWT, importer role, exact gateway/release/source/manifest/planner/trust and one pdc_pmb_email Gmail staging mailbox',
 'Bind only Inbox UIDVALIDITY 1 UID 514 recovery event 25751401 and parent source hash 440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280',
 'Require the exact seven retained MIME-part hashes, four verified PDF hashes and Job Card hash 9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4 through a reviewed typed enqueue path',
 'Permit only the exact authenticated typed recovery RPC to mint a transaction-scoped capability consumed once by the existing enqueue trigger; generic sub-515 and adjacent UID paths remain denied',
 'Create canonical intake/attachment metadata and the existing 257 authorization atomically, preserve immutable provenance, and permit one exact replay without duplicate effects',
 'Gate the existing UID514 claim on the exact enabled recovery control and provide Administrator rollback that disables future enqueue/claim without deleting evidence',
 'Keep successors 670-676, the sealed .44 release, task, mailbox flags, vehicles, outbound email and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
