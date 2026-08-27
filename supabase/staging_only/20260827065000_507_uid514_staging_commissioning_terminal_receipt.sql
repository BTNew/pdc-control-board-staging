-- STAGING ONLY 507: record the reviewed UID514 commissioning terminal
-- receipt required by the frozen VerifyOnly preflight. This is not mailbox
-- evidence and does not claim physical, vehicle, attachment or mail work.
-- Existing dedicated identities continue through PDC_314_MONITOR_DEDICATED_IDENTITY_REQUIRED
-- via the unchanged pdc_monitor_actor_scope() fallback.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-507-uid514-commissioning-terminal',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_reader_hash text; v_scope_hash text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_reader_hash FROM pg_proc p WHERE p.oid='public.read_pdc_uid514_transaction_receipt_257(integer)'::regprocedure;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash FROM pg_proc p WHERE p.oid='public.pdc_monitor_actor_scope()'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827064000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827064000' AND name='506_allow_contained_sales_uid514_receipt_read')<>1
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827064000')<>0
    OR (SELECT count(*) FROM public.pdc_monitor_runtime_binding_compatibility_history_505 WHERE event_kind='forward_project' AND reconciliation_id='0c53cb93-bda2-4d02-90db-4c1b96cc7896')<>1
    OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256 IS NULL AND semantic_planner_trust_receipt_sha256 IS NULL AND semantic_planner_commissioned_at IS NULL)<>1
    OR v_reader_hash<>'fb326a1b0f01bc66fcee0228d138c14c74fd29ba16d2d46c79f50b09e8fbb366'
    OR v_scope_hash<>'55b6e195304992cf4a453d78f628d2591964c343317461b96c51e1df04aa6485'
    OR to_regclass('public.pdc_uid514_staging_commissioning_controls_507') IS NOT NULL
    OR to_regclass('public.pdc_uid514_staging_commissioning_terminal_receipts_507') IS NOT NULL
    OR to_regclass('public.pdc_uid514_staging_commissioning_history_507') IS NOT NULL
    OR to_regprocedure('public.admin_rollback_pdc_uid514_staging_commissioning_507(text)') IS NOT NULL
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827065000')<>0
 THEN RAISE EXCEPTION 'PDC_507_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_uid514_staging_commissioning_controls_507(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton), enabled boolean NOT NULL DEFAULT true,
 reconciliation_id uuid NOT NULL, actor_id uuid NOT NULL, gateway_instance_id text NOT NULL,
 release_name text NOT NULL, source_sha text NOT NULL, source_tree_sha text NOT NULL,
 manifest_sha256 text NOT NULL, archive_sha256 text NOT NULL,
 changed_by uuid, changed_by_email text, changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO public.pdc_uid514_staging_commissioning_controls_507(singleton,enabled,reconciliation_id,actor_id,gateway_instance_id,release_name,source_sha,source_tree_sha,manifest_sha256,archive_sha256)
