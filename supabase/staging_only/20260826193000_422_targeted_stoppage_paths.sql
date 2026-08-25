-- STAGING ONLY 422: exact STOPPAGE targets for Workshop, Parts and PMB.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-422-targeted-stoppages',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826190000' AND name='421_rft_shared_vehicle_snapshot')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826190000')
   OR to_regprocedure('public.return_work_to_queue(uuid,integer,text,jsonb)') IS NULL
   OR to_regprocedure('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)') IS NULL
   OR to_regprocedure('public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)') IS NULL
   OR to_regclass('public.pdc_rft_transport_action_receipts_412') IS NULL THEN
  RAISE EXCEPTION 'PDC_422_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS pmb_stoppage_reason text;
ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS pmb_stoppage_started_at timestamptz;
ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS pmb_stoppage_started_by uuid REFERENCES auth.users(id);
ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS pmb_stoppage_cleared_at timestamptz;
ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS pmb_stoppage_cleared_by uuid REFERENCES auth.users(id);

CREATE TABLE public.pdc_pmb_stoppage_receipts_422(
 receipt_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 action text NOT NULL CHECK(action IN('set','clear')),
 expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
 vehicle_version_before integer NOT NULL CHECK(vehicle_version_before>0),
 vehicle_version_after integer NOT NULL CHECK(vehicle_version_after>0),
 actor_id uuid NOT NULL,
 actor_email text NOT NULL,
 reason text NOT NULL,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 before_state jsonb NOT NULL,
 after_state jsonb NOT NULL,
 response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_pmb_stoppage_receipts_422 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pmb_stoppage_receipts_422 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_pmb_stoppage_receipts_422 FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_pmb_stoppage_receipts_422_append_only BEFORE UPDATE OR DELETE ON public.pdc_pmb_stoppage_receipts_422 FOR EACH ROW EXECUTE FUNCTION public.pdc_412_append_only();

CREATE OR REPLACE FUNCTION public.set_pmb_stoppage_422(p_vehicle_id uuid,p_expected_vehicle_version integer,p_action text,p_reason text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='60s' AS $set$
DECLARE
 uid uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); act text:=lower(btrim(coalesce(p_action,'')));
 reason text:=regexp_replace(btrim(coalesce(p_reason,'')),'\s+',' ','g'); v public.vehicles%rowtype; before_j jsonb; after_j jsonb;
 old public.pdc_pmb_stoppage_receipts_422%rowtype; payload jsonb; sha text; receipt uuid; result jsonb; at_now timestamptz:=clock_timestamp();
BEGIN
 IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL OR act NOT IN('set','clear')
   OR length(reason) NOT BETWEEN 3 AND 240
   OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator')) THEN
  RETURN jsonb_build_object('ok',false,'code','pmb_stoppage_invalid_or_unauthorized'); END IF;
 payload:=jsonb_build_object('contract','pdc-pmb-stoppage-422','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'action',act,'reason',reason,'idempotency_key',p_idempotency_key);
 sha:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-422-pmb:'||uid::text||':'||p_idempotency_key::text,0));
 SELECT * INTO old FROM public.pdc_pmb_stoppage_receipts_422 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
 IF FOUND THEN IF old.request_sha256<>sha THEN RAISE EXCEPTION 'PDC_422_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state IN('completed','deleted') OR upper(btrim(coalesce(v.current_location,'')))<>'PMB' THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_active_in_pmb'); END IF;
 IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','current_version',v.version); END IF;
 IF act='set' AND v.pmb_stoppage_started_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','pmb_stoppage_already_active'); END IF;
 IF act='clear' AND v.pmb_stoppage_started_at IS NULL THEN RETURN jsonb_build_object('ok',false,'code','no_active_pmb_stoppage'); END IF;
 IF v.stock_number LIKE 'HERMES-TEST-%' THEN PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v.id::text,true); END IF;
 before_j:=jsonb_build_object('vehicle_id',v.id,'version',v.version,'current_location',v.current_location,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'reason',v.pmb_stoppage_reason,'started_at',v.pmb_stoppage_started_at,'started_by',v.pmb_stoppage_started_by,'cleared_at',v.pmb_stoppage_cleared_at,'cleared_by',v.pmb_stoppage_cleared_by);
 IF act='set' THEN
  UPDATE public.vehicles SET pmb_stoppage_reason=reason,pmb_stoppage_started_at=at_now,pmb_stoppage_started_by=uid,pmb_stoppage_cleared_at=NULL,pmb_stoppage_cleared_by=NULL,version=version+1,updated_at=at_now,updated_by=uid WHERE id=v.id RETURNING * INTO v;
 ELSE
  UPDATE public.vehicles SET pmb_stoppage_reason=NULL,pmb_stoppage_started_at=NULL,pmb_stoppage_started_by=NULL,pmb_stoppage_cleared_at=at_now,pmb_stoppage_cleared_by=uid,version=version+1,updated_at=at_now,updated_by=uid WHERE id=v.id RETURNING * INTO v;
 END IF;
 after_j:=jsonb_build_object('vehicle_id',v.id,'version',v.version,'current_location',v.current_location,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'reason',v.pmb_stoppage_reason,'started_at',v.pmb_stoppage_started_at,'started_by',v.pmb_stoppage_started_by,'cleared_at',v.pmb_stoppage_cleared_at,'cleared_by',v.pmb_stoppage_cleared_by);
 receipt:=extensions.uuid_generate_v5('42200000-0000-5000-8000-000000000422'::uuid,uid::text||':'||p_idempotency_key::text);
 result:=jsonb_build_object('ok',true,'code',CASE WHEN act='set' THEN 'pmb_stoppage_recorded' ELSE 'pmb_stoppage_cleared' END,'replay',false,'receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'action',act,'reason',reason,'before',before_j,'after',after_j);
 INSERT INTO public.pdc_pmb_stoppage_receipts_422 VALUES(receipt,v.id,act,p_expected_vehicle_version,p_expected_vehicle_version,v.version,uid,email,reason,p_idempotency_key,sha,before_j,after_j,result,at_now);
 PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_j,after_j,jsonb_build_object('action','set_pmb_stoppage_422','stoppage_action',act,'receipt_id',receipt,'reason',reason));
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=at_now WHERE singleton;
 RETURN result;
