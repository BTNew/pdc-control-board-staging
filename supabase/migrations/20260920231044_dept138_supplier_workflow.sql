-- Craig approved Bhavesh's Department 138 workflow, 21 September 2026.
-- Add workflow evidence, never infer physical completion or mutate source hours.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'Staging required'; END IF;
END $guard$;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

CREATE SCHEMA pdc_bus_private;
REVOKE ALL ON SCHEMA pdc_bus_private FROM PUBLIC,anon,authenticated;
CREATE TABLE pdc_bus_private.workflow(
 vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id),
 version integer NOT NULL DEFAULT 0 CHECK(version>=0),
 plan jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(plan)='object'),
 updated_at timestamptz NOT NULL DEFAULT now(),
 updated_by uuid REFERENCES auth.users(id)
);
CREATE TABLE pdc_bus_private.supplier(
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id), line_identity text NOT NULL,
 scope_hash text NOT NULL, status text NOT NULL CHECK(status IN('required','ordered','vendor_completed','technician_verified')),
 version integer NOT NULL CHECK(version>0),note text NOT NULL DEFAULT '' CHECK(length(note)<=2000),
 booking_id uuid REFERENCES public.workshop_bookings(id),technician_id uuid REFERENCES public.workshop_technicians(id),
 updated_at timestamptz NOT NULL DEFAULT now(),updated_by uuid NOT NULL REFERENCES auth.users(id),
 PRIMARY KEY(vehicle_id,line_identity)
);
CREATE TABLE pdc_bus_private.receipts(
 actor_id uuid NOT NULL REFERENCES auth.users(id),request_id uuid NOT NULL,
 request_hash text NOT NULL,result jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(actor_id,request_id)
);
CREATE TABLE pdc_bus_private.audit(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),line_identity text,
 action text NOT NULL,old_value jsonb,new_value jsonb,actor_id uuid NOT NULL REFERENCES auth.users(id),
 request_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE pdc_bus_private.workflow ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_bus_private.supplier ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_bus_private.receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_bus_private.audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA pdc_bus_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA pdc_bus_private FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_bus_private.supplier_kind(p_line jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT CASE WHEN btrim(p_line->>'department') IS DISTINCT FROM '138' OR NOT coalesce((p_line->>'active')::boolean,true) THEN NULL
 WHEN coalesce(p_line->>'description','')~* '(beam.*(rust|underbody)|rust.?proof)' AND
  (coalesce(p_line->>'description','')~* '(beam|sublet|external)' OR
   CASE WHEN jsonb_typeof(p_line->'estimated_hours')='number' THEN (p_line->>'estimated_hours')::numeric=0.01 ELSE false END) THEN 'late'
 WHEN coalesce(p_line->>'description','')~* '(\mMMT\M.*seat|byrnecut.*(sign|logo|ribbon)|perth signcraft|\msublet\M|\mSUB\M[[:space:]]*[-:/])' THEN 'early'
 WHEN CASE WHEN jsonb_typeof(p_line->'estimated_hours')='number' THEN (p_line->>'estimated_hours')::numeric=0.01 ELSE false END
  AND coalesce(p_line->>'description','')~* '(seat.?cover|signage|logos?|ribbons?|decals|reflective.*(sign|strip)|window.?tint|tint.*window|flar[e]|hatch.?cover)' THEN 'early'
 ELSE NULL END
$fn$;
CREATE FUNCTION pdc_bus_private.active_vehicle(p_vehicle_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
  AND EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'department'='138' AND coalesce((l->>'active')::boolean,true)))
