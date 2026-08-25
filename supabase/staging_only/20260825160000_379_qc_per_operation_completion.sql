-- STAGING ONLY 379: per-operation QC completion authority and gate.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-379-qc-operation-completion',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825150000' AND name='378_navision_jita_shared_projection')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825150000')
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM jsonb_build_object('rows',1498,'sha256','cb43c3582df4fd646ffb457a627273ce59dc273034bc0e7b95c24c13f2dc437e') THEN
  RAISE EXCEPTION 'PDC_379_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE TABLE public.pdc_qc_operation_completions_379(
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 line_identity text NOT NULL CHECK(line_identity~'^(source|manual):[0-9a-f-]{36}$'),
 source_kind text NOT NULL CHECK(source_kind IN('authenticated','manual')),
 source_line_id uuid NOT NULL,
 stage_code text NOT NULL CHECK(stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')),
 completed boolean NOT NULL DEFAULT false,
 completed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 completed_at timestamptz,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(vehicle_id,line_identity),
 CHECK((completed AND completed_by IS NOT NULL AND completed_at IS NOT NULL) OR (NOT completed AND completed_by IS NULL AND completed_at IS NULL))
);
ALTER TABLE public.pdc_qc_operation_completions_379 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_operation_completions_379 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_qc_operation_completion_history_379(
 history_id uuid PRIMARY KEY,vehicle_id uuid NOT NULL,line_identity text NOT NULL,actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 before_state jsonb,after_state jsonb NOT NULL,reason text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_qc_operation_completion_history_379 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_operation_completion_history_379 FROM public,anon,authenticated,service_role;
CREATE TABLE public.pdc_qc_operation_completion_receipts_379(
 receipt_id uuid PRIMARY KEY,vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,line_identity text NOT NULL,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,actor_email text NOT NULL,idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),response jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_qc_operation_completion_receipts_379 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_operation_completion_receipts_379 FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.pdc_qc_operation_evidence_append_only_379() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_379_APPEND_ONLY_EVIDENCE' USING errcode='55000';END $$;
REVOKE ALL ON FUNCTION public.pdc_qc_operation_evidence_append_only_379() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_qc_operation_history_append_only_379 BEFORE UPDATE OR DELETE ON public.pdc_qc_operation_completion_history_379 FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_operation_evidence_append_only_379();
CREATE TRIGGER pdc_qc_operation_receipts_append_only_379 BEFORE UPDATE OR DELETE ON public.pdc_qc_operation_completion_receipts_379 FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_operation_evidence_append_only_379();

CREATE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $lines$
 WITH source_lines AS(
  SELECT 'source:'||ol.operation_line_id::text line_identity,'authenticated' source_kind,ol.operation_line_id source_line_id,
   ol.operation_no,ol.description,ol.job_card_number,ol.estimated_hours,
   coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)) stage_code,
   coalesce(a.active,true) active
  FROM public.pdc_authenticated_email_operation_lines ol
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=ol.vehicle_id AND a.line_key='source:'||ol.operation_line_id::text
  WHERE ol.vehicle_id=p_vehicle_id
 ), manual_lines AS(
  SELECT 'manual:'||a.adjustment_id::text,'manual',a.adjustment_id,'MANUAL',a.description,NULL,a.estimated_hours,a.stage_code,a.active
  FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id=p_vehicle_id AND a.source_kind='manual'
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines)
 SELECT coalesce(jsonb_agg(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',l.estimated_hours,
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0)) ORDER BY l.stage_code,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 WHERE l.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')
$lines$;
REVOKE ALL ON FUNCTION public.pdc_qc_operation_lines_379(uuid) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.set_pdc_qc_operation_completion_379(p_vehicle_id uuid,p_expected_vehicle_version integer,p_line_identity text,
 p_expected_line_version integer,p_idempotency_key uuid,p_completed boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $set$
DECLARE v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_line text:=lower(btrim(coalesce(p_line_identity,'')));
 v_vehicle public.vehicles%rowtype;v_current public.pdc_qc_operation_completions_379%rowtype;v_after public.pdc_qc_operation_completions_379%rowtype;
 v_source_kind text;v_source_id uuid;v_stage text;v_active boolean;v_request jsonb;v_sha text;v_receipt public.pdc_qc_operation_completion_receipts_379%rowtype;
 v_response jsonb;v_id uuid;v_before jsonb;v_work_key text;v_all_complete boolean;v_hours numeric;
BEGIN
 IF p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR v_line!~'^(source|manual):[0-9a-f-]{36}$'
   OR p_expected_line_version IS NULL OR p_expected_line_version<0 OR p_idempotency_key IS NULL OR p_completed IS NULL THEN RAISE EXCEPTION 'PDC_379_INVALID_INPUT' USING errcode='22023';END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN RAISE EXCEPTION 'PDC_379_UNAUTHORIZED' USING errcode='42501';END IF;
 v_request:=jsonb_build_object('contract','pdc-qc-operation-379','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,
  'line_identity',v_line,'expected_line_version',p_expected_line_version,'idempotency_key',p_idempotency_key,'completed',p_completed,'actor_id',v_actor);
 v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-qc-op-379:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_qc_operation_completion_receipts_379 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_sha OR v_receipt.actor_email<>v_email THEN RAISE EXCEPTION 'PDC_379_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023';END IF;
  SELECT * INTO v_current FROM public.pdc_qc_operation_completions_379 WHERE vehicle_id=p_vehicle_id AND line_identity=v_line;
  IF to_jsonb(v_current) IS DISTINCT FROM v_receipt.response->'line' OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN RAISE EXCEPTION 'PDC_379_REPLAY_READBACK_MISMATCH' USING errcode='55000';END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-qc-op-vehicle:'||p_vehicle_id::text,0));
 SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' OR upper(btrim(coalesce(v_vehicle.current_location,'')))<>'QC' THEN RAISE EXCEPTION 'PDC_379_VEHICLE_NOT_ACTIVE_QC' USING errcode='22023';END IF;
 IF v_vehicle.version<>p_expected_vehicle_version THEN RAISE EXCEPTION 'PDC_379_VEHICLE_VERSION_CONFLICT' USING errcode='40001';END IF;
 IF v_line LIKE 'source:%' THEN
  v_source_kind:='authenticated';v_source_id:=substring(v_line from 8)::uuid;
  SELECT coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)),coalesce(a.active,true),coalesce(a.estimated_hours,ol.estimated_hours) INTO v_stage,v_active,v_hours
  FROM public.pdc_authenticated_email_operation_lines ol LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=ol.vehicle_id AND a.line_key=v_line
  WHERE ol.operation_line_id=v_source_id AND ol.vehicle_id=p_vehicle_id;
 ELSE
  v_source_kind:='manual';v_source_id:=substring(v_line from 8)::uuid;
  SELECT a.stage_code,a.active,a.estimated_hours INTO v_stage,v_active,v_hours FROM public.vehicle_workshop_line_adjustments a WHERE a.adjustment_id=v_source_id AND a.vehicle_id=p_vehicle_id AND a.source_kind='manual';
 END IF;
 IF v_stage IS NULL OR NOT coalesce(v_active,false) THEN RAISE EXCEPTION 'PDC_379_LINE_UNKNOWN_OR_INACTIVE' USING errcode='22023';END IF;
 IF v_hours IS NULL THEN RAISE EXCEPTION 'PDC_379_LINE_HOURS_UNKNOWN' USING errcode='22023';END IF;
 SELECT * INTO v_current FROM public.pdc_qc_operation_completions_379 WHERE vehicle_id=p_vehicle_id AND line_identity=v_line FOR UPDATE;
 IF (FOUND AND v_current.version<>p_expected_line_version) OR (NOT FOUND AND p_expected_line_version<>0) THEN RAISE EXCEPTION 'PDC_379_LINE_VERSION_CONFLICT' USING errcode='40001';END IF;
 v_before:=CASE WHEN v_current.line_identity IS NULL THEN NULL ELSE to_jsonb(v_current) END;
 INSERT INTO public.pdc_qc_operation_completions_379(vehicle_id,line_identity,source_kind,source_line_id,stage_code,completed,completed_by,completed_at,version)
 VALUES(p_vehicle_id,v_line,v_source_kind,v_source_id,v_stage,p_completed,CASE WHEN p_completed THEN v_actor END,CASE WHEN p_completed THEN clock_timestamp() END,1)
 ON CONFLICT(vehicle_id,line_identity) DO UPDATE SET stage_code=excluded.stage_code,completed=excluded.completed,completed_by=excluded.completed_by,completed_at=excluded.completed_at,version=public.pdc_qc_operation_completions_379.version+1,updated_at=clock_timestamp()
 RETURNING * INTO v_after;
 INSERT INTO public.pdc_qc_operation_completion_history_379(history_id,vehicle_id,line_identity,actor_id,before_state,after_state,reason)
 VALUES(extensions.uuid_generate_v5('37900000-0000-5000-8000-000000000379'::uuid,v_actor::text||':'||p_idempotency_key::text||':history'),p_vehicle_id,v_line,v_actor,v_before,to_jsonb(v_after),'Authenticated per-operation QC completion');
 v_work_key:=lower(replace(v_stage,'_',''));
 v_work_key:=CASE v_stage WHEN 'BUS_4X4' THEN 'bus4x4' WHEN 'FABRICATION' THEN 'fabrication' WHEN 'ELECTRICAL' THEN 'electrical' ELSE lower(v_stage) END;
 SELECT NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l WHERE l->>'stage_code'=v_stage AND coalesce((l->>'active')::boolean,false) AND ((l->>'estimated_hours') IS NULL OR NOT coalesce((l->>'completed')::boolean,false))) INTO v_all_complete;
 UPDATE public.vehicle_work_items SET completed=v_all_complete,completed_by=CASE WHEN v_all_complete THEN v_actor END,completed_at=CASE WHEN v_all_complete THEN clock_timestamp() END,updated_at=clock_timestamp()
 WHERE vehicle_id=p_vehicle_id AND lower(work_key)=v_work_key AND required;
 UPDATE public.vehicles SET version=version+1,qc_completed_at=NULL,qc_completed_by=NULL,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_vehicle;
 PERFORM public.audit_pdc_event('update','pdc_qc_operation_completions_379',v_source_id,p_vehicle_id,v_before,to_jsonb(v_after),jsonb_build_object('action','set_pdc_qc_operation_completion_379','line_identity',v_line,'stage_code',v_stage,'completed',p_completed,'notification_enqueued',false));
 IF (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN RAISE EXCEPTION 'PDC_379_NOTIFICATION_POSTCONDITION' USING errcode='55000';END IF;
 v_id:=extensions.uuid_generate_v5('37900000-0000-5000-8000-000000000379'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','qc_operation_completion_saved','replay',false,'receipt_id',v_id,'request_sha256',v_sha,'vehicle_id',p_vehicle_id,
  'vehicle_version_after',v_vehicle.version,'line',to_jsonb(v_after),'department_complete',v_all_complete,'notification_delta',0);
 INSERT INTO public.pdc_qc_operation_completion_receipts_379(receipt_id,vehicle_id,line_identity,actor_id,actor_email,idempotency_key,request_sha256,response)
 VALUES(v_id,p_vehicle_id,v_line,v_actor,v_email,p_idempotency_key,v_sha,v_response);
 RETURN v_response;
END $set$;
REVOKE ALL ON FUNCTION public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean) TO authenticated;

