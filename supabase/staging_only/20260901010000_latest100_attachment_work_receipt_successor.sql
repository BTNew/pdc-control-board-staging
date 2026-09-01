-- STAGING ONLY 20260901010000: attachment-scoped successor for the
-- immutable email work receipt compatibility boundary.
--
-- The legacy work-receipt table is retained byte-for-byte. Its intake-only
-- uniqueness was correct for the original single-document contract but is too
-- broad for the current attachment-scoped canonical importer. This successor
-- keys work by authenticated actor + intake + attachment, keeps source/work
-- hashes in the replay comparison, and never rewrites or deletes historical
-- receipts. `old_work_before` and `old_work_after` are compared inside the
-- transaction so every historical receipt remains audit-preserved.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901010000-latest100-attachment-work-successor',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

CREATE FUNCTION pg_temp.pdc_latest100_old_work_receipt_digest()
RETURNS text LANGUAGE sql STABLE SET search_path=pg_catalog,public,extensions AS $$
  SELECT encode(extensions.digest(convert_to(coalesce(
    (SELECT string_agg(md5(to_jsonb(x)::text),'' ORDER BY md5(to_jsonb(x)::text))
       FROM public.pdc_email_intake_work_receipts x),''),'UTF8'),'sha256'),'hex')
$$;