END $set$;

CREATE OR REPLACE FUNCTION public.clear_vehicle_stoppage_422(p_vehicle_id uuid,p_expected_vehicle_version integer,p_stoppage_kind text,p_booking_id uuid,p_expected_booking_version integer,p_resolution_note text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='90s' AS $clear$
DECLARE
 uid uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); kind text:=lower(btrim(coalesce(p_stoppage_kind,'')));
 note text:=regexp_replace(btrim(coalesce(p_resolution_note,'')),'\s+',' ','g'); v public.vehicles%rowtype; b public.workshop_bookings%rowtype;
 parts public.vehicle_parts_updates%rowtype; old public.pdc_rft_transport_action_receipts_412%rowtype; before_j jsonb; after_j jsonb; payload jsonb; sha text; receipt uuid; result jsonb; child_key uuid; version_after integer;
BEGIN
 IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL OR kind NOT IN('booking','parts','pmb') OR length(note) NOT BETWEEN 3 AND 240
   OR (kind='booking' AND (p_booking_id IS NULL OR p_expected_booking_version<1))
   OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator')) THEN
  RETURN jsonb_build_object('ok',false,'code','targeted_stoppage_clear_invalid_or_unauthorized'); END IF;
 payload:=jsonb_build_object('contract','pdc-targeted-stoppage-clear-422','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'stoppage_kind',kind,'booking_id',p_booking_id,'expected_booking_version',p_expected_booking_version,'resolution_note',note,'idempotency_key',p_idempotency_key);
 sha:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-422-clear:'||uid::text||':'||p_idempotency_key::text,0));
 SELECT * INTO old FROM public.pdc_rft_transport_action_receipts_412 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
 IF FOUND THEN IF old.request_sha256<>sha THEN RAISE EXCEPTION 'PDC_422_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state IN('completed','deleted') THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_active'); END IF;
 IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','current_version',v.version); END IF;
 IF v.stock_number LIKE 'HERMES-TEST-%' THEN PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v.id::text,true); END IF;
 before_j:=jsonb_build_object('vehicle',to_jsonb(v),'kind',kind);
 IF kind='booking' THEN
  SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=v.id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','booking_not_found_for_vehicle'); END IF;
  IF b.version<>p_expected_booking_version THEN RETURN jsonb_build_object('ok',false,'code','booking_version_conflict','current_booking_version',b.version); END IF;
  IF b.status::text<>'stoppage' THEN RETURN jsonb_build_object('ok',false,'code','booking_not_in_stoppage'); END IF;
  before_j:=before_j||jsonb_build_object('booking',public.workshop_booking_snapshot(b.id));
  result:=public.return_work_to_queue(b.id,b.version,NULL,jsonb_build_object('source','clear_vehicle_stoppage_422','resolution_note',note,'targeted',true));
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_422_BOOKING_CLEAR_FAILED:%',coalesce(result->>'error','unknown') USING errcode='40001'; END IF;
 ELSIF kind='parts' THEN
  SELECT * INTO parts FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND OR NOT coalesce(parts.parts_stoppage,false) THEN RETURN jsonb_build_object('ok',false,'code','no_active_parts_stoppage'); END IF;
  child_key:=extensions.uuid_generate_v5('42200000-0000-5000-8000-000000000422'::uuid,p_idempotency_key::text||':parts');
  result:=public.set_pdc_parts_stoppage_376(v.id,v.version,child_key,'clear',note);
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_422_PARTS_CLEAR_FAILED:%',coalesce(result->>'code','unknown') USING errcode='40001'; END IF;
 ELSE
  IF v.pmb_stoppage_started_at IS NULL THEN RETURN jsonb_build_object('ok',false,'code','no_active_pmb_stoppage'); END IF;
  child_key:=extensions.uuid_generate_v5('42200000-0000-5000-8000-000000000422'::uuid,p_idempotency_key::text||':pmb');
  result:=public.set_pmb_stoppage_422(v.id,v.version,'clear',note,child_key);
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_422_PMB_CLEAR_FAILED:%',coalesce(result->>'code','unknown') USING errcode='40001'; END IF;
 END IF;
 SELECT version INTO version_after FROM public.vehicles WHERE id=v.id;
 after_j:=jsonb_build_object('vehicle',(SELECT to_jsonb(x) FROM public.vehicles x WHERE x.id=v.id),'kind',kind,'booking',CASE WHEN p_booking_id IS NULL THEN NULL ELSE public.workshop_booking_snapshot(p_booking_id) END);
 receipt:=extensions.uuid_generate_v5('42200000-0000-5000-8000-000000000422'::uuid,uid::text||':'||p_idempotency_key::text);
 result:=jsonb_build_object('ok',true,'code','targeted_stoppage_cleared','replay',false,'receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',v.version,'vehicle_version_after',version_after,'stoppage_kind',kind,'booking_id',p_booking_id,'resolution_note',note,'before',before_j,'after',after_j);
 INSERT INTO public.pdc_rft_transport_action_receipts_412 VALUES(receipt,v.id,'clear_stoppage',p_expected_vehicle_version,v.version,version_after,uid,email,p_idempotency_key,sha,payload,before_j,after_j,result,clock_timestamp());
 RETURN result;
