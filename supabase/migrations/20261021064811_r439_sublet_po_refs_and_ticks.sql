-- r439 (F50, change request; revised by Craig 21 Oct 14:37 AWST via PMB Email): sublet purchase orders on the PDC staging board.
-- Staging cdsmnqxtyyoeoznmbidd only. Sublet contractors come on site, do the job and leave, so sublets are never booked into bays:
-- this release changes NO line's category, bay or booking (the r404 QC-lines function is untouched). It adds: (1) a PO-to-line
-- table filled by an audited PO-only import (import_sublet_pos_439: dry-run preview or apply; rows stock / R/O / line / PO plus
-- the source file hash; skips owner-held, RFT, completed and closed jobs and completed lines; never creates lines); (2) a
-- 'sublet done' tick per GP PO line (r401 pattern, keyed by R/O + Line #, imports never clear it; controllers per the Parts
-- received scope, administrators and fitters; every tick audited); (3) the vehicle Sublet box state: orange while a GP PO line is
-- not ticked, green when all are ticked, unchanged when there is no GP PO; (4) the CW CSV and Excel workbook header contracts
-- accept the seven optional sublet columns (PO # etc.). Report-level Company 01 / Division 1 unchanged. Not touched: the clock
-- tick and helpers, Karratha 135, the row validator, every existing table and row.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r439: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r439: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r439: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r439: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure)<>'97fc4caaf7b462163d35b4a3511bc487' THEN RAISE EXCEPTION 'r439: QC lines function is not the r404 version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)'::regprocedure)<>'d232aef8ffdb0506a6befe125ff1cfe0'
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)') THEN RAISE EXCEPTION 'r439: service manifest is not the expected version'; END IF;
 IF to_regprocedure('public.pdc_workshop_controller_scope_423()') IS NULL OR to_regprocedure('public.pdc_auditor_entity_in_scope(text,text,uuid)') IS NULL
    OR to_regclass('public.pdc_auditor_user_dealer_scopes') IS NULL OR to_regclass('pdc_codex_intake_private.owner_board_visibility_holds_20261019') IS NULL
    OR to_regclass('pdc_parts_private.jobs') IS NULL OR to_regprocedure('public.current_pdc_user_role()') IS NULL
    OR to_regprocedure('public.audit_pdc_event(audit_action,text,uuid,uuid,jsonb,jsonb,jsonb)') IS NULL THEN RAISE EXCEPTION 'r439: a dependency is missing'; END IF;
 IF to_regclass('public.pdc_service_line_po_refs_439') IS NOT NULL OR to_regclass('public.pdc_sublet_line_ticks_439') IS NOT NULL OR to_regclass('public.pdc_sublet_line_tick_history_439') IS NOT NULL OR to_regclass('public.pdc_sublet_po_import_receipts_439') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc WHERE proname IN ('sublet_line_key_439','sublet_po_vehicle_439','sublet_tick_role_439','revolution_service_headers_439','get_pdc_sublet_po_board_439','get_pdc_sublet_lines_439','set_pdc_sublet_line_tick_439','import_sublet_pos_439','pdc_sublet_line_tick_history_append_only_439','sublet_po_override_439','capture_sublet_pos_439','import_service_sublet_pos_439'))
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r439')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sublet_po_category_and_ticks' OR added_in='r439') THEN RAISE EXCEPTION 'r439: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=239) THEN RAISE EXCEPTION 'r439: sort_order 239 taken'; END IF;
END $g$;

CREATE TABLE public.pdc_service_line_po_refs_439(
  vehicle_id uuid NOT NULL,
  line_key text NOT NULL CHECK (length(line_key) BETWEEN 4 AND 200),
  po_number text NOT NULL CHECK (po_number ~ '^GP[0-9]{8}$'),
  ro_number text NOT NULL CHECK (length(ro_number)<=40),
  line_no integer NOT NULL CHECK (line_no BETWEEN 1 AND 9999),
  line_identity text,
  active boolean NOT NULL DEFAULT true,
  first_seen_at timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL,
  first_source_file_sha256 text NOT NULL CHECK (first_source_file_sha256 ~ '^[0-9a-f]{64}$'),
  last_source_file_sha256 text NOT NULL CHECK (last_source_file_sha256 ~ '^[0-9a-f]{64}$'),
  created_by text NOT NULL,
  PRIMARY KEY (vehicle_id, line_key, po_number));
CREATE INDEX pdc_service_line_po_refs_439_vehicle ON public.pdc_service_line_po_refs_439(vehicle_id) WHERE active;

CREATE TABLE public.pdc_sublet_line_ticks_439(
  vehicle_id uuid NOT NULL,
  line_key text NOT NULL CHECK (length(line_key) BETWEEN 4 AND 200),
  line_identity text,
  ticked boolean NOT NULL,
  ticked_by uuid, ticked_by_email text, ticked_role text, ticked_at timestamptz,
  changed_by uuid NOT NULL, changed_by_email text NOT NULL,
  changed_role text NOT NULL CHECK (changed_role IN ('operator','administrator','fitter')),
  version integer NOT NULL CHECK (version>0),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (vehicle_id, line_key),
  CHECK ((ticked AND ticked_by IS NOT NULL AND ticked_at IS NOT NULL AND ticked_role IS NOT NULL)
      OR (NOT ticked AND ticked_by IS NULL AND ticked_at IS NULL AND ticked_role IS NULL)));

CREATE TABLE public.pdc_sublet_line_tick_history_439(
  history_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  line_key text NOT NULL,
  line_identity text,
  actor_id uuid NOT NULL, actor_email text NOT NULL, actor_role text NOT NULL,
  idempotency_key uuid NOT NULL,
  request_sha256 text NOT NULL,
  before_state jsonb, after_state jsonb NOT NULL, response jsonb NOT NULL, reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (actor_id, idempotency_key));
CREATE INDEX pdc_sublet_line_tick_history_439_line ON public.pdc_sublet_line_tick_history_439(vehicle_id, line_key);

CREATE TABLE public.pdc_sublet_po_import_receipts_439(
  receipt_id uuid PRIMARY KEY,
  source_file_sha256 text NOT NULL CHECK (source_file_sha256 ~ '^[0-9a-f]{64}$'),
  request_sha256 text NOT NULL,
  actor text NOT NULL, actor_role text NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (source_file_sha256, request_sha256));