DO $guard$
DECLARE d text; old_digest text;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260831461000' AND name='latest100_force_rls_successor')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]+$')<>20260831461000
     OR to_regclass('public.pdc_email_intake_work_receipts_20260901') IS NOT NULL
     OR to_regprocedure('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)') IS NULL
     OR to_regprocedure('public.process_email_intake_work(uuid,text,text,jsonb,text)') IS NULL
     OR to_regprocedure('public.get_pdc_email_intake_work_receipt(uuid,text,text)') IS NULL
     OR to_regclass('public.pdc_email_intake_work_receipts') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901010000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;

  SELECT pg_get_functiondef('public.process_email_intake_work(uuid,text,text,jsonb,text)'::regprocedure) INTO d;
  IF position('where intake_id=p_intake_id' IN d)=0
     OR position('work_receipt_replay_conflict' IN d)=0
     OR position('public.import_pdc_jobcard_attachment_canonical' IN d)=0
  THEN RAISE EXCEPTION 'PDC_20260901010000_PROCESS_SOURCE_DRIFT' USING errcode='55000'; END IF;

  SELECT pg_get_functiondef('public.get_pdc_email_intake_work_receipt(uuid,text,text)'::regprocedure) INTO d;
  IF position('where intake_id=p_intake_id and actor_id=v_actor' IN d)=0
     OR position('work_receipt_binding_mismatch' IN d)=0
  THEN RAISE EXCEPTION 'PDC_20260901010000_READER_SOURCE_DRIFT' USING errcode='55000'; END IF;

  IF NOT EXISTS(SELECT 1 FROM pg_trigger
                WHERE tgrelid='public.pdc_email_intake_work_receipts'::regclass
                  AND tgname='pdc_email_intake_work_receipts_immutable'
                  AND NOT tgisinternal AND tgenabled<>'D')
     OR NOT has_function_privilege('authenticated','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
     OR has_function_privilege('public','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
     OR has_function_privilege('anon','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
     OR has_function_privilege('service_role','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','execute')
  THEN RAISE EXCEPTION 'PDC_20260901010000_CANONICAL_ACL_OR_IMMUTABILITY_DRIFT' USING errcode='55000'; END IF;

  old_digest:=pg_temp.pdc_latest100_old_work_receipt_digest();
  PERFORM set_config('pdc.latest100.old_work_before',old_digest,true);
END
$guard$;

CREATE TABLE public.pdc_email_intake_work_receipts_20260901(
  work_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intake_id uuid NOT NULL REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
  attachment_id uuid NOT NULL REFERENCES public.ai_email_attachments(id) ON DELETE RESTRICT,
  attachment_receipt_id uuid NOT NULL REFERENCES public.pdc_jobcard_attachment_import_receipts(receipt_id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  source_hash text NOT NULL CHECK(source_hash~'^[a-f0-9]{64}$'),
  extraction_hash text NOT NULL CHECK(extraction_hash~'^[a-f0-9]{64}$'),
  server_extraction_hash text NOT NULL CHECK(server_extraction_hash~'^[a-f0-9]{64}$'),
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,intake_id,attachment_id),
  UNIQUE(request_sha256)
);
ALTER TABLE public.pdc_email_intake_work_receipts_20260901 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_intake_work_receipts_20260901 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_intake_work_receipts_20260901 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_intake_work_receipts_20260901_immutable
BEFORE UPDATE OR DELETE ON public.pdc_email_intake_work_receipts_20260901
FOR EACH ROW EXECUTE FUNCTION public.pdc_jobcard_attachment_receipt_reject_mutation();

-- Internal typed envelope builder. It is deliberately not executable by any
-- API role; callers receive only the process/get RPC envelopes below.
CREATE FUNCTION public.pdc_latest100_work_receipt_response_20260901(p_work_receipt_id uuid,p_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $response$
DECLARE w public.pdc_email_intake_work_receipts_20260901%rowtype;
        r public.pdc_jobcard_attachment_import_receipts%rowtype;
BEGIN
  SELECT * INTO w FROM public.pdc_email_intake_work_receipts_20260901 WHERE work_receipt_id=p_work_receipt_id;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'work_receipt_not_found'); END IF;
  SELECT * INTO r FROM public.pdc_jobcard_attachment_import_receipts WHERE receipt_id=w.attachment_receipt_id;
  IF NOT FOUND OR r.intake_id<>w.intake_id OR r.attachment_id<>w.attachment_id
     OR r.parent_source_hash<>w.source_hash
  THEN RETURN public.navision_backend_response(false,'work_receipt_binding_mismatch'); END IF;
  RETURN public.navision_backend_response(true,p_code,jsonb_build_object(
    'receipt_id',w.work_receipt_id,
    'intake_id',w.intake_id,
    'attachment_id',w.attachment_id,
    'parent_source_hash',w.source_hash,
    'attachment_source_hash',r.attachment_source_hash,
    'extraction_hash',w.extraction_hash,
    'canonical_receipt_id',r.receipt_id,
    'canonical_source_hash',r.canonical_source_hash));
END
$response$;
REVOKE ALL ON FUNCTION public.pdc_latest100_work_receipt_response_20260901(uuid,text)
  FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE OR REPLACE FUNCTION public.get_pdc_email_intake_work_receipt(
  p_intake_id uuid,p_expected_source_hash text,p_expected_extraction_hash text
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $work_read_20260901$
DECLARE
  v_actor uuid:=auth.uid();
  v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));
  v_extraction text:=lower(btrim(coalesce(p_expected_extraction_hash,'')));
  v_work public.pdc_email_intake_work_receipts_20260901%rowtype;
  v_legacy public.pdc_email_intake_work_receipts%rowtype;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR v_actor IS NULL
     OR v_source!~'^[a-f0-9]{64}$' OR v_extraction!~'^[a-f0-9]{64}$'
  THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;

  SELECT * INTO v_work
  FROM public.pdc_email_intake_work_receipts_20260901
  WHERE intake_id=p_intake_id AND actor_id=v_actor
    AND source_hash=v_source AND extraction_hash=v_extraction
  ORDER BY created_at DESC,work_receipt_id DESC LIMIT 1;
  IF FOUND THEN
    RETURN public.pdc_latest100_work_receipt_response_20260901(v_work.work_receipt_id,'work_receipt');
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_email_intake_work_receipts_20260901
            WHERE intake_id=p_intake_id AND actor_id=v_actor AND source_hash=v_source)
  THEN RETURN public.navision_backend_response(false,'work_receipt_binding_mismatch'); END IF;

  -- Preserve the legacy reader path for the original actor-owned receipt. No
  -- legacy row is updated, deleted, or reinterpreted here.
  SELECT * INTO v_legacy FROM public.pdc_email_intake_work_receipts
   WHERE intake_id=p_intake_id AND actor_id=v_actor;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'work_receipt_not_found'); END IF;
  IF v_legacy.source_hash<>v_source OR v_legacy.extraction_hash<>v_extraction
  THEN RETURN public.navision_backend_response(false,'work_receipt_binding_mismatch'); END IF;
  RETURN public.read_pdc_jobcard_attachment_import_receipt(v_legacy.attachment_receipt_id);
