-- STAGING ONLY 808: replace only the historical writer authorization's legacy
-- one-mailbox 674 guard with authenticated 802/672 contained authorization.
-- All actor, role, evidence, UID, stock, tuple and fail-closed checks remain
-- unchanged; normal runtime 766 and material proposal conflicts are untouched.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-808-historical-writer-auth-contained',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v_head text; v text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT (version,name)::text INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
 SELECT p.proowner::regrole::text,p.prosecdef,p.proacl::text,p.prosrc INTO owner_name,secdef,acl,v FROM pg_proc p WHERE p.oid='public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '(20260830224000,807_pre796_766_final_contained_runtime_successor)'
    OR owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}'
    OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '2d50ef3031df376a61821332988daf34346bde39504c78757c77fc43c9ca7284'
    OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_773 WHERE active) IS DISTINCT FROM 15
    OR (SELECT count(*) FROM public.pdc_ai_intake_proposals WHERE status::text='pending') IS DISTINCT FROM 15
    OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
 THEN RAISE EXCEPTION 'PDC_808_CURRENT_HEAD_OR_WRITER_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.pdc_historical_writer_authorized_773(p_source_hash text, p_source_uid text, p_sender text, p_authentication jsonb, p_stock text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth', 'extensions'
AS $function$
DECLARE v_source text:=lower(btrim(coalesce(p_source_hash,''))); v_uid text:=btrim(coalesce(p_source_uid,'')); v_sender text:=lower(btrim(coalesce(p_sender,''))); v_stock text:=public.normalize_vehicle_stock_number(p_stock);
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
     OR COALESCE(public.verify_pdc_historical_runtime_binding_authenticated_802('active','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227')->>'ok','false')<>'true'
     OR v_uid='1:197' -- historical_reference_stock_excluded
     OR v_stock='13056899' THEN RETURN false; END IF;
  RETURN EXISTS(SELECT 1 FROM public.pdc_historical_reconciliation_writer_authorizations_773 e
    WHERE e.active AND e.provider_uid=v_uid AND e.parent_source_hash=v_source AND e.sender_email=v_sender
      AND e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
      AND e.provider_authentication IS NOT DISTINCT FROM p_authentication
      AND public.normalize_vehicle_stock_number(e.stock_number)=v_stock
      AND e.authorized_actor_id=auth.uid() AND e.authorized_actor_email=lower(btrim(auth.jwt()->>'email'))
      AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND e.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018');
END
$function$;

revoke all on function public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text) from public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text) TO postgres;
DO $post$
DECLARE v text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT p.proowner::regrole::text,p.prosecdef,p.proacl::text,p.prosrc INTO owner_name,secdef,acl,v FROM pg_proc p WHERE p.oid='public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text)'::regprocedure;
 IF owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}'
    OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'c832a015a4ddee1d9f727f7b196a10d4e2fbf9822d559be1d33e4eab6f590ae1'
    OR position('pdc_monitor_authenticated_active_scope_674' in v)>0
    OR position('verify_pdc_historical_runtime_binding_authenticated_802' in v)=0
    OR position('historical_reference_stock_excluded' in v)=0
    OR position('e.provider_authentication IS NOT DISTINCT FROM p_authentication' in v)=0
    OR position('e.authorized_actor_id=auth.uid()' in v)=0
 THEN RAISE EXCEPTION 'PDC_808_WRITER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830225000','808_historical_writer_auth_contained_successor',ARRAY[
 'replace only pdc_historical_writer_authorized_773 legacy active_scope_674 with authenticated 802/672 contained authorization',
 'preserve actor role evidence UID stock tuple checks and fail-closed conflicts',
 'preserve normal runtime 766 and ten material historical_proposal_tuple_conflict outcomes',
 'no historical Apply outbox mailbox task outbound or Production operation'
]);
COMMIT;
