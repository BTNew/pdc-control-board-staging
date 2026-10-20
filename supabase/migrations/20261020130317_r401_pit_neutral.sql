-- r401 Pit and weigh is neutral (Craig, 20 Oct 2026 20:39 AWST). Staging cdsmnqxtyyoeoznmbidd only.
-- Pit and weigh / Pit inspection lines, every vehicle and department, never block anything and can be
-- ticked or unticked by any department that ticks work (operator, administrator, fitter, salesperson).
-- Kept visible; categorisation unchanged; no data deleted. Job-card notes keep r400 behaviour.
-- 1. pdc_line_is_pit_401: one definition of a Pit line (stage PIT_INSPECTION, category BUS_PIT, or old email Pit).
-- 2. pdc_pit_line_ticks_401 (+ append-only history): the tick, with who/when. Kept apart from QC completions so
--    a tick can never re-route the line or touch the QC checklist.
-- 3. set_pdc_pit_line_tick_401 (tick/untick, audited) and get_pdc_pit_line_ticks_401 (read for the board).
-- 4. ensure_required_work_20261019 no longer creates Pit as required work.
-- QC checklist, reject, rework, RFT, Bus guard, bay rules and progress already exclude Pit (r400 and earlier).
DO $g$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r401: staging cdsmnqxtyyoeoznmbidd only'; END IF;
 IF to_regprocedure('public.pdc_line_is_pit_401(uuid,jsonb)') IS NOT NULL OR to_regprocedure('public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)') IS NOT NULL OR to_regprocedure('public.get_pdc_pit_line_ticks_401(uuid[])') IS NOT NULL THEN RAISE EXCEPTION 'r401: already applied'; END IF;
 IF to_regprocedure('public.pdc_qc_line_not_checkable_400(uuid,jsonb)') IS NULL THEN RAISE EXCEPTION 'r401: needs r400'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'761267c9806683eca13e79c531b4334a' THEN RAISE EXCEPTION 'r401: before md5 mismatch'; END IF;
END $g$;

CREATE TABLE IF NOT EXISTS public.pdc_pit_line_ticks_401(
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 line_identity text NOT NULL CHECK (line_identity ~ '^(source|manual):[0-9a-f-]{36}$'),
 source_line_id uuid,
 ticked boolean NOT NULL DEFAULT false,
 ticked_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
 ticked_by_email text,
 ticked_role text,
 ticked_at timestamptz,
 changed_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 changed_by_email text NOT NULL,
 changed_role text NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK (version>0),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY (vehicle_id,line_identity),
 CHECK ((ticked AND ticked_by IS NOT NULL AND ticked_at IS NOT NULL) OR (NOT ticked AND ticked_by IS NULL AND ticked_at IS NULL))
);
COMMENT ON TABLE public.pdc_pit_line_ticks_401 IS 'r401: optional Pit and weigh ticks. Never read by QC, completion, scheduling or dispatch rules.';
CREATE TABLE IF NOT EXISTS public.pdc_pit_line_tick_history_401(
 history_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 line_identity text NOT NULL,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 actor_role text NOT NULL,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK (request_sha256 ~ '^[a-f0-9]{64}$'),
 before_state jsonb,
 after_state jsonb NOT NULL,
 response jsonb NOT NULL,
 reason text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE (actor_id,idempotency_key)
);
CREATE INDEX IF NOT EXISTS pdc_pit_line_tick_history_401_vehicle ON public.pdc_pit_line_tick_history_401(vehicle_id,line_identity,created_at);
ALTER TABLE public.pdc_pit_line_ticks_401 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pit_line_tick_history_401 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_pit_line_ticks_401, public.pdc_pit_line_tick_history_401 FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.pdc_pit_line_tick_history_append_only_401() RETURNS trigger
 LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public'
AS $r401a$
BEGIN
 RAISE EXCEPTION 'PDC_401_HISTORY_APPEND_ONLY' USING errcode='55000';
END
$r401a$;
REVOKE ALL ON FUNCTION public.pdc_pit_line_tick_history_append_only_401() FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS pdc_pit_line_tick_history_append_only_401 ON public.pdc_pit_line_tick_history_401;
CREATE TRIGGER pdc_pit_line_tick_history_append_only_401 BEFORE UPDATE OR DELETE ON public.pdc_pit_line_tick_history_401
 FOR EACH ROW EXECUTE FUNCTION public.pdc_pit_line_tick_history_append_only_401();

CREATE FUNCTION public.pdc_line_is_pit_401(p_vehicle_id uuid, p_line jsonb)
 RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $r401h$
  -- r401: a Pit and weigh / Pit inspection line, in any department. Optional; never blocks anything.
  SELECT upper(btrim(coalesce(p_line->>'stage_code','')))='PIT_INSPECTION'
  OR upper(btrim(coalesce(p_line->>'work_category','')))='BUS_PIT'
  OR EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line->>'line_identity','')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$r401h$;
