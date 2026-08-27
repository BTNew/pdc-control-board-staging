-- STAGING ONLY 682: make the exact enqueue capability transaction-safe.
-- The 677 helper's custom-GUC token was not observable through the nested
-- security-definer enqueue trigger on the live path. This successor keeps the
-- capability row private and consumes the newest exact actor/mailbox/event row
-- directly, with no generic UID bypass. UID514 remains unprocessed here.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='90s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-682-uid514-capability-consumption-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE h text;
BEGIN
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.pdc_uid514_recovery_enqueue_capability_677(uuid)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR lower(coalesce(current_setting('app.environment',true),''))='production' OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827114000' AND name='679_uid514_recovery_event_key_repair')<>1 OR to_regclass('public.pdc_uid514_capability_consumption_repair_history_682') IS NOT NULL OR h<>'7b9fe1a47cf5a7bc610211de004fe4598b6ccacc31f72afeb6c88cdb4b5fe182' OR (SELECT count(*) FROM public.pdc_uid514_recovery_controls_677 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND recovery_event_id=25751401 AND parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280' AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1 OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0 OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0 THEN RAISE EXCEPTION 'PDC_682_EXACT_679_OR_HELPER_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;
CREATE TABLE public.pdc_uid514_capability_consumption_repair_history_682(
 history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), event_key text NOT NULL UNIQUE,
 event_kind text NOT NULL CHECK(event_kind='forward_capability_consumption_repair'), predecessor_head text NOT NULL CHECK(predecessor_head='20260827114000'), successor_head text NOT NULL CHECK(successor_head='20260828000000'),
 actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'), actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'), jwt_role text NOT NULL CHECK(jwt_role='authenticated'), server_application_role text NOT NULL CHECK(server_application_role='importer'), gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'), release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'), source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'), manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'), planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'), trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'), recovery_event_id integer NOT NULL CHECK(recovery_event_id=25751401), parent_source_hash text NOT NULL CHECK(parent_source_hash='440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280'), predecessor_helper_sha256 text NOT NULL CHECK(predecessor_helper_sha256='7b9fe1a47cf5a7bc610211de004fe4598b6ccacc31f72afeb6c88cdb4b5fe182'), successor_helper_sha256 text NOT NULL CHECK(successor_helper_sha256~'^[a-f0-9]{64}$'), before_definition text NOT NULL, after_definition text NOT NULL, observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7), retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4), task_enabled boolean NOT NULL CHECK(NOT task_enabled), mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted), uid514_processed boolean NOT NULL CHECK(NOT uid514_processed), production_writes boolean NOT NULL CHECK(NOT production_writes), created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_uid514_capability_consumption_repair_history_immutable_682() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_682_CAPABILITY_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_uid514_capability_consumption_repair_history_immutable_682 BEFORE UPDATE OR DELETE ON public.pdc_uid514_capability_consumption_repair_history_682 FOR EACH ROW EXECUTE FUNCTION public.pdc_uid514_capability_consumption_repair_history_immutable_682();
ALTER TABLE public.pdc_uid514_capability_consumption_repair_history_682 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_capability_consumption_repair_history_682 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_capability_consumption_repair_history_682 FROM public,anon,authenticated,service_role,pdc_email_monitor;
DO $repair$
DECLARE b text; n text; h text; k text:=encode(extensions.digest(convert_to('pdc-staging-682-uid514-capability-consumption-repair|forward|25751401','UTF8'),'sha256'),'hex');
BEGIN
 SELECT pg_get_functiondef('public.pdc_uid514_recovery_enqueue_capability_677(uuid)'::regprocedure) INTO b;
 n:=$fn$CREATE OR REPLACE FUNCTION public.pdc_uid514_recovery_enqueue_capability_677(p_mailbox_id uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $body$
DECLARE v_row public.pdc_uid514_recovery_enqueue_capabilities_677%rowtype;
BEGIN
  IF NOT public.pdc_monitor_authenticated_active_scope_674(NULL) OR p_mailbox_id<>'12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid THEN RETURN false; END IF;
  SELECT * INTO v_row FROM public.pdc_uid514_recovery_enqueue_capabilities_677 WHERE actor_id=auth.uid() AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND recovery_event_id=25751401 AND mailbox_id=p_mailbox_id AND consumed_at IS NULL ORDER BY created_at DESC,capability_id DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  UPDATE public.pdc_uid514_recovery_enqueue_capabilities_677 SET consumed_at=clock_timestamp() WHERE capability_id=v_row.capability_id;
  RETURN true;
END
$body$;$fn$;
 IF n=b THEN RAISE EXCEPTION 'PDC_682_HELPER_SOURCE_DRIFT' USING errcode='55000'; END IF;
 EXECUTE n;
 SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO h FROM pg_proc p WHERE p.oid='public.pdc_uid514_recovery_enqueue_capability_677(uuid)'::regprocedure;
 INSERT INTO public.pdc_uid514_capability_consumption_repair_history_682(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,recovery_event_id,parent_source_hash,predecessor_helper_sha256,successor_helper_sha256,before_definition,after_definition,observed_mime_part_count,retained_authenticated_attachment_count,task_enabled,mailbox_contacted,uid514_processed,production_writes) VALUES(k,'forward_capability_consumption_repair','20260827114000','20260828000000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',25751401,'440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280','7b9fe1a47cf5a7bc610211de004fe4598b6ccacc31f72afeb6c88cdb4b5fe182',h,b,n,7,4,false,false,false,false);
END
$repair$;
DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_uid514_capability_consumption_repair_history_682 WHERE event_kind='forward_capability_consumption_repair')<>1 OR position('consumed_at IS NULL' IN pg_get_functiondef('public.pdc_uid514_recovery_enqueue_capability_677(uuid)'::regprocedure))=0 OR position('pdc.uid514.recovery_token' IN pg_get_functiondef('public.pdc_uid514_recovery_enqueue_capability_677(uuid)'::regprocedure))>0 OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0 OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0 OR (SELECT count(*) FROM public.vehicles WHERE stock_number='13016925')<>0 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'PDC_682_CAPABILITY_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260828000000','682_uid514_capability_consumption_repair',ARRAY['Require exact 679 recovery state and exact pre-repair helper hash','Consume only a private capability row bound to the exact actor, gateway, recovery event and mailbox; no custom-GUC dependency or generic sub-515 bypass','Record immutable forced-RLS repair history and preserve exact seven-part/four-PDF, zero UID514/vehicle mutation state']);
NOTIFY pgrst,'reload schema';
COMMIT;