END
$work_read_20260901$;

CREATE OR REPLACE FUNCTION public.process_email_intake_work(
  p_intake_id uuid,p_expected_source_hash text,p_extraction_hash text,
  p_extraction jsonb,p_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
SET statement_timeout='180s' AS $work_20260901$
DECLARE
  v_actor uuid:=auth.uid();
  v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));
  v_extraction_hash text:=lower(btrim(coalesce(p_extraction_hash,'')));
  v_payload jsonb:=coalesce(p_extraction,'null'::jsonb);
  v_server_hash text;
  v_request text;
  v_attachment_id uuid;
  v_existing public.pdc_email_intake_work_receipts_20260901%rowtype;
  v_legacy public.pdc_email_intake_work_receipts%rowtype;
  v_child public.pdc_jobcard_attachment_import_receipts%rowtype;
  v_result jsonb;
  v_receipt_id uuid;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR v_actor IS NULL
     OR lower(btrim(coalesce(p_actor,''))) NOT IN ('pdc-monitor','email_intake_service')
     OR v_source!~'^[a-f0-9]{64}$' OR v_extraction_hash!~'^[a-f0-9]{64}$'
     OR jsonb_typeof(v_payload) IS DISTINCT FROM 'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_payload) k) IS DISTINCT FROM array[
       'authentication','canonical_attachment_id','canonical_document_hash','contract_version',
       'email_vehicle','operation_lines','required_work']::text[]
     OR v_payload->>'contract_version'<>'pmb-email-work-v2'
     OR coalesce(v_payload->>'canonical_attachment_id','')!~'^[a-f0-9-]{36}$'
     OR lower(coalesce(v_payload->>'canonical_document_hash',''))!~'^[a-f0-9]{64}$'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r
                   WHERE r.auth_user_id=v_actor
                     AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
                     AND r.role IN('viewer','importer') AND r.active AND r.account_status='approved')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_canonical_import_capabilities_20260831 c
                   WHERE c.singleton AND c.auth_user_id=v_actor AND c.active
                     AND c.environment='staging' AND c.capability='canonical_attachment_import_only')
        AND NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
                       WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL)
  THEN RETURN public.navision_backend_response(false,'invalid_work_extraction'); END IF;

  v_attachment_id:=(v_payload->>'canonical_attachment_id')::uuid;
  v_server_hash:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','20260901.1','actor_id',v_actor,'intake_id',p_intake_id,
    'attachment_id',v_attachment_id,'source_hash',v_source,'extraction_hash',v_extraction_hash,
    'server_extraction_hash',v_server_hash,'payload',v_payload,'actor_label',lower(btrim(p_actor))
  )::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'pdc-email-intake-work-20260901:'||v_actor::text||':'||p_intake_id::text||':'||v_attachment_id::text,0));

  SELECT * INTO v_existing FROM public.pdc_email_intake_work_receipts_20260901
   WHERE actor_id=v_actor AND intake_id=p_intake_id AND attachment_id=v_attachment_id;
  IF FOUND THEN
    IF v_existing.source_hash<>v_source OR v_existing.extraction_hash<>v_extraction_hash
       OR v_existing.server_extraction_hash<>v_server_hash OR v_existing.request_sha256<>v_request
    THEN RETURN public.navision_backend_response(false,'work_receipt_replay_conflict'); END IF;
    IF v_existing.request_sha256=v_request
    THEN RETURN public.pdc_latest100_work_receipt_response_20260901(v_existing.work_receipt_id,'work_receipt_replayed'); END IF;
    RETURN public.navision_backend_response(false,'work_receipt_identity_conflict');
  END IF;

  -- An old receipt may be retained for the same intake. It is a conflict only
  -- when the same actor + attachment identity is being replayed with different
  -- source/work keys. a different actor is a genuinely distinct old work receipt identity.
  SELECT w.* INTO v_legacy
  FROM public.pdc_email_intake_work_receipts w
  JOIN public.pdc_jobcard_attachment_import_receipts r ON r.receipt_id=w.attachment_receipt_id
  WHERE w.intake_id=p_intake_id AND w.actor_id=v_actor AND r.attachment_id=v_attachment_id
  ORDER BY w.created_at DESC,w.work_receipt_id DESC LIMIT 1;
  IF FOUND THEN
    IF v_legacy.source_hash<>v_source OR v_legacy.extraction_hash<>v_extraction_hash
       OR v_legacy.server_extraction_hash<>v_server_hash OR v_legacy.request_sha256<>v_request
    THEN RETURN public.navision_backend_response(false,'work_receipt_replay_conflict'); END IF;
    INSERT INTO public.pdc_email_intake_work_receipts_20260901(
      intake_id,attachment_id,attachment_receipt_id,actor_id,source_hash,extraction_hash,
      server_extraction_hash,request_sha256)
    VALUES(p_intake_id,v_attachment_id,v_legacy.attachment_receipt_id,v_actor,v_source,
           v_extraction_hash,v_server_hash,v_request)
    RETURNING work_receipt_id INTO v_existing.work_receipt_id;
    RETURN public.pdc_latest100_work_receipt_response_20260901(v_existing.work_receipt_id,'work_receipt_duplicate_zero_add');
  END IF;

  -- If another authenticated actor already produced the exact immutable child,
  -- return a zero-add successor receipt. A different attachment is not a
  -- duplicate and proceeds through the canonical attachment importer.
  SELECT * INTO v_child FROM public.pdc_jobcard_attachment_import_receipts r
  WHERE r.intake_id=p_intake_id AND r.attachment_id=v_attachment_id
  ORDER BY r.created_at DESC,r.receipt_id DESC LIMIT 1;
  IF FOUND THEN
    IF v_child.parent_source_hash<>v_source
       OR lower(coalesce(v_payload->>'canonical_document_hash',''))<>v_child.attachment_source_hash
    THEN RETURN public.navision_backend_response(false,'work_receipt_replay_conflict'); END IF;
    INSERT INTO public.pdc_email_intake_work_receipts_20260901(
      intake_id,attachment_id,attachment_receipt_id,actor_id,source_hash,extraction_hash,
      server_extraction_hash,request_sha256)
    VALUES(p_intake_id,v_attachment_id,v_child.receipt_id,v_actor,v_source,v_extraction_hash,v_server_hash,v_request)
    ON CONFLICT (actor_id,intake_id,attachment_id) DO NOTHING
    RETURNING work_receipt_id INTO v_existing.work_receipt_id;
    IF v_existing.work_receipt_id IS NULL THEN
      SELECT work_receipt_id INTO v_existing.work_receipt_id
      FROM public.pdc_email_intake_work_receipts_20260901
      WHERE actor_id=v_actor AND intake_id=p_intake_id AND attachment_id=v_attachment_id;
    END IF;
    RETURN public.pdc_latest100_work_receipt_response_20260901(v_existing.work_receipt_id,'work_receipt_duplicate_zero_add');
  END IF;

  v_result:=public.import_pdc_jobcard_attachment_canonical(
    p_intake_id,v_attachment_id,v_source,
    lower(v_payload->>'canonical_document_hash'),v_payload->'authentication',
    v_payload->'email_vehicle',v_payload->'required_work',v_payload->'operation_lines');
  IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RETURN v_result; END IF;
  v_receipt_id:=nullif(v_result->'data'->>'receipt_id','')::uuid;
  IF v_receipt_id IS NULL THEN RETURN public.navision_backend_response(false,'attachment_receipt_missing'); END IF;
  SELECT * INTO v_child FROM public.pdc_jobcard_attachment_import_receipts
   WHERE receipt_id=v_receipt_id AND intake_id=p_intake_id AND attachment_id=v_attachment_id
     AND parent_source_hash=v_source;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'attachment_receipt_binding_mismatch'); END IF;
  INSERT INTO public.pdc_email_intake_work_receipts_20260901(
    intake_id,attachment_id,attachment_receipt_id,actor_id,source_hash,extraction_hash,
    server_extraction_hash,request_sha256)
  VALUES(p_intake_id,v_attachment_id,v_receipt_id,v_actor,v_source,v_extraction_hash,v_server_hash,v_request)
  ON CONFLICT (actor_id,intake_id,attachment_id) DO NOTHING
  RETURNING work_receipt_id INTO v_existing.work_receipt_id;
  IF v_existing.work_receipt_id IS NULL THEN
    SELECT work_receipt_id INTO v_existing.work_receipt_id
    FROM public.pdc_email_intake_work_receipts_20260901
    WHERE actor_id=v_actor AND intake_id=p_intake_id AND attachment_id=v_attachment_id;
  END IF;
  RETURN public.pdc_latest100_work_receipt_response_20260901(v_existing.work_receipt_id,'work_receipt_created');
