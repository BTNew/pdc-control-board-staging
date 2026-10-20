-- r410 (F26): snapshot stage 1 - remove proven-redundant work; output unchanged. Staging cdsmnqxtyyoeoznmbidd only.
-- Measured (SNAPSHOT_PLAN.md): one board snapshot spent ~2.8 s in 21 inner layers and ~3 s in small helpers.
-- (1) pre_734 was byte-for-byte pre_693 (same 13000765 injection, already done, and the same sort): now a pass-through.
-- (2) pre_1020 added lifecycle_history and six first/elapsed keys that pre_ext1300 overwrites for every row from the
--     same function: now a pass-through of pre_82000.
-- (3) pre_739 set pdc_lifecycle for every row; the pilbara layer overwrites it for every row from the same function:
--     dropped from the per-row merge (its appended rows keep it).
-- (4) The pilbara layer looked external completion up again although pdc_lifecycle (the same function of the same id)
--     already carries it: reused (direct lookup kept when the vehicle is missing). 3 lookups per vehicle -> 1.
-- (5) Seven hot LANGUAGE sql helpers with SET search_path (never inlined, planned again on every call) become PL/pgSQL
--     with the same expression, signature, volatility, owner, grants and search_path (the r407 / F21 fix).
-- Not touched: the hard-coded vehicle special cases (13000765 in pre_693, d777b071 in pre_767), every grant, the clock
-- tick, and the old layer chain (kept; pre_693 and pre_82000 unchanged). Board and location snapshot JSON were
-- byte-identical (overall, per department and per vehicle, administrator and operator logins, plus edge fixtures)
-- in the rolled-back tests.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r410: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r410: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r410: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r410: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','f2fdaab192cabddc1415818c2a3b123b'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','9c27e4da08f6ba975d3d15a2768bcc0d'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','532d487eb41805833e31504cd126af4d'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','092301d0e275176b27740b1cc7501972'),
  ('public.pdc_is_pre_delivery_20260910(text)','055281182d5c51f94291a8f5a9826c9f'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','136099468c385ae09aab4e43879cfa9e'),
  ('pdc_work_categories_private.stage(text)','622bea0ee56932c041c057927549c678'),
  ('public.pdc_department138_station_20260917(text)','0109ed60a4ea2feb71835633653640a4'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','87169699a45421aa51b80ed658718e4e'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','848892cd570ddfb6bd787af9f0266c56'),
  ('pdc_bus_private.operation_station(uuid)','a63c9309fd6ae046d37709cfb3666019')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>11 THEN RAISE EXCEPTION 'r410: a function to change is not the expected version'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.pdc_is_pre_delivery_20260910(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.stage(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('public.pdc_department138_station_20260917(text)','{postgres=X/postgres,service_role=X/postgres}truei|search_path=pg_catalog'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','{postgres=X/postgres}falsei|search_path=pg_catalog, public'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','{postgres=X/postgres}falses|search_path=pg_catalog, pdc_parts_private'),
  ('pdc_bus_private.operation_station(uuid)','{postgres=X/postgres}trues|search_path=pg_catalog')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>11 THEN RAISE EXCEPTION 'r410: owner, grants, security, volatility or search_path changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='snapshot_redundant_passes_removed') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r410') THEN RAISE EXCEPTION 'r410: already applied'; END IF;
 IF (SELECT prosrc_md5||release FROM pdc_ops.expected_function_md5 WHERE signature='pdc_bus_private.operation_station(uuid)')<>'a63c9309fd6ae046d37709cfb3666019r407' THEN RAISE EXCEPTION 'r410: operation_station pin is not r407'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_734()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 -- r410 (F26): pass-through. Its body was byte-for-byte pre_693's: the same hard-coded 13000765 injection (which pre_693 has
 -- already done, so NOT EXISTS always skipped it) and the same coalesce(stock_number,id) sort. Kept as a
 -- pass-through so the call chain and grants stay as they are. Old body: r410 down migration.
 RETURN public.get_pdc_email_vehicle_location_snapshot_pre_693();
END
$function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_739()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb; rows jsonb; appended jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_734();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  -- r410 (F26): no pdc_lifecycle in the per-row merge; pre_pilbara_service_v1 sets it for every row
  -- from the same function (the appended rows below keep it).
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true,'evidence',coalesce((SELECT jsonb_build_object('evidence_id',e.evidence_id,'mime_version',e.mime_version,'mime_content_type',e.mime_content_type,'mime_sha256',e.mime_sha256,'photo_receipt_id',e.photo_receipt_id,'photo_bucket_id',e.photo_bucket_id,'photo_storage_path',e.photo_storage_path,'photo_content_type',e.photo_content_type,'photo_byte_length',e.photo_byte_length,'photo_sha256',e.photo_sha256,'intercepted',e.intercepted) FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.notification_id=o.notification_id),'{}'::jsonb)) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=(x->>'id')::uuid ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=(x->>'id')::uuid),'{}'::jsonb)) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'rft_transport_booked_at',v.rft_transport_booked_at,'rft_transport_booked_by',v.rft_transport_booked_by,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'salesperson_id',v.salesperson_id,'salesperson_reference',sp->>'salesperson_name','salesperson_code',sp->>'salesperson_code','salesperson_name',sp->>'salesperson_name','salesperson_email',sp->>'salesperson_email','work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id),'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=v.id ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY v.rft_collected_at,v.id),'[]'::jsonb) INTO appended
  FROM public.vehicles v CROSS JOIN LATERAL public.pdc_vehicle_effective_salesperson_json_386(v.id) sp
  WHERE v.deleted_at IS NULL AND v.current_location IN('Collected','Completed') AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q WHERE q.vehicle_id=v.id AND q.action IN('collected','delivered')) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE (x->>'id')=v.id::text);
  rows:=rows||coalesce(appended,'[]'::jsonb);
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_1020()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 -- r410 (F26): pass-through. It added lifecycle_history and six first/elapsed keys from pdc_lifecycle_history_payload_82000
 -- to every row; pre_ext1300 (its only caller) overwrites exactly those keys for every row from the same
 -- function, and sorts by the same key. Pass-through; old body: r410 down migration.
 RETURN public.get_pdc_email_vehicle_location_snapshot_pre_82000();