ALTER TABLE public.pdc_service_line_po_refs_439 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_sublet_line_ticks_439 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_sublet_line_tick_history_439 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_sublet_po_import_receipts_439 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_service_line_po_refs_439, public.pdc_sublet_line_ticks_439, public.pdc_sublet_line_tick_history_439,
  public.pdc_sublet_po_import_receipts_439 FROM PUBLIC, anon, authenticated;


CREATE FUNCTION pdc_work_categories_private.sublet_line_key_439(p_line jsonb) RETURNS text
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $f$
BEGIN
 -- r439 (F50): stable identity of a service line for sublet POs and ticks. A Revolution line is its R/O + Line #
 -- ("jc:J139126041:3"), which survives rolling imports and re-created source rows; any other line falls back to its
 -- canonical line identity ("id:source:<uuid>"). NULL when neither is usable (never ticked or matched).
 RETURN CASE
  WHEN upper(btrim(coalesce(p_line->>'job_card_number',''))) ~ '^[A-Z0-9][A-Z0-9/_-]{1,39}$'
   AND btrim(coalesce(p_line->>'original_line_number','')) ~ '^[0-9]{1,4}$'
   AND (btrim(p_line->>'original_line_number'))::integer>0
  THEN 'jc:'||upper(btrim(p_line->>'job_card_number'))||':'||((btrim(p_line->>'original_line_number'))::integer)::text
  WHEN lower(btrim(coalesce(p_line->>'line_identity',''))) ~ '^(source|manual):[0-9a-f-]{36}$'
  THEN 'id:'||lower(btrim(p_line->>'line_identity'))
  ELSE NULL END;
END
$f$;
CREATE FUNCTION pdc_codex_intake_private.revolution_service_headers_439(p_headers jsonb, p_base jsonb) RETURNS boolean
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $f$
DECLARE n integer; v_extra text[]; 
BEGIN
 -- r439 (F50): a Revolution service header list is the exact base list, in order, optionally followed by any of the
 -- seven sublet columns (each at most once, any order). Nothing else is accepted: no missing, renamed, reordered or
 -- unknown column. The per-line Company / Division sublet columns are evidence only; the report-level Company 01 /
 -- Division 1 checks are unchanged.
 IF jsonb_typeof(p_headers) IS DISTINCT FROM 'array' OR jsonb_typeof(p_base) IS DISTINCT FROM 'array' THEN RETURN false; END IF;
 n:=jsonb_array_length(p_base);
 IF n=0 OR jsonb_array_length(p_headers)<n OR jsonb_array_length(p_headers)>n+7 THEN RETURN false; END IF;
 IF (SELECT jsonb_agg(e ORDER BY o) FROM jsonb_array_elements(p_headers) WITH ORDINALITY x(e,o) WHERE o<=n) IS DISTINCT FROM p_base THEN RETURN false; END IF;
 SELECT coalesce(array_agg(CASE WHEN jsonb_typeof(e)='string' THEN e#>>'{}' END),'{}') INTO v_extra FROM jsonb_array_elements(p_headers) WITH ORDINALITY x(e,o) WHERE o>n;
 RETURN NOT EXISTS(SELECT 1 FROM unnest(v_extra) h WHERE h IS NULL
   OR h <> ALL(ARRAY['Company','Description of sublet','Division','Document Line','Job #','PO #','Sublet Line']))
  AND cardinality(v_extra)=(SELECT count(DISTINCT h) FROM unnest(v_extra) h);
END
$f$;
CREATE FUNCTION pdc_work_categories_private.sublet_po_vehicle_439(p_vehicle_id uuid) RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $f$
BEGIN
 -- r439 (F50, Craig 14:37 AWST): the lines of one vehicle that carry a GP purchase order, with their POs and 'sublet done'
 -- ticks, and the vehicle's Sublet box state: none (no GP PO line), ordered (orange: a GP PO line not yet ticked) or done
 -- (green: every GP PO line ticked). Read only; lines keep their own category, bay and booking (sublet contractors come on
 -- site and are never booked into bays).
 RETURN (
 WITH l AS MATERIALIZED (
  SELECT x.l, x.ord, pdc_work_categories_private.sublet_line_key_439(x.l) k
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY x(l,ord)
  WHERE coalesce((x.l->>'active')::boolean,true) AND NOT coalesce((x.l->>'rejected')::boolean,false)
 ), j AS (
  SELECT l.*, t.ticked, t.ticked_by_email, t.ticked_role, t.ticked_at, coalesce(t.version,0) version,
   (SELECT jsonb_agg(r.po_number ORDER BY r.po_number) FROM public.pdc_service_line_po_refs_439 r
     WHERE r.vehicle_id=p_vehicle_id AND r.active AND r.line_key=l.k) pos
  FROM l LEFT JOIN public.pdc_sublet_line_ticks_439 t ON t.vehicle_id=p_vehicle_id AND t.line_key=l.k
  WHERE l.k IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=p_vehicle_id AND r.active AND r.line_key=l.k)
 )
 SELECT jsonb_build_object('vehicle_id',p_vehicle_id,
  'total',count(*),'ticked',count(*) FILTER (WHERE coalesce(ticked,false)),'with_po',count(*),
  'state',CASE WHEN count(*)=0 THEN 'none' WHEN bool_and(coalesce(ticked,false)) THEN 'done' ELSE 'ordered' END,
  'lines',coalesce(jsonb_agg(jsonb_build_object('line_key',k,'line_identity',l->>'line_identity','job_card_number',l->>'job_card_number',
    'line_no',l->'original_line_number','operation_no',l->>'operation_no','description',left(coalesce(l->>'description',''),180),
    'category',l->>'stage_code','completed',coalesce((l->>'completed')::boolean,false),
    'po_numbers',coalesce(pos,'[]'::jsonb),'has_po',true,'ticked',coalesce(ticked,false),'ticked_by_email',ticked_by_email,
    'ticked_role',ticked_role,'ticked_at',ticked_at,'version',version,'tickable',true) ORDER BY ord) FILTER (WHERE true),'[]'::jsonb))
 FROM j);
END
$f$;
CREATE FUNCTION pdc_work_categories_private.sublet_tick_role_439(p_vehicle_id uuid) RETURNS text
 LANGUAGE plpgsql STABLE SET search_path=pg_catalog, public AS $f$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_role text; v_dealer text;
 v_n integer; v_actor_dealer text;
BEGIN
 -- r439 (F50): who may tick a Sublet line done on this vehicle: controllers, administrators and fitters; every other role
 -- (sales staff, read-only and import accounts) gets NULL. Controllers follow the Parts received rule (r423/751): a
 -- controller with no dealer-scope row works the shared board; a controller with a scope row only ticks vehicles of
 -- that dealer.
 SELECT r.role::text INTO v_role FROM public.pdc_user_roles r
  WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved'
    AND r.role::text IN ('operator','administrator','fitter') LIMIT 1;
 IF v_actor IS NULL OR v_email='' OR v_role IS NULL OR NOT public.pdc_monitor_staging_guard() THEN RETURN NULL; END IF;
 IF v_role='operator' AND public.pdc_workshop_controller_scope_423() IS NULL THEN
  v_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);
  SELECT count(*),min(s.dealer_code) INTO v_n,v_actor_dealer FROM public.pdc_auditor_user_dealer_scopes s
   WHERE s.auth_user_id=v_actor AND s.normalized_email=v_email AND s.environment='staging' AND s.active;
  IF v_n<>1 OR v_dealer IS NULL OR v_actor_dealer IS DISTINCT FROM v_dealer
     OR NOT coalesce(public.pdc_auditor_entity_in_scope(v_actor_dealer,'vehicle',p_vehicle_id),false) THEN RETURN NULL; END IF;
 END IF;
 RETURN v_role;
