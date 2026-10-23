-- r499 (F112): Sales PMB STATUS station icons. PREPARED ONLY - NOT APPLIED (preview 23 Oct 2026; apply only after Craig approves).
-- Staging cdsmnqxtyyoeoznmbidd only. Craig: show the PMB board station icons (Parts / JITA, Tint, Bus 4x4, Hoist, Fitting, Fab, Elec, Tyre,
--   Sublet) in the Sales PMB STATUS column.
-- Why a new RPC: Sales users (role salesperson / linked controller) cannot read vehicle_work_items, vehicle_parts_updates,
--   workshop_bookings, sublet bookings, QC operation lines or parts flags under RLS, and the Sales snapshot does not carry them.
-- New: pdc_sales_private.pmb_stations_499(uuid[]) - STABLE SECURITY DEFINER, search_path pg_catalog, read-only. Goes through
--   pdc_sales_private.context() (same sign-in / Sales access rules as the Sales snapshot; dealer from context, so it also follows
--   the r495 branch if r495 is applied first). Returns station facts only for current Navision vehicles of that dealer: work items
--   required/completed, latest parts update flags, open workshop bookings (stage + status), open QC line stage codes, sublet booking
--   counts, sublet PO summary and open SUBLET lines without a PO, parts flag colour/label, validated JITA number. No names, customers,
--   notes, sign-off people/dates or prices. Empty array -> empty list; more than 1000 ids -> error 22023.
--   Scope is dealer-wide (a salesperson limited to own vehicles can still ask for any current vehicle id of their dealer; status only).
-- New: public.get_broome_sales_pmb_stations(uuid[]) - invoker wrapper (same pattern as get_broome_sales_snapshot()).
-- Both: EXECUTE for authenticated only (revoked from PUBLIC and anon).
-- Timed read-only on staging (dealer 37047, 40 vehicles): 89 ms.
-- Writes no vehicle, job, booking, Navision, finance or account row. Pins +2 (r499). Check sales_pmb_stations_499 (sort 299, F112).
-- Body is LF only. Undo: supabase/rollbacks/20261023040000_r499_sales_pmb_stations.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r499: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r499: staging only'; END IF;
 PERFORM set_config('pdc.r499_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r499_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r499_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r499_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r499: clock tick does not match its pin (this release must not touch it)'; END IF;
 IF to_regprocedure('pdc_sales_private.pmb_stations_499(uuid[])') IS NOT NULL OR to_regprocedure('public.get_broome_sales_pmb_stations(uuid[])') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r499') OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='sales_pmb_stations_499' OR added_in='r499') THEN RAISE EXCEPTION 'r499: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=299 OR fault_id='F112') THEN RAISE EXCEPTION 'r499: sort_order 299 / F112 taken'; END IF;
 IF to_regprocedure('public.pdc_qc_operation_lines_379(uuid)') IS NULL OR to_regprocedure('public.pdc_parts_flags_vehicle_20260911(uuid)') IS NULL OR to_regprocedure('pdc_work_categories_private.sublet_po_vehicle_439(uuid)') IS NULL OR to_regprocedure('pdc_work_categories_private.sublet_line_key_439(jsonb)') IS NULL OR to_regprocedure('pdc_sales_private.context()') IS NULL THEN RAISE EXCEPTION 'r499: a helper function this release reads is missing'; END IF;
 IF to_regclass('public.pdc_service_line_po_refs_439') IS NULL OR to_regclass('public.pdc_sublet_line_ticks_439') IS NULL
    OR to_regclass('public.pdc_sublet_booking_instances') IS NULL OR to_regclass('public.vehicle_parts_updates') IS NULL OR to_regclass('public.vehicle_work_items') IS NULL THEN RAISE EXCEPTION 'r499: a table this release reads is missing'; END IF;
END $g$;