END
$function$;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE base jsonb; rows jsonb; appended jsonb;
BEGIN
  base:=public.get_pdc_email_vehicle_location_snapshot_pre_ext1300();
  IF NOT coalesce((base->>'ok')::boolean,false) THEN RETURN base; END IF;
  -- r410 (F26): pdc_lifecycle already carries external_completion (the same
  -- pdc_external_completion_json_20260903 of the same id), so it is reused instead of looked up again.
  -- A vehicle missing from public.vehicles gets '{}' with no such key and still uses the direct lookup.
  SELECT coalesce(jsonb_agg(x||jsonb_build_object(
    'pdc_lifecycle',lc.v,
    'external_completion',CASE WHEN lc.v ? 'external_completion' THEN lc.v->'external_completion'
      ELSE public.pdc_external_completion_json_20260903((x->>'id')::uuid) END
  ) ORDER BY coalesce(x->>'stock_number',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(base#>'{data,vehicles}','[]'::jsonb)) x
  CROSS JOIN LATERAL (SELECT public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid) AS v OFFSET 0) lc;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,
    'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,
    'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,
    'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
    'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,
    'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,
    'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,
    'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'delivered_to_dealer_date',v.delivered_to_dealer_date,
    'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id),
    'external_completion',public.pdc_external_completion_json_20260903(v.id),
    'lifecycle_history',public.pdc_lifecycle_history_payload_82000(v.id)
  ) ORDER BY r.completed_at,r.vehicle_id),'[]'::jsonb) INTO appended
  FROM public.pdc_external_completion_receipts_20260903 r JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='completed' AND v.current_location='Completed'
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE x->>'id'=v.id::text);
  RETURN jsonb_set(base,'{data,vehicles}',rows||appended,true);
END $function$;