EXCEPTION WHEN unique_violation THEN
  RETURN public.navision_backend_response(false,'work_receipt_identity_conflict');
END
$work_20260901$;

REVOKE ALL ON FUNCTION public.get_pdc_email_intake_work_receipt(uuid,text,text)
  FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_intake_work_receipt(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.process_email_intake_work(uuid,text,text,jsonb,text)
  FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.process_email_intake_work(uuid,text,text,jsonb,text) TO authenticated;

DO $post$
DECLARE old_work_after text; d text;
BEGIN
  old_work_after:=pg_temp.pdc_latest100_old_work_receipt_digest();
  IF old_work_after IS DISTINCT FROM current_setting('pdc.latest100.old_work_before',true)
  THEN RAISE EXCEPTION 'PDC_20260901010000_OLD_WORK_RECEIPT_AUDIT_DRIFT' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.process_email_intake_work(uuid,text,text,jsonb,text)'::regprocedure) INTO d;
  IF position('pdc_email_intake_work_receipts_20260901' IN d)=0
     OR position('work_receipt_replay_conflict' IN d)=0
     OR position('work_receipt_duplicate_zero_add' IN d)=0
     OR position('pdc-email-intake-work-20260901:' IN d)=0
  THEN RAISE EXCEPTION 'PDC_20260901010000_PROCESS_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  IF NOT has_function_privilege('authenticated','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')
     OR has_function_privilege('public','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')
     OR has_function_privilege('anon','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')
     OR has_function_privilege('service_role','public.process_email_intake_work(uuid,text,text,jsonb,text)','execute')
     OR has_table_privilege('public','public.pdc_email_intake_work_receipts_20260901','select')
     OR has_table_privilege('anon','public.pdc_email_intake_work_receipts_20260901','select')
     OR has_table_privilege('authenticated','public.pdc_email_intake_work_receipts_20260901','select')
     OR has_table_privilege('service_role','public.pdc_email_intake_work_receipts_20260901','select')
     OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.pdc_email_intake_work_receipts_20260901'::regclass
                   AND tgname='pdc_email_intake_work_receipts_20260901_immutable'
                   AND NOT tgisinternal AND tgenabled<>'D')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260901010000_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260901010000','latest100_attachment_work_receipt_successor',ARRAY[
  'Preserve the legacy intake-only immutable work-receipt table and prove its historical rows are unchanged by a before/after digest',
  'Add a forced-RLS append-only successor keyed by authenticated actor, intake and attachment so siblings can coexist without broad overloads',
  'Compare exact source, extraction, server and request work keys; true duplicates return a zero-add typed receipt and conflicting identities fail closed',
  'Recognize an exact existing canonical child as a duplicate without deleting or rewriting its historical receipt, while allowing a genuinely different attachment through the canonical importer',
  'Keep the canonical importer signature and exact Viewer capability; preserve authenticated-only EXECUTE and deny API table DML/service-role runtime',
  'Verify the function/grant definition before issuing one bounded PostgREST schema reload; keep mailbox, outbound scheduler and Production untouched'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