END
$f$;
CREATE FUNCTION public.get_pdc_sublet_po_board_439() RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
BEGIN
 -- r439 (F50): Sublet box state for the board, only for vehicles that have a sublet PO or a done tick (every other
 -- vehicle keeps the board's existing Sublet box). Read only; any approved, active PDC user.
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor
    AND lower(r.email)=v_email AND r.active AND r.account_status='approved')
  THEN RAISE EXCEPTION 'PDC_439_UNAUTHORIZED' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('ok',true,'code','sublet_po_board','version','r439','vehicles',coalesce((
  SELECT jsonb_agg(jsonb_build_object('vehicle_id',v.id,'stock_number',v.stock_number,'state',s->>'state',
    'total',(s->>'total')::integer,'ticked',(s->>'ticked')::integer,'with_po',(s->>'with_po')::integer) ORDER BY v.stock_number,v.id)
  FROM public.vehicles v
  CROSS JOIN LATERAL (SELECT pdc_work_categories_private.sublet_po_vehicle_439(v.id) s) x
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='active'
    AND (EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=v.id AND r.active)
      OR EXISTS(SELECT 1 FROM public.pdc_sublet_line_ticks_439 t WHERE t.vehicle_id=v.id))
    AND (s->>'total')::integer>0),'[]'::jsonb));