VALUES(true,true,'0c53cb93-bda2-4d02-90db-4c1b96cc7896','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','8981540501bc629e189c39c9ea8a9adf3165d397','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90');
ALTER TABLE public.pdc_uid514_staging_commissioning_controls_507 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_staging_commissioning_controls_507 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_staging_commissioning_controls_507 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_uid514_staging_commissioning_terminal_receipts_507(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), recovery_event_id integer NOT NULL UNIQUE CHECK(recovery_event_id=25751401),
 actor_id uuid NOT NULL, gateway_instance_id text NOT NULL, release_name text NOT NULL,
 source_sha text NOT NULL, source_tree_sha text NOT NULL, manifest_sha256 text NOT NULL, archive_sha256 text NOT NULL,
 mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'), mailbox_folder text NOT NULL CHECK(mailbox_folder='Inbox'),
 mailbox_uidvalidity bigint NOT NULL CHECK(mailbox_uidvalidity=1), mailbox_uid bigint NOT NULL CHECK(mailbox_uid=514),
 terminal_status text NOT NULL CHECK(terminal_status='staging_commissioned'), synthetic_staging_commissioning boolean NOT NULL CHECK(synthetic_staging_commissioning),
 physical_mailbox_fetch boolean NOT NULL CHECK(NOT physical_mailbox_fetch), mailbox_flags_changed boolean NOT NULL CHECK(NOT mailbox_flags_changed),
 vehicle_operations integer NOT NULL DEFAULT 0 CHECK(vehicle_operations=0), operation_lines integer NOT NULL DEFAULT 0 CHECK(operation_lines=0),
 operational boolean NOT NULL DEFAULT false CHECK(NOT operational), activation_ready boolean NOT NULL DEFAULT false CHECK(NOT activation_ready),
 writer_active boolean NOT NULL DEFAULT false CHECK(NOT writer_active), planner_commissioned boolean NOT NULL DEFAULT false CHECK(NOT planner_commissioned),
 production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
INSERT INTO public.pdc_uid514_staging_commissioning_terminal_receipts_507(recovery_event_id,actor_id,gateway_instance_id,release_name,source_sha,source_tree_sha,manifest_sha256,archive_sha256,mailbox_address,mailbox_folder,mailbox_uidvalidity,mailbox_uid,terminal_status,synthetic_staging_commissioning,physical_mailbox_fetch,mailbox_flags_changed,vehicle_operations,operation_lines)
VALUES(25751401,'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','8981540501bc629e189c39c9ea8a9adf3165d397','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90','pmbcontroller@gmail.com','Inbox',1,514,'staging_commissioned',true,false,false,0,0);
ALTER TABLE public.pdc_uid514_staging_commissioning_terminal_receipts_507 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_staging_commissioning_terminal_receipts_507 FORCE ROW LEVEL SECURITY;

CREATE TABLE public.pdc_uid514_staging_commissioning_history_507(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind IN ('forward_commissioning','rollback')),
 reconciliation_id uuid NOT NULL, terminal_receipt_id uuid NOT NULL, actor_id uuid NOT NULL,
 gateway_instance_id text NOT NULL, release_name text NOT NULL, source_sha text NOT NULL, source_tree_sha text NOT NULL,
 manifest_sha256 text NOT NULL, archive_sha256 text NOT NULL, before_control jsonb NOT NULL, after_control jsonb NOT NULL,
 operational boolean NOT NULL DEFAULT false CHECK(NOT operational), activation_ready boolean NOT NULL DEFAULT false CHECK(NOT activation_ready),
 writer_active boolean NOT NULL DEFAULT false CHECK(NOT writer_active), planner_commissioned boolean NOT NULL DEFAULT false CHECK(NOT planner_commissioned),
 production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes), performed_by uuid, performed_by_email text,
 rollback_contract text NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_uid514_staging_commissioning_history_immutable_507()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_507_COMMISSIONING_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_uid514_staging_commissioning_history_immutable_507
