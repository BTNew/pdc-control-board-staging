-- STAGING ONLY 386: receipt-backed authoritative salesperson assignment.
-- Production is intentionally untouched. No notification is queued.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-386-authoritative-salesperson-assignment',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825220000' AND name='385_qc_mutation_timeouts')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825220000')
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR to_regprocedure('public.current_pdc_user_role()') IS NULL
   OR to_regprocedure('public.pdc_vehicle_sales_dashboard_json(uuid)') IS NULL
   OR to_regprocedure('public.bump_pdc_email_vehicle_revision()') IS NULL THEN
  RAISE EXCEPTION 'PDC_386_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS salesperson_manual_override boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS salesperson_manual_override_at timestamptz,
  ADD COLUMN IF NOT EXISTS salesperson_manual_override_by uuid REFERENCES auth.users(id);

CREATE TABLE public.pdc_vehicle_salesperson_assignment_receipts_386(
 receipt_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 action text NOT NULL CHECK(action IN('assign','clear')),
 expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
 vehicle_version_before integer NOT NULL CHECK(vehicle_version_before>0),
 vehicle_version_after integer NOT NULL CHECK(vehicle_version_after>0),
 salesperson_id uuid REFERENCES public.salespeople(id) ON DELETE RESTRICT,
 salesperson_code text,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 actor_role text NOT NULL CHECK(actor_role IN('operator','administrator')),
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_vehicle_salesperson_assignment_receipts_386 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_vehicle_salesperson_assignment_receipts_386 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_vehicle_salesperson_assignment_history_386(
 history_id uuid PRIMARY KEY,
 receipt_id uuid NOT NULL REFERENCES public.pdc_vehicle_salesperson_assignment_receipts_386(receipt_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 action text NOT NULL CHECK(action IN('assign','clear')),
 vehicle_version_before integer NOT NULL CHECK(vehicle_version_before>0),
 vehicle_version_after integer NOT NULL CHECK(vehicle_version_after>0),
 before_salesperson_id uuid,
 before_salesperson_code text,
 before_salesperson_name text,
 before_salesperson_email text,
 after_salesperson_id uuid,
 after_salesperson_code text,
 after_salesperson_name text,
 after_salesperson_email text,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 actor_role text NOT NULL CHECK(actor_role IN('operator','administrator')),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_vehicle_salesperson_assignment_history_386 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_vehicle_salesperson_assignment_history_386 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_vehicle_salesperson_assignment_append_only_386()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN
 RAISE EXCEPTION 'PDC_386_APPEND_ONLY' USING errcode='55000';
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_vehicle_salesperson_assignment_append_only_386() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_vehicle_salesperson_assignment_receipts_append_only_386
BEFORE UPDATE OR DELETE ON public.pdc_vehicle_salesperson_assignment_receipts_386
FOR EACH ROW EXECUTE FUNCTION public.pdc_vehicle_salesperson_assignment_append_only_386();
CREATE TRIGGER pdc_vehicle_salesperson_assignment_history_append_only_386
BEFORE UPDATE OR DELETE ON public.pdc_vehicle_salesperson_assignment_history_386
FOR EACH ROW EXECUTE FUNCTION public.pdc_vehicle_salesperson_assignment_append_only_386();

-- Navision may continue to update its source/reference text, but once an
-- operator has assigned a salesperson the effective salesperson_id remains
-- pinned until this RPC deliberately changes or clears it.
CREATE OR REPLACE FUNCTION public.pdc_preserve_manual_salesperson_override_386()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $guard$
BEGIN
 IF OLD.salesperson_manual_override
    AND coalesce(current_setting('pdc.salesperson_assignment_manual_386',true),'')<>'allow' THEN
   NEW.salesperson_id:=OLD.salesperson_id;
   NEW.salesperson_reference:=OLD.salesperson_reference;
   NEW.salesperson_manual_override:=true;
   NEW.salesperson_manual_override_at:=OLD.salesperson_manual_override_at;
   NEW.salesperson_manual_override_by:=OLD.salesperson_manual_override_by;
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION public.pdc_preserve_manual_salesperson_override_386() FROM public,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS zz_pdc_preserve_manual_salesperson_override_386 ON public.vehicles;
CREATE TRIGGER zz_pdc_preserve_manual_salesperson_override_386
BEFORE UPDATE OF salesperson_reference,salesperson_id,salesperson_manual_override,salesperson_manual_override_at,salesperson_manual_override_by
ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_preserve_manual_salesperson_override_386();

CREATE OR REPLACE FUNCTION public.pdc_vehicle_effective_salesperson_json_386(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $effective$
 SELECT coalesce((
   SELECT jsonb_build_object(
     'salesperson_code',coalesce(nullif(upper(btrim(s.code)),''),nullif(upper(btrim(v.salesperson_reference)),''),''),
     'salesperson_name',coalesce(nullif(btrim(s.name),''),nullif(btrim(v.salesperson_reference),'')),
     'salesperson_email',coalesce(nullif(lower(btrim(s.email)),''),''),
     'salesperson_manual_override',v.salesperson_manual_override,
     'salesperson_manual_override_at',v.salesperson_manual_override_at,
     'salesperson_manual_override_by',v.salesperson_manual_override_by
   )
   FROM public.vehicles v LEFT JOIN public.salespeople s ON s.id=v.salesperson_id
   WHERE v.id=p_vehicle_id
 ),jsonb_build_object(
   'salesperson_code','','salesperson_name','','salesperson_email','',
   'salesperson_manual_override',false,'salesperson_manual_override_at',null,'salesperson_manual_override_by',null
 ));
$effective$;
REVOKE ALL ON FUNCTION public.pdc_vehicle_effective_salesperson_json_386(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.assign_pdc_vehicle_salesperson_386(
 p_vehicle_id uuid,
 p_expected_vehicle_version integer,
 p_salesperson_code text,
 p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='60s' AS $assign$
DECLARE
 v_actor uuid:=auth.uid();
 v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_role text:=coalesce(public.current_pdc_user_role()::text,'');
 v_actor_role text;
 v_before public.vehicles%rowtype;
 v_after public.vehicles%rowtype;
 v_salesperson public.salespeople%rowtype;
 v_target_salesperson_id uuid;
 v_salesperson_count integer:=0;
 v_before_salesperson public.salespeople%rowtype;
 v_after_salesperson public.salespeople%rowtype;
 v_receipt public.pdc_vehicle_salesperson_assignment_receipts_386%rowtype;
 v_action text;
 v_code text:=nullif(upper(btrim(coalesce(p_salesperson_code,''))),'');
 v_payload jsonb;
 v_request_sha text;
 v_receipt_id uuid;
 v_history_id uuid;
 v_revision_before bigint;
 v_revision_after bigint;
 v_notifications_before bigint;
 v_notifications_after bigint;
 v_changed boolean:=false;
 v_response jsonb;
BEGIN
 IF v_actor IS NULL OR v_role NOT IN('operator','administrator') OR p_vehicle_id IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL THEN
   RETURN jsonb_build_object('ok',false,'code','not_authorized');
 END IF;
 SELECT r.role::text,lower(btrim(r.email)) INTO v_actor_role,v_email
 FROM public.pdc_user_roles r
 WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved'
   AND r.role::text IN('operator','administrator')
 ORDER BY r.updated_at DESC LIMIT 1;
 IF v_actor_role IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 v_action:=CASE WHEN v_code IS NULL THEN 'clear' ELSE 'assign' END;
 IF v_code IS NOT NULL THEN
   SELECT count(*) INTO v_salesperson_count FROM public.salespeople s
   WHERE s.active AND nullif(btrim(s.code),'') IS NOT NULL AND upper(btrim(s.code))=v_code;
   IF v_salesperson_count=0 THEN
     -- Stable contract error: PDC_386_SALESPERSON_NOT_ACTIVE.
     RETURN jsonb_build_object('ok',false,'code','salesperson_not_active');
   END IF;
   IF v_salesperson_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','salesperson_code_ambiguous'); END IF;
   SELECT * INTO v_salesperson FROM public.salespeople s
   WHERE s.active AND upper(btrim(s.code))=v_code LIMIT 1;
 END IF;
 v_target_salesperson_id:=v_salesperson.id;
 v_payload:=jsonb_build_object('contract','pdc-authoritative-salesperson-assignment-386','vehicle_id',p_vehicle_id,
   'expected_vehicle_version',p_expected_vehicle_version,'salesperson_code',v_code,'action',v_action,
   'idempotency_key',p_idempotency_key);
 v_request_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-386-receipt:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_vehicle_salesperson_assignment_receipts_386
 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
   IF v_receipt.request_sha256<>v_request_sha THEN
     RAISE EXCEPTION 'PDC_386_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023';
   END IF;
   RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-386-vehicle:'||p_vehicle_id::text,0));
 LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
 LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
 LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 SELECT revision INTO v_revision_before FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
 SELECT count(*) INTO v_notifications_before FROM public.vehicle_notifications;
 SELECT * INTO v_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v_before.deleted_at IS NOT NULL THEN
   v_response:=jsonb_build_object('ok',false,'code','vehicle_not_found');
 ELSE
   SELECT * INTO v_before_salesperson FROM public.salespeople WHERE id=v_before.salesperson_id;
   IF v_before.version<>p_expected_vehicle_version THEN
     -- Stable contract error: PDC_386_VEHICLE_VERSION_CONFLICT.
     v_response:=jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v_before.id,'vehicle_version',v_before.version,'effective_salesperson',public.pdc_vehicle_effective_salesperson_json_386(v_before.id)));
   ELSIF v_before.salesperson_id IS NOT DISTINCT FROM v_target_salesperson_id
     AND v_before.salesperson_manual_override THEN
     -- Stable contract marker: PDC_386_MANUAL_SALESPERSON_OVERRIDE.
     v_response:=jsonb_build_object('ok',true,'code','salesperson_assignment_unchanged','data',jsonb_build_object('changed',false,'vehicle_id',v_before.id,'vehicle_version',v_before.version,'effective_salesperson',public.pdc_vehicle_effective_salesperson_json_386(v_before.id)));
   ELSE
     PERFORM set_config('pdc.salesperson_assignment_manual_386','allow',true);
     UPDATE public.vehicles SET
       salesperson_id=v_target_salesperson_id,
       salesperson_reference=coalesce(v_code,''),
       salesperson_manual_override=true,
       salesperson_manual_override_at=clock_timestamp(),
       salesperson_manual_override_by=v_actor,
       updated_at=clock_timestamp(),updated_by=v_actor,version=version+1
     WHERE id=p_vehicle_id RETURNING * INTO v_after;
     SELECT * INTO v_after_salesperson FROM public.salespeople WHERE id=v_after.salesperson_id;
     v_changed:=true;
     v_response:=jsonb_build_object('ok',true,'code',CASE WHEN v_action='clear' THEN 'salesperson_cleared' ELSE 'salesperson_assigned' END,
       'data',jsonb_build_object('changed',true,'vehicle_id',v_after.id,'vehicle_version_before',v_before.version,'vehicle_version_after',v_after.version,
         'effective_salesperson',public.pdc_vehicle_effective_salesperson_json_386(v_after.id)));
   END IF;
 END IF;
 SELECT revision INTO v_revision_after FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT count(*) INTO v_notifications_after FROM public.vehicle_notifications;
 IF v_notifications_after<>v_notifications_before OR v_revision_after-v_revision_before<>(CASE WHEN v_changed THEN 1 ELSE 0 END) THEN
   RAISE EXCEPTION 'PDC_386_NOTIFICATION_OR_REVISION_POSTCONDITION' USING errcode='55000';
 END IF;
 v_receipt_id:=extensions.uuid_generate_v5('38600000-0000-5000-8000-000000000386'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=v_response||jsonb_build_object('receipt_id',v_receipt_id,'request_sha256',v_request_sha,'action',v_action,
   'actor_id',v_actor,'actor_email',v_email,'actor_role',v_actor_role,'notification_delta',v_notifications_after-v_notifications_before,
   'revision',jsonb_build_object('table','public.pdc_email_vehicle_revision','before',v_revision_before,'after',v_revision_after,'delta',v_revision_after-v_revision_before),
   'replay',false);
 INSERT INTO public.pdc_vehicle_salesperson_assignment_receipts_386(receipt_id,vehicle_id,action,expected_vehicle_version,vehicle_version_before,vehicle_version_after,
   salesperson_id,salesperson_code,actor_id,actor_email,actor_role,idempotency_key,request_sha256,request_payload,response)
 VALUES(v_receipt_id,p_vehicle_id,v_action,p_expected_vehicle_version,v_before.version,coalesce(v_after.version,v_before.version),
   v_target_salesperson_id,v_code,v_actor,v_email,v_actor_role,p_idempotency_key,v_request_sha,v_payload,v_response);
 IF v_changed THEN
   v_history_id:=extensions.uuid_generate_v5('38600000-0000-5000-8000-000000000386'::uuid,v_receipt_id::text||':history');
   INSERT INTO public.pdc_vehicle_salesperson_assignment_history_386(history_id,receipt_id,vehicle_id,action,vehicle_version_before,vehicle_version_after,
     before_salesperson_id,before_salesperson_code,before_salesperson_name,before_salesperson_email,after_salesperson_id,after_salesperson_code,after_salesperson_name,after_salesperson_email,
     actor_id,actor_email,actor_role)
   VALUES(v_history_id,v_receipt_id,p_vehicle_id,v_action,v_before.version,v_after.version,v_before.salesperson_id,upper(btrim(v_before_salesperson.code)),v_before_salesperson.name,lower(btrim(v_before_salesperson.email)),
     v_after.salesperson_id,upper(btrim(v_after_salesperson.code)),v_after_salesperson.name,lower(btrim(v_after_salesperson.email)),v_actor,v_email,v_actor_role);
   PERFORM public.audit_pdc_event('update','vehicles',v_after.id,v_after.id,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('action','assign_pdc_vehicle_salesperson_386','receipt_id',v_receipt_id,'request_sha256',v_request_sha,'manual_override',true,'notification_enqueued',false));
 END IF;
 RETURN v_response;
END $assign$;
REVOKE ALL ON FUNCTION public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid) TO authenticated;

-- Recompose the current canonical snapshot while preserving all prior fields.
CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb;
BEGIN
 r:=public.get_pdc_email_vehicle_location_snapshot_pre_310();
 IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
 SELECT coalesce(jsonb_agg(x || public.pdc_vehicle_sales_dashboard_json((x->>'id')::uuid) || public.pdc_vehicle_effective_salesperson_json_386((x->>'id')::uuid)),'[]'::jsonb)
 INTO rows FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
 RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

DO $post$
BEGIN
 IF has_function_privilege('public','public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid)','EXECUTE')
   OR has_table_privilege('authenticated','public.pdc_vehicle_salesperson_assignment_receipts_386','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('authenticated','public.pdc_vehicle_salesperson_assignment_history_386','SELECT,INSERT,UPDATE,DELETE') THEN
  RAISE EXCEPTION 'PDC_386_ACL_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825230000','386_authoritative_salesperson_assignment',ARRAY[
 'Receipt-backed canonical UUID/version salesperson assignment and audited clear-to-Unassigned RPC',
 'Active salespeople validation, operator/administrator approval, UUID idempotency and request SHA-256 receipts',
 'Immutable assignment history, manual Navision override preservation, shared revision bump and zero notification delta',
 'Canonical snapshot effective salesperson code/name/email projection and narrow authenticated execute privilege'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