$fn$;
CREATE FUNCTION pdc_bus_private.scope_hash(p_line jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT md5(jsonb_build_array(p_line->>'line_identity',p_line->>'description',p_line->>'stage_code',
 p_line->'estimated_hours',p_line->>'job_card_number',p_line->>'department')::text)
$fn$;
CREATE FUNCTION pdc_bus_private.catalog_hash(p_vehicle_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT md5(coalesce(jsonb_agg(pdc_bus_private.scope_hash(l) ORDER BY l->>'line_identity'),'[]'::jsonb)::text)
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 WHERE l->>'department'='138' AND coalesce((l->>'active')::boolean,true)
$fn$;
CREATE FUNCTION pdc_bus_private.supplier_lines(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 WITH lines AS(
 SELECT l,pdc_bus_private.supplier_kind(l) phase,pdc_bus_private.scope_hash(l) hash
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 WHERE l->>'department'='138' AND coalesce((l->>'active')::boolean,true)
 ) SELECT coalesce(jsonb_agg(jsonb_build_object(
 'line_identity',l->>'line_identity','scope_hash',hash,'description',l->>'description',
 'department','138','stage_code',l->>'stage_code','job_card_number',l->>'job_card_number',
 'source_hours',l->'source_estimated_hours','saved_hours',l->'estimated_hours','internal_hours',0,
 'supplier_phase',phase,'status',CASE WHEN s.scope_hash=hash THEN s.status ELSE 'required' END,
 'version',coalesce(s.version,0),'scope_changed',s.scope_hash IS NOT NULL AND s.scope_hash<>hash,
 'note',CASE WHEN s.scope_hash=hash THEN s.note ELSE '' END,
 'updated_at',s.updated_at,'technician_id',s.technician_id,'booking_id',s.booking_id
 ) ORDER BY phase,l->>'operation_no',l->>'line_identity'),'[]'::jsonb)
 FROM lines LEFT JOIN pdc_bus_private.supplier s ON s.vehicle_id=p_vehicle_id AND s.line_identity=l->>'line_identity'
 WHERE phase IS NOT NULL
$fn$;
CREATE FUNCTION pdc_bus_private.snapshot(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE plan jsonb; vers integer; h text; ready jsonb; item record;
BEGIN
 IF NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'error','active_department138_required'); END IF;
 SELECT w.plan,w.version INTO plan,vers FROM pdc_bus_private.workflow w WHERE w.vehicle_id=p_vehicle_id;
 plan:=coalesce(plan,'{}'::jsonb); h:=pdc_bus_private.catalog_hash(p_vehicle_id);
 ready:=coalesce(plan->'parts_readiness','{}'::jsonb);
 FOR item IN SELECT * FROM jsonb_each(ready) LOOP
  IF item.value->>'scope_hash' IS DISTINCT FROM h THEN
   ready:=jsonb_set(ready,ARRAY[item.key],item.value||jsonb_build_object('ready',null,'review_required',true));
  END IF;
 END LOOP;
 RETURN jsonb_build_object('current_stage','','next_stage','','waiting_reason','',
 'forecasts','{}'::jsonb,'qa_status','required','pit_status','required','rustproof_status',
 CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(pdc_bus_private.supplier_lines(p_vehicle_id)) x WHERE x->>'supplier_phase'='late') THEN 'required' ELSE 'not_required' END,
 'wash_status','required','rft_status','not_ready','notes','')||plan||
 jsonb_build_object('ok',true,'vehicle_id',p_vehicle_id,'version',coalesce(vers,0),'scope_hash',h,
 'parts_readiness',ready,'supplier_lines',pdc_bus_private.supplier_lines(p_vehicle_id),
 'bookings',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',bay.bay_number,
  'status',b.status,'stage_code',s.code,'start_at',b.scheduled_start_at,'end_at',b.scheduled_end_at,
  'planned_minutes',b.default_duration_minutes,'actual_minutes',b.actual_duration_minutes,
  'technician_name',(SELECT t.name FROM public.workshop_technicians t WHERE t.id=coalesce(
   (SELECT a.technician_id FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY a.assigned_at DESC LIMIT 1),bay.default_technician_id)),
  'technician_id',coalesce((SELECT a.technician_id FROM public.workshop_booking_assignments a
  WHERE a.booking_id=b.id AND a.released_at IS NULL ORDER BY a.assigned_at DESC LIMIT 1),bay.default_technician_id)
 ) ORDER BY b.scheduled_start_at),'[]'::jsonb)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
 WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')),
 'booking_rules',jsonb_build_object('department','138','mechanical_shift','06:00–15:00',
 'electrical_shift','06:00–14:00','weekdays_only',true,'bay3_coaster_allowed',false,
 'buffer_working_days',jsonb_build_array(2,3),'pit_notice_hours',jsonb_build_array(48,72),
 'pit_notice_calendar_confirmed',false,'net_productive_capacity_confirmed',false,
 'no_automatic_reschedule',true));