BEFORE UPDATE OR DELETE ON public.pdc_uid514_staging_commissioning_history_507
FOR EACH ROW EXECUTE FUNCTION public.pdc_uid514_staging_commissioning_history_immutable_507();
ALTER TABLE public.pdc_uid514_staging_commissioning_history_507 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_staging_commissioning_history_507 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_staging_commissioning_history_507 FROM public,anon,authenticated,service_role;
REVOKE ALL ON public.pdc_uid514_staging_commissioning_terminal_receipts_507 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.read_pdc_uid514_transaction_receipt_257(p_recovery_event_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $reader$
declare
 v_actor_id uuid:=auth.uid();
 v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
 v_compat_enabled boolean;
 s jsonb;
 v_auth public.pdc_uid514_recovery_authorizations_257%rowtype;
 v_receipt public.pdc_jobcard_attachment_import_receipts%rowtype;
 v_terminal public.pdc_uid514_staging_commissioning_terminal_receipts_507%rowtype;
begin
 if p_recovery_event_id<>25751401 then raise exception 'PDC_261_UID514_SCOPE_INVALID' using errcode='22023';end if;

 if public.pdc_monitor_staging_guard()
    and v_actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid then
  select * into v_binding from public.pdc_monitor_runtime_bindings_255 where singleton;
  select enabled into v_compat_enabled from public.pdc_monitor_uid514_reader_compatibility_controls_506 where singleton;
  if v_compat_enabled is distinct from true then
   raise exception 'PDC_506_READER_COMPATIBILITY_DISABLED' using errcode='55000';
  end if;
  if v_actor_email<>'sales@broometoyota.com.au'
     or coalesce(auth.jwt()->>'role','')<>'authenticated'
     or not exists(select 1 from auth.users u where u.id=v_actor_id and lower(u.email)=v_actor_email and coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor')
     or (select count(*) from public.pdc_user_roles r where r.auth_user_id=v_actor_id and lower(r.email)=v_actor_email and r.active and r.account_status='approved' and r.role::text='viewer')<>1
     or (select count(*) from public.pdc_user_roles r where r.auth_user_id=v_actor_id and r.active)<>1
     or (select count(*) from public.pdc_monitor_stage_activation_writers w where w.active and w.revoked_at is null)<>0
     or exists(select 1 from public.pdc_auditor_worker_identities w where w.auth_user_id=v_actor_id and w.active)
     or exists(select 1 from public.pdc_auditor_user_dealer_scopes s0 where s0.auth_user_id=v_actor_id and s0.active)
     or exists(select 1 from public.pdc_auditor_executor_identities e where e.auth_user_id=v_actor_id and e.active and e.expires_at>clock_timestamp())
     or exists(select 1 from public.pdc_auditor_service_identities_225 s0 where s0.auth_user_id=v_actor_id and s0.active)
     or not exists(select 1 from public.pdc_monitor_runtime_binding_compatibility_history_505 h where h.event_kind='forward_project' and h.reconciliation_id='0c53cb93-bda2-4d02-90db-4c1b96cc7896'::uuid and h.actor_id=v_actor_id and h.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' and h.release_name='pdc-monitor-staging-m502-2026.08.44' and h.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' and h.source_tree_sha='8981540501bc629e189c39c9ea8a9adf3165d397' and h.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' and h.archive_sha256='4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90' and not h.operational and not h.activation_ready and not h.writer_active and not h.planner_commissioned and not h.production_writes)
     or not exists(select 1 from public.pdc_monitor_contained_binding_reconciliations_504 r0 where r0.reconciliation_id='0c53cb93-bda2-4d02-90db-4c1b96cc7896'::uuid and r0.singleton and r0.event_kind='forward_reconcile' and r0.actor_id=v_actor_id and r0.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' and r0.release_name='pdc-monitor-staging-m502-2026.08.44' and r0.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' and r0.source_tree_sha='8981540501bc629e189c39c9ea8a9adf3165d397' and r0.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' and r0.archive_sha256='4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90' and r0.migration_head=503 and r0.mode='contained' and not r0.operational and not r0.activation_ready and not r0.writer_active and not r0.planner_commissioned and not r0.production_writes)
     or not exists(select 1 from public.pdc_monitor_runtime_bindings_255 b0 where b0.singleton and b0.actor_id=v_actor_id and b0.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' and b0.release_name='pdc-monitor-staging-m502-2026.08.44' and b0.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' and b0.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' and b0.semantic_planner_sha256 is null and b0.semantic_planner_trust_receipt_sha256 is null and b0.semantic_planner_commissioned_at is null)
  then
   raise exception 'PDC_506_RECONCILIATION_OR_BINDING_DRIFT' using errcode='55000';
  end if;
  s:=jsonb_build_object('ok',true,'user_id',v_actor_id,'email',v_actor_email,'role','viewer');
  select r.* into v_terminal
  from public.pdc_uid514_staging_commissioning_terminal_receipts_507 r
  join public.pdc_uid514_staging_commissioning_controls_507 c on c.singleton and c.enabled
  where r.recovery_event_id=25751401
    and r.actor_id=v_actor_id
    and r.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
    and r.release_name='pdc-monitor-staging-m502-2026.08.44'
    and r.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'
    and r.source_tree_sha='8981540501bc629e189c39c9ea8a9adf3165d397'
    and r.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
    and r.archive_sha256='4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90'
    and r.synthetic_staging_commissioning
    and not r.physical_mailbox_fetch
    and not r.mailbox_flags_changed
    and r.vehicle_operations=0 and r.operation_lines=0
    and not r.operational and not r.activation_ready and not r.writer_active
    and not r.planner_commissioned and not r.production_writes;
  if found then
   return jsonb_build_object('ok',true,'code','uid514_staging_commissioned_terminal','terminal',true,
    'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox',
    'uidvalidity',1,'uid',514,'canonical_receipt_id',v_terminal.receipt_id,
    'vehicle_id',null,'vehicle_version',null,'synthetic_staging_commissioning',true,
    'physical_mailbox_fetch',false,'mailbox_flags_changed',false,'vehicle_operations',0,
    'operation_lines',0,'operational',false,'activation_ready',false,'writer_active',false,
    'planner_commissioned',false,'production_writes',false);
  end if;
 else
  s:=public.pdc_monitor_actor_scope();
 end if;
 select * into v_auth from public.pdc_uid514_recovery_authorizations_257 where recovery_event_id=25751401;
 if not found then return jsonb_build_object('ok',true,'code','uid514_authorization_pending','terminal',false,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514);end if;
 select * into v_receipt from public.pdc_jobcard_attachment_import_receipts where actor_id=(s->>'user_id')::uuid and intake_id=v_auth.intake_id and parent_source_hash=v_auth.parent_source_hash and attachment_source_hash=v_auth.qualifying_attachment_sha256;
 return jsonb_build_object('ok',true,'code',case when found then 'uid514_receipt_terminal' else 'uid514_receipt_pending' end,'terminal',found,'recovery_event_id',25751401,'mailbox',v_auth.mailbox_address,'folder',v_auth.mailbox_folder,'uidvalidity',1,'uid',514,'parent_source_hash',v_auth.parent_source_hash,'canonical_receipt_id',case when found then v_receipt.receipt_id else null end,'vehicle_id',case when found then v_receipt.vehicle_id else null end,'vehicle_version',case when found then v_receipt.vehicle_version else null end);
end
$reader$;

REVOKE ALL ON FUNCTION public.read_pdc_uid514_transaction_receipt_257(integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_uid514_transaction_receipt_257(integer) TO authenticated;

CREATE FUNCTION public.admin_rollback_pdc_uid514_staging_commissioning_507(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions
AS $rollback$
DECLARE v_admin_id uuid:=auth.uid(); v_admin_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_admin_count integer; v_control public.pdc_uid514_staging_commissioning_controls_507%rowtype; v_receipt public.pdc_uid514_staging_commissioning_terminal_receipts_507%rowtype; v_existing public.pdc_uid514_staging_commissioning_history_507%rowtype; v_before jsonb; v_after jsonb; v_event_key text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_admin_id IS NULL OR v_admin_email='' OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_507_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
 SELECT count(*) INTO v_admin_count FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id AND lower(coalesce(u.email,''))=v_admin_email WHERE r.auth_user_id=v_admin_id AND lower(r.email)=v_admin_email AND r.active AND r.account_status='approved' AND r.role::text='administrator';
 IF v_admin_count<>1 THEN RAISE EXCEPTION 'PDC_507_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-507-uid514-commissioning-terminal',0));
 SELECT * INTO v_control FROM public.pdc_uid514_staging_commissioning_controls_507 WHERE singleton FOR UPDATE;
 SELECT * INTO v_receipt FROM public.pdc_uid514_staging_commissioning_terminal_receipts_507 WHERE recovery_event_id=25751401;
 IF NOT FOUND OR v_control.reconciliation_id<>'0c53cb93-bda2-4d02-90db-4c1b96cc7896'::uuid OR v_control.actor_id<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_control.source_sha<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b' OR v_control.manifest_sha256<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' THEN RAISE EXCEPTION 'PDC_507_TERMINAL_RECEIPT_SCOPE_MISMATCH' USING errcode='55000'; END IF;
 v_event_key:=encode(extensions.digest(convert_to(concat_ws('|','pdc-staging-507-uid514-commissioning-terminal','rollback',v_receipt.receipt_id::text),'UTF8'),'sha256'),'hex');
 SELECT * INTO v_existing FROM public.pdc_uid514_staging_commissioning_history_507 WHERE event_key=v_event_key;
 IF FOUND THEN IF v_control.enabled THEN RAISE EXCEPTION 'PDC_507_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF; RETURN jsonb_build_object('ok',true,'code','uid514_staging_commissioning_rolled_back_507','idempotent',true,'history_id',v_existing.history_id,'terminal',false,'operational',false,'activation_ready',false,'writer_active',false,'planner_commissioned',false,'production_writes',false); END IF;
 IF NOT v_control.enabled THEN RAISE EXCEPTION 'PDC_507_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
 v_before:=to_jsonb(v_control); UPDATE public.pdc_uid514_staging_commissioning_controls_507 SET enabled=false,changed_by=v_admin_id,changed_by_email=v_admin_email,changed_at=clock_timestamp() WHERE singleton RETURNING * INTO v_control; v_after:=to_jsonb(v_control);
 INSERT INTO public.pdc_uid514_staging_commissioning_history_507(event_key,event_kind,reconciliation_id,terminal_receipt_id,actor_id,gateway_instance_id,release_name,source_sha,source_tree_sha,manifest_sha256,archive_sha256,before_control,after_control,operational,activation_ready,writer_active,planner_commissioned,production_writes,performed_by,performed_by_email,rollback_contract) VALUES(v_event_key,'rollback',v_control.reconciliation_id,v_receipt.receipt_id,v_receipt.actor_id,v_receipt.gateway_instance_id,v_receipt.release_name,v_receipt.source_sha,v_receipt.source_tree_sha,v_receipt.manifest_sha256,v_receipt.archive_sha256,v_before,v_after,false,false,false,false,false,v_admin_id,v_admin_email,'forward migration only; commissioning switch disabled');
 INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('update','pdc_uid514_staging_commissioning_controls_507',v_receipt.receipt_id,v_admin_id,v_admin_email,v_before,v_after,jsonb_build_object('event_type','uid514_staging_commissioning_rolled_back_507','reason',btrim(p_reason),'physical_mailbox_fetch',false,'vehicle_operations',0,'operation_lines',0,'production_untouched',true));
 RETURN jsonb_build_object('ok',true,'code','uid514_staging_commissioning_rolled_back_507','idempotent',false,'history_id',v_event_key,'terminal',false,'operational',false,'activation_ready',false,'writer_active',false,'planner_commissioned',false,'production_writes',false,'rollback_available',true);
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_uid514_staging_commissioning_507(text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_uid514_staging_commissioning_507(text) TO authenticated;

DO $history$
DECLARE v_control jsonb; v_receipt public.pdc_uid514_staging_commissioning_terminal_receipts_507%rowtype;
BEGIN
 SELECT to_jsonb(c) INTO v_control FROM public.pdc_uid514_staging_commissioning_controls_507 c WHERE singleton;
 SELECT * INTO v_receipt FROM public.pdc_uid514_staging_commissioning_terminal_receipts_507 WHERE recovery_event_id=25751401;
 INSERT INTO public.pdc_uid514_staging_commissioning_history_507(event_key,event_kind,reconciliation_id,terminal_receipt_id,actor_id,gateway_instance_id,release_name,source_sha,source_tree_sha,manifest_sha256,archive_sha256,before_control,after_control,operational,activation_ready,writer_active,planner_commissioned,production_writes,performed_by,performed_by_email,rollback_contract) VALUES(encode(extensions.digest(convert_to('pdc-staging-507-uid514-commissioning-terminal|forward|25751401','UTF8'),'sha256'),'hex'),'forward_commissioning',(v_control->>'reconciliation_id')::uuid,v_receipt.receipt_id,v_receipt.actor_id,v_receipt.gateway_instance_id,v_receipt.release_name,v_receipt.source_sha,v_receipt.source_tree_sha,v_receipt.manifest_sha256,v_receipt.archive_sha256,'{"enabled":false}'::jsonb,v_control,false,false,false,false,false,null,null,'forward migration only; commissioning switch can be disabled by guarded admin rollback');
END
$history$;

DO $post$
DECLARE v_reader_hash text; v_scope_hash text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_reader_hash FROM pg_proc p WHERE p.oid='public.read_pdc_uid514_transaction_receipt_257(integer)'::regprocedure;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash FROM pg_proc p WHERE p.oid='public.pdc_monitor_actor_scope()'::regprocedure;
 IF v_reader_hash='fb326a1b0f01bc66fcee0228d138c14c74fd29ba16d2d46c79f50b09e8fbb366' OR v_scope_hash<>'55b6e195304992cf4a453d78f628d2591964c343317461b96c51e1df04aa6485' OR NOT has_function_privilege('authenticated','public.read_pdc_uid514_transaction_receipt_257(integer)','execute') OR has_function_privilege('anon','public.read_pdc_uid514_transaction_receipt_257(integer)','execute') OR has_function_privilege('service_role','public.read_pdc_uid514_transaction_receipt_257(integer)','execute') OR NOT has_function_privilege('authenticated','public.admin_rollback_pdc_uid514_staging_commissioning_507(text)','execute') OR has_function_privilege('anon','public.admin_rollback_pdc_uid514_staging_commissioning_507(text)','execute') OR has_function_privilege('service_role','public.admin_rollback_pdc_uid514_staging_commissioning_507(text)','execute') OR NOT (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_staging_commissioning_controls_507'::regclass) OR NOT (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_staging_commissioning_terminal_receipts_507'::regclass) OR NOT (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_uid514_staging_commissioning_history_507'::regclass) OR (select count(*) from public.pdc_uid514_staging_commissioning_terminal_receipts_507 where recovery_event_id=25751401 and synthetic_staging_commissioning and not physical_mailbox_fetch and not mailbox_flags_changed and vehicle_operations=0 and operation_lines=0 and not operational and not activation_ready and not writer_active and not planner_commissioned and not production_writes)<>1 OR (select count(*) from public.pdc_uid514_staging_commissioning_history_507 where event_kind='forward_commissioning')<>1 THEN RAISE EXCEPTION 'PDC_507_TERMINAL_RECEIPT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827065000','507_uid514_staging_commissioning_terminal_receipt',ARRAY[
 'Create only the exact contained UID514 staging commissioning terminal receipt for recovery_event_id 25751401 from reviewed constants',
 'Explicitly record no physical mailbox fetch, no mailbox flag change, zero vehicle operations and zero operation lines',
 'Preserve the frozen read_pdc_uid514_transaction_receipt_257(integer) signature and all existing dedicated identity paths',
 'Require exact 504 reconciliation, 505 compatibility binding and 506 reader compatibility before terminal readback',
 'Preserve forced-RLS immutable receipt/history, authenticated-only reader and guarded admin rollback',
 'Writer, mailbox, monitor, planner, operational and Production state remain inactive and untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
