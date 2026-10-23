-- r514 (F128): accept Outlook parts-complete replies on pdc@pmgwa.com.au.
-- Staging cdsmnqxtyyoeoznmbidd only. PREVIEW / NOT applied. Never touch production.
-- Kajel / Craig 23 Oct ~14:29 AWST: free-text "Parts complete" replies (Talin Parker on
-- Vehicle To Service Purchase Order, stock IS60353006) now arrive at pdc@pmgwa.com.au.
-- The green email-confirmed box is an active row in public.pdc_parts_completion_email_confirmations.
-- Live read before this file: 26 confirmation rows, all mailbox pmbcontroller@gmail.com, all
-- gmail_message_id hex length 16. Zero would fail the r506 shape. Karratha 135 keeps the hex
-- {10,40} and pmbcontroller-only CHECKs (parked). pmbcontroller stays in the public mailbox
-- CHECK because those 26 rows are stored; new Outlook inserts write pdc@pmgwa.com.au.
-- record_pdc_wayne_parts_complete_20260912 is unchanged (one historical stock, Gmail).
-- is_pdc_role is unchanged. A board login that is not an operator still cannot mark parts
-- complete, and service_role still has no EXECUTE on mark_pdc_parts_complete.
-- The mark bypass is only pdc_codex_intake_private.management_connection() (postgres, no JWT,
-- staging guard) and only when that vehicle already has an active pdc@ confirmation.
-- import_actor() is null today: the authorization user codex.pmb.importer.staging@pmb.local
-- is banned. recorded_by / updated_by may be null on this path. This release does not unban it.
-- Pin count stays 225. These two functions are not in expected_function_md5; the new check
-- locks their prosrc md5. No app.js / pdc-qc-rework.js.
-- Undo: supabase/rollbacks/20261023140000_r514_outlook_parts_completion.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r514: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r514: staging only'; END IF;
 PERFORM set_config('pdc.r514_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r514_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r514_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r514_role',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure),true);
 PERFORM set_config('pdc.r514_k135id',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 PERFORM set_config('pdc.r514_k135mb',(
   SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
     AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass),true);
 IF current_setting('pdc.r514_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r514: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r514_pins')::int IS DISTINCT FROM 225 THEN RAISE EXCEPTION 'r514: expected 225 pins at tip, got %', current_setting('pdc.r514_pins'); END IF;
 IF current_setting('pdc.r514_role') IS DISTINCT FROM '39a794b23d1d63117cf549d78acba4de' THEN RAISE EXCEPTION 'r514: is_pdc_role is not the r421 pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '77887b5450188a86acf0f0da34193e11' THEN RAISE EXCEPTION 'r514: person recorder is not the live tip'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM '82d890802677a2ac93942d3f7b7bcd27' THEN RAISE EXCEPTION 'r514: mark_pdc_parts_complete is not the live tip'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_wayne_parts_complete_20260912(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '00f688462ca997065b7ad932a0f4d2c8' THEN RAISE EXCEPTION 'r514: wayne recorder changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure) IS DISTINCT FROM '6c828cb4ffdd7e0717bd5d9f50f4c764' THEN RAISE EXCEPTION 'r514: parts flags changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)')) IS DISTINCT FROM '4df79e85792a93bbac4e484d7a2b82f3' THEN RAISE EXCEPTION 'r514: revolution auth is not the r505 body'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' OR added_in='r514') THEN RAISE EXCEPTION 'r514: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=301 OR fault_id='F128') THEN RAISE EXCEPTION 'r514: sort_order 301 / F128 taken'; END IF;
 IF to_regclass('pdc_ops.r514_parts_completion_prev') IS NOT NULL THEN RAISE EXCEPTION 'r514: undo preimage already exists'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
     AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%^[a-f0-9]{10,40}$%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%BETWEEN 8 AND 512%'
 ) THEN RAISE EXCEPTION 'r514: live message-id CHECK is not the hex {10,40} check'; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM pg_constraint c
   WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
     AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass
     AND pg_get_constraintdef(c.oid) LIKE '%pmbcontroller@gmail.com%'
     AND pg_get_constraintdef(c.oid) NOT LIKE '%pdc@pmgwa.com.au%'
 ) THEN RAISE EXCEPTION 'r514: live mailbox CHECK is not pmbcontroller-only'; END IF;
 IF EXISTS (
   SELECT 1 FROM public.pdc_parts_completion_email_confirmations
   WHERE NOT (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'))
      OR mailbox NOT IN ('pmbcontroller@gmail.com','pdc@pmgwa.com.au')
 ) THEN RAISE EXCEPTION 'r514: a stored confirmation would fail the widened CHECKs'; END IF;
 IF current_setting('pdc.r514_k135id') IS NULL
    OR current_setting('pdc.r514_k135id') NOT LIKE '%^[a-f0-9]{10,40}$%'
    OR current_setting('pdc.r514_k135id') LIKE '%BETWEEN 8 AND 512%' THEN RAISE EXCEPTION 'r514: karratha confirmation message-id CHECK is not the parked hex check'; END IF;
 IF current_setting('pdc.r514_k135mb') IS NULL
    OR current_setting('pdc.r514_k135mb') NOT LIKE '%pmbcontroller@gmail.com%'
    OR current_setting('pdc.r514_k135mb') LIKE '%pdc@pmgwa.com.au%' THEN RAISE EXCEPTION 'r514: karratha confirmation mailbox CHECK is not the parked pmbcontroller check'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508' AND added_in='r508' AND sort_order=293 AND fault_id='F121') THEN RAISE EXCEPTION 'r514: r508 check is not applied'; END IF;
END $g$;

CREATE TABLE pdc_ops.r514_parts_completion_prev (
  signature text PRIMARY KEY,
  prosrc text NOT NULL,
  prosecdef boolean NOT NULL,
  proconfig text[]
);
REVOKE ALL ON TABLE pdc_ops.r514_parts_completion_prev FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO pdc_ops.r514_parts_completion_prev(signature, prosrc, prosecdef, proconfig)
SELECT 'person', p.prosrc, p.prosecdef, p.proconfig
FROM pg_proc p WHERE p.oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure
UNION ALL
SELECT 'mark', p.prosrc, p.prosecdef, p.proconfig
FROM pg_proc p WHERE p.oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure;

ALTER TABLE public.pdc_parts_completion_email_confirmations
 DROP CONSTRAINT pdc_parts_completion_email_confirmations_gmail_message_id_check;
ALTER TABLE public.pdc_parts_completion_email_confirmations
 ADD CONSTRAINT pdc_parts_completion_email_confirmations_gmail_message_id_check
 CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'));

ALTER TABLE public.pdc_parts_completion_email_confirmations
 DROP CONSTRAINT pdc_parts_completion_email_confirmations_mailbox_check;
ALTER TABLE public.pdc_parts_completion_email_confirmations
 ADD CONSTRAINT pdc_parts_completion_email_confirmations_mailbox_check
 CHECK (mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text]));