END $fn$;
CREATE FUNCTION public.get_pdc_bus_workflow(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 RETURN pdc_bus_private.snapshot(p_vehicle_id);
END $fn$;

CREATE FUNCTION public.save_pdc_bus_workflow(p_vehicle_id uuid,p_expected_version integer,p_request_id uuid,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE w pdc_bus_private.workflow; old_plan jsonb; plan jsonb; k text; item record;
 h text; receipt pdc_bus_private.receipts; result jsonb; readonly_keys text[]; value text; date_value timestamptz;
BEGIN
 -- Controller planning is unavailable to the restricted fitter role.
 IF auth.uid() IS NULL OR coalesce(public.current_pdc_user_role()::text,'') NOT IN('operator','administrator')
 THEN RAISE EXCEPTION 'Planner operator required' USING errcode='42501'; END IF;
 IF p_expected_version IS NULL OR p_request_id IS NULL OR jsonb_typeof(p_patch) IS DISTINCT FROM 'object'
 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array('workflow',p_vehicle_id,p_expected_version,p_patch)::text);
 SELECT * INTO receipt FROM pdc_bus_private.receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
  IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
  RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'error','active_department138_required'); END IF;
 SELECT * INTO w FROM pdc_bus_private.workflow WHERE vehicle_id=p_vehicle_id FOR UPDATE;
 IF coalesce(w.version,0)<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','stale_workflow'); END IF;
 old_plan:=coalesce(w.plan,'{}'::jsonb); plan:=old_plan;
 FOR k IN SELECT jsonb_object_keys(p_patch) LOOP
  IF NOT k=ANY(ARRAY['current_stage','next_stage','waiting_reason','forecasts','parts_readiness',
   'qa_status','pit_status','pit_requested_at','pit_booked_at','pit_passed_at','rustproof_status','wash_status','rft_status','notes','downstream_review_acknowledged'])
  THEN RETURN jsonb_build_object('ok',false,'error','unknown_workflow_field','field',k); END IF;
  value:=p_patch->>k;
  IF k='downstream_review_acknowledged' THEN
   IF jsonb_typeof(p_patch->k) IS DISTINCT FROM 'boolean' THEN RETURN jsonb_build_object('ok',false,'error','invalid_review_acknowledgement'); END IF;
   CONTINUE;
  END IF;
  IF k IN('current_stage','next_stage') AND coalesce(value,'')<>'' AND NOT value=ANY(ARRAY[
    'yard','early_sublet','waiting_parts','mechanical','buffer','electrical','qa','pit','rustproof','wash','rft','delivery'])
   THEN RETURN jsonb_build_object('ok',false,'error','invalid_stage'); END IF;
  IF (k='qa_status' AND (value IS NULL OR value NOT IN('required','in_progress','completed')))
   OR (k='pit_status' AND (value IS NULL OR value NOT IN('not_required','required','requested','booked','passed')))
   OR (k='rustproof_status' AND (value IS NULL OR value NOT IN('not_required','required','ordered','vendor_completed')))
   OR (k='wash_status' AND (value IS NULL OR value NOT IN('not_required','required','requested','completed')))
   OR (k='rft_status' AND (value IS NULL OR value NOT IN('not_ready','ready_for_qc_check')))
   THEN RETURN jsonb_build_object('ok',false,'error','invalid_milestone_status','field',k); END IF;
  IF k IN('waiting_reason','notes') AND (jsonb_typeof(p_patch->k) IS DISTINCT FROM 'string' OR length(value)>2000)
   THEN RETURN jsonb_build_object('ok',false,'error','invalid_note'); END IF;
  IF k IN('pit_requested_at','pit_booked_at','pit_passed_at') THEN
   BEGIN date_value:=value::timestamptz; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'error','invalid_date','field',k); END;
  END IF;
  IF k='forecasts' THEN
   IF jsonb_typeof(p_patch->k) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object('ok',false,'error','invalid_forecasts'); END IF;
   FOR item IN SELECT * FROM jsonb_each(p_patch->k) LOOP
    IF item.key NOT IN('mechanical_complete','electrical_complete','vehicle_ready','delivery')
      THEN RETURN jsonb_build_object('ok',false,'error','invalid_forecast_field'); END IF;
    BEGIN date_value:=(item.value#>>'{}')::timestamptz; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('ok',false,'error','invalid_date','field',item.key); END;
   END LOOP;
   plan:=jsonb_set(plan,ARRAY[k],coalesce(plan->k,'{}'::jsonb)||(p_patch->k)); CONTINUE;
  END IF;
  IF k='parts_readiness' THEN
   IF jsonb_typeof(p_patch->k) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object('ok',false,'error','invalid_readiness'); END IF;
   IF NOT plan?k THEN plan:=jsonb_set(plan,ARRAY[k],'{}'::jsonb); END IF;
   FOR item IN SELECT * FROM jsonb_each(p_patch->k) LOOP
    IF item.key NOT IN('mechanical','electrical','accessory') OR jsonb_typeof(item.value) IS DISTINCT FROM 'object'
     OR NOT(item.value?'ready') OR jsonb_typeof(item.value->'ready') NOT IN('boolean','null')
     OR EXISTS(SELECT 1 FROM jsonb_object_keys(item.value) x WHERE x NOT IN('ready','note'))
     OR length(coalesce(item.value->>'note',''))>2000
     OR (item.value->>'ready'='true' AND nullif(btrim(item.value->>'note'),'') IS NULL)
     THEN RETURN jsonb_build_object('ok',false,'error','readiness_evidence_required'); END IF;
    IF (old_plan#>ARRAY[k,item.key])-ARRAY['confirmed_at','confirmed_by','scope_hash'] = item.value
     AND old_plan#>>ARRAY[k,item.key,'scope_hash']=pdc_bus_private.catalog_hash(p_vehicle_id) THEN CONTINUE; END IF;
    plan:=jsonb_set(plan,ARRAY[k,item.key],item.value||jsonb_build_object('confirmed_at',now(),
     'confirmed_by',auth.uid(),'scope_hash',pdc_bus_private.catalog_hash(p_vehicle_id)));
   END LOOP;
   CONTINUE;
  END IF;
  plan:=jsonb_set(plan,ARRAY[k],p_patch->k);
 END LOOP;
 IF coalesce(plan->'forecasts','{}'::jsonb) IS DISTINCT FROM coalesce(old_plan->'forecasts','{}'::jsonb) THEN
  plan:=plan||jsonb_build_object('downstream_review_required',true,'downstream_review_reason','Forecast dates changed. Review electrical, QA, pits, suppliers, wash and delivery arrangements. Existing bookings were not moved.');
 ELSIF p_patch->>'downstream_review_acknowledged'='true' THEN
  plan:=plan||jsonb_build_object('downstream_review_required',false,'downstream_review_reason','','downstream_reviewed_by',auth.uid(),'downstream_reviewed_at',now());
 END IF;
 INSERT INTO pdc_bus_private.workflow(vehicle_id,version,plan,updated_by)
 VALUES(p_vehicle_id,p_expected_version+1,plan,auth.uid())
 ON CONFLICT(vehicle_id) DO UPDATE SET version=excluded.version,plan=excluded.plan,updated_by=excluded.updated_by,updated_at=now();
 INSERT INTO pdc_bus_private.audit(vehicle_id,action,old_value,new_value,actor_id,request_id)
 VALUES(p_vehicle_id,'workflow',old_plan,plan,auth.uid(),p_request_id);
 result:=pdc_bus_private.snapshot(p_vehicle_id);
 INSERT INTO pdc_bus_private.receipts VALUES(auth.uid(),p_request_id,h,result,now());
 RETURN result;
END $fn$;

CREATE FUNCTION public.set_pdc_bus_supplier_status(p_vehicle_id uuid,p_line_identity text,p_scope_hash text,
 p_expected_version integer,p_status text,p_note text,p_request_id uuid,p_booking_id uuid DEFAULT NULL,p_technician_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE s pdc_bus_private.supplier; l jsonb; h text; receipt pdc_bus_private.receipts; result jsonb; role_name text;
BEGIN
 role_name:=public.current_pdc_user_role()::text;
 IF auth.uid() IS NULL OR NOT(coalesce(role_name,'') IN('operator','administrator') OR pdc_fitter_private.authorized_request(true))
 THEN RAISE EXCEPTION 'Workshop operator required' USING errcode='42501'; END IF;
 IF p_request_id IS NULL OR p_expected_version IS NULL OR p_status IS NULL
  OR p_status NOT IN('required','ordered','vendor_completed','technician_verified')
  OR length(coalesce(p_note,''))>2000
 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 IF coalesce(role_name,'') NOT IN('operator','administrator') AND p_status<>'technician_verified'
 THEN RAISE EXCEPTION 'Controller action required' USING errcode='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array('supplier',p_vehicle_id,p_line_identity,p_scope_hash,p_expected_version,p_status,p_note,p_booking_id,p_technician_id)::text);
 SELECT * INTO receipt FROM pdc_bus_private.receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
  IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
  RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',false,'error','active_department138_required'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(pdc_bus_private.supplier_lines(p_vehicle_id)) x WHERE x->>'line_identity'=p_line_identity;
 IF l IS NULL OR l->>'scope_hash' IS DISTINCT FROM p_scope_hash THEN RETURN jsonb_build_object('ok',false,'error','supplier_scope_changed'); END IF;
 SELECT * INTO s FROM pdc_bus_private.supplier WHERE vehicle_id=p_vehicle_id AND line_identity=p_line_identity FOR UPDATE;
 IF coalesce(s.version,0)<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','stale_supplier'); END IF;
 IF p_status='technician_verified' THEN
  IF nullif(btrim(p_note),'') IS NULL OR p_booking_id IS NULL OR p_technician_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages st ON st.id=b.stage_id
   WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status='started'
    AND st.code IN('BUS_4X4','TINT') AND pdc_fitter_private.assigned(b.id,p_technician_id))
  THEN RETURN jsonb_build_object('ok',false,'error','physical_verification_requires_assigned_started_job'); END IF;
 ELSIF p_status IN('ordered','vendor_completed') AND nullif(btrim(p_note),'') IS NULL THEN
  RETURN jsonb_build_object('ok',false,'error','supplier_evidence_required');
 END IF;
 INSERT INTO pdc_bus_private.supplier(vehicle_id,line_identity,scope_hash,status,version,note,booking_id,technician_id,updated_by)
 VALUES(p_vehicle_id,p_line_identity,p_scope_hash,p_status,p_expected_version+1,coalesce(p_note,''),
 CASE WHEN p_status='technician_verified' THEN p_booking_id END,
 CASE WHEN p_status='technician_verified' THEN p_technician_id END,auth.uid())
 ON CONFLICT(vehicle_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,status=excluded.status,
 version=excluded.version,note=excluded.note,booking_id=excluded.booking_id,technician_id=excluded.technician_id,
 updated_by=excluded.updated_by,updated_at=now();
 INSERT INTO pdc_bus_private.audit(vehicle_id,line_identity,action,old_value,new_value,actor_id,request_id)
 VALUES(p_vehicle_id,p_line_identity,'supplier_status',to_jsonb(s),
 jsonb_build_object('status',p_status,'version',p_expected_version+1,'scope_hash',p_scope_hash,'note',p_note,'booking_id',p_booking_id,'technician_id',p_technician_id),auth.uid(),p_request_id);
 result:=pdc_bus_private.snapshot(p_vehicle_id);
 INSERT INTO pdc_bus_private.receipts VALUES(auth.uid(),p_request_id,h,result,now());
 RETURN result;
END $fn$;

-- Public entry points are authenticated RPCs. Private tables/functions have no direct Data API surface.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_bus_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_pdc_bus_workflow(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.save_pdc_bus_workflow(uuid,integer,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.set_pdc_bus_supplier_status(uuid,text,text,integer,text,text,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_bus_workflow(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_pdc_bus_workflow(uuid,integer,uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_pdc_bus_supplier_status(uuid,text,text,integer,text,text,uuid,uuid,uuid) TO authenticated;

-- Authorised technician verification extends the existing deliberately narrow fitter RPC allowlist.
DO $patch$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('pdc_fitter_private.authorized_request(boolean)'::regprocedure);
 IF strpos(d,'''rpc/fitter_job_command''')=0 THEN RAISE EXCEPTION 'Fitter authority changed'; END IF;
 d:=replace(d,'=''rpc/fitter_job_command''',' IN(''rpc/fitter_job_command'',''rpc/set_pdc_bus_supplier_status'')');
 d:=replace(d,'''rpc/get_fitter_refresh'',''rpc/fitter_job_command'')','''rpc/get_fitter_refresh'',''rpc/fitter_job_command'',''rpc/get_pdc_bus_workflow'',''rpc/set_pdc_bus_supplier_status'')');
 EXECUTE d;
END $patch$;

ALTER FUNCTION pdc_fitter_private.lines(uuid,uuid) RENAME TO lines_before_bus_workflow_20260921;
CREATE FUNCTION pdc_fitter_private.lines(p_vehicle_id uuid,p_booking_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 WITH supplier AS MATERIALIZED(SELECT x FROM jsonb_array_elements(pdc_bus_private.supplier_lines(p_vehicle_id)) x)
 SELECT coalesce(jsonb_agg(CASE WHEN s.x IS NULL THEN l ELSE l||jsonb_build_object(
  'supplier_work',s.x,'internal_hours',0,'completed',s.x->>'status'='technician_verified') END ORDER BY ord),'[]'::jsonb)
 FROM jsonb_array_elements(pdc_fitter_private.lines_before_bus_workflow_20260921(p_vehicle_id,p_booking_id)) WITH ORDINALITY rows(l,ord)
 LEFT JOIN supplier s ON s.x->>'line_identity'=l->>'line_identity'
$fn$;
CREATE OR REPLACE FUNCTION pdc_fitter_private.summary(p_lines jsonb,p_stage text)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 WITH lines AS(
 SELECT l,CASE WHEN l->'supplier_work' IS NOT NULL THEN 0
 WHEN jsonb_typeof(l->'hours')='number' THEN (l->>'hours')::numeric END hours
 FROM jsonb_array_elements(p_lines) l WHERE l->>'stage_code'=p_stage
 ),totals AS(
 SELECT count(*) total_lines,count(*) FILTER(WHERE (l->>'completed')::boolean) completed_lines,
 count(*) FILTER(WHERE (hours IS NULL OR hours<=0) AND l->'supplier_work' IS NULL) unknown_hours,
 coalesce(sum(greatest(hours,0)),0) total_hours,
 coalesce(sum(greatest(hours,0)*CASE WHEN (l->>'completed')::boolean THEN 1 ELSE coalesce((l->>'completed_fraction')::numeric,0) END),0) completed_hours
 FROM lines)
 SELECT jsonb_build_object('total_lines',total_lines,'completed_lines',completed_lines,'unknown_hours',unknown_hours,
 'total_hours',total_hours,'completed_hours',completed_hours,
 'percent',CASE WHEN total_lines>0 AND total_lines=completed_lines AND unknown_hours=0 THEN 100
 WHEN total_hours>0 THEN least(99,floor(100*completed_hours/total_hours)) ELSE 0 END,
 'can_complete',total_lines>0 AND total_lines=completed_lines AND unknown_hours=0) FROM totals
$fn$;
DO $patch$
DECLARE d text; needle text;
BEGIN
 d:=pg_get_functiondef('public.get_fitter_job(uuid,uuid)'::regprocedure);
 needle:='''status'',b.status,''stage_code'',code';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Fitter detail anchor changed'; END IF;
 d:=replace(d,needle,'''vehicle_id'',b.vehicle_id,''supplier_lines'',pdc_bus_private.supplier_lines(b.vehicle_id),'||needle);
 EXECUTE d;
 d:=pg_get_functiondef('public.get_fitter_refresh(uuid,uuid,text)'::regprocedure);
 needle:='SELECT md5(jsonb_build_array(p_technician_id,auth.uid(),auth.jwt()->>''session_id'',';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Fitter refresh anchor changed'; END IF;
 d:=replace(d,needle,needle||'(SELECT max(id) FROM pdc_bus_private.audit),');
 EXECUTE d;
 d:=pg_get_functiondef('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure);
 needle:='IF l->''conversion'' IS NOT NULL THEN';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Fitter command anchor changed'; END IF;
 d:=replace(d,needle,'IF l->''supplier_work'' IS NOT NULL THEN RETURN jsonb_build_object(''ok'',false,''error'',''bus_supplier_verification_required''); END IF; '||needle);
 EXECUTE d;
END $patch$;

CREATE FUNCTION pdc_bus_private.completion_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE code text;
BEGIN
 IF NEW.status<>'completed' OR (TG_OP='UPDATE' AND OLD.status='completed') OR NEW.deleted_at IS NOT NULL THEN RETURN NEW; END IF;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=NEW.stage_id;
 IF code IN('BUS_4X4','TINT') AND EXISTS(
 SELECT 1 FROM jsonb_array_elements(pdc_bus_private.supplier_lines(NEW.vehicle_id)) l
 WHERE l->>'stage_code'=code AND l->>'status'<>'technician_verified')
 THEN RAISE EXCEPTION 'bus_supplier_verification_required' USING errcode='23514'; END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER bus_supplier_completion_guard BEFORE INSERT OR UPDATE OF status
 ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION pdc_bus_private.completion_guard();

-- New production allocation requires a controller's physical stage-readiness evidence,
-- independently of imported green flags. Revisions to the approved work invalidate it.
CREATE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid,p_bay_id uuid,p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 IF bay=3 AND (model_name~* 'coaster' OR model_name!~* 'hi[[:space:]-]?ace') THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'required_model','HiAce'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 stage:=CASE WHEN bay BETWEEN 1 AND 4 THEN 'mechanical' WHEN bay IN(8,9) THEN 'electrical' WHEN bay=10 THEN 'accessory' END;
 IF stage IS NULL THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT w.plan#>ARRAY['parts_readiness',stage] INTO ready FROM pdc_bus_private.workflow w WHERE w.vehicle_id=p_vehicle_id;
 IF ready->>'ready' IS DISTINCT FROM 'true' OR ready->>'scope_hash' IS DISTINCT FROM pdc_bus_private.catalog_hash(p_vehicle_id)
 THEN RETURN jsonb_build_object('ok',false,'error','bus_stage_parts_required','workflow_stage',stage); END IF;
 RETURN jsonb_build_object('ok',true);
END $fn$;

-- Shift envelope only; existing break/closure rules still apply. No assumption
-- that every shift minute is productive labour; no existing booking is rewritten.
CREATE FUNCTION pdc_bus_private.minute_available(p_at timestamptz,p_bay_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE bay integer; code text; local_at timestamp; breaks jsonb; closures jsonb;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' THEN RETURN public.workshop_calendar_minute_available(p_at); END IF;
 local_at:=p_at AT TIME ZONE 'Australia/Perth';
 SELECT coalesce(value,'[]'::jsonb) INTO breaks FROM public.workshop_settings WHERE key='break_windows';
 SELECT coalesce(value,'[]'::jsonb) INTO closures FROM public.workshop_settings WHERE key='closures';
 RETURN extract(isodow FROM local_at) BETWEEN 1 AND 5 AND local_at::time>=time '06:00'
 AND local_at::time<CASE WHEN bay IN(8,9) THEN time '14:00' ELSE time '15:00' END
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(closures,'[]'::jsonb)) c WHERE c->>'date'=local_at::date::text)
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(breaks,'[]'::jsonb)) b
 WHERE local_at::time>=(b->>'start')::time AND local_at::time<(b->>'end')::time
 AND ((b?'date' AND b->>'date'=local_at::date::text) OR (NOT(b?'date') AND
 lower(coalesce(b->>'scope',b->>'day','global')) IN('global','working_day',lower(to_char(local_at,'FMDay'))))));
END $fn$;
CREATE FUNCTION pdc_bus_private.add_minutes(p_start timestamptz,p_minutes integer,p_bay_id uuid)
RETURNS timestamptz LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE cursor_at timestamptz:=date_trunc('minute',p_start); remaining integer:=p_minutes; max_at timestamptz:=p_start+interval '366 days';
BEGIN
 IF p_start IS NULL OR p_minutes IS NULL OR p_minutes<0 OR p_minutes>59999 THEN RAISE EXCEPTION 'Invalid duration' USING errcode='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id AND s.code='BUS_4X4')
 THEN RETURN public.workshop_add_operational_minutes(p_start,p_minutes); END IF;
 WHILE remaining>0 AND cursor_at<max_at LOOP
  IF pdc_bus_private.minute_available(cursor_at,p_bay_id) THEN remaining:=remaining-1; END IF;
  cursor_at:=cursor_at+interval '1 minute';
 END LOOP;
 IF remaining>0 THEN RAISE EXCEPTION 'Bus shift duration exceeded calendar guard'; END IF;
 RETURN cursor_at;
END $fn$;
ALTER TABLE public.workshop_bookings ADD COLUMN bus_calendar_version integer CHECK(bus_calendar_version IS NULL OR bus_calendar_version=1);
CREATE FUNCTION pdc_bus_private.booking_shift_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE result jsonb;
BEGIN
 IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN('planned','started','stoppage') OR NEW.bay_id IS NULL
 THEN RETURN NEW; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_stages s WHERE s.id=NEW.stage_id AND s.code='BUS_4X4')
 OR NOT pdc_bus_private.active_vehicle(NEW.vehicle_id) THEN RETURN NEW; END IF;
 -- Starting/stopping unchanged work preserves its original accepted calendar.
 IF TG_OP='UPDATE' AND NEW.vehicle_id=OLD.vehicle_id AND NEW.bay_id IS NOT DISTINCT FROM OLD.bay_id
  AND NEW.scheduled_start_at=OLD.scheduled_start_at AND NEW.scheduled_end_at=OLD.scheduled_end_at
  AND NEW.default_duration_minutes=OLD.default_duration_minutes AND OLD.status IN('planned','started','stoppage')
 THEN NEW.bus_calendar_version:=OLD.bus_calendar_version; RETURN NEW; END IF;
 result:=pdc_bus_private.booking_rule(NEW.vehicle_id,NEW.bay_id,NEW.id);
 IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'Bus workflow: %',result USING errcode='23514'; END IF;
 IF NOT pdc_bus_private.minute_available(NEW.scheduled_start_at,NEW.bay_id)
 THEN RAISE EXCEPTION 'bus_shift_outside_hours' USING errcode='23514'; END IF;
 NEW.scheduled_end_at:=pdc_bus_private.add_minutes(NEW.scheduled_start_at,NEW.default_duration_minutes,NEW.bay_id);
 NEW.bus_calendar_version:=1;
 RETURN NEW;
END $fn$;
CREATE TRIGGER workshop_booking_046a_bus_shift BEFORE INSERT OR UPDATE OF vehicle_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,deleted_at,bus_calendar_version
 ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION pdc_bus_private.booking_shift_guard();

-- Server allocation paths use the scoped calendar; old caller estimates are
-- accepted only if they exactly match the previous canonical calculation.
DO $patch$
DECLARE d text; needle text;
BEGIN
 d:=pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure);
 needle:='v_preserve_historical_calendar boolean:=false;';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Booking validator changed'; END IF;
 d:=replace(d,needle,needle||' v_bus_calendar boolean:=false; v_bus_rule jsonb; v_bus_end timestamptz; v_bus_unchanged boolean:=false;');
 needle:='if not v_active then return jsonb_build_object(''ok'',true); end if;';
 d:=replace(d,needle,needle||'
 v_bus_calendar:=pdc_bus_private.active_vehicle(p_vehicle_id) AND EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id AND s.code=''BUS_4X4'');
 IF v_bus_calendar THEN
  v_bus_unchanged:=EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.bay_id=p_bay_id AND b.deleted_at IS NULL
   AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at AND b.default_duration_minutes=p_duration_minutes AND b.status IN(''planned'',''started'',''stoppage''));
  IF NOT v_bus_unchanged THEN
   v_bus_rule:=pdc_bus_private.booking_rule(p_vehicle_id,p_bay_id,p_booking_id);
   IF v_bus_rule->>''ok'' IS DISTINCT FROM ''true'' THEN RETURN v_bus_rule; END IF;
   IF NOT pdc_bus_private.minute_available(p_scheduled_start_at,p_bay_id) THEN RETURN jsonb_build_object(''ok'',false,''error'',''bus_shift_outside_hours''); END IF;
   v_bus_end:=pdc_bus_private.add_minutes(p_scheduled_start_at,p_duration_minutes,p_bay_id);
   IF p_scheduled_end_at IS DISTINCT FROM v_bus_end AND p_scheduled_end_at IS DISTINCT FROM public.workshop_add_operational_minutes(p_scheduled_start_at,p_duration_minutes)
   THEN RETURN jsonb_build_object(''ok'',false,''error'',''calendar_duration_mismatch''); END IF;
   p_scheduled_end_at:=v_bus_end;
  END IF;
 END IF;');
 d:=replace(d,'if NOT v_preserve_historical_calendar AND not public.workshop_calendar_minute_available',
 'if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND not public.workshop_calendar_minute_available');
 d:=replace(d,'if NOT v_preserve_historical_calendar AND public.workshop_operational_minutes_between',
 'if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND public.workshop_operational_minutes_between');
 d:=replace(d,'then public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) else',
 'then CASE WHEN v_bus_calendar THEN CASE WHEN v_bus_unchanged THEN p_scheduled_end_at ELSE pdc_bus_private.add_minutes(p_scheduled_start_at,v_estimated_duration,p_bay_id) END ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END else');
 EXECUTE d;
END $patch$;

-- Supplier time is projected separately for NEW allocations only. Existing
-- booking capacity/history and every saved source/staff estimate are untouched.
ALTER FUNCTION public.workshop_booking_capacity_duration_minutes(uuid,uuid,uuid,uuid)
 RENAME TO workshop_booking_capacity_duration_before_bus_20260921;
CREATE FUNCTION public.workshop_booking_capacity_duration_minutes(p_booking_id uuid,p_vehicle_id uuid,p_stage_id uuid,p_bay_id uuid)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE quote numeric; supplied numeric; result integer; code text;
BEGIN
 result:=public.workshop_booking_capacity_duration_before_bus_20260921(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id);
 IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE id=p_booking_id) THEN RETURN result; END IF;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=p_stage_id;
 IF code NOT IN('BUS_4X4','TINT') OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN result; END IF;
 SELECT coalesce(sum((l->>'saved_hours')::numeric),0) INTO supplied FROM jsonb_array_elements(pdc_bus_private.supplier_lines(p_vehicle_id)) l
 WHERE l->>'stage_code'=code AND jsonb_typeof(l->'saved_hours')='number';
 IF supplied<=0 THEN RETURN result; END IF;
 quote:=public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,code);
 RETURN public.workshop_capacity_duration_minutes(greatest(1,round(greatest(0,quote-supplied)*60)),p_bay_id);
END $fn$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_bus_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION pdc_fitter_private.lines_before_bus_workflow_20260921(uuid,uuid),pdc_fitter_private.lines(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.workshop_booking_capacity_duration_before_bus_20260921(uuid,uuid,uuid,uuid),public.workshop_booking_capacity_duration_minutes(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';

-- Capture separate internal minutes when a new allocation is explicitly made.
DO $patch$ DECLARE d text; needle text;
BEGIN
 d:=pg_get_functiondef('public.workshop_capture_capacity_basis()'::regprocedure);
 needle:='manual:=public.workshop_capacity_manual_minutes';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Capacity capture changed'; END IF;
 d:=replace(d,needle,'IF TG_OP=''INSERT'' AND pdc_bus_private.active_vehicle(NEW.vehicle_id) THEN
  SELECT greatest(1,quote-coalesce(round(sum((l->>''saved_hours'')::numeric)*60),0)) INTO base
  FROM jsonb_array_elements(pdc_bus_private.supplier_lines(NEW.vehicle_id)) l
  WHERE l->>''stage_code''=(SELECT code FROM public.workshop_stages WHERE id=NEW.stage_id)
  AND jsonb_typeof(l->''saved_hours'')=''number'';
 END IF;
 '||needle);
 EXECUTE d;
END $patch$;

ALTER FUNCTION public.workshop_booking_effective_end_at(uuid) RENAME TO workshop_booking_effective_end_before_bus_20260921;
CREATE FUNCTION public.workshop_booking_effective_end_at(p_booking_id uuid)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT CASE WHEN b.bus_calendar_version=1 AND b.status IN('queued','planned','started','stoppage')
 THEN pdc_bus_private.add_minutes(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id),b.bay_id)
 ELSE public.workshop_booking_effective_end_before_bus_20260921(b.id) END
 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.deleted_at IS NULL
$fn$;
REVOKE ALL ON FUNCTION public.workshop_booking_effective_end_before_bus_20260921(uuid),public.workshop_booking_effective_end_at(uuid) FROM PUBLIC,anon,authenticated,service_role;
