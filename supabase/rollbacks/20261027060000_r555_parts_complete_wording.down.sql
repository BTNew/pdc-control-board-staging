-- Undo r555 (F169). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores the r515 person recorder (prosrc md5 8ddb1477beeb94c7879c4021cccf1d40) and the 8-digit stock check. Helper names are the *_541 functions this release created.
-- Refuses while a confirmation stock is a rego, so those rows are not discarded here.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r555 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r555 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r555 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM 'c5314b7bed8a1401b6698319125c2d74' THEN RAISE EXCEPTION 'r555 undo: person body is not the r555 body'; END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_parts_completion_email_confirmations WHERE stock_number !~ '^([0-9]{8}|IS[0-9]{8})$') THEN RAISE EXCEPTION 'r555 undo: a rego-stock confirmation is stored'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.record_pdc_person_parts_complete_20260913(p_stock text, p_gmail_message_id text, p_received_at timestamp with time zone, p_subject text, p_confirmation_text text, p_evidence_sha256 text, p_authentication jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_codex_intake_private'
AS $person515$
DECLARE v public.vehicles%rowtype; c public.pdc_parts_completion_email_confirmations%rowtype;
 actor uuid; status jsonb; sender text:=lower(btrim(p_authentication->>'from_address'));
 domain text; auth_result text; body text; authenticated_sender boolean;
 outlook boolean; gmail_ok boolean; outlook_ok boolean; body_ok boolean; mailbox text;
 auth_as text; auth_as_alt text; auth_source text; auth_source_alt text;
 auth_source_raw text; auth_source_alt_raw text;
 internal_auth boolean; source_ok boolean; external_ok boolean; internal_ok boolean;
BEGIN
 IF pdc_codex_intake_private.management_connection() IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 domain:=split_part(sender,'@',2); auth_result:=p_authentication->>'authentication_results';
 body:=lower(regexp_replace(btrim(coalesce(p_confirmation_text,'')),'[[:space:]]+',' ','g'));
 outlook:=p_authentication->>'mailbox'='pdc@pmgwa.com.au';
 authenticated_sender:=coalesce(auth_result ~* '^mx[.]google[.]com;' AND (
   auth_result ~* ('dkim=pass[^;]*header[.](i=@|d=)'||replace(domain,'.','\.')||'([;[:space:]]|$)')
   OR auth_result ~* ('(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)')
 ),false);
 gmail_ok:=p_authentication->>'mailbox'='pmbcontroller@gmail.com'
  AND coalesce(p_gmail_message_id,'') ~ '^[a-f0-9]{10,40}$'
  AND p_authentication->>'to_address'='pmbcontroller@gmail.com'
  AND p_authentication->>'verified_by'='gmail_receiving_provider'
  AND authenticated_sender;
 -- r515 internal same-tenant keys (copy the header; do not invent Authentication-Results):
 -- auth_as, or x_ms_exchange_organization_authas, value Internal. If both are sent they must agree.
 -- auth_source and x_ms_exchange_organization_authsource are optional. If a key is present it must be
 -- one hostname (letters, digits, dots, hyphens). If both are present they must be the same hostname.
 auth_as:=nullif(lower(btrim(p_authentication->>'auth_as')),'');
 auth_as_alt:=nullif(lower(btrim(p_authentication->>'x_ms_exchange_organization_authas')),'');
 internal_auth:=coalesce((auth_as='internal' OR auth_as_alt='internal')
  AND (auth_as IS NULL OR auth_as_alt IS NULL OR auth_as=auth_as_alt),false);
 auth_source_raw:=p_authentication->>'auth_source';
 auth_source_alt_raw:=p_authentication->>'x_ms_exchange_organization_authsource';
 auth_source:=nullif(btrim(auth_source_raw),'');
 auth_source_alt:=nullif(btrim(auth_source_alt_raw),'');
 source_ok:=coalesce((auth_source_raw IS NULL AND auth_source_alt_raw IS NULL) OR (
   (auth_source_raw IS NULL OR auth_source ~ '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$')
   AND (auth_source_alt_raw IS NULL OR auth_source_alt ~ '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$')
   AND (auth_source IS NULL OR auth_source_alt IS NULL OR lower(auth_source)=lower(auth_source_alt))
   AND (auth_source IS NOT NULL OR auth_source_alt IS NOT NULL)
 ),false);
 external_ok:=coalesce(
   auth_result ~* ('dkim=pass[^;]*header[.](i=@|d=)'||replace(domain,'.','\.')||'([;[:space:]]|$)')
   OR auth_result ~* ('(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)')
   OR auth_result ~* ('(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=([^;[:space:]]*@)?'||replace(domain,'.','\.')||'([;[:space:]]|$)')
 ,false);
 internal_ok:=coalesce(internal_auth AND source_ok AND domain='pmgwa.com.au'
  AND coalesce(auth_result,'') ~* ('header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)'),false);
 outlook_ok:=coalesce(outlook
  AND p_gmail_message_id IS NOT NULL
  AND length(p_gmail_message_id) BETWEEN 8 AND 512
  AND p_gmail_message_id !~ '[[:space:]]'
  AND (p_authentication->>'internet_message_id'=p_gmail_message_id
    OR p_authentication->>'outlook_message_id'=p_gmail_message_id
    OR p_authentication->>'microsoft_message_id'=p_gmail_message_id)
  AND p_authentication->>'to_address'='pdc@pmgwa.com.au'
  AND p_authentication->>'verified_by'='microsoft_receiving_provider'
  AND coalesce(auth_result,'') ~* '^mx[.]microsoft[.]com([[:space:]]+[0-9]+)?[[:space:]]*;'
  AND (external_ok OR internal_ok),false);
 body_ok:=body ~ ('^(parts complete( for)? '||lower(p_stock)||'|'||lower(p_stock)||' parts complete)[.!]?$')
  OR (outlook AND body ~ '^parts complete[.!]?$'
      AND coalesce(p_subject,'') ~* ('(^|[^A-Za-z0-9])'||p_stock||'([^A-Za-z0-9]|$)'));
 IF p_stock IS NULL OR p_stock !~ '^([0-9]{8}|IS[0-9]{8})$'
 OR p_gmail_message_id IS NULL
 OR p_received_at IS NULL OR p_received_at<'2026-09-12T00:00:00Z' OR p_received_at>clock_timestamp()+interval '5 minutes'
 OR p_evidence_sha256 IS NULL OR p_evidence_sha256 !~ '^[a-f0-9]{64}$'
 OR sender IS NULL OR sender !~ '^[^[:space:]@]+@[a-z0-9.-]+\.[a-z]{2,}$'
 OR sender ~* '(^|[._-])(no[._-]?reply|mailer.daemon|postmaster)(@|[._-])'
 OR p_authentication->>'header_from' IS DISTINCT FROM domain
 OR p_authentication->>'human_message' IS DISTINCT FROM 'true'
 OR p_authentication->>'unquoted_affirmative' IS DISTINCT FROM 'true'
 OR coalesce(nullif(p_authentication->>'reply_to',''),sender)<>sender
 OR lower(coalesce(p_authentication->>'auto_submitted','no'))<>'no'
 OR NOT (gmail_ok OR outlook_ok)
 OR NOT body_ok
 THEN RETURN jsonb_build_object('ok',false,'code','unverified_or_ambiguous_confirmation'); END IF;
 IF sender='bhavesh.patel@pmgwa.com.au' AND NOT outlook
 AND NOT pdc_codex_intake_private.bhavesh_email_authenticated_20260923(p_authentication,p_gmail_message_id)
 THEN RETURN jsonb_build_object('ok',false,'code','unverified_or_ambiguous_confirmation'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE stock_number=p_stock AND deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board AND board_purged_at IS NULL FOR UPDATE;
 IF NOT FOUND OR (SELECT count(*) FROM public.vehicles WHERE stock_number=p_stock AND deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board AND board_purged_at IS NULL)<>1
 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_identity_requires_review'); END IF;
 IF sender='bhavesh.patel@pmgwa.com.au' AND NOT pdc_codex_intake_private.bhavesh_vehicle_scope_20260923(v.id)
 THEN RETURN jsonb_build_object('ok',false,'code','department_138_vehicle_scope_required'); END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_parts_completion_email_confirmations WHERE gmail_message_id=p_gmail_message_id AND evidence_sha256<>p_evidence_sha256) THEN RETURN jsonb_build_object('ok',false,'code','evidence_replay_conflict'); END IF;
 SELECT * INTO c FROM public.pdc_parts_completion_email_confirmations WHERE gmail_message_id=p_gmail_message_id AND vehicle_id=v.id;
 IF FOUND THEN
  IF c.vehicle_id<>v.id OR c.evidence_sha256<>p_evidence_sha256 THEN RETURN jsonb_build_object('ok',false,'code','evidence_replay_conflict'); END IF;
  RETURN jsonb_build_object('ok',true,'replay',true,'confirmation_id',c.confirmation_id,'vehicle_id',v.id,'parts_status',public.pdc_parts_flags_vehicle_20260911(v.id));
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_parts_completion_email_confirmations WHERE vehicle_id=v.id AND active)
 THEN RETURN jsonb_build_object('ok',true,'code','already_confirmed','vehicle_id',v.id,'parts_status',public.pdc_parts_flags_vehicle_20260911(v.id)); END IF;
 actor:=pdc_codex_intake_private.import_actor();
 mailbox:=CASE WHEN outlook THEN 'pdc@pmgwa.com.au' ELSE 'pmbcontroller@gmail.com' END;
 INSERT INTO public.pdc_parts_completion_email_confirmations(vehicle_id,stock_number,mailbox,sender,gmail_message_id,received_at,subject,confirmation_text,evidence_sha256,authentication,recorded_by,owner_authority)
 VALUES(v.id,p_stock,mailbox,sender,p_gmail_message_id,p_received_at,coalesce(p_subject,''),p_confirmation_text,p_evidence_sha256,p_authentication,actor,
 'Craig ChatGPT 13 September 2026: verified person Parts Complete email confirms the exact board vehicle, overrides import flags and uses a green box with dark-green outline') RETURNING * INTO c;
 INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_received,updated_by) VALUES(v.id,true,true,actor);
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,after_data,metadata)
 VALUES('insert','pdc_parts_completion_email_confirmations',c.confirmation_id,v.id,actor,'codex-management',
 jsonb_build_object('parts_complete',true,'sender',sender,'received_at',c.received_at),
 jsonb_build_object('source','craig_authorised_person_email','gmail_message_id',p_gmail_message_id,'evidence_sha256',p_evidence_sha256,'overrides_import_flags',true,'workshop_completion_changed',false));
 PERFORM public.workshop_bump_revision();
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 status:=public.pdc_parts_flags_vehicle_20260911(v.id);
 IF status->>'colour' IS DISTINCT FROM 'green' OR status->>'person_confirmed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'confirmation_readback_failed'; END IF;
 RETURN jsonb_build_object('ok',true,'confirmation_id',c.confirmation_id,'vehicle_id',v.id,'stock_number',v.stock_number,'parts_status',status);