END
$f$;
CREATE FUNCTION public.get_pdc_sublet_lines_439(p_vehicle_id uuid) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_role text; v_tick_role text;
BEGIN
 -- r439 (F50): the vehicle drop-down's Sublet lines (PO, status, done tick, who/when). Read only; any approved,
 -- active PDC user. can_tick says whether this user may tick on this vehicle (the server checks again on every tick).
 SELECT r.role::text INTO v_role FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
  AND r.active AND r.account_status='approved' LIMIT 1;
 IF v_actor IS NULL OR v_email='' OR v_role IS NULL THEN RAISE EXCEPTION 'PDC_439_UNAUTHORIZED' USING errcode='42501'; END IF;
 IF p_vehicle_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL) THEN
  RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 v_tick_role:=pdc_work_categories_private.sublet_tick_role_439(p_vehicle_id);
 RETURN pdc_work_categories_private.sublet_po_vehicle_439(p_vehicle_id)||jsonb_build_object('ok',true,'code','sublet_po_lines',
  'version','r439','actor_role',v_role,'can_tick',v_tick_role IS NOT NULL AND EXISTS(SELECT 1 FROM public.vehicles v
   WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'));
END
$f$;
CREATE FUNCTION public.set_pdc_sublet_line_tick_439(p_vehicle_id uuid, p_line_key text, p_expected_version integer, p_ticked boolean, p_idempotency_key uuid) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog, public AS $f$
DECLARE v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_key text:=btrim(coalesce(p_line_key,''));
 v_role text;v_vehicle public.vehicles%rowtype;v_l jsonb;v_n integer;v_current public.pdc_sublet_line_ticks_439%rowtype;
 v_after public.pdc_sublet_line_ticks_439%rowtype;v_before jsonb;v_request jsonb;v_sha text;v_prior public.pdc_sublet_line_tick_history_439%rowtype;
 v_response jsonb;v_id uuid;v_state jsonb;
BEGIN
 -- r439 (F50): tick or untick 'sublet done' on one line that carries a GP PO (modelled on the r401 Pit tick). Controllers (within their dealer
 -- scope), administrators and fitters only. Idempotent per actor + key, version-checked, history and audit kept.
 -- The tick lives in its own table keyed by R/O + Line #, so rolling imports never remove it. It changes no vehicle,
 -- work item, booking, location, QC, RFT or notification.
 IF p_vehicle_id IS NULL OR v_key!~'^(jc:[A-Z0-9][A-Z0-9/_-]{1,39}:[0-9]{1,4}|id:(source|manual):[0-9a-f-]{36})$' OR p_expected_version IS NULL
   OR p_expected_version<0 OR p_ticked IS NULL OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'PDC_439_INVALID_INPUT' USING errcode='22023';END IF;
 IF v_actor IS NULL OR v_email='' THEN RAISE EXCEPTION 'PDC_439_UNAUTHORIZED' USING errcode='42501';END IF;
 v_role:=pdc_work_categories_private.sublet_tick_role_439(p_vehicle_id);
 IF v_role IS NULL THEN RAISE EXCEPTION 'PDC_439_UNAUTHORIZED: controllers (in their dealer scope), administrators and fitters only' USING errcode='42501';END IF;
 v_request:=jsonb_build_object('contract','pdc-sublet-line-tick-439','vehicle_id',p_vehicle_id,'line_key',v_key,
  'expected_version',p_expected_version,'ticked',p_ticked,'idempotency_key',p_idempotency_key,'actor_id',v_actor);
 v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-439:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_prior FROM public.pdc_sublet_line_tick_history_439 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_prior.request_sha256<>v_sha THEN RAISE EXCEPTION 'PDC_439_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023';END IF;
  RETURN jsonb_set(v_prior.response,'{replay}','true'::jsonb,false);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-439-line:'||p_vehicle_id::text||':'||v_key,0));
 SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id;
 IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state::text<>'active' THEN RAISE EXCEPTION 'PDC_439_VEHICLE_NOT_ACTIVE' USING errcode='22023';END IF;
 SELECT count(*),min(l::text)::jsonb INTO v_n,v_l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE pdc_work_categories_private.sublet_line_key_439(l)=v_key;
 IF v_n<>1 THEN RAISE EXCEPTION 'PDC_439_LINE_UNKNOWN_OR_AMBIGUOUS' USING errcode='22023';END IF;
 IF NOT coalesce((v_l->>'active')::boolean,true) OR coalesce((v_l->>'rejected')::boolean,false) THEN RAISE EXCEPTION 'PDC_439_LINE_INACTIVE' USING errcode='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=p_vehicle_id AND r.line_key=v_key AND r.active)
 THEN RAISE EXCEPTION 'PDC_439_LINE_HAS_NO_GP_PO' USING errcode='22023';END IF;
 SELECT * INTO v_current FROM public.pdc_sublet_line_ticks_439 WHERE vehicle_id=p_vehicle_id AND line_key=v_key FOR UPDATE;
 IF (FOUND AND v_current.version<>p_expected_version) OR (NOT FOUND AND p_expected_version<>0) THEN RAISE EXCEPTION 'PDC_439_VERSION_CONFLICT' USING errcode='40001';END IF;
 v_before:=CASE WHEN v_current.line_key IS NULL THEN NULL ELSE to_jsonb(v_current) END;
 INSERT INTO public.pdc_sublet_line_ticks_439(vehicle_id,line_key,line_identity,ticked,ticked_by,ticked_by_email,ticked_role,ticked_at,changed_by,changed_by_email,changed_role,version,updated_at)
 VALUES(p_vehicle_id,v_key,v_l->>'line_identity',p_ticked,CASE WHEN p_ticked THEN v_actor END,CASE WHEN p_ticked THEN v_email END,CASE WHEN p_ticked THEN v_role END,
  CASE WHEN p_ticked THEN clock_timestamp() END,v_actor,v_email,v_role,1,clock_timestamp())
 ON CONFLICT(vehicle_id,line_key) DO UPDATE SET line_identity=excluded.line_identity,ticked=excluded.ticked,ticked_by=excluded.ticked_by,
  ticked_by_email=excluded.ticked_by_email,ticked_role=excluded.ticked_role,ticked_at=excluded.ticked_at,changed_by=excluded.changed_by,
  changed_by_email=excluded.changed_by_email,changed_role=excluded.changed_role,version=public.pdc_sublet_line_ticks_439.version+1,updated_at=clock_timestamp()
 WHERE public.pdc_sublet_line_ticks_439.version=p_expected_version
 RETURNING * INTO v_after;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_439_VERSION_CONFLICT' USING errcode='40001';END IF;
 v_state:=pdc_work_categories_private.sublet_po_vehicle_439(p_vehicle_id);
 v_id:=extensions.uuid_generate_v5('43900000-0000-5000-8000-000000000439'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','sublet_line_tick_saved','replay',false,'receipt_id',v_id,'request_sha256',v_sha,'vehicle_id',p_vehicle_id,
  'line_key',v_key,'tick',to_jsonb(v_after),'ticked',p_ticked,'actor_role',v_role,
  'vehicle_state',jsonb_build_object('state',v_state->>'state','total',v_state->'total','ticked',v_state->'ticked','with_po',v_state->'with_po'));
 INSERT INTO public.pdc_sublet_line_tick_history_439(history_id,vehicle_id,line_key,line_identity,actor_id,actor_email,actor_role,idempotency_key,request_sha256,before_state,after_state,response,reason)
 VALUES(v_id,p_vehicle_id,v_key,v_l->>'line_identity',v_actor,v_email,v_role,p_idempotency_key,v_sha,v_before,to_jsonb(v_after),v_response,
  CASE WHEN p_ticked THEN 'Sublet line ticked done' ELSE 'Sublet line unticked' END);
 PERFORM public.audit_pdc_event('update','pdc_sublet_line_ticks_439',NULL,p_vehicle_id,v_before,to_jsonb(v_after),
  jsonb_build_object('action','set_pdc_sublet_line_tick_439','line_key',v_key,'line_identity',v_l->>'line_identity','ticked',p_ticked,'actor_role',v_role,
   'po_numbers',coalesce(v_l->'sublet_po_numbers','[]'::jsonb),'vehicle_state',v_state->>'state','notification_enqueued',false));
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 RETURN v_response;
END
$f$;
CREATE FUNCTION public.import_sublet_pos_439(p_rows jsonb, p_source_file_sha256 text, p_dry_run boolean DEFAULT true) RETURNS jsonb
 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog, public SET statement_timeout='120s' AS $f$
DECLARE
 v_role text:=public.current_pdc_user_role()::text; v_uid uuid:=auth.uid(); v_jwt_role text:=coalesce(auth.jwt()->>'role','');
 v_actor text; v_dry boolean:=coalesce(p_dry_run,true); v_sha text:=lower(btrim(coalesce(p_source_file_sha256,'')));
 v_req text; v_prior public.pdc_sublet_po_import_receipts_439%rowtype; v_now timestamptz:=clock_timestamp();
 r record; v_stock text; v_ro text; v_line_txt text; v_line integer; v_po text; v_status text; v_vid uuid; v_n integer;
 v_ls text; v_l jsonb; v_key text; v_lines jsonb:='{}'::jsonb; v_seen jsonb:='{}'::jsonb; v_out jsonb:='[]'::jsonb;
 v_ins boolean; v_res jsonb; v_jobs integer; v_open integer; v_veh jsonb:='{}'::jsonb;
BEGIN
 -- r439 (F50, Craig 21 Oct 14:37 AWST): PO-only sublet import. Rows [{stock, ro, line, po}] from one source file
 -- (p_source_file_sha256). Records each GP purchase order against an EXISTING open line so the vehicle shows the PO and a
 -- 'sublet done' tick. It never creates vehicles, jobs or lines and never changes a category, bay, booking, location or tick.
 -- Skipped (per-row status): owner-held vehicles, RFT / completed / inactive vehicles, closed jobs, completed, inactive or
 -- job-card-notes lines. 'All' and blank POs are ignored; other non-GP values are reported. Rolling: a PO missing from a later
 -- file is never removed. p_dry_run (default true) previews and writes nothing; an apply is audited and idempotent per
 -- (file hash, request).
 IF v_role IN ('importer','operator','administrator') THEN
  v_actor:=coalesce(auth.jwt()->>'email',v_uid::text);
 ELSIF v_uid IS NULL AND (v_jwt_role='service_role' OR session_user IN ('postgres','supabase_admin')) THEN
  v_actor:='service:'||CASE WHEN v_jwt_role='service_role' THEN 'service_role' ELSE session_user::text END; v_role:='service';
 ELSE RAISE EXCEPTION 'PDC_439_IMPORT_FORBIDDEN: importer, controller or administrator access is required' USING errcode='42501';
 END IF;
 IF v_sha !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'PDC_439_SOURCE_FILE_SHA256_REQUIRED' USING errcode='22023'; END IF;
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows)=0 OR jsonb_array_length(p_rows)>30000 THEN
  RAISE EXCEPTION 'PDC_439_ROWS_MUST_BE_A_NON_EMPTY_ARRAY_OF_AT_MOST_30000' USING errcode='22023'; END IF;
 v_req:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-sublet-po-import-439','sha',v_sha,'rows',p_rows)::text,'UTF8'),'sha256'),'hex');
 IF NOT v_dry THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-sublet-po-import-439:'||v_sha,0));
  SELECT * INTO v_prior FROM public.pdc_sublet_po_import_receipts_439 WHERE source_file_sha256=v_sha AND request_sha256=v_req;
  IF FOUND THEN RETURN jsonb_set(v_prior.response,'{replay}','true'::jsonb,false); END IF;
 END IF;
 FOR r IN SELECT x.e, x.o FROM jsonb_array_elements(p_rows) WITH ORDINALITY x(e,o) LOOP
  v_status:=NULL; v_vid:=NULL; v_key:=NULL; v_l:=NULL;
  v_stock:=upper(btrim(coalesce(r.e->>'stock',r.e->>'stock_number','')));
  v_ro:=upper(btrim(coalesce(r.e->>'ro',r.e->>'repair_order_number','')));
  v_line_txt:=btrim(coalesce(r.e->>'line',r.e->>'original_line_number',''));
  v_po:=upper(regexp_replace(btrim(coalesce(r.e->>'po','')),'\s+','','g'));
  IF jsonb_typeof(r.e) IS DISTINCT FROM 'object' THEN v_status:='invalid_row';
  ELSIF v_po='' THEN v_status:='ignored_blank_po';
  ELSIF v_po='ALL' THEN v_status:='ignored_all_placeholder';
  ELSIF v_po !~ '^GP[0-9]{8}$' THEN v_status:='held_non_gp_po';
  ELSIF v_stock='' OR length(v_stock)>40 THEN v_status:='invalid_stock';
  ELSIF v_ro !~ '^[A-Z0-9][A-Z0-9/_-]{1,39}$' THEN v_status:='invalid_ro';
  ELSIF v_line_txt !~ '^[0-9]{1,4}$' OR v_line_txt::integer<1 THEN v_status:='invalid_line';
  ELSIF v_seen ? (v_stock||'|'||v_ro||'|'||v_line_txt||'|'||v_po) THEN v_status:='duplicate_in_file';
  END IF;
  IF v_status IS NULL THEN
   v_seen:=v_seen||jsonb_build_object(v_stock||'|'||v_ro||'|'||v_line_txt||'|'||v_po,true);
   v_line:=v_line_txt::integer;
   SELECT count(*),min(v.id::text)::uuid,min(v.lifecycle_state::text) INTO v_n,v_vid,v_ls FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND upper(btrim(v.stock_number))=v_stock;
   IF v_n=0 THEN v_status:='unmatched_stock_not_on_board';
   ELSIF v_n>1 THEN v_status:='held_stock_ambiguous';
   ELSIF EXISTS(SELECT 1 FROM pdc_codex_intake_private.owner_board_visibility_holds_20261019 h WHERE h.vehicle_id=v_vid AND h.released_at IS NULL) THEN v_status:='skipped_owner_hold';
   ELSIF v_ls='rft' THEN v_status:='skipped_vehicle_rft';
   ELSIF v_ls='completed' THEN v_status:='skipped_vehicle_completed';
   ELSIF v_ls IS DISTINCT FROM 'active' THEN v_status:='skipped_vehicle_not_active';
   ELSE
    SELECT count(*),count(*) FILTER (WHERE j.closed_at IS NULL) INTO v_jobs,v_open FROM pdc_parts_private.jobs j
     WHERE j.vehicle_id=v_vid AND upper(btrim(j.ro_number))=v_ro;
    IF v_jobs>0 AND v_open=0 THEN v_status:='skipped_job_closed';
    ELSE
     IF NOT v_lines ? v_vid::text THEN v_lines:=v_lines||jsonb_build_object(v_vid::text,public.pdc_qc_operation_lines_379(v_vid)); END IF;
     SELECT count(*),min(l::text)::jsonb INTO v_n,v_l FROM jsonb_array_elements(v_lines->(v_vid::text)) l
      WHERE upper(btrim(coalesce(l->>'job_card_number','')))=v_ro AND btrim(coalesce(l->>'original_line_number',''))=v_line::text;
     v_key:=pdc_work_categories_private.sublet_line_key_439(v_l);
     IF v_n=0 THEN v_status:='unmatched_line_not_on_job_card';
     ELSIF v_n>1 THEN v_status:='held_line_ambiguous';
     ELSIF NOT coalesce((v_l->>'active')::boolean,true) OR coalesce((v_l->>'rejected')::boolean,false) THEN v_status:='skipped_line_inactive';
     ELSIF coalesce((v_l->>'completed')::boolean,false) THEN v_status:='skipped_line_completed';
     ELSIF upper(btrim(coalesce(v_l->>'stage_code','')))='JOB_CARD_NOTES' THEN v_status:='skipped_notes_line';
     ELSIF v_key IS NULL OR v_key<>'jc:'||v_ro||':'||v_line THEN v_status:='held_line_without_identity';
     ELSIF EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 x WHERE x.vehicle_id=v_vid AND x.line_key=v_key AND x.po_number=v_po) THEN
      v_status:='already_attached';
      IF NOT v_dry THEN
       UPDATE public.pdc_service_line_po_refs_439 SET last_seen_at=v_now,last_source_file_sha256=v_sha,active=true
        WHERE vehicle_id=v_vid AND line_key=v_key AND po_number=v_po;
      END IF;
     ELSE
      v_status:='attached';
      IF NOT v_dry THEN
       INSERT INTO public.pdc_service_line_po_refs_439(vehicle_id,line_key,po_number,ro_number,line_no,line_identity,active,
        first_seen_at,last_seen_at,first_source_file_sha256,last_source_file_sha256,created_by)
       VALUES(v_vid,v_key,v_po,v_ro,v_line,v_l->>'line_identity',true,v_now,v_now,v_sha,v_sha,v_actor)
       ON CONFLICT(vehicle_id,line_key,po_number) DO NOTHING;
      END IF;
     END IF;
    END IF;
   END IF;
  END IF;
  IF v_status IN ('attached','already_attached') THEN
   v_veh:=jsonb_set(v_veh,ARRAY[v_vid::text],to_jsonb(coalesce((v_veh->>(v_vid::text))::integer,0)+1));
  END IF;
  v_out:=v_out||jsonb_build_object('row',r.o,'status',v_status,'stock',nullif(v_stock,''),'ro',nullif(v_ro,''),'line',nullif(v_line_txt,''),
   'po',nullif(left(v_po,40),''),'category',v_l->>'stage_code');
 END LOOP;
 v_res:=jsonb_build_object('ok',true,'contract','pdc-sublet-po-import-439','dry_run',v_dry,'replay',false,'source_file_sha256',v_sha,
  'request_sha256',v_req,'actor_role',v_role,'rows',jsonb_array_length(p_rows),
  'totals',(SELECT jsonb_object_agg(s,n) FROM (SELECT x->>'status' s,count(*) n FROM jsonb_array_elements(v_out) x GROUP BY 1) z),
  'lines_with_po',(SELECT count(DISTINCT (x->>'stock')||'|'||(x->>'ro')||'|'||(x->>'line')) FROM jsonb_array_elements(v_out) x WHERE x->>'status' IN ('attached','already_attached')),
  'vehicles_with_po',(SELECT count(*) FROM jsonb_object_keys(v_veh)),
  'distinct_pos',(SELECT count(DISTINCT x->>'po') FROM jsonb_array_elements(v_out) x WHERE x->>'status' IN ('attached','already_attached')),
  'by_category',coalesce((SELECT jsonb_object_agg(c,n) FROM (SELECT coalesce(x->>'category','?') c,count(*) n FROM jsonb_array_elements(v_out) x WHERE x->>'status' IN ('attached','already_attached') GROUP BY 1) z),'{}'::jsonb),
  'created_vehicles',0,'created_jobs',0,'created_lines',0,'category_changes',0,'booking_changes',0,
  'row_statuses',v_out);
 IF NOT v_dry THEN
  INSERT INTO public.pdc_sublet_po_import_receipts_439(receipt_id,source_file_sha256,request_sha256,actor,actor_role,response)
  VALUES(extensions.uuid_generate_v5('43900000-0000-5000-8000-000000000439'::uuid,'import:'||v_sha||':'||v_req),v_sha,v_req,v_actor,v_role,v_res);
  PERFORM public.audit_pdc_event('update','pdc_service_line_po_refs_439',NULL,NULL,NULL,NULL,
   jsonb_build_object('action','import_sublet_pos_439','source_file_sha256',v_sha,'request_sha256',v_req,'actor',v_actor,'actor_role',v_role,
    'totals',v_res->'totals','lines_with_po',v_res->'lines_with_po','vehicles_with_po',v_res->'vehicles_with_po'));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 END IF;
 RETURN v_res;
