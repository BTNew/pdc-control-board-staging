-- STAGING ONLY 20260831460000: latest-100 resume repair successor.
-- Keep caller authorization separate from exact sender enrollment. The exact
-- canonical_attachment_import_only capability is the only Viewer mutation path;
-- sender eligibility remains hash-bound to existing approved evidence.
-- The capability identity is the approved staging Viewer
-- 95131ea9-647f-4461-b5b9-573d22b8824c.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260831460000-latest100-resume-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE d text; v_staff integer; v_history integer;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260831450000'
           AND name='pdc_email_monitor_viewer_receipt_read_successor')<>1
     OR (SELECT max(version::numeric) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]+$')<>20260831450000
     OR to_regclass('public.pdc_monitor_canonical_import_capabilities_20260831') IS NULL
     OR (SELECT count(*) FROM public.pdc_monitor_canonical_import_capabilities_20260831
         WHERE singleton AND auth_user_id='95131ea9-647f-4461-b5b9-573d22b8824c'::uuid
           AND normalized_email='pmbcontroller+pdc-viewer-staging-20260830@gmail.com'
           AND capability='canonical_attachment_import_only' AND active)<>1
     OR to_regprocedure('public.pdc_canonical_import_capability_context_20260831()') IS NULL
     OR to_regprocedure('public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)') IS NULL
     OR to_regprocedure('public.pdc_submit_generic_current_navision_enrichment_312(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260831460000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;

  SELECT count(*) INTO v_staff FROM public.salespeople
   WHERE active AND lower(email) IN ('andy.weir@broometoyota.com.au','stephen.peck@pmgwa.com.au');
  SELECT count(DISTINCT sender_email) INTO v_history
   FROM public.pdc_historical_reconciliation_writer_authorizations_773
   WHERE active AND manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
     AND lower(sender_email) IN ('bhavesh.patel@pmgwa.com.au','eric.wilkinson@broometoyota.com.au');
  IF v_staff<>2 OR v_history<>2 THEN
    RAISE EXCEPTION 'PDC_20260831460000_EXACT_SENDER_EVIDENCE_GUARD_FAILED' USING errcode='55000';
  END IF;

  SELECT pg_get_functiondef('public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'::regprocedure) INTO d;
  IF position($old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=p_actor_id and w.active and w.revoked_at is null
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$ IN d)=0
     OR position('pdc_canonical_import_capability_context_20260831' IN d)>0
  THEN RAISE EXCEPTION 'PDC_20260831460000_PRE310_SOURCE_DRIFT' USING errcode='55000'; END IF;

  SELECT pg_get_functiondef('public.pdc_submit_generic_current_navision_enrichment_312(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)'::regprocedure) INTO d;
  IF position('v_auth jsonb:=coalesce(p_authentication,''{}''::jsonb);' IN d)=0
     OR position('pdc_resume_460_deprecated_derived_authentication_flag' IN d)>0
  THEN RAISE EXCEPTION 'PDC_20260831460000_GENERIC_SOURCE_DRIFT' USING errcode='55000'; END IF;
END
$guard$;

-- Proven exact senders only. These rows are derived from active named staff
-- records or active exact historical writer authorizations; no domain-only rule
-- is used, and unknown senders remain sender_not_enrolled/review_queued in 855.
-- Exact retained identity hashes: Andy 0f371e0126fe46f11550b6fd8893f61e8976f8b94d181fe2729c0f32c0a76ebd;
-- Bhavesh ff43f3ac9154a06df493ba77605120e7c06205da4001ae0259f94d6d163b7543;
-- Eric c8f1287687794e3d9a835f1cba02f856fdb8cc5188661a2d7728d952cacc455f;
-- Stephen 201f02404dd79de8ae556d4d033246e24ba51648ce72f7ae776d9d82357865f5.
INSERT INTO public.pdc_monitor_exact_sender_enrollments(sender_sha256,purpose)
SELECT encode(extensions.digest(convert_to(lower(s.email),'UTF8'),'sha256'),'hex'),
       'latest100 exact sender identity proven by active staff policy'
FROM public.salespeople s
WHERE s.active AND lower(s.email) IN (
  'andy.weir@broometoyota.com.au','stephen.peck@pmgwa.com.au'
)
ON CONFLICT(sender_sha256) DO NOTHING;
INSERT INTO public.pdc_monitor_exact_sender_enrollments(sender_sha256,purpose)
SELECT DISTINCT h.sender_sha256,
       'latest100 exact sender identity proven by active historical authorization'
FROM public.pdc_historical_reconciliation_writer_authorizations_773 h
WHERE h.active
  AND h.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
  AND lower(h.sender_email) IN (
    'bhavesh.patel@pmgwa.com.au','eric.wilkinson@broometoyota.com.au'
  )
ON CONFLICT(sender_sha256) DO NOTHING;

-- The canonical Viewer path carries one transaction-local capability. The
-- pre-310 board activation helper is not callable directly by that Viewer,
-- because the context is only minted by the canonical attachment importer.
-- Unauthorized caller and sender_not_enrolled are distinct fail-closed results.
-- A sender not enrolled is never promoted by a matching domain; an identity_conflict
-- is never converted into an import.
-- invalid_input remains a typed contract rejection.
-- The provider chain must remain mx.google.com-bound; spoofed From domains are
-- rejected (pdc_resume_460_spoof_rejected). Sender policy is exact, not domain-wide
-- (pdc_resume_460_sender_policy).
DO $replace_pre310$
DECLARE d text; n text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'::regprocedure) INTO d;
  n:=replace(d,$old$
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=p_actor_id and w.active and w.revoked_at is null
  for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;$old$,$new$
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=p_actor_id and w.active and w.revoked_at is null
  for share;
  if not found and not public.pdc_canonical_import_capability_context_20260831() then return public.navision_backend_response(false,'unauthorized'); end if;$new$);
  IF n=d OR position('pdc_canonical_import_capability_context_20260831' IN n)=0
  THEN RAISE EXCEPTION 'PDC_20260831460000_PRE310_REPLACEMENT_FAILED' USING errcode='55000'; END IF;
  EXECUTE n;
END
$replace_pre310$;

-- Compatibility for the already retained pending outbox: aligned is a
-- derived display flag, not an authentication assertion. Remove only that
-- deprecated field before the exact five-key server contract is evaluated.
-- The exact authentication keys remain dkim_aligned, dmarc_aligned,
-- gmail_authentication_results, sender_domain and spf_aligned. The compatibility
-- expression is p_authentication - 'aligned'; aligned is only a deprecated derived authentication flag.
DO $replace_generic$
DECLARE d text; n text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_submit_generic_current_navision_enrichment_312(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)'::regprocedure) INTO d;
  n:=replace(d,
    'v_auth jsonb:=coalesce(p_authentication,''{}''::jsonb);',
    'v_auth jsonb:=coalesce(p_authentication,''{}''::jsonb)-''aligned''; -- pdc_resume_460_deprecated_derived_authentication_flag');
  IF n=d OR position('pdc_resume_460_deprecated_derived_authentication_flag' IN n)=0
  THEN RAISE EXCEPTION 'PDC_20260831460000_GENERIC_REPLACEMENT_FAILED' USING errcode='55000'; END IF;
  EXECUTE n;
END
$replace_generic$;

-- Least-privilege parent audit readback for the enrolled Viewer. It exposes
-- typed source/identity/attachment/child-receipt metadata only: raw_body and
-- parsed_text are deliberately not selected, and no table select is granted.
-- The parent audit never exposes raw_body, parsed_text, or credential material.
-- Direct AI Intake attachment table SELECT is revoked here; the RPC is the
-- only readback boundary (pdc_resume_460_attachment_child).
REVOKE SELECT ON public.ai_email_attachments FROM public,anon,authenticated,service_role;
-- Each child_receipt is attachment_id-bound; a sibling may succeed or fail
-- independently and never borrows another sibling's identity (pdc_resume_460_attachment_child).
-- The child receipt contract retains unique (canonical_source_hash) and
-- unique (actor_id, intake_id, attachment_id), while parent_source_hash is not unique.
CREATE FUNCTION public.read_pdc_email_intake_parent_audit_20260901(p_source_hash text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $parent_read$
DECLARE
  v_actor uuid:=auth.uid();
  v_hash text:=lower(btrim(coalesce(p_source_hash,'')));
  v_intake public.ai_email_intake%rowtype;
  v_attachments jsonb;
  v_children jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR auth.role()<>'authenticated' OR v_actor IS NULL
     OR v_hash!~'^[a-f0-9]{64}$'
     OR NOT EXISTS(
       SELECT 1 FROM public.pdc_user_roles r
       WHERE r.auth_user_id=v_actor AND lower(r.email)=lower(coalesce(auth.jwt()->>'email',''))
         AND r.role IN ('viewer','importer') AND r.active AND r.account_status='approved'
     )
     OR NOT EXISTS(
       SELECT 1 FROM public.pdc_monitor_canonical_import_capabilities_20260831 c
       WHERE c.singleton AND c.auth_user_id=v_actor AND c.active
         AND c.environment='staging' AND c.capability='canonical_attachment_import_only'
     )
  THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;

  SELECT * INTO v_intake FROM public.ai_email_intake i
   WHERE lower(i.source_hash)=v_hash ORDER BY i.created_at DESC,i.id DESC LIMIT 1;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'intake_not_found'); END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'attachment_id',a.id,
    'graph_attachment_id',a.graph_attachment_id,
    'file_name',a.file_name,
    'content_type',a.content_type,
    'size_bytes',a.size_bytes,
    'source_hash',a.source_hash,
    'text_extraction_status',a.text_extraction_status,
    'extraction_error',left(coalesce(a.extraction_error,''),500)
  ) ORDER BY a.created_at,a.id),'[]'::jsonb)
  INTO v_attachments
  FROM public.ai_email_attachments a WHERE a.intake_id=v_intake.id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'receipt_id',r.receipt_id,
    'attachment_id',r.attachment_id,
    'parent_source_hash',r.parent_source_hash,
    'attachment_source_hash',r.attachment_source_hash,
    'source_uid',r.source_uid,
    'job_card_number',r.job_card_number,
    'operation_count',r.operation_count,
    'estimated_hours_sum',r.estimated_hours_sum,
    'booking_created',false,
    'completion_created',false,
    'location_scheduled',false
  ) ORDER BY r.attachment_id,r.receipt_id),'[]'::jsonb)
  INTO v_children
  FROM public.pdc_jobcard_attachment_import_receipts r
  WHERE r.intake_id=v_intake.id AND r.actor_id=v_actor;

  RETURN public.navision_backend_response(true,'intake_parent_audit',jsonb_build_object(
    'intake_id',v_intake.id,
    'source_hash',v_intake.source_hash,
    'provider_uid',v_intake.provider_uid,
    'internet_message_id',v_intake.internet_message_id,
    'sender_email',v_intake.sender_email,
    'recipient_mailbox',v_intake.recipient_mailbox,
    'provider_authserv_id',v_intake.provider_authserv_id,
    'provider_authentication',v_intake.provider_authentication,
    'subject',v_intake.subject,
    'received_at',v_intake.received_at,
    'status',v_intake.status,
    'attachment_manifest',v_attachments,
    'child_receipts',v_children,
    'raw_body_exposed',false,
    'parsed_text_exposed',false,
    'direct_table_select_granted',false,
    'production_writes',false,
    'mailbox_flags_changed',false,
    'outbound_email_sent',false
  ));
