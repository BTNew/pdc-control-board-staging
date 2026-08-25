-- STAGING ONLY 388: receipt-backed Vehicle detail fields for canonical rows.
-- Allowlist: salesperson is 386; this contract owns client, PMB key and JC.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-388-authoritative-vehicle-detail-fields',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825231000' AND name='387_salesperson_synthetic_route')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825231000')
   OR to_regprocedure('public.assign_pdc_vehicle_salesperson_386(uuid,integer,text,uuid)') IS NULL
   OR to_regprocedure('public.pdc_vehicle_effective_salesperson_json_386(uuid)') IS NULL THEN
  RAISE EXCEPTION 'PDC_388_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

CREATE TABLE public.pdc_vehicle_detail_edit_receipts_388(
 receipt_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
 vehicle_version_before integer NOT NULL CHECK(vehicle_version_before>0),
 vehicle_version_after integer NOT NULL CHECK(vehicle_version_after>0),
 changed_fields jsonb NOT NULL CHECK(jsonb_typeof(changed_fields)='object'),
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
ALTER TABLE public.pdc_vehicle_detail_edit_receipts_388 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_vehicle_detail_edit_receipts_388 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_vehicle_detail_edit_history_388(
 history_id uuid PRIMARY KEY,
 receipt_id uuid NOT NULL REFERENCES public.pdc_vehicle_detail_edit_receipts_388(receipt_id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 vehicle_version_before integer NOT NULL,
 vehicle_version_after integer NOT NULL,
 before_data jsonb NOT NULL CHECK(jsonb_typeof(before_data)='object'),
 after_data jsonb NOT NULL CHECK(jsonb_typeof(after_data)='object'),
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 actor_role text NOT NULL CHECK(actor_role IN('operator','administrator')),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_vehicle_detail_edit_history_388 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_vehicle_detail_edit_history_388 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_vehicle_detail_edit_append_only_388()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $immutable$
BEGIN RAISE EXCEPTION 'PDC_388_APPEND_ONLY' USING errcode='55000'; END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_vehicle_detail_edit_append_only_388() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_vehicle_detail_edit_receipts_append_only_388
BEFORE UPDATE OR DELETE ON public.pdc_vehicle_detail_edit_receipts_388
FOR EACH ROW EXECUTE FUNCTION public.pdc_vehicle_detail_edit_append_only_388();
CREATE TRIGGER pdc_vehicle_detail_edit_history_append_only_388
BEFORE UPDATE OR DELETE ON public.pdc_vehicle_detail_edit_history_388
FOR EACH ROW EXECUTE FUNCTION public.pdc_vehicle_detail_edit_append_only_388();

CREATE OR REPLACE FUNCTION public.pdc_vehicle_effective_salesperson_json_386(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $effective$
 SELECT coalesce((
   SELECT jsonb_build_object(
     'salesperson_code',coalesce(nullif(upper(btrim(s.code)),''),nullif(upper(btrim(v.salesperson_reference)),''),''),
     'salesperson_name',coalesce(nullif(btrim(s.name),''),nullif(btrim(v.salesperson_reference),''),''),
     'salesperson_email',coalesce(nullif(lower(btrim(s.email)),''),''),
     'salesperson_manual_override',v.salesperson_manual_override,
     'salesperson_manual_override_at',v.salesperson_manual_override_at,
     'salesperson_manual_override_by',v.salesperson_manual_override_by
   ) FROM public.vehicles v LEFT JOIN public.salespeople s ON s.id=v.salesperson_id WHERE v.id=p_vehicle_id
 ),jsonb_build_object('salesperson_code','','salesperson_name','','salesperson_email','','salesperson_manual_override',false,'salesperson_manual_override_at',null,'salesperson_manual_override_by',null));
$effective$;

CREATE OR REPLACE FUNCTION public.update_pdc_vehicle_detail_fields_388(
 p_vehicle_id uuid,
 p_expected_vehicle_version integer,
 p_changes jsonb,
 p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='60s' AS $detail$
DECLARE
 v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_role text:=coalesce(public.current_pdc_user_role()::text,''); v_actor_role text;
 v_before public.vehicles%rowtype; v_after public.vehicles%rowtype;
 v_receipt public.pdc_vehicle_detail_edit_receipts_388%rowtype;
 v_changes jsonb:=coalesce(p_changes,'{}'::jsonb); v_payload jsonb; v_request_sha text; v_receipt_id uuid; v_history_id uuid;
 v_client text; v_key text; v_jobcard text; v_revision_before bigint; v_revision_after bigint;
 v_notifications_before bigint; v_notifications_after bigint; v_changed boolean:=false; v_response jsonb;
BEGIN
 IF v_actor IS NULL OR v_role NOT IN('operator','administrator') OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL
    OR jsonb_typeof(v_changes)<>'object' OR NOT (v_changes ?| ARRAY['client_name','key_number','job_card_number']) THEN
   RETURN jsonb_build_object('ok',false,'code','detail_invalid_input');
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(v_changes) k WHERE k NOT IN('client_name','key_number','job_card_number')) THEN
   RETURN jsonb_build_object('ok',false,'code','detail_field_not_allowlisted');
 END IF;
 SELECT r.role::text,lower(btrim(r.email)) INTO v_actor_role,v_email FROM public.pdc_user_roles r
 WHERE r.auth_user_id=v_actor AND r.active AND r.account_status='approved' AND r.role::text IN('operator','administrator')
 ORDER BY r.updated_at DESC LIMIT 1;
 IF v_actor_role IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 v_payload:=jsonb_build_object('contract','pdc-authoritative-vehicle-detail-fields-388','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'changes',v_changes,'idempotency_key',p_idempotency_key);
 v_request_sha:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-receipt:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_vehicle_detail_edit_receipts_388 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
   IF v_receipt.request_sha256<>v_request_sha THEN RAISE EXCEPTION 'PDC_388_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF;
   RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-vehicle:'||p_vehicle_id::text,0));
 SELECT revision INTO v_revision_before FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
 SELECT count(*) INTO v_notifications_before FROM public.vehicle_notifications;
 SELECT * INTO v_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v_before.deleted_at IS NOT NULL THEN
   v_response:=jsonb_build_object('ok',false,'code','vehicle_not_found');
 ELSIF v_before.version<>p_expected_vehicle_version THEN
   -- Stable contract error: PDC_388_VEHICLE_VERSION_CONFLICT.
   v_response:=jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v_before.id,'vehicle_version',v_before.version));
 ELSE
   IF v_changes ? 'client_name' THEN
     v_client:=nullif(regexp_replace(btrim(coalesce(v_changes->>'client_name','')),'\s+',' ','g'),'');
     IF v_client IS NOT NULL AND (length(v_client)>160 OR v_client~'[[:cntrl:]]') THEN RETURN jsonb_build_object('ok',false,'code','client_name_invalid'); END IF;
   END IF;
   IF v_changes ? 'job_card_number' THEN
     v_jobcard:=nullif(regexp_replace(btrim(coalesce(v_changes->>'job_card_number','')),'\s+',' ','g'),'');
     IF v_jobcard IS NOT NULL AND (length(v_jobcard)>80 OR v_jobcard~'[[:cntrl:]]') THEN RETURN jsonb_build_object('ok',false,'code','job_card_number_invalid'); END IF;
   END IF;
   IF v_changes ? 'key_number' THEN
     IF upper(btrim(coalesce(v_before.current_location,'')))<>'PMB' THEN RETURN jsonb_build_object('ok',false,'code','key_not_editable_outside_pmb'); END IF;
     v_key:=nullif(regexp_replace(upper(btrim(coalesce(v_changes->>'key_number',''))),'\s+',' ','g'),'');
     IF v_key IS NOT NULL AND (length(v_key)>40 OR v_key~'[[:cntrl:]]') THEN RETURN jsonb_build_object('ok',false,'code','key_number_invalid'); END IF;
     IF v_key IS NOT NULL THEN
       PERFORM pg_advisory_xact_lock(hashtextextended('pdc-388-key:'||v_key,0));
       IF EXISTS(SELECT 1 FROM public.vehicles x WHERE x.id<>v_before.id AND x.deleted_at IS NULL AND x.lifecycle_state='active' AND upper(btrim(coalesce(x.current_location,'')))='PMB' AND upper(btrim(coalesce(x.key_number,'')))=v_key) THEN
         RETURN jsonb_build_object('ok',false,'code','key_number_in_use');
       END IF;
     END IF;
   END IF;
   v_changed:=(v_changes ? 'client_name' AND v_before.customer_name IS DISTINCT FROM v_client)
      OR (v_changes ? 'key_number' AND v_before.key_number IS DISTINCT FROM v_key)
      OR (v_changes ? 'job_card_number' AND v_before.job_card_number IS DISTINCT FROM v_jobcard);
   IF v_changed THEN
     PERFORM set_config('pdc.salesperson_assignment_manual_386','allow',true);
     UPDATE public.vehicles SET
       customer_name=CASE WHEN v_changes ? 'client_name' THEN v_client ELSE customer_name END,
       key_number=CASE WHEN v_changes ? 'key_number' THEN v_key ELSE key_number END,
       job_card_number=CASE WHEN v_changes ? 'job_card_number' THEN v_jobcard ELSE job_card_number END,
       updated_at=clock_timestamp(),updated_by=v_actor,version=version+1
     WHERE id=v_before.id RETURNING * INTO v_after;
     v_response:=jsonb_build_object('ok',true,'code','vehicle_detail_updated','data',jsonb_build_object('changed',true,'vehicle_id',v_after.id,'vehicle_version_before',v_before.version,'vehicle_version_after',v_after.version,'changed_fields',v_changes));
   ELSE
     v_after:=v_before;
     v_response:=jsonb_build_object('ok',true,'code','vehicle_detail_unchanged','data',jsonb_build_object('changed',false,'vehicle_id',v_before.id,'vehicle_version',v_before.version,'changed_fields',v_changes));
   END IF;
 END IF;
 SELECT revision INTO v_revision_after FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT count(*) INTO v_notifications_after FROM public.vehicle_notifications;
 IF v_notifications_after<>v_notifications_before OR v_revision_after-v_revision_before<>(CASE WHEN v_changed THEN 1 ELSE 0 END) THEN RAISE EXCEPTION 'PDC_388_NOTIFICATION_OR_REVISION_POSTCONDITION' USING errcode='55000'; END IF;
 v_receipt_id:=extensions.uuid_generate_v5('38800000-0000-5000-8000-000000000388'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=v_response||jsonb_build_object('receipt_id',v_receipt_id,'request_sha256',v_request_sha,'actor_id',v_actor,'actor_email',v_email,'actor_role',v_actor_role,'notification_delta',v_notifications_after-v_notifications_before,'revision',jsonb_build_object('table','public.pdc_email_vehicle_revision','before',v_revision_before,'after',v_revision_after,'delta',v_revision_after-v_revision_before),'replay',false);
 INSERT INTO public.pdc_vehicle_detail_edit_receipts_388(receipt_id,vehicle_id,expected_vehicle_version,vehicle_version_before,vehicle_version_after,changed_fields,actor_id,actor_email,actor_role,idempotency_key,request_sha256,request_payload,response)
 VALUES(v_receipt_id,p_vehicle_id,p_expected_vehicle_version,v_before.version,v_after.version,v_changes,v_actor,v_email,v_actor_role,p_idempotency_key,v_request_sha,v_payload,v_response);
 IF v_changed THEN
   v_history_id:=extensions.uuid_generate_v5('38800000-0000-5000-8000-000000000388'::uuid,v_receipt_id::text||':history');
   INSERT INTO public.pdc_vehicle_detail_edit_history_388(history_id,receipt_id,vehicle_id,vehicle_version_before,vehicle_version_after,before_data,after_data,actor_id,actor_email,actor_role)
   VALUES(v_history_id,v_receipt_id,p_vehicle_id,v_before.version,v_after.version,to_jsonb(v_before),to_jsonb(v_after),v_actor,v_email,v_actor_role);
   PERFORM public.audit_pdc_event('update','vehicles',v_after.id,v_after.id,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object('action','update_pdc_vehicle_detail_fields_388','receipt_id',v_receipt_id,'changed_fields',v_changes,'notification_enqueued',false));
 END IF;
 RETURN v_response;
END $detail$;
REVOKE ALL ON FUNCTION public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid) TO authenticated;

DO $post$
BEGIN
 IF has_function_privilege('public','public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.update_pdc_vehicle_detail_fields_388(uuid,integer,jsonb,uuid)','EXECUTE')
   OR has_table_privilege('authenticated','public.pdc_vehicle_detail_edit_receipts_388','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('authenticated','public.pdc_vehicle_detail_edit_history_388','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'PDC_388_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825232000','388_authoritative_vehicle_detail_fields',ARRAY[
 'Allowlisted receipt-backed client_name, PMB-only unique key_number and job_card_number update contract',
 'Exact UUID/version/operator checks, bounded normalization, stale/replay handling and immutable before/after history',
 'No notifications, shared revision publication and narrow authenticated execute privilege'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