END
$f$;
CREATE FUNCTION public.pdc_sublet_line_tick_history_append_only_439() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog, public AS $f$
BEGIN
 RAISE EXCEPTION 'PDC_439_HISTORY_APPEND_ONLY' USING errcode='55000';
END
$f$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.sublet_line_key_439(jsonb), pdc_codex_intake_private.revolution_service_headers_439(jsonb,jsonb), pdc_work_categories_private.sublet_po_vehicle_439(uuid), pdc_work_categories_private.sublet_tick_role_439(uuid), public.pdc_sublet_line_tick_history_append_only_439() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_pdc_sublet_po_board_439(), public.get_pdc_sublet_lines_439(uuid), public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid), public.import_sublet_pos_439(jsonb,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_sublet_po_board_439(), public.get_pdc_sublet_lines_439(uuid), public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid), public.import_sublet_pos_439(jsonb,text,boolean) TO authenticated, service_role;

CREATE TRIGGER pdc_sublet_line_tick_history_append_only_439 BEFORE DELETE OR UPDATE ON public.pdc_sublet_line_tick_history_439
 FOR EACH ROW EXECUTE FUNCTION public.pdc_sublet_line_tick_history_append_only_439();
CREATE TRIGGER pdc_sublet_line_tick_history_no_truncate_439 BEFORE TRUNCATE ON public.pdc_sublet_line_tick_history_439
 FOR EACH STATEMENT EXECUTE FUNCTION public.pdc_sublet_line_tick_history_append_only_439();

CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_manifest_20261006(p_provenance jsonb, p_message_id text, p_filename text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $f$
 SELECT coalesce(p_provenance->>'authority'='explicit_user_request'
 AND length(p_provenance->>'user_instruction')>20
 AND p_provenance->>'company'='01' AND p_provenance->>'division'='1'
 AND pdc_codex_intake_private.revolution_parts_authenticated_20261006(p_provenance->'authentication',p_message_id)
 AND (
  (p_provenance->>'source_kind'='revolution_automated_service_workbook'
   AND p_provenance->>'subject'='PMG PD Service Complete'
   AND p_filename ~ '^PMG PD Service Complete( - Job 1)?[.]xlsx?$'
   AND p_provenance->>'source_format'='ooxml_workbook')
  OR
  (p_provenance->>'source_kind'='revolution_automated_service_csv'
   AND p_provenance->>'subject'='CW PMB Service Complete'
   AND p_filename='.csv' AND p_provenance->>'source_format'='csv'
   -- r439 (F50): the exact fifteen headers, optionally followed by the seven sublet columns (PO # etc.); nothing else.
   AND pdc_codex_intake_private.revolution_service_headers_439(p_provenance->'source_headers','["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Status","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb)
   AND p_provenance->>'snapshot_basis'='authenticated_revolution_email_date'
   AND p_provenance->>'source_scope_basis'='craig_20261019_fixed_company01_division1'
   AND p_provenance->>'source_snapshot_at'=p_provenance->>'producer_email_date_utc'
   AND p_provenance->>'producer_email_date_utc' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND p_provenance->>'received_at' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
   AND abs(extract(epoch from ((p_provenance->>'received_at')::timestamptz-(p_provenance->>'producer_email_date_utc')::timestamptz)))<=300)
 ),false);
$f$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_work_categories_private.sublet_line_key_439(jsonb)','099708a1aa8f0d76d148152fd2b5f965','r439','r439 (F50): stable line key (R/O + Line #) for sublet POs and ticks'),
 ('pdc_work_categories_private.sublet_po_vehicle_439(uuid)','bf4f60277f69b53cbd982c7aa24b2401','r439','r439 (F50): one vehicle GP PO lines, ticks and Sublet box state'),
 ('pdc_work_categories_private.sublet_tick_role_439(uuid)','b0b6a97bf5642e1ed0796bd37ff01dac','r439','r439 (F50): who may tick sublet done (controller per Parts received scope, admin, fitter)'),
 ('pdc_codex_intake_private.revolution_service_headers_439(jsonb,jsonb)','bfda8a3acd8a08bb36f5851ead2cd5e4','r439','r439 (F50): service header list = exact base + optional 7 sublet columns'),
 ('public.get_pdc_sublet_po_board_439()','7dde7e19d31b269136a93ebecd12217a','r439','r439 (F50): board Sublet box state for vehicles with a GP PO'),
 ('public.get_pdc_sublet_lines_439(uuid)','b211d82171b565ee841c08ae9023c297','r439','r439 (F50): drop-down GP PO lines with a sublet done tick'),
 ('public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)','709b0156a11db82721e6acb40c2c947b','r439','r439 (F50): tick/untick sublet done on a GP PO line (audited, idempotent, versioned)'),
 ('public.import_sublet_pos_439(jsonb,text,boolean)','6cc118c512e103e33bfe94118b91d8a1','r439','r439 (F50): PO-only sublet import (dry run / apply); never creates or recategorises'),
 ('public.pdc_sublet_line_tick_history_append_only_439()','2d7abb89fad05067312e2dfe6bf5320f','r439','r439 (F50): sublet tick history is append-only'),
 ('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','88c75359be6f3e4802c3c1a8f8fd3e10','r439','r439 (F50): CW CSV and workbook header contracts accept the 7 optional sublet columns (was d232aef8ffdb0506a6befe125ff1cfe0)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('sublet_po_category_and_ticks','F50','Sublet POs (r439): no category change (QC lines function is still r404); the four r439 stores have RLS and no app-role access; the PO-only import is importer/controller/admin/service only, writes only PO refs, receipts and audit, skips owner holds and closed jobs, and its dry-run cases hold (All/blank ignored, non-GP held, duplicate, invalid line, unknown stock); tick RPC limited to controllers (Parts received scope), administrators and fitters and writes only its own table plus audit; CW CSV and workbook header contracts = exact base + optional 7 sublet columns; every tick and import audited',
  $chk$WITH src AS (
 SELECT (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)')) tick,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.sublet_tick_role_439(uuid)')) rl,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.import_sublet_pos_439(jsonb,text,boolean)')) imp,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)')) unc,
  (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)')) man
), hdr AS (
 SELECT '["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Status","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb b,
  '["Type","Dept","Stock #","Rego #","Owner Name","Parts Location","Key Tag Number","R/O #","Sub Status","Line #","Operation Desc","Estimated labour hours","Modified Date","Range #"]'::jsonb wb
), dry AS (
 SELECT public.import_sublet_pos_439(jsonb_build_array(
   jsonb_build_object('stock','R439-NO-SUCH-STOCK','ro','J139000439','line',1,'po','GP13900439'),
   jsonb_build_object('stock','R439-NO-SUCH-STOCK','ro','J139000439','line',2,'po','All'),
   jsonb_build_object('stock','R439-NO-SUCH-STOCK','ro','J139000439','line',3,'po',''),
   jsonb_build_object('stock','R439-NO-SUCH-STOCK','ro','J139000439','line',4,'po','XX13900439'),
   jsonb_build_object('stock','R439-NO-SUCH-STOCK','ro','J139000439','line',1,'po','GP13900439'),
   jsonb_build_object('stock','R439-NO-SUCH-STOCK','ro','J139000439','line',0,'po','GP13900440')),
  repeat('0',64),true) r
), w AS (
 SELECT
  (SELECT bool_and(c.relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE,SELECT') AND NOT has_table_privilege('anon',c.oid,'SELECT'))
    FROM pg_catalog.pg_class c WHERE c.oid IN (to_regclass('public.pdc_service_line_po_refs_439'),to_regclass('public.pdc_sublet_line_ticks_439'),
     to_regclass('public.pdc_sublet_line_tick_history_439'),to_regclass('public.pdc_sublet_po_import_receipts_439')))
   AND (SELECT count(*) FROM pg_catalog.pg_class c WHERE c.oid IN (to_regclass('public.pdc_service_line_po_refs_439'),to_regclass('public.pdc_sublet_line_ticks_439'),
     to_regclass('public.pdc_sublet_line_tick_history_439'),to_regclass('public.pdc_sublet_po_import_receipts_439')))=4 AS stores,
  has_function_privilege('authenticated','public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)','EXECUTE')
   AND has_function_privilege('authenticated','public.import_sublet_pos_439(jsonb,text,boolean)','EXECUTE')
   AND has_function_privilege('service_role','public.import_sublet_pos_439(jsonb,text,boolean)','EXECUTE')
   AND NOT has_function_privilege('anon','public.import_sublet_pos_439(jsonb,text,boolean)','EXECUTE')
   AND NOT has_function_privilege('anon','public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)','EXECUTE')
   AND NOT has_function_privilege('anon','public.get_pdc_sublet_po_board_439()','EXECUTE')
   AND NOT has_function_privilege('anon','public.get_pdc_sublet_lines_439(uuid)','EXECUTE')
   AND NOT has_function_privilege('authenticated','pdc_work_categories_private.sublet_tick_role_439(uuid)','EXECUTE') AS grants,
  position($q$r.role::text IN ('operator','administrator','fitter')$q$ in src.rl)>0 AND position('pdc_workshop_controller_scope_423' in src.rl)>0 AND position('pdc_auditor_user_dealer_scopes' in src.rl)>0
   AND src.rl !~ '(salesperson|importer|viewer)' AND position('sublet_tick_role_439' in src.tick)>0
   AND position($q$v_role IN ('importer','operator','administrator')$q$ in src.imp)>0 AS roles,
  position('UPDATE public.vehicles' in src.tick)=0 AND position('vehicle_work_items' in src.tick)=0 AND position('workshop_bookings' in src.tick)=0
   AND position('audit_pdc_event' in src.tick)>0 AS tick_only,
  src.imp !~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.(vehicles|vehicle_work_items|workshop_bookings|pdc_pilbara_service_operations|pdc_sublet_line_ticks_439)\b'
   AND src.imp !~* 'pdc_work_categories_private\.(line_overrides|owner_line_reviews)' AND position('audit_pdc_event' in src.imp)>0
   AND position('owner_board_visibility_holds_20261019' in src.imp)>0 AND position('closed_at IS NULL' in src.imp)>0 AS import_writes_po_only,
  md5(src.unc)='97fc4caaf7b462163d35b4a3511bc487' AS no_category_change,
  position('revolution_service_headers_439' in src.man)>0
   AND pdc_codex_intake_private.revolution_service_headers_439(hdr.b,hdr.b)
   AND pdc_codex_intake_private.revolution_service_headers_439(hdr.b||'["Company","Description of sublet","Division","Document Line","Job #","PO #","Sublet Line"]'::jsonb,hdr.b)
   AND pdc_codex_intake_private.revolution_service_headers_439(hdr.b||'["PO #"]'::jsonb,hdr.b)
   AND pdc_codex_intake_private.revolution_service_headers_439(hdr.wb||'["PO #"]'::jsonb,hdr.wb)
   AND NOT pdc_codex_intake_private.revolution_service_headers_439(hdr.b||'["PO #","Other"]'::jsonb,hdr.b)
   AND NOT pdc_codex_intake_private.revolution_service_headers_439(hdr.b||'["PO #","PO #"]'::jsonb,hdr.b)
   AND NOT pdc_codex_intake_private.revolution_service_headers_439(hdr.b-0,hdr.b)
   AND NOT pdc_codex_intake_private.revolution_service_headers_439(jsonb_build_array(hdr.b->1,hdr.b->0)||(hdr.b-0-0),hdr.b) AS headers,
  dry.r->'totals'='{"unmatched_stock_not_on_board":1,"ignored_all_placeholder":1,"ignored_blank_po":1,"held_non_gp_po":1,"duplicate_in_file":1,"invalid_line":1}'::jsonb
   AND (dry.r->>'dry_run')::boolean AND (dry.r->>'lines_with_po')::int=0 AS importer,
  (SELECT coalesce(sum(t.version),0) FROM public.pdc_sublet_line_ticks_439 t)=(SELECT count(*) FROM public.pdc_sublet_line_tick_history_439) AS audited,
  NOT EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r LEFT JOIN public.vehicles v ON v.id=r.vehicle_id WHERE v.id IS NULL) AS refs_on_vehicles,
  (SELECT count(*) FROM public.pdc_sublet_po_import_receipts_439)<=(SELECT count(*) FROM public.audit_events a WHERE a.table_name='pdc_service_line_po_refs_439') AS imports_audited
 FROM src, hdr, dry
)
SELECT w.stores AND w.grants AND w.roles AND w.tick_only AND w.import_writes_po_only AND w.no_category_change AND w.headers AND w.importer AND w.audited
  AND w.refs_on_vehicles AND w.imports_audited AS ok,
 format('%s GP PO refs on %s vehicles (%s lines); %s ticked of %s tick rows, %s history rows, %s import receipts; stores %s, grants %s, roles %s, tick-only %s, import writes PO refs only %s, no category change %s, header contract %s, importer dry-run cases %s, every tick audited %s, refs on vehicles %s, imports audited %s',
  (SELECT count(*) FROM public.pdc_service_line_po_refs_439 WHERE active),(SELECT count(DISTINCT vehicle_id) FROM public.pdc_service_line_po_refs_439 WHERE active),
  (SELECT count(DISTINCT (vehicle_id,line_key)) FROM public.pdc_service_line_po_refs_439 WHERE active),
  (SELECT count(*) FROM public.pdc_sublet_line_ticks_439 WHERE ticked),(SELECT count(*) FROM public.pdc_sublet_line_ticks_439),
  (SELECT count(*) FROM public.pdc_sublet_line_tick_history_439),(SELECT count(*) FROM public.pdc_sublet_po_import_receipts_439),
  w.stores,w.grants,w.roles,w.tick_only,w.import_writes_po_only,w.no_category_change,w.headers,w.importer,w.audited,w.refs_on_vehicles,w.imports_audited) AS detail
FROM w
$chk$,true,239,'r439');

