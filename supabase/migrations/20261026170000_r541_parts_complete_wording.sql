-- r541 (F155). PREVIEW. SQL is not applied. Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- 26 Oct 2026 10:43 AWST: Talin Parker's reply 'All parts complete' on
-- 'RE: New vehicle order for 13102818 - PMG Build'
-- (message <SY1P282MB6355D7DB1314F5E461980BCEAC642@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>)
-- was refused as unverified_or_ambiguous_confirmation.
-- 26 Oct 2026 10:49 AWST: a clear affirmative counts. Parts complete, all parts complete, all parts are here,
-- parts are here, parts arrived, all parts in, and the same kind of sentence. A negative, a question or a
-- partial does not: not complete, waiting on, except, is it complete?, all parts removed.
-- The email-AI path may pass ai_classification (complete, not_complete or ambiguous), ai_confidence and ai_quote.
-- Only complete at high confidence is accepted, and a negative, question or partial still wins.
-- The verified internal pmgwa sender and the header checks stay.
-- The stock in 'New vehicle order for <stock> - PMG Build' is the number after for.
-- 26 Oct 2026 10:33 AWST: parts.malaga@pmgwa.com.au said 'Parts complete' for 1IRU519 / J138000880.
-- That row is active and was version 13. Version is not part of the match.
-- A stock may be 8 digits, IS plus 8, a rego such as 1IRU519, or one job card such as J138000880.
-- pdc@pmgwa.com.au may be in To, in Cc, or the message may be a forward. A plain reply that is not addressed to pdc@ stays refused.
-- Two stocks, two job cards, or two vehicles are still refused.
-- Pin count stays 241. The person recorder is not pinned. Sort 318 is r539. This check is sort 319.
-- Person prosrc md5 c5314b7bed8a1401b6698319125c2d74 (was 8ddb1477beeb94c7879c4021cccf1d40).
-- Undo: supabase/rollbacks/20261026170000_r541_parts_complete_wording.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r541: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r541: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r541: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM '8ddb1477beeb94c7879c4021cccf1d40' THEN RAISE EXCEPTION 'r541: person recorder is not the r515 body'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS TRUE THEN RAISE EXCEPTION 'r541: person recorder is security definer'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=319 OR fault_id='F155' OR check_name='parts_complete_wording_541' OR added_in='r541') THEN RAISE EXCEPTION 'r541: sort 319 or F155 is taken'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND fault_id='F128' AND sort_order=301) IS DISTINCT FROM 'afa4f64947a3a6a80c356928de75c918' THEN RAISE EXCEPTION 'r541: outlook_parts_completion_514 is not the live text'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515' AND added_in='r515' AND fault_id='F129' AND sort_order=302) IS DISTINCT FROM 'da6dcc4cd843090558c6e063b149035a' THEN RAISE EXCEPTION 'r541: outlook_internal_parts_auth_515 is not the live text'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conname='person_confirmation_stock' AND c.conrelid=to_regclass('public.pdc_parts_completion_email_confirmations')) IS DISTINCT FROM 'CHECK ((stock_number ~ ''^([0-9]{8}|IS[0-9]{8})$''::text))' THEN RAISE EXCEPTION 'r541: public stock check is not the live text'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conname='person_confirmation_stock' AND c.conrelid=to_regclass('karratha135_pdc.pdc_parts_completion_email_confirmations')) IS DISTINCT FROM 'CHECK ((stock_number ~ ''^([0-9]{8}|IS[0-9]{8})$''::text))' THEN RAISE EXCEPTION 'r541: karratha stock check changed'; END IF;
END $g$;

ALTER TABLE public.pdc_parts_completion_email_confirmations DROP CONSTRAINT person_confirmation_stock;
ALTER TABLE public.pdc_parts_completion_email_confirmations ADD CONSTRAINT person_confirmation_stock CHECK (stock_number ~ '^([0-9]{8}|IS[0-9]{8}|[0-9][A-Z]{2,4}[0-9]{2,4})$');

