-- r460 (F73, change request; Craig approved 22 Oct 2026 06:50 AWST): the vehicle key number becomes editable by controllers and
-- administrators on PDC staging, with a full audit trail. Staging cdsmnqxtyyoeoznmbidd only.
-- Builds on the existing field: public.vehicles.key_number (filled by the service import: pdc_pilbara_service_apply_v1 ->
-- pdc_apply_tune_key_number_v1 'Key Tag Number', pdc_codex_intake_private.apply_service_arrival, upsert_vehicle_master_import;
-- shown as the 'Key' identity column on the board). No new key column; no importer changes: a later service import still
-- updates key_number exactly as before.
-- (1) public.pdc_vehicle_key_number_audit_460: one row per key change (who, when, old value, new value, source). Written by an
--     AFTER INSERT/UPDATE trigger on vehicles that fires only when key_number changes, so every writer is caught:
--     source 'edit' (controller/admin through set_pdc_vehicle_key_number_460, or the legacy PMB vehicle form r388),
--     'release' (release/admin context with a named approver and reason), 'import' (any service/master import in the call
--     stack), 'system' (anything else, e.g. direct SQL). The writer (call stack) is kept. Append-only, RLS, no app-role access.
-- (2) set_pdc_vehicle_key_number_460(vehicle, expected version, key, idempotency key): controllers/admins, any location
--     (the r388 form only allows PMB); one key tag per active PMB vehicle is still enforced at PMB; idempotent receipts.
-- (3) get_pdc_vehicle_key_number_460(vehicle): key, version, can_edit and (controllers/admins) the audit history.
--     get_pdc_vehicle_key_number_460(NULL): just can_edit (the screen's role probe).
-- (4) pdc_key_number_private.release_set_key_number_460(...): the same edit path for a release/admin context (no app role can
--     execute it; requires a named approver and reason).
-- Not touched: workshop_clock_tick, importers, other vehicle columns, lines, ticks, bookings, bays, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r460: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r460: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r460: clock tick changed since prepared (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r460: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)'::regprocedure)<>'4b25c88071288d598d4ae29c50320d3b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)'::regprocedure)<>'eabd64cea227ce91a1f3005569c16439'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.upsert_vehicle_master_import(text,text,text,jsonb,integer,text)'::regprocedure)<>'6de06150e585964d5a84ad435c701df6'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.apply_service_arrival(uuid)'::regprocedure)<>'5e9ca7c4862bdee353c958f86f2edd35' THEN RAISE EXCEPTION 'r460: key writers changed since prepared (this release must not touch them)'; END IF;
 IF to_regclass('public.pdc_vehicle_key_number_audit_460') IS NOT NULL OR to_regnamespace('pdc_key_number_private') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.vehicles'::regclass AND tgname LIKE '%key_number_audit_460%')
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r460')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='vehicle_key_number_audit_460' OR added_in='r460') THEN RAISE EXCEPTION 'r460: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=259 OR fault_id='F73') THEN RAISE EXCEPTION 'r460: sort_order 259 / F73 taken'; END IF;
 PERFORM set_config('pdc.r460_pins_before',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE SCHEMA pdc_key_number_private;
REVOKE ALL ON SCHEMA pdc_key_number_private FROM PUBLIC;
REVOKE ALL ON SCHEMA pdc_key_number_private FROM anon, authenticated, service_role;

CREATE TABLE public.pdc_vehicle_key_number_audit_460 (
 audit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL,
 stock_number text,
 old_value text,
 new_value text,
 source text NOT NULL CHECK (source IN ('edit','release','import','system')),
 writer text NOT NULL CHECK (length(writer) BETWEEN 1 AND 400),
 actor_id uuid,
 actor_email text,
 actor_role text,
 approved_by text CHECK (approved_by IS NULL OR length(btrim(approved_by)) BETWEEN 3 AND 200),
 reason text CHECK (reason IS NULL OR length(reason) <= 500),
 receipt_id uuid,
 vehicle_version integer,
 db_role text NOT NULL DEFAULT current_user,
 txid bigint NOT NULL DEFAULT txid_current(),
 context jsonb NOT NULL DEFAULT '{}'::jsonb,
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT pdc_vehicle_key_number_audit_460_changed CHECK (old_value IS DISTINCT FROM new_value),
 CONSTRAINT pdc_vehicle_key_number_audit_460_release CHECK (source<>'release' OR (approved_by IS NOT NULL AND reason IS NOT NULL AND receipt_id IS NOT NULL))
);
CREATE INDEX pdc_vehicle_key_number_audit_460_vehicle ON public.pdc_vehicle_key_number_audit_460(vehicle_id, changed_at DESC);
ALTER TABLE public.pdc_vehicle_key_number_audit_460 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_vehicle_key_number_audit_460 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_vehicle_key_number_audit_460 IS 'r460 (F73): append-only audit of every vehicles.key_number change (edit / release / import / system). Read through get_pdc_vehicle_key_number_460.';

CREATE TABLE public.pdc_vehicle_key_number_receipts_460 (
 receipt_id uuid PRIMARY KEY,
 actor_key text NOT NULL,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
 vehicle_id uuid NOT NULL,
 response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE (actor_key, idempotency_key)
);
ALTER TABLE public.pdc_vehicle_key_number_receipts_460 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_vehicle_key_number_receipts_460 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_key_number_private.append_only_460() RETURNS trigger LANGUAGE plpgsql SET search_path TO 'pg_catalog' AS $f$
BEGIN
 RAISE EXCEPTION 'PDC_460_KEY_AUDIT_APPEND_ONLY: % on % is not allowed', TG_OP, TG_TABLE_NAME USING errcode='42501';
END $f$;
CREATE TRIGGER pdc_vehicle_key_number_audit_append_only_460 BEFORE UPDATE OR DELETE ON public.pdc_vehicle_key_number_audit_460
 FOR EACH ROW EXECUTE FUNCTION pdc_key_number_private.append_only_460();
CREATE TRIGGER pdc_vehicle_key_number_audit_no_truncate_460 BEFORE TRUNCATE ON public.pdc_vehicle_key_number_audit_460
 FOR EACH STATEMENT EXECUTE FUNCTION pdc_key_number_private.append_only_460();
CREATE TRIGGER pdc_vehicle_key_number_receipts_append_only_460 BEFORE UPDATE OR DELETE ON public.pdc_vehicle_key_number_receipts_460
 FOR EACH ROW EXECUTE FUNCTION pdc_key_number_private.append_only_460();

-- Every key change, from any writer. Never blocks the writer for audit reasons other than a failed insert.
CREATE FUNCTION pdc_key_number_private.capture_460() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE
 v_ctx text; v_fns text[]; v_writer text; v_source text; v_old text;
 v_set_source text:=nullif(current_setting('pdc.key_number_source_460',true),'');
 v_actor uuid; v_email text; v_role text; v_jwt jsonb;
BEGIN
 v_old:=CASE WHEN TG_OP='UPDATE' THEN OLD.key_number END;
 IF v_old IS NOT DISTINCT FROM NEW.key_number THEN RETURN NULL; END IF;
 GET DIAGNOSTICS v_ctx = PG_CONTEXT;
 SELECT coalesce(array_agg(f ORDER BY o),'{}') INTO v_fns FROM (
  SELECT regexp_replace(m[2],'^(public|pdc_key_number_private)\.','') f, o
  FROM regexp_matches(v_ctx,'(PL/pgSQL function |SQL function ")([A-Za-z0-9_.]+)','g') WITH ORDINALITY t(m,o)) s
 WHERE f<>'capture_460';
 v_writer:=left(coalesce(nullif(array_to_string(v_fns,' < '),''),'direct SQL'),400);
 BEGIN v_actor:=auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor:=NULL; END;
 BEGIN v_jwt:=auth.jwt(); EXCEPTION WHEN OTHERS THEN v_jwt:=NULL; END;
 v_email:=nullif(lower(btrim(coalesce(v_jwt->>'email',''))),'');
 IF v_actor IS NOT NULL THEN
  SELECT r.role::text INTO v_role FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved' ORDER BY r.updated_at DESC LIMIT 1;
 END IF;
 IF v_set_source IN ('edit','release') AND 'apply_key_number_460'=ANY(v_fns) THEN
  v_source:=v_set_source;
 ELSIF EXISTS(SELECT 1 FROM unnest(v_fns) f WHERE f ~ '(import|pilbara_service_apply|tune_key_number|service_arrival|intake)') THEN
  v_source:='import';
 ELSIF EXISTS(SELECT 1 FROM unnest(v_fns) f WHERE f IN ('update_pdc_vehicle_detail_fields_388','update_pdc_vehicle_operational_state','edit_vehicle_master')) THEN
  v_source:='edit';
 ELSE
  v_source:='system';
 END IF;
 INSERT INTO public.pdc_vehicle_key_number_audit_460(vehicle_id,stock_number,old_value,new_value,source,writer,actor_id,actor_email,actor_role,approved_by,reason,receipt_id,vehicle_version,context)
 VALUES(NEW.id,NEW.stock_number,v_old,NEW.key_number,v_source,v_writer,v_actor,v_email,
  CASE WHEN v_source='release' THEN 'release' ELSE v_role END,
  CASE WHEN v_source='release' THEN nullif(current_setting('pdc.key_number_approved_by_460',true),'') END,
  CASE WHEN v_source IN ('edit','release') AND 'apply_key_number_460'=ANY(v_fns) THEN nullif(current_setting('pdc.key_number_reason_460',true),'') END,
  CASE WHEN 'apply_key_number_460'=ANY(v_fns) THEN nullif(current_setting('pdc.key_number_receipt_460',true),'')::uuid END,
  NEW.version,
  jsonb_strip_nulls(jsonb_build_object('op',lower(TG_OP),'stack',to_jsonb(v_fns),
   'tune_key_batch_id',CASE WHEN TG_OP='INSERT' OR (OLD.source_payload->>'tune_key_batch_id') IS DISTINCT FROM (NEW.source_payload->>'tune_key_batch_id') THEN NEW.source_payload->>'tune_key_batch_id' END,
   'application_name',nullif(current_setting('application_name',true),''))));
 RETURN NULL;
END $f$;
REVOKE ALL ON FUNCTION pdc_key_number_private.capture_460() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER zz_pdc_key_number_audit_460_upd AFTER UPDATE ON public.vehicles FOR EACH ROW
 WHEN (OLD.key_number IS DISTINCT FROM NEW.key_number) EXECUTE FUNCTION pdc_key_number_private.capture_460();
CREATE TRIGGER zz_pdc_key_number_audit_460_ins AFTER INSERT ON public.vehicles FOR EACH ROW
 WHEN (NEW.key_number IS NOT NULL) EXECUTE FUNCTION pdc_key_number_private.capture_460();

-- The one edit path (screen and release context).
CREATE FUNCTION pdc_key_number_private.apply_key_number_460(p_vehicle_id uuid, p_expected_vehicle_version integer, p_key_number text,
 p_source text, p_actor uuid, p_actor_email text, p_actor_role text, p_approved_by text, p_reason text, p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'extensions' AS $f$
DECLARE
 v_actor_key text:=CASE WHEN p_source='release' THEN 'release' ELSE p_actor::text END;
 v_raw text:=btrim(coalesce(p_key_number,'')); v_key text; v_payload jsonb; v_sha text; v_receipt public.pdc_vehicle_key_number_receipts_460%rowtype;
 v_receipt_id uuid; v_before public.vehicles%rowtype; v_after public.vehicles%rowtype; v_response jsonb; v_audit uuid; v_also jsonb;
BEGIN
 IF p_source NOT IN ('edit','release') OR v_actor_key IS NULL OR p_vehicle_id IS NULL OR p_idempotency_key IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR length(v_raw)>64 THEN
  RETURN jsonb_build_object('ok',false,'code','key_number_invalid_input');
 END IF;
 v_key:=nullif(upper(regexp_replace(v_raw,'\s+','','g')),'');
 IF v_key IS NOT NULL AND (v_key !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' OR v_key ~ '^0+$') THEN
  RETURN jsonb_build_object('ok',false,'code','key_number_invalid','message','Use letters and numbers only (up to 32), not 0. Leave it empty to clear the key.');
 END IF;
 v_payload:=jsonb_build_object('contract','pdc-vehicle-key-number-460','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'key_number',v_key,'source',p_source,'approved_by',p_approved_by,'reason',p_reason);
 v_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-460-receipt:'||v_actor_key||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_vehicle_key_number_receipts_460 WHERE actor_key=v_actor_key AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
  RETURN v_receipt.response||jsonb_build_object('replay',true);
 END IF;
 v_receipt_id:=extensions.uuid_generate_v5('46000000-0000-5000-8000-000000000460'::uuid,v_actor_key||':'||p_idempotency_key::text);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-460-vehicle:'||p_vehicle_id::text,0));
 SELECT * INTO v_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v_before.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 IF v_before.version<>p_expected_vehicle_version THEN
  RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v_before.id,'vehicle_version',v_before.version,'key_number',v_before.key_number));
 END IF;
 IF v_key IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-key:'||v_key,0));
  IF upper(btrim(coalesce(v_before.current_location,'')))='PMB' AND EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v_before.id AND x.deleted_at IS NULL
     AND x.lifecycle_state='active' AND upper(btrim(coalesce(x.current_location,'')))='PMB' AND upper(btrim(coalesce(x.key_number,'')))=v_key) THEN
   RETURN jsonb_build_object('ok',false,'code','key_number_in_use','message','Another active PMB vehicle already has this key tag.');
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('stock_number',x.stock_number,'location',x.current_location) ORDER BY x.stock_number),'[]') INTO v_also
  FROM public.vehicles x WHERE x.id<>v_before.id AND x.deleted_at IS NULL AND x.lifecycle_state='active' AND upper(btrim(coalesce(x.key_number,'')))=v_key;
 END IF;
 IF v_before.key_number IS NOT DISTINCT FROM v_key THEN
  v_response:=jsonb_build_object('ok',true,'code','key_number_unchanged','data',jsonb_build_object('changed',false,'vehicle_id',v_before.id,'key_number',v_key,'vehicle_version',v_before.version));
 ELSE
  PERFORM set_config('pdc.key_number_source_460',p_source,true);
  PERFORM set_config('pdc.key_number_reason_460',coalesce(p_reason,''),true);
  PERFORM set_config('pdc.key_number_approved_by_460',coalesce(p_approved_by,''),true);
  PERFORM set_config('pdc.key_number_receipt_460',v_receipt_id::text,true);
  UPDATE public.vehicles SET key_number=v_key, version=version+1, updated_at=clock_timestamp(), updated_by=coalesce(p_actor,updated_by)
   WHERE id=v_before.id RETURNING * INTO v_after;
  PERFORM set_config('pdc.key_number_source_460','',true);
  PERFORM set_config('pdc.key_number_reason_460','',true);
  PERFORM set_config('pdc.key_number_approved_by_460','',true);
  PERFORM set_config('pdc.key_number_receipt_460','',true);
  SELECT a.audit_id INTO v_audit FROM public.pdc_vehicle_key_number_audit_460 a WHERE a.receipt_id=v_receipt_id AND a.vehicle_id=v_before.id;
  IF v_audit IS NULL THEN RAISE EXCEPTION 'PDC_460_AUDIT_ROW_MISSING' USING errcode='55000'; END IF;
  v_response:=jsonb_build_object('ok',true,'code','key_number_updated','data',jsonb_build_object('changed',true,'vehicle_id',v_after.id,'stock_number',v_after.stock_number,
   'key_number_before',v_before.key_number,'key_number',v_after.key_number,'vehicle_version_before',v_before.version,'vehicle_version_after',v_after.version,
   'audit_id',v_audit,'source',p_source,'also_on',coalesce(v_also,'[]'::jsonb)));
 END IF;
 v_response:=v_response||jsonb_build_object('receipt_id',v_receipt_id,'actor_email',p_actor_email,'actor_role',p_actor_role,'replay',false);
 INSERT INTO public.pdc_vehicle_key_number_receipts_460(receipt_id,actor_key,idempotency_key,request_sha256,vehicle_id,response)
 VALUES(v_receipt_id,v_actor_key,p_idempotency_key,v_sha,p_vehicle_id,v_response);
 RETURN v_response;