DO $g$ BEGIN
 IF (SELECT count(*) FROM (VALUES ('pdc_work_categories_private.sublet_line_key_439(jsonb)','099708a1aa8f0d76d148152fd2b5f965'),('pdc_work_categories_private.sublet_po_vehicle_439(uuid)','bf4f60277f69b53cbd982c7aa24b2401'),('pdc_work_categories_private.sublet_tick_role_439(uuid)','b0b6a97bf5642e1ed0796bd37ff01dac'),('pdc_codex_intake_private.revolution_service_headers_439(jsonb,jsonb)','bfda8a3acd8a08bb36f5851ead2cd5e4'),('public.get_pdc_sublet_po_board_439()','7dde7e19d31b269136a93ebecd12217a'),('public.get_pdc_sublet_lines_439(uuid)','b211d82171b565ee841c08ae9023c297'),('public.set_pdc_sublet_line_tick_439(uuid,text,integer,boolean,uuid)','709b0156a11db82721e6acb40c2c947b'),('public.import_sublet_pos_439(jsonb,text,boolean)','6cc118c512e103e33bfe94118b91d8a1'),('public.pdc_sublet_line_tick_history_append_only_439()','2d7abb89fad05067312e2dfe6bf5320f'),('pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)','88c75359be6f3e4802c3c1a8f8fd3e10')) e(s,m)
     JOIN pg_proc p ON p.oid=to_regprocedure(e.s) WHERE md5(p.prosrc)=e.m AND p.proowner::regrole::text='postgres')<>10 THEN RAISE EXCEPTION 'r439: functions did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r439')<>10 THEN RAISE EXCEPTION 'r439: pins not written'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='sublet_po_category_and_ticks' AND added_in='r439')<>'316a5c862f738c9f433ab1840fab1ff9' THEN RAISE EXCEPTION 'r439: check did not land as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure)<>'97fc4caaf7b462163d35b4a3511bc487' THEN RAISE EXCEPTION 'r439: QC lines function changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r439: clock tick changed'; END IF;
END $g$;
