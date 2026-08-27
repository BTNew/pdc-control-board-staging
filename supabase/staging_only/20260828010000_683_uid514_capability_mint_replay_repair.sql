-- STAGING ONLY 683: always mint the exact private enqueue capability.
-- 682 proved the trigger consumes a private capability correctly. This
-- successor makes the 677 typed recovery call mint that capability on every
-- exact invocation, including a replay where the prior authorization exists;
-- the row is consumed or marked consumed before return. No UID514/vehicle
-- mutation is performed by this migration.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-683-uid514-capability-mint-replay-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE e text; h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO e FROM pg_proc p WHERE p.oid='public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.pdc_uid514_recovery_enqueue_capability_677(uuid)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828000000' AND name='682_uid514_capability_consumption_repair')<>1 OR to_regclass('public.pdc_uid514_capability_mint_replay_repair_history_683') IS NOT NULL OR e<>'a86a2e0c9f17a3f568999fee80ee7d6d233a45b7a2a8b72a57a913136d11f7d4' OR h<>'828d1bd6db27521ed0e6749e2b24a43edc39461f516eb30706bab156f2a0b252' OR (SELECT count(*) FROM public.pdc_uid514_recovery_controls_677 WHERE singleton AND enabled AND recovery_event_id=25751401 AND mailbox_uidvalidity=1 AND mailbox_uid=514 AND parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1 OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0 OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0 THEN RAISE EXCEPTION 'PDC_683_EXACT_682_OR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;
CREATE TABLE public.pdc_uid514_capability_mint_replay_repair_history_683(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE, event_kind text NOT NULL CHECK(event_kind='forward_capability_mint_replay_repair'), predecessor_head text NOT NULL CHECK(predecessor_head='20260828000000'), successor_head text NOT NULL CHECK(successor_head='20260828010000'), actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'), actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'), jwt_role text NOT NULL CHECK(jwt_role='authenticated'), server_application_role text NOT NULL CHECK(server_application_role='importer'), gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'), release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'), source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'), manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'), planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'), trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'), recovery_event_id integer NOT NULL CHECK(recovery_event_id=25751401), parent_source_hash text NOT NULL CHECK(parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280'), predecessor_enqueue_sha256 text NOT NULL CHECK(predecessor_enqueue_sha256='a86a2e0c9f17a3f568999fee80ee7d6d233a45b7a2a8b72a57a913136d11f7d4'), predecessor_helper_sha256 text NOT NULL CHECK(predecessor_helper_sha256='828d1bd6db27521ed0e6749e2b24a43edc39461f516eb30706bab156f2a0b252'), successor_enqueue_sha256 text NOT NULL CHECK(successor_enqueue_sha256~'^[a-f0-9]{64}$'), before_definition text NOT NULL, after_definition text NOT NULL, observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7), retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4), task_enabled boolean NOT NULL CHECK(NOT task_enabled), mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted), uid514_processed boolean NOT NULL CHECK(NOT uid514_processed), production_writes boolean NOT NULL CHECK(NOT production_writes), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_uid514_capability_mint_replay_repair_history_immutable_683() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_683_CAPABILITY_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_uid514_capability_mint_replay_repair_history_immutable_683 BEFORE UPDATE OR DELETE ON public.pdc_uid514_capability_mint_replay_repair_history_683 FOR EACH ROW EXECUTE FUNCTION public.pdc_uid514_capability_mint_replay_repair_history_immutable_683();
ALTER TABLE public.pdc_uid514_capability_mint_replay_repair_history_683 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_capability_mint_replay_repair_history_683 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_capability_mint_replay_repair_history_683 FROM public,anon,authenticated,service_role,pdc_email_monitor;
DO $repair$
DECLARE b text; n text; h text; k text:=encode(extensions.digest(convert_to('pdc-staging-683-uid514-capability-mint-replay-repair|forward|25751401','UTF8'),'sha256'),'hex');
BEGIN
 SELECT pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure) INTO b;
 n:=replace(b,$old$  IF NOT v_existing THEN
    INSERT INTO public.pdc_uid514_recovery_enqueue_capabilities_677(token_hash,actor_id,gateway_instance_id,recovery_event_id,mailbox_id)
    VALUES(encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex'),auth.uid(),'pdc-monitor-staging-sales-uid509-v1',25751401,'12fe383d-5c1e-5801-96e4-f67cf3e3bb57');
    PERFORM set_config('pdc.uid514.recovery_token',v_token,true);
  END IF;$old$,$new$  INSERT INTO public.pdc_uid514_recovery_enqueue_capabilities_677(token_hash,actor_id,gateway_instance_id,recovery_event_id,mailbox_id)
  VALUES(encode(extensions.digest(convert_to(v_token,'UTF8'),'sha256'),'hex'),auth.uid(),'pdc-monitor-staging-sales-uid509-v1',25751401,'12fe383d-5c1e-5801-96e4-f67cf3e3bb57');$new$);
 IF n=b THEN RAISE EXCEPTION 'PDC_683_ENQUEUE_SOURCE_DRIFT' USING errcode='55000'; END IF;
 EXECUTE n;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure;
 INSERT INTO public.pdc_uid514_capability_mint_replay_repair_history_683(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,recovery_event_id,parent_source_hash,predecessor_enqueue_sha256,predecessor_helper_sha256,successor_enqueue_sha256,before_definition,after_definition,observed_mime_part_count,retained_authenticated_attachment_count,task_enabled,mailbox_contacted,uid514_processed,production_writes) VALUES(k,'forward_capability_mint_replay_repair','20260828000000','20260828010000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',25751401,'440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280','a86a2e0c9f17a3f568999fee80ee7d6d233a45b7a2a8b72a57a913136d11f7d4','828d1bd6db27521ed0e6749e2b24a43edc39461f516eb30706bab156f2a0b252',h,b,n,7,4,false,false,false,false);
END
$repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_uid514_capability_mint_replay_repair_history_683 WHERE event_kind='forward_capability_mint_replay_repair')<>1 OR position('IF NOT v_existing THEN' IN pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure))>0 OR position('INSERT INTO public.pdc_uid514_recovery_enqueue_capabilities_677' IN pg_get_functiondef('public.enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)'::regprocedure))=0 OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0 OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0 OR (SELECT count(*) FROM public.vehicles WHERE stock_number='13016925')<>0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_683_CAPABILITY_REPLAY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828010000','683_uid514_capability_mint_replay_repair',ARRAY['Require exact 682 predecessor state and exact enqueue/helper hashes','Mint one private capability for every exact typed UID514 call so first enqueue and idempotent replay both traverse the reviewed trigger path','Record immutable forced-RLS repair history and preserve exact actor/binding/mailbox/planner/trust, seven MIME parts/four PDFs, task disabled, UID514 unprocessed and Production untouched']);
NOTIFY pgrst,'reload schema';
COMMIT;