CREATE OR REPLACE FUNCTION public.record_pdc_person_parts_complete_20260913(p_stock text, p_gmail_message_id text, p_received_at timestamp with time zone, p_subject text, p_confirmation_text text, p_evidence_sha256 text, p_authentication jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pdc_codex_intake_private'
AS $person514$
DECLARE v public.vehicles%rowtype; c public.pdc_parts_completion_email_confirmations%rowtype;
 actor uuid; status jsonb; sender text:=lower(btrim(p_authentication->>'from_address'));
 domain text; auth_result text; body text; authenticated_sender boolean;
 outlook boolean; gmail_ok boolean; outlook_ok boolean; body_ok boolean; mailbox text;
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
 outlook_ok:=outlook
  AND p_gmail_message_id IS NOT NULL
  AND length(p_gmail_message_id) BETWEEN 8 AND 512
  AND p_gmail_message_id !~ '[[:space:]]'
  AND (p_authentication->>'internet_message_id'=p_gmail_message_id
    OR p_authentication->>'outlook_message_id'=p_gmail_message_id
    OR p_authentication->>'microsoft_message_id'=p_gmail_message_id)
  AND p_authentication->>'to_address'='pdc@pmgwa.com.au'
  AND p_authentication->>'verified_by'='microsoft_receiving_provider'
  AND coalesce(auth_result,'') ~* '^mx[.]microsoft[.]com([[:space:]]+[0-9]+)?[[:space:]]*;'
  AND (
    auth_result ~* ('dkim=pass[^;]*header[.](i=@|d=)'||replace(domain,'.','\.')||'([;[:space:]]|$)')
    OR auth_result ~* ('(^|;)[[:space:]]*dmarc=pass[^;]*header[.]from='||replace(domain,'.','\.')||'([;[:space:]]|$)')
    OR auth_result ~* ('(^|;)[[:space:]]*spf=pass[^;]*smtp[.]mailfrom=([^;[:space:]]*@)?'||replace(domain,'.','\.')||'([;[:space:]]|$)')
  );
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
$person514$;

REVOKE ALL ON FUNCTION public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mark_pdc_parts_complete(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $mark514$
declare
  v_vehicle_before public.vehicles%rowtype;
  v_vehicle_after public.vehicles%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_work_before public.vehicle_work_items%rowtype;
  v_work_after public.vehicle_work_items%rowtype;
  v_receipt_id uuid;
  v_revision bigint;
  v_actor uuid:=auth.uid();
  v_expected_version integer:=p_expected_version;
  v_email_path boolean:=false;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  -- r514: management SQL (no JWT) may finish PARTS only after a pdc@ confirmation exists.
  -- Board logins still go through require_pdc_role('operator'). The role helper is not changed.
  if pdc_codex_intake_private.management_connection() is true
     and exists (
       select 1 from public.pdc_parts_completion_email_confirmations c
       where c.vehicle_id=p_vehicle_id and c.active and c.mailbox='pdc@pmgwa.com.au')
  then
    v_email_path:=true;
    v_actor:=pdc_codex_intake_private.import_actor();
  else
    IF public.current_pdc_user_role()::text='importer' AND current_setting('pdc_monitor_canonical_action',true)<>'pdc-email-ai-693' THEN RAISE EXCEPTION 'PDC_MONITOR_DIRECT_OPERATOR_RPC_DENIED' USING errcode='42501'; END IF;
    perform public.require_pdc_role('operator');
  end if;
  if p_vehicle_id is null or v_expected_version is null or (v_actor is null and not v_email_path) then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  select * into v_vehicle_before from public.vehicles where id=p_vehicle_id for update;
  if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
  if v_vehicle_before.lifecycle_state<>'active' or v_vehicle_before.deleted_at is not null then
    return public.navision_backend_response(false,'not_in_active_lifecycle');
  end if;

  select case when a.metadata->>'receipt_id' ~* '^[0-9a-f-]{36}$' then (a.metadata->>'receipt_id')::uuid end
    into v_receipt_id
  from public.audit_events a
  where a.vehicle_id=p_vehicle_id
    and a.metadata->>'action'='mark_pdc_parts_complete'
    and a.metadata->>'expected_version'=v_expected_version::text
  order by a.created_at desc,a.id desc limit 1;
  if v_receipt_id is not null then
    return public.navision_backend_response(true,'replayed',jsonb_build_object(
      'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,
      'vehicle_version',v_vehicle_before.version,'changed',false));
  end if;
  if v_vehicle_before.version<>v_expected_version then
    return public.navision_backend_response(false,'vehicle_version_conflict');
  end if;

  select * into v_parts_before from public.vehicle_parts_updates
  where vehicle_id=p_vehicle_id order by updated_at desc,id desc limit 1;
  select * into v_work_before from public.vehicle_work_items
  where vehicle_id=p_vehicle_id and upper(work_key)='PARTS' for update;
  if coalesce(v_parts_before.parts_received,false) or coalesce(v_work_before.completed,false) then
    if not v_email_path then
      return public.navision_backend_response(false,'parts_already_received');
    elsif coalesce(v_parts_before.parts_received,false) and coalesce(v_work_before.completed,false) then
      return public.navision_backend_response(true,'parts_already_received',jsonb_build_object(
        'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle_before.version,'changed',false,'email_confirmation',true));
    end if;
  end if;

  v_receipt_id:=gen_random_uuid();
  perform set_config('pdc.parts_completion_revision_managed','on',true);
  insert into public.vehicle_parts_updates(
    vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
    parts_stoppage_reason,worst_eta,updated_by,updated_at
  ) values(
    p_vehicle_id,true,coalesce(v_parts_before.parts_ordered,true),true,false,
    null,null,v_actor,clock_timestamp()
  ) returning * into v_parts_after;
  insert into public.vehicle_work_items(
    vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at
  ) values(
    p_vehicle_id,'PARTS',true,true,v_actor,clock_timestamp(),
    coalesce(v_work_before.notes,'Parts received on Parts board'),clock_timestamp()
  ) on conflict(vehicle_id,work_key) do update set
    required=true,completed=true,completed_by=v_actor,completed_at=clock_timestamp(),updated_at=clock_timestamp()
  returning * into v_work_after;
  update public.vehicles set version=version+1,updated_by=v_actor
  where id=p_vehicle_id returning * into v_vehicle_after;

  perform public.audit_pdc_event('insert','vehicle_parts_updates',v_parts_after.id,p_vehicle_id,
    case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,
    to_jsonb(v_parts_after),jsonb_build_object('action','mark_pdc_parts_complete','receipt_id',v_receipt_id,'expected_version',v_expected_version,'changed',true));
  perform public.audit_pdc_event(
    case when v_work_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
    'vehicle_work_items',v_work_after.id,p_vehicle_id,
    case when v_work_before.id is null then null else to_jsonb(v_work_before) end,
    to_jsonb(v_work_after),jsonb_build_object('action','mark_pdc_parts_complete','receipt_id',v_receipt_id,'expected_version',v_expected_version,'changed',true));
  update public.pdc_email_vehicle_revision
  set revision=revision+1,updated_at=clock_timestamp()
  where singleton returning revision into v_revision;
  return public.navision_backend_response(true,'parts_completed',jsonb_build_object(
    'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,
    'vehicle_version',v_vehicle_after.version,'revision',v_revision,'changed',true));
end;
$mark514$;

REVOKE ALL ON FUNCTION public.mark_pdc_parts_complete(uuid,integer) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_pdc_parts_complete(uuid,integer) TO authenticated;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('outlook_parts_completion_514','F128','Parts-complete email confirmations (r514): hex ids still pass; an Outlook internet_message_id (length 8-512, no whitespace) passes; whitespace and a 513-character id fail; mailbox pmbcontroller@gmail.com and pdc@pmgwa.com.au pass and a third mailbox fails; every stored row still passes; Karratha confirmations stay hex {10,40} and pmbcontroller-only; person recorder accepts pdc@ plus an IS stock; mark still requires an operator except the management-connection pdc@ confirmation path; is_pdc_role and the wayne recorder are unchanged; service_role cannot execute mark',
  $chk514$WITH ids(label, id, want) AS (
  VALUES
   ('hex short','abc',true),
   ('hex gmail','1a158481917b7196',true),
   ('outlook internet','<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>',true),
   ('outlook graph','AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE9bAAA',true),
   ('whitespace','<id with space@10.255.11.20>',false),
   ('too long',repeat('x',513),false),
   ('short nonhex','Abcdef',false)
), ev AS (
  SELECT label, want,
    (id ~ '^[a-f0-9]+$' OR (length(id) BETWEEN 8 AND 512 AND id !~ '[[:space:]]')) AS got
  FROM ids
), bodies(label, stock, body, subject, outlook, want) AS (
  VALUES
   ('exact 8','13000001','parts complete for 13000001','x',false,true),
   ('exact is','IS60353006','parts complete for is60353006','x',true,true),
   ('short subject','IS60353006','parts complete','Vehicle To Service Purchase Order - Stock: IS60353006 P/O: GP10403460',true,true),
   ('short gmail','13000001','parts complete','Stock: 13000001',false,false),
   ('short no stock','IS60353006','parts complete','Vehicle To Service Purchase Order',true,false),
   ('longer text','IS60353006','parts complete thanks','Stock: IS60353006',true,false)
), bv AS (
  SELECT label, want,
    (lower(body) ~ ('^(parts complete( for)? '||lower(stock)||'|'||lower(stock)||' parts complete)[.!]?$')
     OR (outlook AND lower(body) ~ '^parts complete[.!]?$'
         AND coalesce(subject,'') ~* ('(^|[^A-Za-z0-9])'||stock||'([^A-Za-z0-9]|$)'))) AS got
  FROM bodies
), mb(label, mailbox, want) AS (
  VALUES ('pmb','pmbcontroller@gmail.com',true), ('pdc','pdc@pmgwa.com.au',true), ('other','other@example.com',false)
), mv AS (
  SELECT label, want,
    (mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text])) AS got
  FROM mb
), def_id AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
    AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass
), def_mb AS (
  SELECT pg_get_constraintdef(c.oid) AS d
  FROM pg_constraint c
  WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
    AND c.conrelid='public.pdc_parts_completion_email_confirmations'::regclass
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
), fn AS (
  SELECT
   (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) AS person_md5,
   (SELECT prosrc FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) AS person_src,
   (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) AS mark_md5,
   (SELECT prosrc FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) AS mark_src
)
SELECT (SELECT count(*)=7 AND bool_and(got IS NOT DISTINCT FROM want) FROM ev)
   AND (SELECT count(*)=6 AND bool_and(got IS NOT DISTINCT FROM want) FROM bv)
   AND (SELECT count(*)=3 AND bool_and(got IS NOT DISTINCT FROM want) FROM mv)
   AND (SELECT count(*)=1 FROM def_id WHERE d LIKE '%^[a-f0-9]+$%'
            AND (d LIKE '%BETWEEN 8 AND 512%' OR (d LIKE '%>= 8%' AND d LIKE '%<= 512%'))
            AND d LIKE '%[[:space:]]%'
            AND d NOT LIKE '%[a-f0-9]{10,40}%')
   AND (SELECT count(*)=1 FROM def_mb WHERE d LIKE '%pmbcontroller@gmail.com%' AND d LIKE '%pdc@pmgwa.com.au%')
   AND NOT EXISTS (
     SELECT 1 FROM public.pdc_parts_completion_email_confirmations m
     WHERE NOT (m.gmail_message_id ~ '^[a-f0-9]+$' OR (length(m.gmail_message_id) BETWEEN 8 AND 512 AND m.gmail_message_id !~ '[[:space:]]'))
        OR NOT (m.mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text]))
   )
   AND (SELECT count(*)=1 FROM k_id WHERE d LIKE '%^[a-f0-9]{10,40}$%' AND d NOT LIKE '%BETWEEN 8 AND 512%')
   AND (SELECT count(*)=1 FROM k_mb WHERE d LIKE '%pmbcontroller@gmail.com%' AND d NOT LIKE '%pdc@pmgwa.com.au%')
   AND (SELECT person_md5 FROM fn)='eb02f76ec94cd0b6c824a18660432afa'
   AND (SELECT mark_md5 FROM fn)='1a89be6cc2e0bac0e3be3112b30f379f'
   AND (SELECT person_src FROM fn) LIKE '%pdc@pmgwa.com.au%'
   AND (SELECT person_src FROM fn) LIKE '%pmbcontroller@gmail.com%'
   AND (SELECT person_src FROM fn) LIKE '%microsoft_receiving_provider%'
   AND (SELECT person_src FROM fn) LIKE '%IS[0-9]{8}%'
   AND (SELECT mark_src FROM fn) LIKE '%management_connection()%'
   AND (SELECT mark_src FROM fn) LIKE '%require_pdc_role(''operator'')%'
   AND (SELECT mark_src FROM fn) NOT LIKE '%is_pdc_role%'
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure)='39a794b23d1d63117cf549d78acba4de'
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_wayne_parts_complete_20260912(text,text,timestamptz,text,text,text,jsonb)'::regprocedure)='00f688462ca997065b7ad932a0f4d2c8'
   AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure)='6c828cb4ffdd7e0717bd5d9f50f4c764'
   AND NOT has_function_privilege('anon','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
   AND NOT has_function_privilege('service_role','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
   AND has_function_privilege('authenticated','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
   AND NOT has_function_privilege('anon','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
   AND NOT has_function_privilege('authenticated','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
   AND NOT has_function_privilege('service_role','public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)','EXECUTE')
   AND (SELECT count(*) FROM pdc_ops.expected_function_md5)=225
 AS ok,
 'ids '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM ev)||'/'||(SELECT count(*) FROM ev)
 ||' bodies '||(SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) FROM bv)||'/'||(SELECT count(*) FROM bv)
 ||coalesce(' (WRONG: '||(SELECT string_agg(label,', ') FROM (
    SELECT label FROM ev WHERE got IS DISTINCT FROM want
    UNION ALL SELECT label FROM bv WHERE got IS DISTINCT FROM want
    UNION ALL SELECT label FROM mv WHERE got IS DISTINCT FROM want) w)||')','')
 AS detail$chk514$,true,301,'r514');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM 225
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5) IS DISTINCT FROM current_setting('pdc.r514_pins')::int THEN RAISE EXCEPTION 'r514: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM 'eb02f76ec94cd0b6c824a18660432afa' THEN RAISE EXCEPTION 'r514: person md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS DISTINCT FROM '1a89be6cc2e0bac0e3be3112b30f379f' THEN RAISE EXCEPTION 'r514: mark md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.is_pdc_role(public.pdc_role)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r514_role') THEN RAISE EXCEPTION 'r514: is_pdc_role changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_wayne_parts_complete_20260912(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS DISTINCT FROM '00f688462ca997065b7ad932a0f4d2c8' THEN RAISE EXCEPTION 'r514: wayne recorder changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure) IS DISTINCT FROM '6c828cb4ffdd7e0717bd5d9f50f4c764' THEN RAISE EXCEPTION 'r514: parts flags changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r514_tick') THEN RAISE EXCEPTION 'r514: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r514_frc') THEN RAISE EXCEPTION 'r514: fault_regression_check changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_gmail_message_id_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r514_k135id') THEN RAISE EXCEPTION 'r514: karratha message-id CHECK changed'; END IF;
 IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
     WHERE c.conname='pdc_parts_completion_email_confirmations_mailbox_check'
       AND c.conrelid='karratha135_pdc.pdc_parts_completion_email_confirmations'::regclass)
    IS DISTINCT FROM current_setting('pdc.r514_k135mb') THEN RAISE EXCEPTION 'r514: karratha mailbox CHECK changed'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.mark_pdc_parts_complete(uuid,integer)'::regprocedure) IS NOT TRUE THEN RAISE EXCEPTION 'r514: mark lost SECURITY DEFINER'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid='public.record_pdc_person_parts_complete_20260913(text,text,timestamptz,text,text,text,jsonb)'::regprocedure) IS TRUE THEN RAISE EXCEPTION 'r514: person recorder became SECURITY DEFINER'; END IF;
 IF has_function_privilege('service_role','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.mark_pdc_parts_complete(uuid,integer)','EXECUTE') THEN RAISE EXCEPTION 'r514: mark grants changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outlook_parts_completion_514' AND added_in='r514' AND sort_order=301 AND fault_id='F128') THEN RAISE EXCEPTION 'r514: check missing'; END IF;
 IF (SELECT md5(prosrc) FROM pdc_ops.r514_parts_completion_prev WHERE signature='person') IS DISTINCT FROM '77887b5450188a86acf0f0da34193e11' THEN RAISE EXCEPTION 'r514: person preimage missing'; END IF;
 IF (SELECT md5(prosrc) FROM pdc_ops.r514_parts_completion_prev WHERE signature='mark') IS DISTINCT FROM '82d890802677a2ac93942d3f7b7bcd27' THEN RAISE EXCEPTION 'r514: mark preimage missing'; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_parts_completion_514';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r514: outlook_parts_completion_514 failed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_sales_receipt_message_id_508';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r514: r508 check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_message_id_506';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r514: r506 check regressed: %', y; END IF;
 SELECT * INTO y FROM pdc_ops.fault_regression_check() WHERE check_name='outlook_manifest_mailbox_507';
 IF y IS NULL OR y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r514: r507 check regressed: %', y; END IF;
END $g$;