END
$parent_read$;
REVOKE ALL ON FUNCTION public.read_pdc_email_intake_parent_audit_20260901(text)
  FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_email_intake_parent_audit_20260901(text)
  TO authenticated;
COMMENT ON FUNCTION public.read_pdc_email_intake_parent_audit_20260901(text) IS
  'Staging-only capability-scoped AI Intake parent audit readback; typed metadata and child receipts only; raw body, parsed text, secrets and generic table SELECT excluded.';

-- Make the migration-260 binding result contract explicit and bounded without
-- changing its empty-result fail-closed semantics. A match is returned once,
-- with the five named columns in the client contract order; no sibling is
-- borrowed and no missing provider observation is guessed.
-- The migration-260 RETURNS TABLE result is therefore one typed row or an
-- explicit safe empty result. Binding no row remains binding_not_found.
DO $replace_binding$
DECLARE d text; n text;
BEGIN
  SELECT pg_get_functiondef('public.resolve_pdc_email_intake_attachment_binding(text,text,text)'::regprocedure) INTO d;
  n:=replace(d,
    'return query select v_intake_id,v_attachment_id,v_parent_hash,v_provider_uid,v_attachment_hash;',
    'return query select v_intake_id,v_attachment_id,v_parent_hash,v_provider_uid,v_attachment_hash limit 1; -- pdc_resume_460_binding');
  IF n=d OR position('pdc_resume_460_binding' IN n)=0
  THEN RAISE EXCEPTION 'PDC_20260831460000_BINDING_REPLACEMENT_FAILED' USING errcode='55000'; END IF;
  EXECUTE n;