END
$person515$;

DROP FUNCTION IF EXISTS public.pdc_parts_reply_decision_541(text, jsonb);
DROP FUNCTION IF EXISTS public.pdc_parts_reply_wording_541(text);
DROP FUNCTION IF EXISTS public.pdc_parts_reply_norm_541(text);
DROP FUNCTION IF EXISTS public.pdc_parts_vehicle_match_541(text, text);
DROP FUNCTION IF EXISTS public.pdc_parts_mailbox_recipient_541(jsonb, text);

ALTER TABLE public.pdc_parts_completion_email_confirmations DROP CONSTRAINT person_confirmation_stock;
ALTER TABLE public.pdc_parts_completion_email_confirmations ADD CONSTRAINT person_confirmation_stock CHECK (stock_number ~ '^([0-9]{8}|IS[0-9]{8})$');

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, 'c5314b7bed8a1401b6698319125c2d74', '8ddb1477beeb94c7879c4021cccf1d40')
WHERE check_name IN ('outlook_parts_completion_514','outlook_internal_parts_auth_515')
  AND fault_id IN ('F128','F129')
  AND sort_order IN (301,302)
  AND check_sql LIKE '%c5314b7bed8a1401b6698319125c2d74%';

DELETE FROM pdc_ops.regression_checks
WHERE check_name='parts_complete_wording_555' AND fault_id='F169' AND sort_order=330 AND added_in='r555';

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r555 undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM '8ddb1477beeb94c7879c4021cccf1d40' THEN RAISE EXCEPTION 'r555 undo: person body was not restored'; END IF;
 IF to_regprocedure('public.pdc_parts_reply_wording_541(text)') IS NOT NULL
    OR to_regprocedure('public.pdc_parts_reply_decision_541(text,jsonb)') IS NOT NULL
    OR to_regprocedure('public.pdc_parts_reply_norm_541(text)') IS NOT NULL
    OR to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)') IS NOT NULL
    OR to_regprocedure('public.pdc_parts_vehicle_match_541(text,text)') IS NOT NULL
 THEN RAISE EXCEPTION 'r555 undo: wording helper remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='parts_complete_wording_555') THEN RAISE EXCEPTION 'r555 undo: check remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name IN ('outlook_parts_completion_514','outlook_internal_parts_auth_515') AND check_sql LIKE '%c5314b7bed8a1401b6698319125c2d74%') THEN RAISE EXCEPTION 'r555 undo: new person md5 remains'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conname='person_confirmation_stock' AND c.conrelid=to_regclass('public.pdc_parts_completion_email_confirmations')) IS DISTINCT FROM 'CHECK ((stock_number ~ ''^([0-9]{8}|IS[0-9]{8})$''::text))' THEN RAISE EXCEPTION 'r555 undo: public stock check was not restored'; END IF;
END $p$;