CREATE FUNCTION pdc_sales_private.pmb_stations_499(p_vehicle_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE ctx jsonb; out jsonb; n integer;
BEGIN
 -- r499 (F112): read-only work-station status for the Sales PMB STATUS column (the board's Parts / JITA, Tint, Bus 4x4, Hoist,
 -- Fitting, Fab, Elec, Tyre and Sublet boxes). One batched call per Sales refresh; the browser draws the boxes with the board's rules.
 -- Returns station facts only (no names, customers, notes, dates of sign-off or prices) for current Navision vehicles of the
 -- caller's Sales dealer (pdc_sales_private.context() decides who may ask and which dealer). Unknown or other-dealer ids are skipped.
 ctx := pdc_sales_private.context();
 IF coalesce(ctx->>'dealer_code','') !~ '^[0-9]{4,6}$' THEN RAISE EXCEPTION 'Sales access required' USING errcode='42501'; END IF;
 n := coalesce(cardinality(p_vehicle_ids),0);
 IF n=0 THEN RETURN jsonb_build_object('ok',true,'version','r499','vehicles','[]'::jsonb); END IF;
 IF n>1000 THEN RAISE EXCEPTION 'Too many vehicles in one request (% > 1000)',n USING errcode='22023'; END IF;
 SELECT (
  WITH ids AS MATERIALIZED (
    SELECT DISTINCT n.canonical_vehicle_id AS vehicle_id
    FROM public.navision_backend_records n
    WHERE n.canonical_vehicle_id = ANY(p_vehicle_ids) AND n.source_system='microsoft_navision'
      AND n.dealer_code=(ctx->>'dealer_code') AND n.is_current AND n.record_status='current'
   ), veh AS MATERIALIZED (
    SELECT v.id, v.stock_number, v.pmb_stage, v.pmb_stoppage_reason,
     (v.pmb_stoppage_started_at IS NOT NULL AND v.pmb_stoppage_cleared_at IS NULL) AS pmb_stopped
    FROM public.vehicles v JOIN ids ON ids.vehicle_id=v.id WHERE v.deleted_at IS NULL
   ), work AS MATERIALIZED (
    SELECT w.vehicle_id, jsonb_object_agg(w.work_key, jsonb_build_object('required',coalesce(w.required,false),'completed',coalesce(w.completed,false))) AS work
    FROM public.vehicle_work_items w JOIN veh ON veh.id=w.vehicle_id GROUP BY w.vehicle_id
   ), parts AS MATERIALIZED (
    SELECT DISTINCT ON (p.vehicle_id) p.vehicle_id, jsonb_build_object('parts_required',p.parts_required,'parts_ordered',coalesce(p.parts_ordered,false),
     'parts_received',p.parts_received,'parts_stoppage',coalesce(p.parts_stoppage,false),'parts_stoppage_reason',coalesce(p.parts_stoppage_reason,'')) AS parts
    FROM public.vehicle_parts_updates p JOIN veh ON veh.id=p.vehicle_id ORDER BY p.vehicle_id, p.updated_at DESC, p.id DESC
   ), bookings AS MATERIALIZED (
    SELECT b.vehicle_id, jsonb_agg(jsonb_build_object('stage_code',s.code,'status',b.status::text,'stoppage_reason',coalesce(b.stoppage_reason,'')) ORDER BY s.code, b.status::text) AS bookings
    FROM public.workshop_bookings b JOIN veh ON veh.id=b.vehicle_id JOIN public.workshop_stages s ON s.id=b.stage_id
    WHERE b.deleted_at IS NULL AND b.status::text IN ('queued','planned','started','stoppage') GROUP BY b.vehicle_id
   ), sublet_bookings AS MATERIALIZED (
    SELECT i.vehicle_id, count(*) FILTER (WHERE i.status='active')::int AS active_bookings, count(*) FILTER (WHERE i.status='returned')::int AS returned_bookings
    FROM public.pdc_sublet_booking_instances i JOIN veh ON veh.id=i.vehicle_id
    WHERE i.status IN ('active','returned') AND i.cancelled_at IS NULL AND i.provider_id IS NOT NULL GROUP BY i.vehicle_id
   ), jita AS MATERIALIZED (
    SELECT veh.id AS vehicle_id, count(n.id) AS match_count,
     bool_or(coalesce((n.normalized_data->>'_navisionJitaNumberColumnPresent')::boolean,false)) AS column_present,
     max(n.normalized_data->>'navisionJitaNumberAuthority') AS authority, max(n.normalized_data->>'jitQty') AS jita_number
    FROM veh LEFT JOIN public.navision_backend_records n ON n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision'
      AND n.canonical_vehicle_id=veh.id AND upper(btrim(coalesce(n.normalized_data->>'stock','')))=upper(btrim(veh.stock_number))
    GROUP BY veh.id
   ), flags AS MATERIALIZED (
    SELECT veh.id AS vehicle_id, public.pdc_parts_flags_vehicle_20260911(veh.id) AS f FROM veh
   ), po_veh AS MATERIALIZED (
    SELECT veh.id FROM veh WHERE EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=veh.id AND r.active)
     OR EXISTS(SELECT 1 FROM public.pdc_sublet_line_ticks_439 t WHERE t.vehicle_id=veh.id)
   ), po AS MATERIALIZED (
    SELECT po_veh.id AS vehicle_id, pdc_work_categories_private.sublet_po_vehicle_439(po_veh.id) AS s FROM po_veh
   ), open_lines AS MATERIALIZED (
    -- Open operation lines (the board's QC projection rules: active, not rejected, not completed). Stage codes only leave this function.
    SELECT veh.id AS vehicle_id, upper(coalesce(x.l->>'stage_code','')) AS stage_code, x.l
    FROM veh CROSS JOIN LATERAL jsonb_array_elements(coalesce(public.pdc_qc_operation_lines_379(veh.id),'[]'::jsonb)) x(l)
    WHERE jsonb_typeof(x.l)='object' AND (x.l->>'active')='true' AND coalesce(x.l->>'rejected','')<>'true' AND coalesce(x.l->>'completed','')<>'true'
   ), stage_codes AS MATERIALIZED (
    SELECT o.vehicle_id, jsonb_agg(DISTINCT o.stage_code) AS codes FROM open_lines o WHERE o.stage_code<>'' GROUP BY o.vehicle_id
   ), lines AS MATERIALIZED (
    SELECT o.vehicle_id, pdc_work_categories_private.sublet_line_key_439(o.l) AS k FROM open_lines o WHERE o.stage_code='SUBLET'
   ), sublet_lines AS MATERIALIZED (
    SELECT lines.vehicle_id, count(*)::int AS open_lines,
     count(*) FILTER (WHERE lines.k IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_service_line_po_refs_439 r WHERE r.vehicle_id=lines.vehicle_id AND r.active AND r.line_key=lines.k))::int AS without_po
    FROM lines GROUP BY lines.vehicle_id
   )
   SELECT coalesce(jsonb_agg(jsonb_build_object(
     'vehicle_id',veh.id,
     'has_stock',btrim(coalesce(veh.stock_number,''))<>'',
     'pmb_stage',coalesce(veh.pmb_stage,''),
     'pmb_stoppage',veh.pmb_stopped,
     'pmb_stoppage_reason',CASE WHEN veh.pmb_stopped THEN coalesce(veh.pmb_stoppage_reason,'') ELSE '' END,
     'work',coalesce(work.work,'{}'::jsonb),
     'parts',coalesce(parts.parts,'{}'::jsonb),
     'bookings',coalesce(bookings.bookings,'[]'::jsonb),
     'qc_open_stage_codes',coalesce(stage_codes.codes,'[]'::jsonb),
     'parts_flags',CASE WHEN flags.f->>'colour' IN ('orange','red','green','grey','review') THEN jsonb_build_object('colour',flags.f->>'colour',
       'label',left(coalesce(flags.f->>'label',''),160),'meaning',left(coalesce(flags.f->>'meaning',''),400),'last_successful_import_at',flags.f->'last_successful_import_at') END,
     'sublet_active_bookings',coalesce(sublet_bookings.active_bookings,0),
     'sublet_returned_bookings',coalesce(sublet_bookings.returned_bookings,0),
     'sublet_open_lines',coalesce(sublet_lines.open_lines,0),
     'sublet_without_po',coalesce(sublet_lines.without_po,0),
     'sublet_po',CASE WHEN coalesce((po.s->>'total')::int,0)>0 THEN jsonb_build_object('state',po.s->>'state','total',(po.s->>'total')::int,
       'ticked',(po.s->>'ticked')::int,'with_po',(po.s->>'with_po')::int) END,
     'jita_number',CASE WHEN jita.match_count=1 AND jita.column_present AND jita.authority='validated-navision-import-v1' THEN nullif(btrim(jita.jita_number),'') END
    ) ORDER BY veh.id),'[]'::jsonb)
   FROM veh
   LEFT JOIN work ON work.vehicle_id=veh.id LEFT JOIN parts ON parts.vehicle_id=veh.id LEFT JOIN bookings ON bookings.vehicle_id=veh.id
   LEFT JOIN sublet_bookings ON sublet_bookings.vehicle_id=veh.id LEFT JOIN jita ON jita.vehicle_id=veh.id
   LEFT JOIN po ON po.vehicle_id=veh.id LEFT JOIN sublet_lines ON sublet_lines.vehicle_id=veh.id
   LEFT JOIN stage_codes ON stage_codes.vehicle_id=veh.id LEFT JOIN flags ON flags.vehicle_id=veh.id
 ) INTO out;
 RETURN jsonb_build_object('ok',true,'version','r499','vehicles',coalesce(out,'[]'::jsonb));
