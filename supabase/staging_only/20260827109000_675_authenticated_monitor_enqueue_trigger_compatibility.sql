-- STAGING ONLY 675: allow the exact authenticated .44 actor to enqueue
-- through the already-active exact staging mailbox while the automatic pilot
-- remains disabled. This repairs the external dispatch seam only; it does not
-- weaken RLS/ACLs, enable a task, fetch mail, process UID514, mutate vehicles,
-- send email, or contact Production.
--
-- Exact predecessor/function/runtime anchors:
--   674 scope p.prosrc: 4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629
--   674 runtime helper p.prosrc: de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351
--   pilot trigger predecessor p.prosrc: edd514bd5512fec84c164493bd8ad9df3b452e7d916760424f2f9da0eba5cd51
--   sealed .44 runner: 52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd
--   external adapter: a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-675-authenticated-monitor-enqueue-trigger-compatibility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_scope_hash text;
  v_runtime_hash text;
  v_trigger_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash
    FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_active_scope_674(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_runtime_hash
    FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_runtime_authorized_502(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_trigger_hash
    FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827108000' AND name='674_authenticated_monitor_mailbox_activation_transition')<>1
     OR to_regclass('public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675') IS NOT NULL
     OR to_regclass('public.pdc_email_monitor_authenticated_enqueue_trigger_history_675') IS NOT NULL
     OR to_regprocedure('public.admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675(text)') IS NOT NULL
     OR v_scope_hash<>'4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629'
     OR v_runtime_hash<>'de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351'
     OR v_trigger_hash<>'edd514bd5512fec84c164493bd8ad9df3b452e7d916760424f2f9da0eba5cd51'
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND enabled AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND mailbox_address='pmbcontroller@gmail.com' AND provider='gmail' AND test_mode)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND active AND test_mode)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
  THEN RAISE EXCEPTION 'PDC_675_EXACT_674_PREDECESSOR_FUNCTION_OR_MAILBOX_STATE_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true CHECK(enabled),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  predecessor_trigger_sha256 text NOT NULL CHECK(predecessor_trigger_sha256='edd514bd5512fec84c164493bd8ad9df3b452e7d916760424f2f9da0eba5cd51'),
  trigger_sha256 text NOT NULL CHECK(trigger_sha256~'^[a-f0-9]{64}$'),
  active_mailbox_id uuid NOT NULL CHECK(active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  active_mailbox_address text NOT NULL CHECK(active_mailbox_address='pmbcontroller@gmail.com'),
  pilot_remains_disabled boolean NOT NULL DEFAULT true CHECK(pilot_remains_disabled),
  task_enabled boolean NOT NULL DEFAULT false CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL DEFAULT false CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE TABLE public.pdc_email_monitor_authenticated_enqueue_trigger_history_675(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('forward_authenticated_enqueue_trigger','rollback')),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827108000'),
  successor_head text NOT NULL CHECK(successor_head='20260827109000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  predecessor_trigger_sha256 text NOT NULL,
  trigger_sha256 text NOT NULL,
  before_definition text NOT NULL,
  after_definition text NOT NULL,
  pilot_remains_disabled boolean NOT NULL CHECK(pilot_remains_disabled),
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  performed_by uuid,
  performed_by_email text,
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_email_monitor_authenticated_enqueue_trigger_history_immutable_675()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_675_AUTHENTICATED_ENQUEUE_TRIGGER_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_email_monitor_authenticated_enqueue_trigger_history_immutable_675
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_authenticated_enqueue_trigger_history_675
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_authenticated_enqueue_trigger_history_immutable_675();
ALTER TABLE public.pdc_email_monitor_authenticated_enqueue_trigger_history_675 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_enqueue_trigger_history_675 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_enqueue_trigger_history_675 FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $repair$
DECLARE
  v_before text;
  v_after text;
  v_replacement text;
  v_trigger_sha text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure) INTO v_before;
  IF position('pdc_monitor_authenticated_active_scope_674' IN v_before)>0 THEN RAISE EXCEPTION 'PDC_675_TRIGGER_ALREADY_REPAIRED' USING errcode='55000'; END IF;
  v_replacement:=E'  select * into p from public.pdc_email_monitor_pilot where singleton;\n'
    ||E'  if public.pdc_monitor_authenticated_active_scope_674(NULL) then\n'
    ||E'    if not m.active or not m.test_mode or lower(m.mailbox_address)<>''pmbcontroller@gmail.com'' or lower(m.provider)<>''gmail'' then raise exception ''pdc_monitor_mailbox_not_bound'' using errcode=''42501''; end if;\n'
    ||E'    if coalesce(new.provider_uid,'''')!~''^imap_uid:[0-9]+$'' or substring(new.provider_uid from ''^imap_uid:([0-9]+)$'')::bigint<515 then raise exception ''pdc_monitor_uid_before_active_floor'' using errcode=''42501''; end if;\n'
    ||E'    return new;\n'
    ||E'  end if;\n'
    ||E'  ';
  IF position('  select * into p from public.pdc_email_monitor_pilot where singleton;' IN v_before)=0 THEN RAISE EXCEPTION 'PDC_675_TRIGGER_SHAPE_MISMATCH' USING errcode='55000'; END IF;
  v_after:=replace(v_before,'  select * into p from public.pdc_email_monitor_pilot where singleton;'||chr(10),v_replacement);
  EXECUTE v_after;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_trigger_sha FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure;
  INSERT INTO public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675(actor_id,actor_email,jwt_role,gateway_instance_id,release_name,source_sha,manifest_sha256,predecessor_trigger_sha256,trigger_sha256,active_mailbox_id,active_mailbox_address)
  VALUES('df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','edd514bd5512fec84c164493bd8ad9df3b452e7d916760424f2f9da0eba5cd51',v_trigger_sha,'12fe383d-5c1e-5801-96e4-f67cf3e3bb57','pmbcontroller@gmail.com');
  INSERT INTO public.pdc_email_monitor_authenticated_enqueue_trigger_history_675(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,gateway_instance_id,release_name,source_sha,manifest_sha256,predecessor_trigger_sha256,trigger_sha256,before_definition,after_definition,pilot_remains_disabled,task_enabled,mailbox_contacted,uid514_processed,production_writes,rollback_contract)
  VALUES(encode(extensions.digest(convert_to('pdc-staging-675-authenticated-monitor-enqueue-trigger-compatibility|forward|pdc_pmb_email','UTF8'),'sha256'),'hex'),'forward_authenticated_enqueue_trigger','20260827108000','20260827109000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','edd514bd5512fec84c164493bd8ad9df3b452e7d916760424f2f9da0eba5cd51',v_trigger_sha,v_before,v_after,true,false,false,false,false,'Guarded trigger compatibility only; rollback is permitted only after the 674 exact mailbox rollback and restores the predecessor function definition from immutable history');
END
$repair$;

CREATE FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $rollback$
DECLARE
  v_admin uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_count integer;
  v_control public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675%rowtype;
  v_forward public.pdc_email_monitor_authenticated_enqueue_trigger_history_675%rowtype;
  v_existing public.pdc_email_monitor_authenticated_enqueue_trigger_history_675%rowtype;
  v_current text; v_before text; v_after text; v_event_key text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_admin IS NULL OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_675_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  SELECT count(*) INTO v_count FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id AND lower(u.email)=v_email WHERE r.auth_user_id=v_admin AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF v_count<>1 THEN RAISE EXCEPTION 'PDC_675_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  IF (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0 THEN RAISE EXCEPTION 'PDC_675_ROLLBACK_REQUIRES_MAILBOX_ROLLBACK' USING errcode='55000'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-675-authenticated-monitor-enqueue-trigger-compatibility',0));
  SELECT * INTO v_control FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_675_CONTROL_MISSING' USING errcode='55000'; END IF;
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-675-authenticated-monitor-enqueue-trigger-compatibility|rollback|pdc_pmb_email','UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing FROM public.pdc_email_monitor_authenticated_enqueue_trigger_history_675 WHERE event_key=v_event_key;
  IF FOUND THEN
    IF v_control.enabled THEN RAISE EXCEPTION 'PDC_675_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_authenticated_enqueue_trigger_rolled_back_675','idempotent',true,'history_id',v_existing.history_id,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false);
  END IF;
  SELECT * INTO v_forward FROM public.pdc_email_monitor_authenticated_enqueue_trigger_history_675 WHERE event_kind='forward_authenticated_enqueue_trigger';
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_675_FORWARD_HISTORY_MISSING' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure) INTO v_current;
  IF position('pdc_monitor_authenticated_active_scope_674' IN v_current)=0 THEN RAISE EXCEPTION 'PDC_675_TRIGGER_ROLLBACK_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  EXECUTE v_forward.before_definition;
  SELECT pg_get_functiondef('public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure) INTO v_after;
  UPDATE public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 SET enabled=false,changed_at=clock_timestamp() WHERE singleton;
  INSERT INTO public.pdc_email_monitor_authenticated_enqueue_trigger_history_675(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,gateway_instance_id,release_name,source_sha,manifest_sha256,predecessor_trigger_sha256,trigger_sha256,before_definition,after_definition,pilot_remains_disabled,task_enabled,mailbox_contacted,uid514_processed,production_writes,performed_by,performed_by_email,rollback_contract)
  VALUES(v_event_key,'rollback','20260827108000','20260827109000',v_control.actor_id,v_control.actor_email,'authenticated',v_control.gateway_instance_id,v_control.release_name,v_control.source_sha,v_control.manifest_sha256,v_control.predecessor_trigger_sha256,v_control.trigger_sha256,v_current,v_after,true,false,false,false,false,v_admin,v_email,'Restores exact predecessor pilot trigger only after 674 mailbox rollback; immutable history remains; no task, mailbox, UID514, vehicle, outbound email or Production action');
  RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_authenticated_enqueue_trigger_rolled_back_675','idempotent',false,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false,'rollback_available',true);
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675(text) TO authenticated;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND jwt_role='authenticated' AND active_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND active_mailbox_address='pmbcontroller@gmail.com' AND pilot_remains_disabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_history_675 WHERE event_kind='forward_authenticated_enqueue_trigger')<>1
     OR position('pdc_monitor_authenticated_active_scope_674' IN pg_get_functiondef('public.pdc_email_monitor_pilot_intake_guard_223()'::regprocedure))=0
     OR NOT has_function_privilege('authenticated','public.admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675(text)','execute')
     OR has_function_privilege('anon','public.admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675(text)','execute')
     OR has_function_privilege('service_role','public.admin_rollback_pdc_email_monitor_authenticated_enqueue_trigger_675(text)','execute')
     OR has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675','select')
     OR has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_enqueue_trigger_history_675','select')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_email_monitor_authenticated_enqueue_trigger_history_675'::regclass) IS DISTINCT FROM true
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_675_AUTHENTICATED_ENQUEUE_TRIGGER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827109000','675_authenticated_monitor_enqueue_trigger_compatibility',ARRAY[
  'Require exact applied 674 mailbox activation, exact 674 scope/runtime and predecessor pilot-trigger hashes, staging sentinel and absent Production sentinel',
  'Add one exact authenticated active-actor trigger branch for the exact active pdc_pmb_email staging mailbox and provider UID floor 515',
  'Keep the automatic pilot disabled and preserve all contained, low-UID, malformed, wrong-actor, anon/service_role and direct-DML denials',
  'Record immutable forced-RLS trigger definitions and provide Administrator rollback only after the exact mailbox transition is rolled back',
  'Keep task, mailbox fetch/flags, UID514, vehicles, outbound email and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
