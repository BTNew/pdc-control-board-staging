-- r515 (F129): internal same-tenant Outlook parts-complete replies.
-- Staging cdsmnqxtyyoeoznmbidd only. Preview. Not applied by this change. Never touch production.
-- Follow-up to live r514 (F128, person prosrc eb02f76ec94cd0b6c824a18660432afa, mark prosrc f5bdb212b439fd37adb73860c5e5d4d3).
-- Kajel called record_pdc_person_parts_complete_20260913 for IS60353006 and got
-- unverified_or_ambiguous_confirmation. The message never left the tenant, so Exchange
-- stamped X-MS-Exchange-Organization-AuthAs: Internal and Authentication-Results
--   mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=pmgwa.com.au;
-- mx.microsoft.com matches. dkim=none, dmarc=none and there is no spf=pass, so r514 outlook_ok rejects it.
-- This release does not invent Authentication-Results. The external dkim/dmarc/spf path stays.
-- An internal path accepts AuthAs=Internal when the sender domain and header.from are pmgwa.com.au.
-- Gmail branch unchanged. mark_pdc_parts_complete unchanged. Karratha unchanged. service_role still has no EXECUTE.
-- Pin count stays 225. These two functions are not in expected_function_md5.
-- Evidence (do not invent a different Authentication-Results or an AuthSource):
--   internetMessageId <SY1P282MB63556EA203EA75E467DCAC23AC642@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>
--   mailbox pdc@pmgwa.com.au, from talin.parker@pmgwa.com.au
--   evidence_sha256 c94f7ca4357c95113dbfcb15cd93cb21d24d9714ad99056cbaaf59bfcdda8656
-- Kajel jsonb keys for the internal path are documented in release_log/r515/NOTES.
-- Undo: supabase/rollbacks/20261023170000_r515_outlook_internal_parts_auth.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r515: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r515: staging only'; END IF;
 PERFORM set_config('pdc.r515_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r515_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r515_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r515_role',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure),true);
 PERFORM set_config('pdc.r515_k135id',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 PERFORM set_config('pdc.r515_k135mb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 IF current_setting('pdc.r515_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r515: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r515_pins')::int IS DISTINCT FROM 225 THEN RAISE EXCEPTION 'r515: expected 225 pins at tip, got %', current_setting('pdc.r515_pins'); END IF;
 IF current_setting('pdc.r515_role') IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r515: is_pdc_role is not the r421 pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM 'eb02f76ec94cd0b6c824a18660432afa' THEN RAISE EXCEPTION 'r515: person recorder is not the r514 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM 'f5bdb212b439fd37adb73860c5e5d4d3' THEN RAISE EXCEPTION 'r515: mark_pdc_parts_complete is not the r514 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_wayne_parts_complete_20260912(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '00f688462ca997065b7ad932a0f4d2c8' THEN RAISE EXCEPTION 'r515: wayne recorder changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure) IS DISTINCT FROM '6c828cb4ffdd7e0717bd5d9f50f4c764' THEN RAISE EXCEPTION 'r515: parts flags changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r515: revolution auth is not the r505 body'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' OR added_in='r515' OR fault_id='F129' OR sort_order=302) THEN RAISE EXCEPTION 'r515: id taken'; END IF;
 IF to_regclass('pdc_ops.r515_person_parts_prev') IS NOT NULL THEN RAISE EXCEPTION 'r515: undo preimage already exists'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301) IS DISTINCT FROM 'cd2ee86341370cb6b214456ed7da5640' THEN RAISE EXCEPTION 'r515: r514 check is not the live text'; END IF;
 IF (SELECT (length(check_sql)-length(replace(check_sql,'eb02f76ec94cd0b6c824a18660432afa','')))/32 FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'r515: r514 check does not pin the r514 person md5 once'; END IF;
 IF current_setting('pdc.r515_k135id') IS NULL
    OR current_setting('pdc.r515_k135id') NOT LIKE '%^[a-f0-9]{10,40}$%'
    OR current_setting('pdc.r515_k135id') LIKE '%BETWEEN 8 AND 512%' THEN RAISE EXCEPTION 'r515: karratha confirmation message-id CHECK is not the parked hex check'; END IF;
 IF current_setting('pdc.r515_k135mb') IS NULL
    OR current_setting('pdc.r515_k135mb') NOT LIKE '%pmbcontroller@gmail.com%'
    OR current_setting('pdc.r515_k135mb') LIKE '%pdc@pmgwa.com.au%' THEN RAISE EXCEPTION 'r515: karratha confirmation mailbox CHECK is not the parked pmbcontroller check'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND sort_order=301 AND fault_id='F128') THEN RAISE EXCEPTION 'r515: r514 check is not applied'; END IF;
END $g$;

CREATE TABLE pdc_ops.r515_person_parts_prev (
  signature text PRIMARY KEY,
  body text NOT NULL,
  prosecdef boolean,
  proconfig text[]
);
REVOKE ALL ON TABLE pdc_ops.r515_person_parts_prev FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO pdc_ops.r515_person_parts_prev(signature, body, prosecdef, proconfig)
SELECT 'person', p.prosrc, p.prosecdef, p.proconfig
FROM pg_proc p WHERE p.oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure
UNION ALL
SELECT 'check514', c.check_sql, NULL, NULL
FROM pdc_ops.regression_checks c
WHERE c.check_name='outlook_parts_completion_514' AND c.added_in='r514' AND c.fault_id='F128' AND c.sort_order=301;

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

REVOKE ALL ON FUNCTION public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, 'eb02f76ec94cd0b6c824a18660432afa', '8ddb1477beeb94c7879c4021cccf1d40')
WHERE check_name='outlook_parts_completion_514'
  AND added_in='r514'
  AND fault_id='F128'
  AND sort_order=301
  AND md5(check_sql)='cd2ee86341370cb6b214456ed7da5640';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('outlook_internal_parts_auth_515','F129','Internal same-tenant Outlook parts-complete (r515): mailbox and To stay pdc@pmgwa.com.au, verified_by stays microsoft_receiving_provider, and the message id still matches internet_message_id or the r514 outlook/microsoft aliases. The r514 external path still needs dkim, dmarc or spf pass. The internal path accepts auth_as or x_ms_exchange_organization_authas = Internal when from_address and header.from are pmgwa.com.au, including the real dkim=none / dmarc=none Authentication-Results with no spf pass. auth_source and x_ms_exchange_organization_authsource are optional hostnames. Gmail still needs the Gmail mailbox, verifier and mx.google.com. mark_pdc_parts_complete stays the r514 body. Karratha confirmations stay hex and pmbcontroller-only. service_role still cannot execute either function.',
  $chk515$
WITH base AS (
  SELECT jsonb_build_object(
    'mailbox','pdc@pmgwa.com.au',
    'to_address','pdc@pmgwa.com.au',
    'from_address','talin.parker@pmgwa.com.au',
    'header_from','pmgwa.com.au',
    'verified_by','microsoft_receiving_provider',
    'internet_message_id','<SY1P282MB63556EA203EA75E467DCAC23AC642@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>',
    'p_gmail_message_id','<SY1P282MB63556EA203EA75E467DCAC23AC642@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>',
    'authentication_results','mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=pmgwa.com.au;',
    'auth_as','Internal',
    'human_message','true',
    'unquoted_affirmative','true',
    'auto_submitted','no'
  ) AS a
), cases(label, want, a) AS (
  SELECT * FROM (VALUES
    ('real internal, no auth_source', true, (SELECT a FROM base)),
    ('missing auth_as', false, (SELECT a FROM base) - 'auth_as'),
    ('auth_as External', false, (SELECT a FROM base) || '{"auth_as":"External"}'::jsonb),
    ('auth_as Anonymous', false, (SELECT a FROM base) || '{"auth_as":"Anonymous"}'::jsonb),
    ('header key only', true, ((SELECT a FROM base) - 'auth_as') || '{"x_ms_exchange_organization_authas":"Internal"}'::jsonb),
    ('both auth_as keys agree', true, (SELECT a FROM base) || '{"x_ms_exchange_organization_authas":"internal"}'::jsonb),
    ('auth_as keys disagree', false, (SELECT a FROM base) || '{"x_ms_exchange_organization_authas":"External"}'::jsonb),
    ('padded auth_as', true, (SELECT a FROM base) || '{"auth_as":" Internal "}'::jsonb),
    ('hostname auth_source', true, (SELECT a FROM base) || '{"auth_source":"SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM"}'::jsonb),
    ('blank auth_source', false, (SELECT a FROM base) || '{"auth_source":""}'::jsonb),
    ('spaced auth_source', false, (SELECT a FROM base) || '{"auth_source":"not a host"}'::jsonb),
    ('auth_source keys disagree', false, (SELECT a FROM base) || '{"auth_source":"server-a.outlook.com","x_ms_exchange_organization_authsource":"server-b.outlook.com"}'::jsonb),
    ('auth_source keys same hostname', true, (SELECT a FROM base) || '{"auth_source":"Server.Example.com","x_ms_exchange_organization_authsource":"server.example.com"}'::jsonb),
    ('mixed-case from address', true, (SELECT a FROM base) || '{"from_address":"Talin.Parker@PMGWA.com.au"}'::jsonb),
    ('header_from mismatches from domain', false, (SELECT a FROM base) || '{"header_from":"evil.com"}'::jsonb),
    ('other from domain', false, (SELECT a FROM base) || jsonb_build_object(
       'from_address','person@example.com','header_from','example.com',
       'authentication_results','mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=example.com;')),
    ('ar header.from is not the sender domain', false, (SELECT a FROM base) || jsonb_build_object(
       'authentication_results','mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=example.com;')),
    ('no header.from in authentication_results', false, (SELECT a FROM base) || jsonb_build_object(
       'authentication_results','mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none;')),
    ('spf fail still internal', true, (SELECT a FROM base) || jsonb_build_object(
       'authentication_results','mx.microsoft.com 1; spf=fail smtp.mailfrom=pmgwa.com.au; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=pmgwa.com.au;')),
    ('external spf pass, no auth_as', true, ((SELECT a FROM base) - 'auth_as') || jsonb_build_object(
       'authentication_results','mx.microsoft.com 1; spf=pass smtp.mailfrom=pmgwa.com.au;')),
    ('external dkim pass, no auth_as', true, ((SELECT a FROM base) - 'auth_as') || jsonb_build_object(
       'authentication_results','mx.microsoft.com; dkim=pass header.d=pmgwa.com.au;')),
    ('external dmarc pass, no auth_as', true, ((SELECT a FROM base) - 'auth_as') || jsonb_build_object(
       'authentication_results','mx.microsoft.com; dmarc=pass header.from=pmgwa.com.au;')),
    ('external spf for another sender domain', true, ((SELECT a FROM base) - 'auth_as') || jsonb_build_object(
       'from_address','person@revolutionsoftware.com.au','header_from','revolutionsoftware.com.au',
       'authentication_results','mx.microsoft.com; spf=pass smtp.mailfrom=revolutionsoftware.com.au;')),
    ('internal auth_as for another sender domain', false, (SELECT a FROM base) || jsonb_build_object(
       'from_address','person@revolutionsoftware.com.au','header_from','revolutionsoftware.com.au',
       'authentication_results','mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=revolutionsoftware.com.au;')),
    ('id mismatch', false, (SELECT a FROM base) || '{"p_gmail_message_id":"<other@host>"}'::jsonb),
    ('outlook_message_id alias', true, ((SELECT a FROM base) - 'internet_message_id') || jsonb_build_object('outlook_message_id','<SY1P282MB63556EA203EA75E467DCAC23AC642@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>')),
    ('wrong to', false, (SELECT a FROM base) || '{"to_address":"other@pmgwa.com.au"}'::jsonb),
    ('gmail verifier', false, (SELECT a FROM base) || '{"verified_by":"gmail_receiving_provider"}'::jsonb),
    ('mx.google.com', false, (SELECT a FROM base) || jsonb_build_object(
       'authentication_results','mx.google.com; dkim=none header.d=none; dmarc=none header.from=pmgwa.com.au;')),
    ('spaced message id', false, (SELECT a FROM base) || jsonb_build_object(
       'p_gmail_message_id','<id with space@host>','internet_message_id','<id with space@host>')),
    ('gmail classic still passes', true, jsonb_build_object(
       'mailbox','pmbcontroller@gmail.com','to_address','pmbcontroller@gmail.com',
       'from_address','person@pmgwa.com.au','header_from','pmgwa.com.au',
       'verified_by','gmail_receiving_provider','p_gmail_message_id','1a158481917b7196',
       'internet_message_id','1a158481917b7196',
       'authentication_results','mx.google.com; dkim=pass header.d=pmgwa.com.au; dmarc=pass header.from=pmgwa.com.au')),
    ('gmail mailbox plus auth_as internal', false, jsonb_build_object(
       'mailbox','pmbcontroller@gmail.com','to_address','pmbcontroller@gmail.com',
       'from_address','talin.parker@pmgwa.com.au','header_from','pmgwa.com.au',
       'verified_by','gmail_receiving_provider','p_gmail_message_id','1a158481917b7196',
       'internet_message_id','<SY1P282MB63556EA203EA75E467DCAC23AC642@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>','auth_as','Internal',
       'authentication_results','mx.microsoft.com 1; dkim=none (message not signed) header.d=none;dmarc=none action=none header.from=pmgwa.com.au;'))
  ) AS v(label, want, a)
), step AS (
  SELECT label, want, a,
    lower(btrim(a->>'from_address')) AS sender,
    split_part(lower(btrim(a->>'from_address')),'@',2) AS domain,
    a->>'authentication_results' AS auth_result,
    nullif(lower(btrim(a->>'auth_as')),'') AS auth_as,
    nullif(lower(btrim(a->>'x_ms_exchange_organization_authas')),'') AS auth_as_alt,
    a->>'auth_source' AS auth_source_raw,
    a->>'x_ms_exchange_organization_authsource' AS auth_source_alt_raw
  FROM cases
), step2 AS (
  SELECT *,
    nullif(btrim(auth_source_raw),'') AS auth_source,
    nullif(btrim(auth_source_alt_raw),'') AS auth_source_alt,
    coalesce((auth_as='internal' OR auth_as_alt='internal')
      AND (auth_as IS NULL OR auth_as_alt IS NULL OR auth_as=auth_as_alt),false) AS internal_auth
  FROM step
), step3 AS (
  SELECT *,
    coalesce((auth_source_raw IS NULL AND auth_source_alt_raw IS NULL) OR (
      (auth_source_raw IS NULL OR auth_source ~ '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$')
      AND (auth_source_alt_raw IS NULL OR auth_source_alt ~ '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$')
      AND (auth_source IS NULL OR auth_source_alt IS NULL OR lower(auth_source)=lower(auth_source_alt))
      AND (auth_source IS NOT NULL OR auth_source_alt IS NOT NULL)
    ),false) AS source_ok,
    coalesce(
      auth_result ~* ('dkim=pass[^;]*header[.](i=@|d=)'||replace(domain,'.','\.')||'([;[:space:]]|$)')
      OR auth_result ~* ('(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)')
      OR auth_result ~* ('(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=([^;[:space:]]*@)?'||replace(domain,'.','\.')||'([;[:space:]]|$)')
    ,false) AS external_ok
  FROM step2
), step4 AS (
  SELECT *,
    coalesce(internal_auth AND source_ok AND domain='pmgwa.com.au'
      AND coalesce(auth_result,'') ~* ('header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)'),false) AS internal_ok,
    (a->>'mailbox'='pdc@pmgwa.com.au') AS outlook,
    (a->>'mailbox'='pmbcontroller@gmail.com'
      AND coalesce(a->>'p_gmail_message_id','') ~ '^[a-f0-9]{10,40}$'
      AND a->>'to_address'='pmbcontroller@gmail.com'
      AND a->>'verified_by'='gmail_receiving_provider'
      AND coalesce(auth_result ~* '^mx[.]google[.]com;' AND (
        auth_result ~* ('dkim=pass[^;]*header[.](i=@|d=)'||replace(domain,'.','\.')||'([;[:space:]]|$)')
        OR auth_result ~* ('(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)')
      ),false)) AS gmail_ok
  FROM step3
), ev AS (
  SELECT label, want,
    ((a->>'header_from' IS NOT DISTINCT FROM domain) AND (gmail_ok OR coalesce(outlook
      AND a->>'p_gmail_message_id' IS NOT NULL
      AND length(a->>'p_gmail_message_id') BETWEEN 8 AND 512
      AND a->>'p_gmail_message_id' !~ '[[:space:]]'
      AND (a->>'internet_message_id'=a->>'p_gmail_message_id'
        OR a->>'outlook_message_id'=a->>'p_gmail_message_id'
        OR a->>'microsoft_message_id'=a->>'p_gmail_message_id')
      AND a->>'to_address'='pdc@pmgwa.com.au'
      AND a->>'verified_by'='microsoft_receiving_provider'
      AND coalesce(auth_result,'') ~* '^mx[.]microsoft[.]com([[:space:]]+[0-9]+)?[[:space:]]*;'
      AND (external_ok OR internal_ok),false))) AS got
  FROM step4
), fn AS (
  SELECT
   (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) AS person_md5,
   (SELECT prosrc FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) AS person_src,
   (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) AS mark_md5,
   (SELECT prosrc FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) AS mark_src
), k_id AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
    AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass
), k_mb AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
    AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass
)
SELECT (SELECT count(*)=32 AND bool_and(got IS NOT DISTINCT FROM want) FROM ev)
   AND (SELECT person_md5 FROM fn)='8ddb1477beeb94c7879c4021cccf1d40'
   AND (SELECT mark_md5 FROM fn)='f5bdb212b439fd37adb73860c5e5d4d3'
   AND (SELECT person_src FROM fn) LIKE '%auth_as%'
   AND (SELECT person_src FROM fn) LIKE '%x_ms_exchange_organization_authas%'
   AND (SELECT person_src FROM fn) LIKE '%x_ms_exchange_organization_authsource%'
   AND (SELECT person_src FROM fn) LIKE '%p_authentication->>''auth_source''%'
   AND (SELECT person_src FROM fn) LIKE '%domain=''pmgwa.com.au''%'
   AND (SELECT person_src FROM fn) LIKE '%gmail_receiving_provider%'
   AND (SELECT person_src FROM fn) LIKE '%pmbcontroller@gmail.com%'
   AND (SELECT person_src FROM fn) LIKE '%mx[.]google[.]com%'
   AND (SELECT mark_src FROM fn) LIKE '%management_connection()%'
   AND (SELECT mark_src FROM fn) LIKE '%require_pdc_role(''operator'')%'
   AND (SELECT mark_src FROM fn) NOT LIKE '%auth_as%'
   AND (SELECT mark_src FROM fn) NOT LIKE '%is_pdc_role%'
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure)='39a794b23d1d63117cf549d78acba4de'
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_wayne_parts_complete_20260912(text,text,timestamptz,text,text,text,jsonb)'::regprocedure)='00f688462ca997065b7ad932a0f4d2c8'
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure)='6c828cb4ffdd7e0717bd5d9f50f4c764'
   AND (SELECT count(*)=1 FROM k_id WHERE d LIKE '%^[a-f0-9]{10,40}$%' AND d NOT LIKE '%BETWEEN 8 AND 512%')
   AND (SELECT count(*)=1 FROM k_mb WHERE d LIKE '%pmbcontroller@gmail.com%' AND d NOT LIKE '%pdc@pmgwa.com.au%')
   AND NOT has_function_privilege('anon','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
   AND NOT has_function_privilege('authenticated','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
   AND NOT has_function_privilege('service_role','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
   AND NOT has_function_privilege('service_role','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
   AND has_function_privilege('authenticated','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
   AND (SELECT prosecdef FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS NOT TRUE
   AND (SELECT prosecdef FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS TRUE
   AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=225
   AND (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301)
       = md5(replace((SELECT body FROM pdc_ops.r515_person_parts_prev WHERE signature='check514'),'eb02f76ec94cd0b6c824a18660432afa','8ddb1477beeb94c7879c4021cccf1d40'))
   AND (SELECT check_sql LIKE '%8ddb1477beeb94c7879c4021cccf1d40%' AND check_sql NOT LIKE '%eb02f76ec94cd0b6c824a18660432afa%'
        FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514')
 AS ok,
 'cases '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM ev)||'/'||(SELECT count(*) FROM ev)
 ||coalesce(' WRONG: '||(SELECT string_agg(label,', ' ORDER BY label) FROM ev WHERE got IS DISTINCT FROM want),'')
 ||' person '||coalesce((SELECT left(person_md5,8) FROM fn),'missing')
 ||' mark '||coalesce((SELECT left(mark_md5,8) FROM fn),'missing')
 AS detail
$chk515$,true,302,'r515');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 225
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM current_setting('pdc.r515_pins')::int THEN RAISE EXCEPTION 'r515: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '8ddb1477beeb94c7879c4021cccf1d40' THEN RAISE EXCEPTION 'r515: person md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM 'f5bdb212b439fd37adb73860c5e5d4d3' THEN RAISE EXCEPTION 'r515: mark md5 changed'; END IF;
 IF (SELECT md5(body) FROM pdc_ops.r515_person_parts_prev WHERE signature='person') IS DISTINCT FROM 'eb02f76ec94cd0b6c824a18660432afa' THEN RAISE EXCEPTION 'r515: person preimage is not r514'; END IF;
 IF (SELECT md5(body) FROM pdc_ops.r515_person_parts_prev WHERE signature='check514') IS DISTINCT FROM 'cd2ee86341370cb6b214456ed7da5640' THEN RAISE EXCEPTION 'r515: r514 check preimage missing'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514')
    IS DISTINCT FROM md5(replace((SELECT body FROM pdc_ops.r515_person_parts_prev WHERE signature='check514'),'eb02f76ec94cd0b6c824a18660432afa','8ddb1477beeb94c7879c4021cccf1d40')) THEN RAISE EXCEPTION 'r515: r514 check was not re-pinned'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301) IS DISTINCT FROM 'd876e9bd42a929e659c811c0c9e6c2ec' THEN RAISE EXCEPTION 'r515: r514 check md5'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' AND added_in='r515' AND fault_id='F129' AND sort_order=302) IS DISTINCT FROM 'ece98352be4126d5fd4ad2707157cae2' THEN RAISE EXCEPTION 'r515: r515 check md5'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS TRUE THEN RAISE EXCEPTION 'r515: person recorder became SECURITY DEFINER'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS NOT TRUE THEN RAISE EXCEPTION 'r515: mark lost SECURITY DEFINER'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r515_role') THEN RAISE EXCEPTION 'r515: is_pdc_role changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_wayne_parts_complete_20260912(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '00f688462ca997065b7ad932a0f4d2c8' THEN RAISE EXCEPTION 'r515: wayne recorder changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure) IS DISTINCT FROM '6c828cb4ffdd7e0717bd5d9f50f4c764' THEN RAISE EXCEPTION 'r515: parts flags changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r515_tick') THEN RAISE EXCEPTION 'r515: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r515_frc') THEN RAISE EXCEPTION 'r515: fault_regression_check changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r515_k135id') THEN RAISE EXCEPTION 'r515: karratha message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r515_k135mb') THEN RAISE EXCEPTION 'r515: karratha mailbox CHECK changed'; END IF;
 IF has_function_privilege('service_role','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE') THEN RAISE EXCEPTION 'r515: mark grants changed'; END IF;
 IF has_function_privilege('service_role','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
    OR has_function_privilege('anon','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'r515: person grants changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' AND added_in='r515' AND sort_order=302 AND fault_id='F129') THEN RAISE EXCEPTION 'r515: check missing'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_internal_parts_auth_515';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r515: outlook_internal_parts_auth_515 failed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_parts_completion_514';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r515: r514 check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_sales_receipt_message_id_508';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r515: r508 check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_message_id_506';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r515: r506 check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_mailbox_507';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r515: r507 check regressed: %', y; END IF;
END $g$;