ALTER FUNCTION public.pdc_line_is_pit_401(uuid,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.pdc_line_is_pit_401(uuid,jsonb) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.set_pdc_pit_line_tick_401(p_vehicle_id uuid, p_line_identity text, p_expected_version integer, p_ticked boolean, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $r401t$
DECLARE v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_line text:=lower(btrim(coalesce(p_line_identity,'')));
 v_role text;v_vehicle public.vehicles%rowtype;v_l jsonb;v_n integer;v_current public.pdc_pit_line_ticks_401%rowtype;
 v_after public.pdc_pit_line_ticks_401%rowtype;v_before jsonb;v_request jsonb;v_sha text;v_prior public.pdc_pit_line_tick_history_401%rowtype;
 v_response jsonb;v_id uuid;v_source_id uuid;
BEGIN
 -- r401 (F10): Pit and weigh is optional. Any department that can tick work may tick or untick it.
 -- The tick lives in its own table, so it never changes the line's category, the QC checklist, a
 -- vehicle, work item, booking, location, RFT or notification. Who/when, history and audit are kept.
 IF p_vehicle_id IS NULL OR v_line!~'^(source|manual):[0-9a-f-]{36}$' OR p_expected_version IS NULL OR p_expected_version<0
   OR p_ticked IS NULL OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'PDC_401_INVALID_INPUT' USING errcode='22023';END IF;
 SELECT r.role::text INTO v_role FROM public.pdc_user_roles r
  WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved'
    AND r.role::text IN ('operator','administrator','fitter','salesperson') LIMIT 1;
 IF v_actor IS NULL OR v_email='' OR v_role IS NULL THEN RAISE EXCEPTION 'PDC_401_UNAUTHORIZED' USING errcode='42501';END IF;
 v_request:=jsonb_build_object('contract','pdc-pit-line-tick-401','vehicle_id',p_vehicle_id,'line_identity',v_line,
  'expected_version',p_expected_version,'ticked',p_ticked,'idempotency_key',p_idempotency_key,'actor_id',v_actor);
 v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-pit-401:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_prior FROM public.pdc_pit_line_tick_history_401 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_prior.request_sha256<>v_sha THEN RAISE EXCEPTION 'PDC_401_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023';END IF;
  RETURN jsonb_set(v_prior.response,'{replay}','true'::jsonb,false);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-pit-401-line:'||p_vehicle_id::text||':'||v_line,0));
 SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id;
 IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL THEN RAISE EXCEPTION 'PDC_401_VEHICLE_NOT_FOUND' USING errcode='22023';END IF;
 SELECT count(*),min(l::text)::jsonb INTO v_n,v_l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l WHERE l->>'line_identity'=v_line;
 IF v_n<>1 THEN RAISE EXCEPTION 'PDC_401_LINE_UNKNOWN_OR_AMBIGUOUS' USING errcode='22023';END IF;
 IF NOT coalesce((v_l->>'active')::boolean,false) THEN RAISE EXCEPTION 'PDC_401_LINE_INACTIVE' USING errcode='22023';END IF;
 IF NOT public.pdc_line_is_pit_401(p_vehicle_id,v_l) THEN RAISE EXCEPTION 'PDC_401_NOT_A_PIT_LINE' USING errcode='22023';END IF;
 v_source_id:=nullif(v_l->>'source_line_id','')::uuid;
 SELECT * INTO v_current FROM public.pdc_pit_line_ticks_401 WHERE vehicle_id=p_vehicle_id AND line_identity=v_line FOR UPDATE;
 IF (FOUND AND v_current.version<>p_expected_version) OR (NOT FOUND AND p_expected_version<>0) THEN RAISE EXCEPTION 'PDC_401_VERSION_CONFLICT' USING errcode='40001';END IF;
 v_before:=CASE WHEN v_current.line_identity IS NULL THEN NULL ELSE to_jsonb(v_current) END;
 INSERT INTO public.pdc_pit_line_ticks_401(vehicle_id,line_identity,source_line_id,ticked,ticked_by,ticked_by_email,ticked_role,ticked_at,changed_by,changed_by_email,changed_role,version,updated_at)
 VALUES(p_vehicle_id,v_line,v_source_id,p_ticked,CASE WHEN p_ticked THEN v_actor END,CASE WHEN p_ticked THEN v_email END,CASE WHEN p_ticked THEN v_role END,CASE WHEN p_ticked THEN clock_timestamp() END,
  v_actor,v_email,v_role,1,clock_timestamp())
 ON CONFLICT(vehicle_id,line_identity) DO UPDATE SET ticked=excluded.ticked,ticked_by=excluded.ticked_by,ticked_by_email=excluded.ticked_by_email,ticked_role=excluded.ticked_role,
  ticked_at=excluded.ticked_at,changed_by=excluded.changed_by,changed_by_email=excluded.changed_by_email,changed_role=excluded.changed_role,
  version=public.pdc_pit_line_ticks_401.version+1,updated_at=clock_timestamp()
 WHERE public.pdc_pit_line_ticks_401.version=p_expected_version
 RETURNING * INTO v_after;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_401_VERSION_CONFLICT' USING errcode='40001';END IF;
 v_id:=extensions.uuid_generate_v5('40100000-0000-5000-8000-000000000401'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','pit_line_tick_saved','replay',false,'receipt_id',v_id,'request_sha256',v_sha,'vehicle_id',p_vehicle_id,
  'tick',to_jsonb(v_after),'ticked',p_ticked,'actor_role',v_role,'blocks_nothing',true);
 INSERT INTO public.pdc_pit_line_tick_history_401(history_id,vehicle_id,line_identity,actor_id,actor_email,actor_role,idempotency_key,request_sha256,before_state,after_state,response,reason)
 VALUES(v_id,p_vehicle_id,v_line,v_actor,v_email,v_role,p_idempotency_key,v_sha,v_before,to_jsonb(v_after),v_response,
  CASE WHEN p_ticked THEN 'Pit and weigh ticked (optional; never blocks)' ELSE 'Pit and weigh unticked (optional; never blocks)' END);
 PERFORM public.audit_pdc_event('update','pdc_pit_line_ticks_401',v_source_id,p_vehicle_id,v_before,to_jsonb(v_after),
  jsonb_build_object('action','set_pdc_pit_line_tick_401','line_identity',v_line,'ticked',p_ticked,'actor_role',v_role,'blocks_nothing',true,'notification_enqueued',false));
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 RETURN v_response;
END
$r401t$;
ALTER FUNCTION public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid) TO authenticated;

CREATE FUNCTION public.get_pdc_pit_line_ticks_401(p_vehicle_ids uuid[] DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $r401r$
DECLARE v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
BEGIN
 -- r401: current Pit and weigh ticks for the board (read-only; any approved PDC user).
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved')
  THEN RAISE EXCEPTION 'PDC_401_UNAUTHORIZED' USING errcode='42501';END IF;
 RETURN jsonb_build_object('ok',true,'code','pit_line_ticks','ticks',coalesce((SELECT jsonb_agg(jsonb_build_object('vehicle_id',t.vehicle_id,'line_identity',t.line_identity,
  'ticked',t.ticked,'ticked_by_email',t.ticked_by_email,'ticked_role',t.ticked_role,'ticked_at',t.ticked_at,'version',t.version) ORDER BY t.vehicle_id,t.line_identity)
  FROM public.pdc_pit_line_ticks_401 t JOIN public.vehicles v ON v.id=t.vehicle_id
  WHERE v.deleted_at IS NULL AND (p_vehicle_ids IS NULL OR t.vehicle_id=ANY(p_vehicle_ids))),'[]'::jsonb));
END
$r401r$;
ALTER FUNCTION public.get_pdc_pit_line_ticks_401(uuid[]) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_pdc_pit_line_ticks_401(uuid[]) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_pit_line_ticks_401(uuid[]) TO authenticated;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $r401e$
DECLARE changed integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'staging_required'; END IF;
 -- Existing deferred mutation paths explicitly reconcile their accepted changes.
 IF current_setting('pdc.defer_workshop_required_work_reconcile',true)='407' THEN RETURN 0; END IF;
 PERFORM 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL
  AND v.lifecycle_state='active' AND v.visible_on_board AND v.qc_completed_at IS NULL
  AND upper(coalesce(v.current_location,'')) NOT IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='approved')
  AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.department IN('138','139')) FOR UPDATE;
 IF NOT FOUND THEN RETURN 0; END IF;
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 SELECT DISTINCT p_vehicle_id,s.work_key,true,false,'Required by canonical imported jobcard work'
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  -- r401: Pit and weigh is never required work (optional, ticked by any department).
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $r401e$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.pdc_line_is_pit_401(uuid,jsonb)','6d071672dd859d7ec3e889ece66624ff','r401','Pit line definition'),
 ('public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)','961830f0c389853706fb7239b7b96dc9','r401','Pit tick by any tick role; own table; touches no vehicle/QC state'),
 ('public.get_pdc_pit_line_ticks_401(uuid[])','2ee29cafcd7b4affaa7929114900c835','r401','Pit ticks read for the board'),
 ('pdc_operation_updates_private.ensure_required_work_20261019(uuid)','4db6302844ef0da651d165a3716bbbac','r401','Pit never required work')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now() WHERE true;
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('pit_lines_neutral_and_tickable','F10','Pit and weigh never on a QC checklist and never required work; any tick role can tick it in its own table; Bus guard, PMB->QC gate and QC trigger ignore it',$c401$WITH qcv AS (
  SELECT v.id FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND upper(btrim(coalesce(v.current_location,'')))='QC'
), pit_on_checklist AS (
  SELECT qcv.id FROM qcv CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(qcv.id)) l
  WHERE public.pdc_line_is_pit_401(qcv.id,l)
), src AS (
  SELECT (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)'::regprocedure) rpc,
         (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure) ens,
         (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure) gate,
         (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure) cats,
         (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.pdc_qc_require_all_operations_complete_379()'::regprocedure) qctrg
), w AS (
  SELECT
   (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid='public.pdc_pit_line_ticks_401'::regclass)
     AND NOT has_table_privilege('authenticated','public.pdc_pit_line_ticks_401','INSERT,UPDATE,DELETE')
     AND NOT has_table_privilege('anon','public.pdc_pit_line_ticks_401','SELECT') AS tick_store,
   has_function_privilege('authenticated','public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)','EXECUTE')
     AND NOT has_function_privilege('anon','public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)','EXECUTE')
     AND position($q$IN ('operator','administrator','fitter','salesperson')$q$ in src.rpc)>0
     AND position('UPDATE public.vehicles' in src.rpc)=0 AND position('vehicle_work_items' in src.rpc)=0
     AND position('pdc_qc_operation_completions_379' in src.rpc)=0 AS any_role_tick,
   position($q$'PIT_INSPECTION'$q$ in src.ens)=0 AS never_required_work,
   position('PITINSPECTION' in src.gate)>0 AND position($q$'PIT_INSPECTION'$q$ in src.gate)>0 AS pmb_to_qc_gate,
   position($q$l->>'stage_code'='BUS_4X4'$q$ in src.cats)>0 AS bus_guard,
   src.qctrg !~* 'pitinspection|PIT_INSPECTION' AS qc_trigger,
   public.pdc_line_is_pit_401(NULL,'{"stage_code":"PIT_INSPECTION"}'::jsonb) AND public.pdc_line_is_pit_401(NULL,'{"work_category":"BUS_PIT"}'::jsonb)
     AND NOT public.pdc_line_is_pit_401(NULL,'{"stage_code":"BUS_4X4","work_category":"BUS_MECHANICAL"}'::jsonb)
     AND public.pdc_qc_line_not_checkable_400(NULL,'{"stage_code":"PIT_INSPECTION"}'::jsonb) AS helper
  FROM src
)
SELECT (SELECT count(*) FROM pit_on_checklist)=0 AND w.tick_store AND w.any_role_tick AND w.never_required_work
   AND w.pmb_to_qc_gate AND w.bus_guard AND w.qc_trigger AND w.helper AS ok,
  format('%s Pit lines on a QC checklist (%s vehicles in QC); own tick store %s, any-role tick %s, never required work %s, PMB->QC gate ignores Pit %s, Bus guard ignores Pit %s, QC trigger ignores Pit %s, helper %s; %s Pit lines ticked',
   (SELECT count(*) FROM pit_on_checklist),(SELECT count(*) FROM qcv),w.tick_store,w.any_role_tick,w.never_required_work,w.pmb_to_qc_gate,w.bus_guard,w.qc_trigger,w.helper,
   (SELECT count(*) FROM public.pdc_pit_line_ticks_401 WHERE ticked)) AS detail
FROM w$c401$,true,180,'r401');

DO $p$
DECLARE want jsonb:='{"public.pdc_line_is_pit_401(uuid,jsonb)": "6d071672dd859d7ec3e889ece66624ff", "public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)": "961830f0c389853706fb7239b7b96dc9", "public.get_pdc_pit_line_ticks_401(uuid[])": "2ee29cafcd7b4affaa7929114900c835", "pdc_operation_updates_private.ensure_required_work_20261019(uuid)": "4db6302844ef0da651d165a3716bbbac"}'::jsonb; k text; r record;
BEGIN
 FOR k IN SELECT jsonb_object_keys(want) LOOP
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=k::regprocedure)<>want->>k THEN RAISE EXCEPTION 'r401: post md5 mismatch %',k; END IF;
 END LOOP;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r401: helper ACL'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r401: tick ACL %',(SELECT proacl::text FROM pg_proc WHERE oid='public.set_pdc_pit_line_tick_401(uuid,text,integer,boolean,uuid)'::regprocedure); END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.get_pdc_pit_line_ticks_401(uuid[])'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r401: read ACL'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='pit_lines_neutral_and_tickable') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r401: new check not ok: %',r.detail; END IF;
END $p$;