END $f$;
REVOKE ALL ON FUNCTION pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.set_pdc_vehicle_key_number_460(p_vehicle_id uuid, p_expected_vehicle_version integer, p_key_number text, p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_actor uuid:=auth.uid(); v_role text; v_email text;
BEGIN
 IF v_actor IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 SELECT r.role::text, lower(btrim(r.email)) INTO v_role, v_email FROM public.pdc_user_roles r
 WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved' AND r.role::text IN ('operator','administrator')
   AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))
 ORDER BY r.updated_at DESC LIMIT 1;
 IF v_role IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 RETURN pdc_key_number_private.apply_key_number_460(p_vehicle_id,p_expected_vehicle_version,p_key_number,'edit',v_actor,v_email,v_role,NULL,NULL,p_idempotency_key);
END $f$;
REVOKE ALL ON FUNCTION public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid) TO authenticated;

-- Release / admin context: same path, named approver and reason, no app role can call it.
CREATE FUNCTION pdc_key_number_private.release_set_key_number_460(p_vehicle_id uuid, p_expected_vehicle_version integer, p_key_number text,
 p_approved_by text, p_reason text, p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_uid uuid;
BEGIN
 BEGIN v_uid:=auth.uid(); EXCEPTION WHEN OTHERS THEN v_uid:=NULL; END;
 IF v_uid IS NOT NULL OR current_user NOT IN ('postgres','supabase_admin') THEN RAISE EXCEPTION 'PDC_460_RELEASE_CONTEXT_ONLY' USING errcode='42501'; END IF;
 IF length(btrim(coalesce(p_approved_by,'')))<3 OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_460_RELEASE_NEEDS_APPROVER_AND_REASON' USING errcode='22023'; END IF;
 RETURN pdc_key_number_private.apply_key_number_460(p_vehicle_id,p_expected_vehicle_version,p_key_number,'release',NULL,NULL,'release',btrim(p_approved_by),btrim(p_reason),p_idempotency_key);
END $f$;
REVOKE ALL ON FUNCTION pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_pdc_vehicle_key_number_460(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $f$
DECLARE v_actor uuid:=auth.uid(); v_role text; v_edit boolean; v public.vehicles%rowtype;
BEGIN
 IF v_actor IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 SELECT r.role::text INTO v_role FROM public.pdc_user_roles r
 WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved' AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))
 ORDER BY r.updated_at DESC LIMIT 1;
 IF v_role IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 v_edit:=v_role IN ('operator','administrator');
 IF p_vehicle_id IS NULL THEN RETURN jsonb_build_object('ok',true,'code','key_number_role','can_edit',v_edit,'role',v_role); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 RETURN jsonb_build_object('ok',true,'code','key_number','vehicle_id',v.id,'key_number',v.key_number,'vehicle_version',v.version,'can_edit',v_edit,
  'history',CASE WHEN v_edit THEN coalesce((SELECT jsonb_agg(jsonb_build_object('at',a.changed_at,'source',a.source,'old',a.old_value,'new',a.new_value,
     'by',coalesce(a.actor_email,CASE WHEN a.approved_by IS NOT NULL THEN a.approved_by||' (release)' END,CASE WHEN a.source='import' THEN 'service import' END,a.writer),
     'role',a.actor_role,'writer',a.writer,'reason',a.reason) ORDER BY a.changed_at DESC)
    FROM (SELECT * FROM public.pdc_vehicle_key_number_audit_460 WHERE vehicle_id=v.id ORDER BY changed_at DESC LIMIT 20) a),'[]'::jsonb) ELSE '[]'::jsonb END);
END $f$;
REVOKE ALL ON FUNCTION public.get_pdc_vehicle_key_number_460(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_key_number_460(uuid) TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at)
SELECT p.oid::regprocedure::text, md5(p.prosrc), 'r460', 'r460 (F73) vehicle key number edit + audit', now()
FROM pg_proc p WHERE p.oid IN ('pdc_key_number_private.append_only_460()'::regprocedure,'pdc_key_number_private.capture_460()'::regprocedure,
 'pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)'::regprocedure,
 'pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid)'::regprocedure,
 'public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)'::regprocedure,'public.get_pdc_vehicle_key_number_460(uuid)'::regprocedure);

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('vehicle_key_number_audit_460','F73','r460: vehicle key number edit (controllers/admins) with a full audit: audit table append-only and private, capture triggers on vehicles enabled, the latest audit value matches the vehicle key, release rows carry an approver and reason, edit rows a controller/admin, grants as designed.',
$chk$WITH b AS (
 SELECT (SELECT bool_and(c.relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') AND NOT has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE'))
    FROM pg_catalog.pg_class c WHERE c.oid IN (to_regclass('public.pdc_vehicle_key_number_audit_460'),to_regclass('public.pdc_vehicle_key_number_receipts_460')))
   AND (SELECT count(*) FROM pg_catalog.pg_class WHERE oid IN (to_regclass('public.pdc_vehicle_key_number_audit_460'),to_regclass('public.pdc_vehicle_key_number_receipts_460')))=2 AS tables,
  (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid=to_regclass('public.pdc_vehicle_key_number_audit_460') AND tgname IN ('pdc_vehicle_key_number_audit_append_only_460','pdc_vehicle_key_number_audit_no_truncate_460') AND tgenabled='O')=2 AS append_only,
  (SELECT count(*) FROM pg_catalog.pg_trigger WHERE tgrelid='public.vehicles'::regclass AND tgname IN ('zz_pdc_key_number_audit_460_upd','zz_pdc_key_number_audit_460_ins') AND tgenabled='O')=2 AS capture,
  NOT EXISTS(SELECT 1 FROM (SELECT DISTINCT ON (a.vehicle_id) a.vehicle_id,a.new_value FROM public.pdc_vehicle_key_number_audit_460 a ORDER BY a.vehicle_id,a.changed_at DESC,a.txid DESC) l
    JOIN public.vehicles v ON v.id=l.vehicle_id WHERE v.key_number IS DISTINCT FROM l.new_value) AS latest_matches,
  NOT EXISTS(SELECT 1 FROM public.pdc_vehicle_key_number_audit_460 a WHERE (a.source='release' AND (a.approved_by IS NULL OR a.reason IS NULL OR a.actor_role<>'release'))
    OR (a.source='edit' AND a.writer LIKE '%apply_key_number_460%' AND (a.actor_id IS NULL OR a.actor_email IS NULL OR a.actor_role NOT IN ('operator','administrator') OR a.receipt_id IS NULL))
    OR (a.receipt_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.pdc_vehicle_key_number_receipts_460 r WHERE r.receipt_id=a.receipt_id AND r.vehicle_id=a.vehicle_id))) AS attributed,
  has_function_privilege('authenticated','public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)','EXECUTE')
   AND NOT has_function_privilege('anon','public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)','EXECUTE')
   AND has_function_privilege('authenticated','public.get_pdc_vehicle_key_number_460(uuid)','EXECUTE')
   AND NOT has_function_privilege('anon','public.get_pdc_vehicle_key_number_460(uuid)','EXECUTE')
   AND NOT has_schema_privilege('authenticated','pdc_key_number_private','USAGE') AND NOT has_schema_privilege('anon','pdc_key_number_private','USAGE')
   AND NOT has_function_privilege('authenticated','pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid)','EXECUTE')
   AND NOT has_function_privilege('service_role','pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid)','EXECUTE') AS grants,
  auth.uid() IS NOT NULL OR ((SELECT public.get_pdc_vehicle_key_number_460(NULL)->>'code')='not_authorized'
   AND (SELECT public.set_pdc_vehicle_key_number_460(NULL,1,'1',NULL)->>'code')='not_authorized') AS no_session_refused
)
SELECT b.tables AND b.append_only AND b.capture AND b.latest_matches AND b.attributed AND b.grants AND b.no_session_refused AS ok,
 format('%s key changes audited (%s edit, %s release, %s import, %s system) on %s vehicles; tables %s, append-only %s, capture triggers %s, latest audit = vehicle key %s, attributed %s, grants %s, no-session refused %s',
  (SELECT count(*) FROM public.pdc_vehicle_key_number_audit_460),
  (SELECT count(*) FROM public.pdc_vehicle_key_number_audit_460 WHERE source='edit'),(SELECT count(*) FROM public.pdc_vehicle_key_number_audit_460 WHERE source='release'),
  (SELECT count(*) FROM public.pdc_vehicle_key_number_audit_460 WHERE source='import'),(SELECT count(*) FROM public.pdc_vehicle_key_number_audit_460 WHERE source='system'),
  (SELECT count(DISTINCT vehicle_id) FROM public.pdc_vehicle_key_number_audit_460),
  b.tables,b.append_only,b.capture,b.latest_matches,b.attributed,b.grants,b.no_session_refused) AS detail
FROM b
$chk$,true,259,'r460');

DO $g$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r460')<>6
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r460_pins_before')::int+6 THEN RAISE EXCEPTION 'r460: pins not written'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r460: clock tick changed'; END IF;
 IF has_function_privilege('anon','public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)','EXECUTE')
    OR has_function_privilege('authenticated','pdc_key_number_private.release_set_key_number_460(uuid,integer,text,text,text,uuid)','EXECUTE')
    OR has_function_privilege('service_role','pdc_key_number_private.apply_key_number_460(uuid,integer,text,text,uuid,text,text,text,text,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.set_pdc_vehicle_key_number_460(uuid,integer,text,uuid)','EXECUTE') THEN RAISE EXCEPTION 'r460: unexpected function grants'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='vehicle_key_number_audit_460' AND sort_order=259 AND fault_id='F73' AND enabled)<>1 THEN RAISE EXCEPTION 'r460: check missing'; END IF;
END $g$;