END $function$;

CREATE FUNCTION public.get_broome_sales_pmb_stations(p_vehicle_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$ SELECT pdc_sales_private.pmb_stations_499(p_vehicle_ids) $function$;

REVOKE ALL ON FUNCTION pdc_sales_private.pmb_stations_499(uuid[]), public.get_broome_sales_pmb_stations(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION pdc_sales_private.pmb_stations_499(uuid[]), public.get_broome_sales_pmb_stations(uuid[]) TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at) VALUES
 ('pdc_sales_private.pmb_stations_499(uuid[])','ec5161da807d08c71fe4f59c2cd78c11','r499','r499 (F112): Sales PMB STATUS station icons',now()),
 ('public.get_broome_sales_pmb_stations(uuid[])','cbd4b27bcd6202dc3038dee145d5da00','r499','r499 (F112): Sales PMB STATUS station icons',now());

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('sales_pmb_stations_499','F112','Sales PMB STATUS station icons (r499): read-only station RPC is SECURITY DEFINER with search_path pg_catalog, goes through the Sales check, caps 1000 ids, writes nothing; public wrapper is invoker; both signed-in only (not anon); helper functions present',
  $chk$WITH f AS (
  SELECT p.oid, p.prosecdef, p.provolatile, p.proconfig, p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('pdc_sales_private.pmb_stations_499(uuid[])')
), w AS (
  SELECT p.oid, p.prosecdef, p.prosrc FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.get_broome_sales_pmb_stations(uuid[])')
), s AS (
  SELECT (SELECT prosecdef AND provolatile='s' AND proconfig=ARRAY['search_path=pg_catalog'] FROM f) shape_ok,
   (SELECT position('pdc_sales_private.context()' IN prosrc)>0 AND position('n>1000' IN prosrc)>0
      AND prosrc !~* '\m(insert|update|delete|truncate|perform|execute)\M' FROM f) body_ok,
   (SELECT NOT prosecdef AND position('pdc_sales_private.pmb_stations_499(p_vehicle_ids)' IN prosrc)>0 FROM w) wrapper_ok,
   (SELECT NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE') AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE') FROM f) priv_acl,
   (SELECT NOT pg_catalog.has_function_privilege('anon',oid,'EXECUTE') AND pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE') FROM w) wrap_acl,
   (SELECT pg_catalog.count(*) FROM pg_catalog.unnest(ARRAY['public.pdc_qc_operation_lines_379(uuid)','public.pdc_parts_flags_vehicle_20260911(uuid)',
     'pdc_work_categories_private.sublet_po_vehicle_439(uuid)','pdc_work_categories_private.sublet_line_key_439(jsonb)']) x(sig)
     WHERE pg_catalog.to_regprocedure(x.sig) IS NULL) missing_helpers
)
SELECT coalesce(shape_ok AND body_ok AND wrapper_ok AND priv_acl AND wrap_acl,false) AND missing_helpers=0 AS ok,
 'Sales PMB stations RPC: secdef read-only, search_path pg_catalog: '||CASE WHEN shape_ok AND body_ok THEN 'yes' ELSE 'NO' END
 ||'; Sales check + 1000-id cap: '||CASE WHEN body_ok THEN 'yes' ELSE 'NO' END
 ||'; public wrapper invoker: '||CASE WHEN wrapper_ok THEN 'yes' ELSE 'NO' END
 ||'; signed-in only (not anon): '||CASE WHEN priv_acl AND wrap_acl THEN 'yes' ELSE 'NO' END
 ||'; missing helpers: '||missing_helpers AS detail FROM s$chk$,true,299,'r499');

DO $g$ DECLARE y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_sales_private.pmb_stations_499(uuid[])')) IS DISTINCT FROM 'ec5161da807d08c71fe4f59c2cd78c11' THEN RAISE EXCEPTION 'r499: pdc_sales_private.pmb_stations_499(uuid[]) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_broome_sales_pmb_stations(uuid[])')) IS DISTINCT FROM 'cbd4b27bcd6202dc3038dee145d5da00' THEN RAISE EXCEPTION 'r499: public.get_broome_sales_pmb_stations(uuid[]) did not land as expected (line ends changed in transport?)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r499_tick') THEN RAISE EXCEPTION 'r499: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r499_frc') THEN RAISE EXCEPTION 'r499: fault_regression_check changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r499')<>2 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r499_pins')::int+2 THEN RAISE EXCEPTION 'r499: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='sales_pmb_stations_499' AND added_in='r499' AND sort_order=299) IS DISTINCT FROM 'a882ed7534300b99e3acc71588ec0d76' THEN RAISE EXCEPTION 'r499: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='sales_pmb_stations_499') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r499: check not OK: %',y.detail; END IF;
 PERFORM set_config('search_path','public, extensions',true);
END $g$;