CREATE OR REPLACE FUNCTION public.pdc_is_pre_delivery_20260910(p_description text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same expression, same result.
 RETURN (
 lower(coalesce(p_description,'')) ~ '(^|[^a-z0-9])(pre[[:space:]‐‑–—-]*delivery|pdi)([^a-z0-9]|$)');
END
$function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.import_description_hash_20261017(description text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same expression, same result.
 RETURN (
 md5(upper(regexp_replace(btrim(coalesce(description,'')),'\s+',' ','g'))));
END
$function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.stage(category text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same expression, same result.
 RETURN (
 CASE WHEN category='BUS_PIT' THEN 'PIT_INSPECTION'
 WHEN category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA') THEN 'BUS_4X4' ELSE category END);
END
$function$;

CREATE OR REPLACE FUNCTION public.pdc_department138_station_20260917(p_description text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same expression, same result.
 RETURN (
 pdc_work_categories_private.stage(pdc_work_categories_private.suggest(jsonb_build_object('department','138','description',p_description))));
END
$function$;

CREATE OR REPLACE FUNCTION public.pdc_standard_operation_display_20260910(p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same expression, same result.
 RETURN (
 CASE WHEN lower(coalesce(p_line->>'description','')) ~ '\m(fill[[:space:]]+(with[[:space:]]+)?fuel|full[[:space:]]+tank[[:space:]]+(of[[:space:]]+)?fuel|refuel(ling|ing)?)\M' THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',0.17::numeric,'effective_estimated_hours',0.17::numeric,'estimated_minutes',10,
'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_fuel_10_minutes')
WHEN lower(coalesce(p_line->>'description','')) ~ '\mpit[[:space:]]*(and|&)[[:space:]]*weigh\M' THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',0.17::numeric,'effective_estimated_hours',0.17::numeric,'estimated_minutes',10,
'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_pit_and_weigh_10_minutes')
WHEN public.pdc_is_pre_delivery_20260910(p_line->>'description') THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',1.0,'effective_estimated_hours',1.0,'estimated_hours_source','business_rule_default','hours_provenance','craig_standard_pre_delivery_1_hour')
WHEN lower(coalesce(p_line->>'description','')) ~ '\mtint\M'
AND (p_line->'estimated_hours' IS NULL OR p_line->'estimated_hours'='null'::jsonb OR p_line->'estimated_hours'='0'::jsonb) THEN
p_line||jsonb_build_object('source_estimated_hours',coalesce(p_line->'source_estimated_hours',p_line->'estimated_hours'),
'estimated_hours',1.0,'effective_estimated_hours',1.0,'estimated_hours_source','business_rule_default','hours_provenance','craig_tint_default_1_hour')
ELSE p_line END);
END
$function$;

CREATE OR REPLACE FUNCTION pdc_parts_private.service_scope(raw jsonb, stock text, ro text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'pdc_parts_private'
AS $function$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same expression, same result; no parameter name matches a column.
 RETURN (
 CASE WHEN coalesce(nullif(btrim(raw->>'Company'),''),nullif(btrim(raw->>'company'),'')) IS NULL
 AND coalesce(nullif(btrim(raw->>'Division'),''),nullif(btrim(raw->>'division'),'')) IS NULL
 THEN coalesce((SELECT jsonb_build_object('company',c.company,'division',c.division) FROM pdc_parts_private.owner_scope_confirmations c
 WHERE c.stock_number=btrim(stock) AND c.ro_number=upper(btrim(ro))),'{"company":"","division":""}'::jsonb)
 ELSE jsonb_build_object('company',coalesce(nullif(btrim(raw->>'Company'),''),raw->>'company',''),
 'division',coalesce(nullif(btrim(raw->>'Division'),''),raw->>'division','')) END);
END
$function$;

CREATE OR REPLACE FUNCTION pdc_bus_private.operation_station(p_operation_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same query; LIMIT 1 keeps the SQL-function rule (first row) and the keys are unique anyway.
 RETURN (
-- r407 (F21): the approved description is looked up once per operation (OFFSET 0 keeps
 -- it a single evaluation) instead of once in the result and again in the routing join.
 -- The joined keys are unique (history pkey operation_id; ai_routing pkey
 -- (department, description_hash)), so at most one row, as before.
 SELECT coalesce(h.stage_code,pdc_work_categories_private.stage(r.category),
  public.pdc_department138_station_20260917(d.description))
 FROM public.pdc_pilbara_service_operations o
 CROSS JOIN LATERAL (
  SELECT coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description) AS description
  OFFSET 0) d
 LEFT JOIN pdc_bus_private.operation_routing_history_20261015 h ON h.operation_id=o.operation_id
 LEFT JOIN pdc_operation_updates_private.ai_routing_20261019 r ON r.department=btrim(o.department)
  AND r.description_hash=pdc_work_categories_private.import_description_hash_20261017(d.description)
 WHERE o.operation_id=p_operation_id
 LIMIT 1);
END
$function$;

DELETE FROM pdc_ops.expected_function_md5 WHERE signature='pdc_bus_private.operation_station(uuid)' AND release='r407';
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
('public.get_pdc_email_vehicle_location_snapshot_pre_734()','2ed0984e0f1a6b6e10ac5601a0014e18','r410','Snapshot layer pre_734: pass-through of pre_693 (r410, F26)'),
('public.get_pdc_email_vehicle_location_snapshot_pre_739()','733c898847d84a79576f028dd9d1fea6','r410','Snapshot layer pre_739: no per-row pdc_lifecycle, set later by the pilbara layer (r410, F26)'),
('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','623b014b00ab74159639ed23f257f607','r410','Snapshot layer pre_1020: pass-through of pre_82000; ext1300 sets the same keys (r410, F26)'),
('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','844c796008c0c49e7328779214eae64f','r410','Snapshot layer pilbara: external_completion reused from pdc_lifecycle (r410, F26)'),
('public.pdc_is_pre_delivery_20260910(text)','e672cbcbdda24268013a30401b68d5b0','r410','Pre-delivery test; PL/pgSQL so the plan is kept (r410, F26)'),
('pdc_work_categories_private.import_description_hash_20261017(text)','2077a9f7f13668245b302b2ae80cb965','r410','Import description hash; PL/pgSQL so the plan is kept (r410, F26)'),
('pdc_work_categories_private.stage(text)','91e0fc2be1c7bb92a8f98d2baa0f0b6e','r410','Work category stage; PL/pgSQL so the plan is kept (r410, F26)'),
('public.pdc_department138_station_20260917(text)','9f1cf3370971e3a77f5335632d4f3f8c','r410','Department 138 station; PL/pgSQL so the plan is kept (r410, F26)'),
('public.pdc_standard_operation_display_20260910(jsonb)','ef6301a91e9fcbb7a663c2319c5bef9d','r410','Standard operation display rules; PL/pgSQL so the plan is kept (r410, F26)'),
('pdc_parts_private.service_scope(jsonb,text,text)','1db89bd7bae513ec6f165dc0b1a87a80','r410','Parts service scope; PL/pgSQL so the plan is kept (r410, F26)'),
('pdc_bus_private.operation_station(uuid)','f7ab4745fb8e97fcd58a209145cfab0f','r410','Operation station; PL/pgSQL so the plan is kept, approved description looked up once (r407/r410, F21/F26)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
('snapshot_redundant_passes_removed','F26','Snapshot stage 1 stays in place: pre_734 and pre_1020 are pass-throughs, pre_739 looks the lifecycle up once (appended rows only), the pilbara layer reuses external_completion from pdc_lifecycle, the seven hot helpers stay PL/pgSQL with their volatility and a fixed search_path (plan kept, not re-planned per call), and the import description hash still equals its inline expression.','WITH p AS (
  SELECT e.sig, e.want_lang, p.oid IS NOT NULL AS present, l.lanname, p.prosrc, p.provolatile::text AS v, e.want_v,
         coalesce(array_to_string(p.proconfig, ''|''), '''') LIKE ''search_path=%'' AS sp
  FROM (VALUES
    (''public.get_pdc_email_vehicle_location_snapshot_pre_734()'',''plpgsql'',''s''),
    (''public.get_pdc_email_vehicle_location_snapshot_pre_739()'',''plpgsql'',''s''),
    (''public.get_pdc_email_vehicle_location_snapshot_pre_1020()'',''plpgsql'',''s''),
    (''public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'',''plpgsql'',''s''),
    (''public.pdc_is_pre_delivery_20260910(text)'',''plpgsql'',''i''),
    (''pdc_work_categories_private.import_description_hash_20261017(text)'',''plpgsql'',''i''),
    (''pdc_work_categories_private.stage(text)'',''plpgsql'',''i''),
    (''public.pdc_department138_station_20260917(text)'',''plpgsql'',''i''),
    (''public.pdc_standard_operation_display_20260910(jsonb)'',''plpgsql'',''i''),
    (''pdc_parts_private.service_scope(jsonb,text,text)'',''plpgsql'',''s''),
    (''pdc_bus_private.operation_station(uuid)'',''plpgsql'',''s'')) e(sig, want_lang, want_v)
  LEFT JOIN pg_catalog.pg_proc p ON p.oid = to_regprocedure(e.sig)
  LEFT JOIN pg_catalog.pg_language l ON l.oid = p.prolang
), s AS (
  SELECT
    count(*) FILTER (WHERE NOT present OR lanname IS DISTINCT FROM want_lang OR v IS DISTINCT FROM want_v OR NOT sp) AS bad_fn,
    bool_and(CASE sig
      WHEN ''public.get_pdc_email_vehicle_location_snapshot_pre_734()'' THEN prosrc LIKE ''%RETURN public.get_pdc_email_vehicle_location_snapshot_pre_693();%'' AND prosrc NOT LIKE ''%jsonb_agg%''
      WHEN ''public.get_pdc_email_vehicle_location_snapshot_pre_1020()'' THEN prosrc LIKE ''%RETURN public.get_pdc_email_vehicle_location_snapshot_pre_82000();%'' AND prosrc NOT LIKE ''%jsonb_agg%''
      WHEN ''public.get_pdc_email_vehicle_location_snapshot_pre_739()'' THEN (length(prosrc) - length(replace(prosrc, ''pdc_rft_transport_lifecycle_state_734('', ''''))) / length(''pdc_rft_transport_lifecycle_state_734('') = 1
      WHEN ''public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()'' THEN prosrc LIKE ''%AS v OFFSET 0) lc%'' AND prosrc LIKE ''%lc.v ? ''''external_completion''''%''
      ELSE true END) AS layers_ok
  FROM p
), eq AS (
  SELECT count(*) AS n,
    count(*) FILTER (WHERE pdc_work_categories_private.import_description_hash_20261017(d.d)
                     IS DISTINCT FROM md5(upper(regexp_replace(btrim(coalesce(d.d, '''')), ''\s+'', '' '', ''g'')))) AS bad
  FROM (SELECT DISTINCT operation_description AS d FROM public.pdc_pilbara_service_operations
        UNION SELECT NULL UNION SELECT '''' UNION SELECT E'' a \t b '') d
)
SELECT s.bad_fn = 0 AND coalesce(s.layers_ok, false) AND eq.bad = 0 AS ok,
  s.bad_fn || '' of 11 r410 functions not PL/pgSQL with their volatility and fixed search_path; snapshot layers ''
  || CASE WHEN coalesce(s.layers_ok, false) THEN ''collapsed (pre_734, pre_1020 pass-through; one lifecycle lookup in pre_739; external_completion reused in the pilbara layer)'' ELSE ''NOT as r410 left them'' END
  || ''; '' || eq.bad || ''/'' || eq.n || '' descriptions hash differently from the inline expression'' AS detail
FROM s, eq',true,198,'r410');

DO $p$ DECLARE r record; BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r410: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r410: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r410: clock tick changed'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','2ed0984e0f1a6b6e10ac5601a0014e18'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','733c898847d84a79576f028dd9d1fea6'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','623b014b00ab74159639ed23f257f607'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','844c796008c0c49e7328779214eae64f'),
  ('public.pdc_is_pre_delivery_20260910(text)','e672cbcbdda24268013a30401b68d5b0'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','2077a9f7f13668245b302b2ae80cb965'),
  ('pdc_work_categories_private.stage(text)','91e0fc2be1c7bb92a8f98d2baa0f0b6e'),
  ('public.pdc_department138_station_20260917(text)','9f1cf3370971e3a77f5335632d4f3f8c'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','ef6301a91e9fcbb7a663c2319c5bef9d'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','1db89bd7bae513ec6f165dc0b1a87a80'),
  ('pdc_bus_private.operation_station(uuid)','f7ab4745fb8e97fcd58a209145cfab0f')) e(sig,m) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig) WHERE md5(p.prosrc)=e.m)<>11 THEN RAISE EXCEPTION 'r410: a function is not the r410 version'; END IF;
 IF (SELECT count(*) FROM (VALUES
  ('public.get_pdc_email_vehicle_location_snapshot_pre_734()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_739()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_1020()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()','{postgres=X/postgres}trues|search_path=pg_catalog, public'),
  ('public.pdc_is_pre_delivery_20260910(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.import_description_hash_20261017(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('pdc_work_categories_private.stage(text)','{postgres=X/postgres}falsei|search_path=pg_catalog'),
  ('public.pdc_department138_station_20260917(text)','{postgres=X/postgres,service_role=X/postgres}truei|search_path=pg_catalog'),
  ('public.pdc_standard_operation_display_20260910(jsonb)','{postgres=X/postgres}falsei|search_path=pg_catalog, public'),
  ('pdc_parts_private.service_scope(jsonb,text,text)','{postgres=X/postgres}falses|search_path=pg_catalog, pdc_parts_private'),
  ('pdc_bus_private.operation_station(uuid)','{postgres=X/postgres}trues|search_path=pg_catalog')) e(sig,a) JOIN pg_proc p ON p.oid=to_regprocedure(e.sig)
  WHERE p.proacl::text||p.prosecdef::text||p.provolatile::text||'|'||array_to_string(p.proconfig,'|')=e.a AND p.proowner='postgres'::regrole)<>11 THEN RAISE EXCEPTION 'r410: owner, grants, security, volatility or search_path changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='snapshot_redundant_passes_removed')<>'e9c666e0e1548ed62c97d964e5fc08fe' THEN RAISE EXCEPTION 'r410: check md5'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 e JOIN pg_proc p ON p.oid=to_regprocedure(e.signature) WHERE e.release='r410' AND md5(p.prosrc)=e.prosrc_md5)<>11 THEN RAISE EXCEPTION 'r410: pins'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='snapshot_redundant_passes_removed') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r410: check not ok: %', r.detail; END IF;
END $p$;