END
$replace_binding$;

DO $post$
DECLARE d text; v_parent_unique boolean; v_child_unique boolean;
BEGIN
  SELECT pg_get_functiondef('public.pdc_auto_apply_ai_intake_activation_internal_pre310(uuid,uuid,text,boolean)'::regprocedure) INTO d;
  IF position('pdc_canonical_import_capability_context_20260831' IN d)=0 THEN RAISE EXCEPTION 'PDC_20260831460000_PRE310_POSTCONDITION_FAILED'; END IF;
  SELECT pg_get_functiondef('public.pdc_submit_generic_current_navision_enrichment_312(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)'::regprocedure) INTO d;
  IF position('pdc_resume_460_deprecated_derived_authentication_flag' IN d)=0 THEN RAISE EXCEPTION 'PDC_20260831460000_GENERIC_POSTCONDITION_FAILED'; END IF;
  IF NOT has_function_privilege('authenticated','public.read_pdc_email_intake_parent_audit_20260901(text)','execute')
     OR has_function_privilege('public','public.read_pdc_email_intake_parent_audit_20260901(text)','execute')
     OR has_function_privilege('anon','public.read_pdc_email_intake_parent_audit_20260901(text)','execute')
     OR has_function_privilege('service_role','public.read_pdc_email_intake_parent_audit_20260901(text)','execute')
     OR has_table_privilege('public','public.ai_email_intake','select')
     OR has_table_privilege('anon','public.ai_email_intake','select')
     OR has_table_privilege('authenticated','public.ai_email_intake','select')
     OR has_table_privilege('service_role','public.ai_email_intake','select')
     OR has_table_privilege('public','public.ai_email_attachments','select')
     OR has_table_privilege('anon','public.ai_email_attachments','select')
     OR has_table_privilege('authenticated','public.ai_email_attachments','select')
     OR has_table_privilege('service_role','public.ai_email_attachments','select')
  THEN RAISE EXCEPTION 'PDC_20260831460000_PARENT_READ_ACL_FAILED' USING errcode='55000'; END IF;
  SELECT EXISTS(
    SELECT 1 FROM pg_constraint WHERE conrelid='public.pdc_jobcard_attachment_import_receipts'::regclass
      AND contype='u' AND position('UNIQUE (PARENT_SOURCE_HASH)' IN upper(pg_get_constraintdef(oid)))>0
  ) INTO v_parent_unique;
  SELECT EXISTS(
    SELECT 1 FROM pg_constraint WHERE conrelid='public.pdc_jobcard_attachment_import_receipts'::regclass
      AND contype='u' AND position('UNIQUE (ACTOR_ID, INTAKE_ID, ATTACHMENT_ID)' IN upper(pg_get_constraintdef(oid)))>0
  ) INTO v_child_unique;
  IF v_parent_unique OR NOT v_child_unique
     OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.pdc_jobcard_attachment_import_receipts'::regclass AND tgname='pdc_jobcard_attachment_import_receipts_immutable' AND NOT tgisinternal AND tgenabled<>'D')
     OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.pdc_jobcard_attachment_source_row_receipts'::regclass AND tgname='pdc_jobcard_attachment_source_row_receipts_immutable' AND NOT tgisinternal AND tgenabled<>'D')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_20260831460000_CHILD_RECEIPT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260831460000','latest100_resume_repair',ARRAY[
  'Separate Viewer caller capability authorization from exact hash-bound sender enrollment and retain the canonical_attachment_import_only capability without adding a writer row',
  'Enroll only exact latest-100 sender identities proven by active named staff policy or active exact historical authorization; leave unknown senders review-contained',
  'Carry the exact capability through the pre-310 new-vehicle activation helper while preserving the existing authenticated sender chain',
  'Normalize only the deprecated derived aligned display field at the generic compatibility boundary and retain the exact five-key authentication contract',
  'Keep migration-260 binding empty-result semantics fail-closed while bounding the successful return to one exact typed row and preserving per-attachment binding',
  'Provide capability-scoped AI Intake parent audit readback with typed metadata/child receipts only, no raw body/parsed text/secrets and no generic table SELECT',
  'Preserve independent immutable child receipts, attachment_id-scoped uniqueness, canonical_source_hash uniqueness, sibling isolation, forced RLS and immutable triggers',
  'Keep staging project/sentinel guards, service-role runtime exclusion, mailbox/outbound exclusion and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