END $clear$;

-- Fail closed instead of retaining the former vehicle-wide multi-stoppage clear.
CREATE OR REPLACE FUNCTION public.clear_vehicle_stoppage_412(p_vehicle_id uuid,p_expected_vehicle_version integer,p_resolution_note text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN PERFORM public.workshop_require_planner_operator(); RETURN jsonb_build_object('ok',false,'code','target_required_use_clear_vehicle_stoppage_422'); END $$;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_422;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb;
BEGIN
 r:=public.get_pdc_email_vehicle_location_snapshot_pre_422(); IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
 SELECT coalesce(jsonb_agg(x||jsonb_build_object('pmb_stoppage_reason',v.pmb_stoppage_reason,'pmb_stoppage_started_at',v.pmb_stoppage_started_at,'pmb_stoppage_started_by',v.pmb_stoppage_started_by,'pmb_stoppage_cleared_at',v.pmb_stoppage_cleared_at,'pmb_stoppage_cleared_by',v.pmb_stoppage_cleared_by,
   'workshop_bookings',coalesce((SELECT jsonb_agg(j.value||jsonb_build_object('version',b.version) ORDER BY j.ordinality) FROM jsonb_array_elements(coalesce(x->'workshop_bookings','[]'::jsonb)) WITH ORDINALITY j(value,ordinality) JOIN public.workshop_bookings b ON b.id=(j.value->>'booking_id')::uuid),'[]'::jsonb)) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb)
 INTO rows FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x JOIN public.vehicles v ON v.id=(x->>'id')::uuid;
 RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $snapshot$;

REVOKE ALL ON FUNCTION public.set_pmb_stoppage_422(uuid,integer,text,text,uuid) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.clear_vehicle_stoppage_422(uuid,integer,text,uuid,integer,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_pmb_stoppage_422(uuid,integer,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_vehicle_stoppage_422(uuid,integer,text,uuid,integer,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_422() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

DO $post$
BEGIN
 IF NOT has_function_privilege('authenticated','public.set_pmb_stoppage_422(uuid,integer,text,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.clear_vehicle_stoppage_422(uuid,integer,text,uuid,integer,text,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.clear_vehicle_stoppage_422(uuid,integer,text,uuid,integer,text,uuid)','EXECUTE')
   OR has_table_privilege('authenticated','public.pdc_pmb_stoppage_receipts_422','SELECT,INSERT,UPDATE,DELETE') THEN
  RAISE EXCEPTION 'PDC_422_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826193000','422_targeted_stoppage_paths',ARRAY[
 'One exact Clear stoppage action targets one Workshop booking, Parts stoppage or authoritative PMB stoppage and never clears unrelated stoppages',
 'PMB stoppage state and append-only set/clear receipts are server-authoritative; browser-local operational blockers are not used',
 'Legacy vehicle-wide clear fails closed; exact vehicle/booking versions, actor/idempotency and immutable before/after evidence retained'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