CREATE FUNCTION public.pdc_qc_require_all_operations_complete_379() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $gate$
BEGIN
 IF NEW.qc_completed_at IS NOT NULL AND OLD.qc_completed_at IS NULL AND (
  (EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=NEW.id AND w.required AND lower(w.work_key) IN('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre'))
   AND jsonb_array_length(public.pdc_qc_operation_lines_379(NEW.id))=0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(NEW.id)) l WHERE coalesce((l->>'active')::boolean,false) AND ((l->>'estimated_hours') IS NULL OR NOT coalesce((l->>'completed')::boolean,false)))
 ) THEN RAISE EXCEPTION 'PDC_QC_OPERATION_LINES_INCOMPLETE_OR_UNKNOWN' USING errcode='23514';END IF;
 RETURN NEW;
END $gate$;
CREATE TRIGGER pdc_qc_require_all_operations_complete_379 BEFORE UPDATE OF qc_completed_at ON public.vehicles FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_require_all_operations_complete_379();

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_379;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE v jsonb;rows jsonb;
BEGIN
 v:=public.get_pdc_email_vehicle_location_snapshot_pre_379();
 SELECT coalesce(jsonb_agg(vehicle||jsonb_build_object('qc_operation_lines',public.pdc_qc_operation_lines_379((vehicle->>'id')::uuid)) ORDER BY ordinal),'[]'::jsonb) INTO rows
 FROM jsonb_array_elements(v#>'{data,vehicles}') WITH ORDINALITY x(vehicle,ordinal);
 RETURN jsonb_set(v,'{data,vehicles}',rows,false);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260825160000','379_qc_per_operation_completion',array[
 'Stable authenticated/manual line identities with per-line expected version, actor, timestamp, receipt, history and replay',
 'Department work completion derived only when every active line in that stage is complete',
 'QC sign-off trigger rejects any active incomplete operation line; QC and RFT remain separate',
 'Snapshot exposes exact OP number, description, department, hours, source JC and authoritative completion state'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