CREATE OR REPLACE FUNCTION public.pdc_parts_reply_norm_541(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO pg_catalog
AS $norm541$
DECLARE t text := lower(regexp_replace(btrim(coalesce(p_text,'')), '[[:space:]]+', ' ', 'g'));
BEGIN
  t := replace(t, '’', '''');
  t := regexp_replace(t, '[.,!]+$', '');
  t := btrim(regexp_replace(t, '\m(thanks|thank you|many thanks|cheers)\M$', ''));
  t := btrim(regexp_replace(t, '[.,!]+$', ''));
  RETURN t;
END
$norm541$;

CREATE OR REPLACE FUNCTION public.pdc_parts_reply_wording_541(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO pg_catalog
AS $word541$
DECLARE t text := public.pdc_parts_reply_norm_541(p_text);
BEGIN
  IF t = '' THEN RETURN 'ambiguous'; END IF;
  IF t ~ '\?'
     OR t ~ '^(is|are|do|does|did|can|could|has|have|will|would|when|what|which|why|how)\M'
     OR t ~ '\m(not|no|never|without|missing|waiting|except|outstanding|incomplete|removed|partial|but|none)\M'
     OR t ~ '\m(haven''t|hasn''t|don''t|didn''t|won''t|cannot|can''t|isn''t|aren''t)\M'
     OR t ~ '(all but|only some|some parts|most parts|apart from|other than|except for|waiting on|still waiting|yet to)'
  THEN RETURN 'not_complete'; END IF;
  IF length(t) > 80 THEN RETURN 'ambiguous'; END IF;
  IF t ~ '^(all )?(of )?(the |our )?parts( are| is| have| has| been)?( all| now| fully)? (here|in|complete|completed|arrived|received|ready|on hand|on site)( now)?$'
     OR t ~ '^(all )?(of )?(the |our )?parts (have |has )?(all )?(now )?(arrived|come in|come through)$'
     OR t ~ '^we (have|got) (all )?(of )?(the |our )?parts( now| here| in)?$'
     OR t ~ '^we''ve got (all )?(of )?(the |our )?parts( now| here| in)?$'
  THEN RETURN 'complete'; END IF;
  RETURN 'ambiguous';
END
$word541$;

CREATE OR REPLACE FUNCTION public.pdc_parts_reply_decision_541(p_text text, p_ai jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO pg_catalog
AS $dec541$
DECLARE
  wording text := public.pdc_parts_reply_wording_541(p_text);
  klass text := lower(btrim(coalesce(p_ai->>'ai_classification','')));
  confidence text := lower(btrim(coalesce(p_ai->>'ai_confidence','')));
  high boolean;
  quote text := public.pdc_parts_reply_norm_541(p_ai->>'ai_quote');
  body text := public.pdc_parts_reply_norm_541(p_text);
BEGIN
  high := confidence IN ('high','high_confidence')
    OR (confidence ~ '^[0-9]+([.][0-9]+)?$' AND confidence::numeric >= 0.9);
  IF wording = 'not_complete' OR klass = 'not_complete' THEN RETURN 'not_complete'; END IF;
  IF klass = 'ambiguous' THEN RETURN 'ambiguous'; END IF;
  IF klass = 'complete' AND high AND quote <> '' AND quote IS DISTINCT FROM body THEN RETURN 'ambiguous'; END IF;
  IF klass = 'complete' AND high AND wording = 'complete' THEN RETURN 'complete'; END IF;
  IF klass = 'complete' AND high AND quote = body AND body <> '' THEN RETURN 'complete'; END IF;
  IF klass = 'complete' AND NOT high THEN RETURN wording; END IF;
  IF klass = '' THEN RETURN wording; END IF;
  RETURN 'ambiguous';
END
$dec541$;

REVOKE ALL ON FUNCTION public.pdc_parts_reply_norm_541(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.pdc_parts_reply_wording_541(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.pdc_parts_reply_decision_541(text, jsonb) FROM PUBLIC, anon, authenticated, service_role;

-- pdc@ in To, Cc, or a forward. The mailbox flag and the sender proof stay in the recorder.
CREATE OR REPLACE FUNCTION public.pdc_parts_mailbox_recipient_541(p_authentication jsonb, p_subject text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO pg_catalog
AS $mb541$
DECLARE
  auth jsonb := coalesce(p_authentication, '{}'::jsonb);
  pat text := '(^|[^a-z0-9._%+-])pdc@pmgwa[.]com[.]au([^a-z0-9.-]|$)';
  blob text;
  key text;
  elem jsonb;
  subj text;
BEGIN
  blob := lower(concat_ws(' ', auth->>'to_address', auth->>'cc_address', auth->>'cc'));
  IF blob ~ pat THEN RETURN true; END IF;
  FOREACH key IN ARRAY ARRAY['to_addresses', 'cc_addresses', 'recipients']
  LOOP
    IF jsonb_typeof(auth->key) = 'array' THEN
      FOR elem IN SELECT t.value FROM jsonb_array_elements(auth->key) AS t(value)
      LOOP
        IF lower(coalesce(elem #>> '{}', '')) ~ pat THEN RETURN true; END IF;
      END LOOP;
    ELSIF jsonb_typeof(auth->key) = 'string' AND lower(auth->>key) ~ pat THEN
      RETURN true;
    END IF;
  END LOOP;
  IF lower(btrim(coalesce(auth->>'forwarded', ''))) IN ('true', 'yes', '1') THEN
    RETURN true;
  END IF;
  subj := lower(regexp_replace(btrim(coalesce(p_subject, '')), '[[:space:]]+', ' ', 'g'));
  subj := regexp_replace(subj, '^((re):[[:space:]]+)+', '');
  RETURN subj ~ '^(fw|fwd):[[:space:]]';
END
$mb541$;

-- One active visible vehicle. p_stock may be the stock, the rego, or the job card.
-- A subject token that names a second vehicle, or two rows, is ambiguous. Version is not a filter.
CREATE OR REPLACE FUNCTION public.pdc_parts_vehicle_match_541(p_stock text, p_subject text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO pg_catalog, public
AS $veh541$
DECLARE
  token text := upper(btrim(coalesce(p_stock, '')));
  subj text := lower(regexp_replace(btrim(coalesce(p_subject, '')), '[[:space:]]+', ' ', 'g'));
  shape text;
  stock_n integer := 0;
  job_n integer := 0;
  rego_n integer := 0;
  stock_tok text;
  job_tok text;
  rego_tok text;
  order_stock text;
  n integer := 0;
  vid text;
  vstock text;
  vjob text;
  vreg text;
BEGIN
  subj := regexp_replace(subj, '^((re|fw|fwd):[[:space:]]+)+', '');
  IF token ~ '^([0-9]{8}|IS[0-9]{8})$' THEN shape := 'eight';
  ELSIF token ~ '^[0-9][A-Z]{2,4}[0-9]{2,4}$' THEN shape := 'rego';
  ELSIF token ~ '^J[0-9]{6,12}$' THEN shape := 'job';
  ELSE RETURN jsonb_build_object('ok', false, 'code', 'not_found');
  END IF;
  SELECT count(DISTINCT upper(m[2]))::integer, min(upper(m[2])) INTO stock_n, stock_tok
    FROM regexp_matches(coalesce(p_subject, ''), '(^|[^A-Za-z0-9])(IS[0-9]{8}|[0-9]{8})(?=[^A-Za-z0-9]|$)', 'gi') AS m;
  SELECT count(DISTINCT upper(m[2]))::integer, min(upper(m[2])) INTO job_n, job_tok
    FROM regexp_matches(coalesce(p_subject, ''), '(^|[^A-Za-z0-9])(J[0-9]{6,12})(?=[^A-Za-z0-9]|$)', 'gi') AS m;
  SELECT count(DISTINCT upper(m[2]))::integer, min(upper(m[2])) INTO rego_n, rego_tok
    FROM regexp_matches(coalesce(p_subject, ''), '(^|[^A-Za-z0-9])([0-9][A-Za-z]{2,4}[0-9]{2,4})(?=[^A-Za-z0-9]|$)', 'gi') AS m;
  order_stock := substring(subj from '^new vehicle order for ([0-9]{8}|is[0-9]{8}) - pmg build$');
  IF stock_n > 1 OR job_n > 1 OR rego_n > 1 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF shape = 'eight' AND stock_n = 1 AND stock_tok IS DISTINCT FROM token THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF shape = 'rego' AND rego_n = 1 AND rego_tok IS DISTINCT FROM token THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF shape = 'job' AND job_n = 1 AND job_tok IS DISTINCT FROM token THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF shape = 'eight' AND order_stock IS NOT NULL AND order_stock IS DISTINCT FROM lower(token) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF shape IN ('eight', 'rego') THEN
    SELECT count(*)::integer,
           CASE WHEN count(*) = 1 THEN min(v.id::text) END,
           CASE WHEN count(*) = 1 THEN min(v.stock_number) END,
           CASE WHEN count(*) = 1 THEN min(upper(btrim(v.job_card_number))) END,
           CASE WHEN count(*) = 1 THEN min(upper(btrim(coalesce(v.registration, '')))) END
      INTO n, vid, vstock, vjob, vreg
      FROM public.vehicles v
     WHERE v.deleted_at IS NULL
       AND v.lifecycle_state = 'active'
       AND v.visible_on_board IS TRUE
       AND v.board_purged_at IS NULL
       AND (
         upper(btrim(v.stock_number)) = token
         OR (shape = 'rego' AND upper(btrim(coalesce(v.registration, ''))) = token)
       );
  ELSE
    SELECT count(*)::integer,
           CASE WHEN count(*) = 1 THEN min(v.id::text) END,
           CASE WHEN count(*) = 1 THEN min(v.stock_number) END,
           CASE WHEN count(*) = 1 THEN min(upper(btrim(v.job_card_number))) END,
           CASE WHEN count(*) = 1 THEN min(upper(btrim(coalesce(v.registration, '')))) END
      INTO n, vid, vstock, vjob, vreg
      FROM public.vehicles v
     WHERE v.deleted_at IS NULL
       AND v.lifecycle_state = 'active'
       AND v.visible_on_board IS TRUE
       AND v.board_purged_at IS NULL
       AND upper(btrim(v.job_card_number)) = token;
  END IF;
  IF coalesce(n, 0) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_found');
  END IF;
  IF n <> 1 OR vid IS NULL OR vstock IS NULL
     OR vstock !~ '^([0-9]{8}|IS[0-9]{8}|[0-9][A-Z]{2,4}[0-9]{2,4})$' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF job_n = 1 AND job_tok IS DISTINCT FROM vjob THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF rego_n = 1 AND rego_tok IS DISTINCT FROM upper(btrim(vstock)) AND rego_tok IS DISTINCT FROM vreg THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF stock_n = 1 AND stock_tok IS DISTINCT FROM upper(btrim(vstock)) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  IF order_stock IS NOT NULL AND order_stock IS DISTINCT FROM lower(vstock) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ambiguous');
  END IF;
  RETURN jsonb_build_object('ok', true, 'code', 'matched', 'vehicle_id', vid, 'stock_number', vstock);
END
$veh541$;

REVOKE ALL ON FUNCTION public.pdc_parts_mailbox_recipient_541(jsonb, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.pdc_parts_vehicle_match_541(text, text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.record_pdc_person_parts_complete_20260913(p_stock text, p_gmail_message_id text, p_received_at timestamp with time zone, p_subject text, p_confirmation_text text, p_evidence_sha256 text, p_authentication jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_codex_intake_private'
AS $person541$
DECLARE v public.vehicles%rowtype; c public.pdc_parts_completion_email_confirmations%rowtype;
 actor uuid; status jsonb; sender text:=lower(btrim(p_authentication->>'from_address'));
 domain text; auth_result text; body text; authenticated_sender boolean;
 outlook boolean; gmail_ok boolean; outlook_ok boolean; body_ok boolean; mailbox text;
 auth_as text; auth_as_alt text; auth_source text; auth_source_alt text;
 auth_source_raw text; auth_source_alt_raw text;
 internal_auth boolean; source_ok boolean; external_ok boolean; internal_ok boolean;
 subj text; order_stock text; plain boolean; order_disagrees boolean;
 stock_n integer; stock_body text; stock_hit boolean;
 ident jsonb; tok text; nveh integer;
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
  AND public.pdc_parts_mailbox_recipient_541(p_authentication, p_subject)
  AND p_authentication->>'verified_by'='microsoft_receiving_provider'
  AND coalesce(auth_result,'') ~* '^mx[.]microsoft[.]com([[:space:]]+[0-9]+)?[[:space:]]*;'
  AND (external_ok OR internal_ok),false);
 -- r541: a clear affirmative, or email-AI complete at high confidence. A negative, question or partial stays refused.
 subj:=lower(regexp_replace(btrim(coalesce(p_subject,'')),'[[:space:]]+',' ','g'));
 subj:=regexp_replace(subj,'^((re|fw|fwd):[[:space:]]+)+','');
 order_stock:=substring(subj from '^new vehicle order for ([0-9]{8}|is[0-9]{8}) - pmg build$');
 SELECT count(DISTINCT upper(m[2]))::integer INTO stock_n
  FROM regexp_matches(coalesce(p_subject,''),'(^|[^A-Za-z0-9])(IS[0-9]{8}|[0-9]{8})(?=[^A-Za-z0-9]|$)','gi') AS m;
 stock_hit:=coalesce(p_stock,'') ~ '^([0-9]{8}|IS[0-9]{8})$'
  AND coalesce(body,'') ~* ('(^|[^A-Za-z0-9])'||p_stock||'([^A-Za-z0-9]|$)');
 stock_body:=CASE WHEN stock_hit THEN btrim(regexp_replace(regexp_replace(
   regexp_replace(body,'(^|[^A-Za-z0-9])'||lower(p_stock)||'([^A-Za-z0-9]|$)',' ','gi'),
   '\mfor\M',' ','g'),'[[:space:]]+',' ','g')) ELSE '' END;
 plain:=public.pdc_parts_reply_decision_541(p_confirmation_text, p_authentication)='complete';
 order_disagrees:=order_stock IS NOT NULL AND order_stock IS DISTINCT FROM lower(p_stock);
 -- parts.malaga@pmgwa.com.au may say Parts complete for 1IRU519 / J138000880. pdc@pmgwa.com.au may be in Cc.
 body_ok:=(body ~ ('^(parts complete( for)? '||lower(p_stock)||'|'||lower(p_stock)||' parts complete)[.!]?$')
   AND upper(btrim(coalesce(p_stock,''))) ~ '^([0-9]{8}|IS[0-9]{8})$'
   AND coalesce(stock_n,0)<=1 AND NOT order_disagrees)
  OR (outlook AND body ~ '^parts complete[.!]?$'
      AND coalesce(p_stock,'') ~ '^([0-9]{8}|IS[0-9]{8})$'
      AND stock_n=1 AND NOT order_disagrees
      AND coalesce(p_subject,'') ~* ('(^|[^A-Za-z0-9])'||p_stock||'([^A-Za-z0-9]|$)'))
  OR (outlook AND internal_ok AND stock_hit AND public.pdc_parts_reply_wording_541(stock_body)='complete'
      AND coalesce(stock_n,0)<=1 AND NOT order_disagrees)
  OR (outlook AND internal_ok AND domain='pmgwa.com.au' AND plain);
 IF p_stock IS NULL OR upper(btrim(p_stock)) !~ '^([0-9]{8}|IS[0-9]{8}|[0-9][A-Z]{2,4}[0-9]{2,4}|J[0-9]{6,12})$'
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
 ident:=public.pdc_parts_vehicle_match_541(p_stock, p_subject);
 IF coalesce(ident->>'code','') <> 'matched' OR ident->>'vehicle_id' IS NULL THEN
  RETURN jsonb_build_object('ok',false,'code','vehicle_identity_requires_review');
 END IF;
 tok:=upper(btrim(p_stock));
 SELECT * INTO v FROM public.vehicles
  WHERE id=(ident->>'vehicle_id')::uuid
    AND deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board IS TRUE AND board_purged_at IS NULL
  FOR UPDATE;
 IF tok ~ '^J[0-9]{6,12}$' THEN
  SELECT count(*)::integer INTO nveh FROM public.vehicles
   WHERE deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board IS TRUE AND board_purged_at IS NULL
     AND upper(btrim(job_card_number))=tok;
 ELSIF tok ~ '^([0-9]{8}|IS[0-9]{8})$' THEN
  SELECT count(*)::integer INTO nveh FROM public.vehicles
   WHERE deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board IS TRUE AND board_purged_at IS NULL
     AND upper(btrim(stock_number))=tok;
 ELSE
  SELECT count(*)::integer INTO nveh FROM public.vehicles
   WHERE deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board IS TRUE AND board_purged_at IS NULL
     AND (upper(btrim(stock_number))=tok OR upper(btrim(coalesce(registration,'')))=tok);
 END IF;
 IF NOT FOUND OR coalesce(nveh,0)<>1
  OR public.pdc_parts_vehicle_match_541(p_stock, p_subject)->>'vehicle_id' IS DISTINCT FROM v.id::text
  OR v.stock_number !~ '^([0-9]{8}|IS[0-9]{8}|[0-9][A-Z]{2,4}[0-9]{2,4})$'
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
 VALUES(v.id,v.stock_number,mailbox,sender,p_gmail_message_id,p_received_at,coalesce(p_subject,''),p_confirmation_text,p_evidence_sha256,p_authentication,actor,
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
$person541$;

REVOKE ALL ON FUNCTION public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;

UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql, '8ddb1477beeb94c7879c4021cccf1d40', 'c5314b7bed8a1401b6698319125c2d74')
WHERE check_name IN ('outlook_parts_completion_514','outlook_internal_parts_auth_515')
  AND fault_id IN ('F128','F129')
  AND sort_order IN (301,302)
  AND check_sql LIKE '%8ddb1477beeb94c7879c4021cccf1d40%';

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('parts_complete_wording_541', 'F155',
 'Parts-complete wording (r541): a clear affirmative from a verified internal pmgwa sender counts. A rego such as 1IRU519 or one job card such as J138000880 resolves one active vehicle. pdc@ in To, Cc, or a forward counts. A second match, or a reply that is not addressed to pdc@, stays refused. Karratha keeps the 8-digit stock check.',
 $chk541$
SELECT
 (
  pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)') IS NOT NULL
  AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'))
      = 'c5314b7bed8a1401b6698319125c2d74'
  AND (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS NOT TRUE
  AND pg_catalog.to_regprocedure('public.pdc_parts_reply_wording_541(text)') IS NOT NULL
  AND pg_catalog.to_regprocedure('public.pdc_parts_reply_decision_541(text,jsonb)') IS NOT NULL
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%pdc_parts_reply_decision_541%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_reply_decision_541(text,jsonb)')) LIKE '%ai_classification%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_reply_decision_541(text,jsonb)')) LIKE '%ai_confidence%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_reply_decision_541(text,jsonb)')) LIKE '%ai_quote%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%new vehicle order for%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%parts.malaga@pmgwa.com.au%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%IS[0-9]{8}%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%internal_ok AND domain=''pmgwa.com.au'' AND plain%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%pdc_parts_mailbox_recipient_541%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%pdc_parts_vehicle_match_541%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) LIKE '%pdc@pmgwa.com.au%'
  AND pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)') IS NOT NULL
  AND pg_catalog.to_regprocedure('public.pdc_parts_vehicle_match_541(text,text)') IS NOT NULL
  AND (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) IS NOT TRUE
  AND (SELECT p.prosecdef FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_vehicle_match_541(text,text)')) IS NOT TRUE
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) LIKE '%cc_addresses%'
  AND (SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.pdc_parts_mailbox_recipient_541(jsonb,text)')) LIKE '%forwarded%'
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"pdc@pmgwa.com.au"}'::pg_catalog.jsonb, 'Parts complete') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"parts.malaga@pmgwa.com.au","cc_addresses":["pdc@pmgwa.com.au"]}'::pg_catalog.jsonb, '1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"parts.malaga@pmgwa.com.au","cc_address":"Workshop <pdc@pmgwa.com.au>"}'::pg_catalog.jsonb, '1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au"}'::pg_catalog.jsonb, 'FW: 1IRU519 J138000880 EPT') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au","forwarded":"true"}'::pg_catalog.jsonb, '1IRU519 J138000880') IS TRUE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au"}'::pg_catalog.jsonb, 'RE: New vehicle order for 13102818 - PMG Build') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"other@pmgwa.com.au","cc_addresses":[]}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND public.pdc_parts_mailbox_recipient_541('{"to_address":"pdc@pmgwa.com.au.example.net"}'::pg_catalog.jsonb, 'Parts complete') IS FALSE
  AND public.pdc_parts_reply_wording_541('parts complete') = 'complete'
  AND public.pdc_parts_reply_wording_541('all parts complete') = 'complete'
  AND public.pdc_parts_reply_wording_541('all parts are here') = 'complete'
  AND public.pdc_parts_reply_wording_541('parts are here') = 'complete'
  AND public.pdc_parts_reply_wording_541('parts arrived') = 'complete'
  AND public.pdc_parts_reply_wording_541('all parts in') = 'complete'
  AND public.pdc_parts_reply_wording_541('All parts complete.') = 'complete'
  AND public.pdc_parts_reply_wording_541('the parts have arrived') = 'complete'
  AND public.pdc_parts_reply_wording_541('parts complete thanks') = 'complete'
  AND public.pdc_parts_reply_wording_541('not complete') = 'not_complete'
  AND public.pdc_parts_reply_wording_541('waiting on') = 'not_complete'
  AND public.pdc_parts_reply_wording_541('except') = 'not_complete'
  AND public.pdc_parts_reply_wording_541('is it complete?') = 'not_complete'
  AND public.pdc_parts_reply_wording_541('all parts removed') = 'not_complete'
  AND public.pdc_parts_reply_wording_541('parts are not here') = 'not_complete'
  AND public.pdc_parts_reply_wording_541('some parts are here') = 'not_complete'
  AND public.pdc_parts_reply_decision_541('parts complete', NULL::pg_catalog.jsonb) = 'complete'
  AND public.pdc_parts_reply_decision_541('the canopy landed', '{"ai_classification":"complete","ai_confidence":"high","ai_quote":"the canopy landed"}'::pg_catalog.jsonb) = 'complete'
  AND public.pdc_parts_reply_decision_541('all parts removed', '{"ai_classification":"complete","ai_confidence":"high","ai_quote":"all parts removed"}'::pg_catalog.jsonb) = 'not_complete'
  AND public.pdc_parts_reply_decision_541('is it complete?', '{"ai_classification":"complete","ai_confidence":"high","ai_quote":"is it complete?"}'::pg_catalog.jsonb) = 'not_complete'
  AND public.pdc_parts_reply_decision_541('waiting on', '{"ai_classification":"complete","ai_confidence":"high","ai_quote":"waiting on"}'::pg_catalog.jsonb) = 'not_complete'
  AND public.pdc_parts_reply_decision_541('except', '{"ai_classification":"complete","ai_confidence":"high","ai_quote":"except"}'::pg_catalog.jsonb) = 'not_complete'
  AND public.pdc_parts_reply_decision_541('parts complete', '{"ai_classification":"ambiguous","ai_confidence":"high","ai_quote":"parts complete"}'::pg_catalog.jsonb) = 'ambiguous'
  AND public.pdc_parts_reply_decision_541('parts complete', '{"ai_classification":"not_complete","ai_confidence":"high","ai_quote":"parts complete"}'::pg_catalog.jsonb) = 'not_complete'
  AND public.pdc_parts_reply_decision_541('parts arrived yesterday', '{"ai_classification":"complete","ai_confidence":"low","ai_quote":"parts arrived yesterday"}'::pg_catalog.jsonb) = 'ambiguous'
  AND public.pdc_parts_reply_decision_541('parts arrived yesterday', '{"ai_classification":"complete","ai_confidence":"high","ai_quote":"parts arrived yesterday"}'::pg_catalog.jsonb) = 'complete'
  AND public.pdc_parts_reply_decision_541('parts are here', '{"ai_classification":"complete","ai_confidence":"high","ai_quote":"a different sentence"}'::pg_catalog.jsonb) = 'ambiguous'
  AND substring(regexp_replace(lower('RE: New vehicle order for 13102818 - PMG Build'), '^((re|fw|fwd):[[:space:]]+)+', '') from '^new vehicle order for ([0-9]{8}|is[0-9]{8}) - pmg build$') = '13102818'
  AND (SELECT count(*) FROM public.vehicles WHERE stock_number='13102818' AND deleted_at IS NULL AND lifecycle_state='active' AND visible_on_board AND board_purged_at IS NULL) = 1
  AND (SELECT count(*) FROM public.vehicles v
       WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.visible_on_board AND v.board_purged_at IS NULL
         AND upper(btrim(v.job_card_number))='J138000880'
         AND (upper(btrim(v.stock_number))='1IRU519' OR upper(btrim(coalesce(v.registration,'')))='1IRU519')) = 1
  AND public.pdc_parts_vehicle_match_541('13102818', 'RE: New vehicle order for 13102818 - PMG Build')->>'code' = 'matched'
  AND public.pdc_parts_vehicle_match_541('13102818', 'RE: New vehicle order for 13102818 - PMG Build')->>'vehicle_id' = 'd9192a72-0987-496b-b395-b9c836dff8e8'
  AND public.pdc_parts_vehicle_match_541('1IRU519', '1IRU519 J138000880 EPT')->>'code' = 'matched'
  AND public.pdc_parts_vehicle_match_541('1IRU519', '1IRU519 J138000880 EPT')->>'vehicle_id' = 'b85d26fb-8f52-40fe-b06b-bb1bf87b0659'
  AND public.pdc_parts_vehicle_match_541('1IRU519', '1IRU519 J138000880 EPT')->>'stock_number' = '1IRU519'
  AND public.pdc_parts_vehicle_match_541('J138000880', '1IRU519 J138000880 EPT')->>'vehicle_id' = 'b85d26fb-8f52-40fe-b06b-bb1bf87b0659'
  AND public.pdc_parts_vehicle_match_541('1IRU519', '1IRU519 EPT')->>'vehicle_id' = 'b85d26fb-8f52-40fe-b06b-bb1bf87b0659'
  AND public.pdc_parts_vehicle_match_541('J138000880', '1IRU519 J138000880 J139126037 EPT')->>'code' = 'ambiguous'
  AND public.pdc_parts_vehicle_match_541('13102818', '13102818 13047270')->>'code' = 'ambiguous'
  AND public.pdc_parts_vehicle_match_541('NOPE', 'NOPE')->>'code' = 'not_found'
  AND (SELECT pg_catalog.pg_get_constraintdef(c.oid) FROM pg_catalog.pg_constraint c
       WHERE c.conname='person_confirmation_stock' AND c.conrelid=pg_catalog.to_regclass('public.pdc_parts_completion_email_confirmations'))
      LIKE '%[0-9][A-Z]{2,4}[0-9]{2,4}%'
  AND (SELECT pg_catalog.pg_get_constraintdef(c.oid) FROM pg_catalog.pg_constraint c
       WHERE c.conname='person_confirmation_stock' AND c.conrelid=pg_catalog.to_regclass('karratha135_pdc.pdc_parts_completion_email_confirmations'))
      NOT LIKE '%[0-9][A-Z]{2,4}[0-9]{2,4}%'
  AND (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='parts_complete_wording_541' AND fault_id='F155' AND sort_order=319 AND added_in='r541' AND enabled) = 1
 ) AS ok,
 '13102818 and 1IRU519/J138000880 each match one vehicle; Cc and a forward reach pdc@; a plain reply to someone else does not' AS detail
$chk541$, true, 319, 'r541');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r541: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS DISTINCT FROM 'c5314b7bed8a1401b6698319125c2d74' THEN RAISE EXCEPTION 'r541: person md5'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)')) IS TRUE THEN RAISE EXCEPTION 'r541: person recorder became security definer'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c WHERE c.conname='person_confirmation_stock' AND c.conrelid=to_regclass('karratha135_pdc.pdc_parts_completion_email_confirmations')) LIKE '%[0-9][A-Z]{2,4}[0-9]{2,4}%' THEN RAISE EXCEPTION 'r541: karratha stock check widened'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name IN ('outlook_parts_completion_514','outlook_internal_parts_auth_515') AND check_sql LIKE '%8ddb1477beeb94c7879c4021cccf1d40%') THEN RAISE EXCEPTION 'r541: old person md5 remains in a check'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='parts_complete_wording_541') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r541: parts_complete_wording_541 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='outlook_internal_parts_auth_515') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r541: outlook_internal_parts_auth_515 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r541: outlook_parts_completion_514 not OK: %', x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='regression_checks_self_test') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r541: regression_checks_self_test not OK: %', x.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $p$;
