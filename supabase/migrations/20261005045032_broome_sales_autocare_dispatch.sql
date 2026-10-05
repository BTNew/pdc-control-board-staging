-- Sales-only Autocare dispatch tracking. No PDC vehicle, workshop or import mutations.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 IF md5(pg_get_functiondef('public.get_broome_sales_snapshot()'::regprocedure))<>'bfbec1419f6dfa2bc1611fbb4310c822' THEN
  RAISE EXCEPTION 'Sales snapshot wrapper changed; review before replacing it';
 END IF;
END $guard$;

CREATE TABLE pdc_sales_private.autocare_dispatches (
 dealer_code text NOT NULL CHECK(dealer_code='37047'),
 order_key text NOT NULL CHECK(length(order_key) BETWEEN 1 AND 100),
 tracking_id uuid NOT NULL,
 dispatched boolean NOT NULL,
 transport_number text NOT NULL DEFAULT '',
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 dispatched_at timestamptz,
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_by uuid NOT NULL REFERENCES auth.users(id),
 PRIMARY KEY(dealer_code,order_key)
);
ALTER TABLE pdc_sales_private.autocare_dispatches ENABLE ROW LEVEL SECURITY;
CREATE POLICY autocare_dispatches_rpc_only ON pdc_sales_private.autocare_dispatches
 AS RESTRICTIVE FOR ALL TO authenticated USING(false) WITH CHECK(false);
REVOKE ALL ON TABLE pdc_sales_private.autocare_dispatches FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_sales_private.snapshot_with_autocare()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path='pg_catalog','public','pdc_sales_private' AS $fn$
DECLARE base jsonb; items jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 base:=pdc_sales_private.snapshot_with_pmb();
 SELECT coalesce(jsonb_agg(e.item||jsonb_build_object(
  'transport_number',coalesce(nullif(btrim(n.normalized_data->>'navisionTransportLoadNo'),''),
    public.navision_original_column_value(n.normalized_data,'Transport Load No.'),''),
  'autocare_dispatched',coalesce(d.dispatched,false) AND NOT (lower(coalesce(e.item->>'toyota_status','')) ~ 'delivered.*dealer|at dealer'),
  'autocare_dispatch_version',coalesce(d.version,0),'autocare_dispatched_at',d.dispatched_at
 ) ORDER BY e.ord),'[]'::jsonb) INTO items
 FROM jsonb_array_elements(base->'items') WITH ORDINALITY e(item,ord)
 LEFT JOIN public.navision_backend_records n ON n.id=(e.item->>'navision_record_id')::uuid
 LEFT JOIN pdc_sales_private.autocare_dispatches d ON d.dealer_code=e.item->>'dealer_code'
  AND d.order_key=upper(btrim(e.item->>'order'));
 RETURN jsonb_set(base,'{items}',items);
END $fn$;

CREATE FUNCTION pdc_sales_private.set_autocare_dispatch(p_entries jsonb,p_dispatched boolean)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='pg_catalog','public','pdc_sales_private' AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.context(); base jsonb; requested jsonb; target jsonb;
 prior pdc_sales_private.autocare_dispatches; saved pdc_sales_private.autocare_dispatches;
 id uuid; expected integer; order_id text; result jsonb:='[]'::jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 IF p_dispatched IS NULL OR jsonb_typeof(p_entries) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Select vehicles to update'; END IF;
 IF jsonb_array_length(p_entries) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'Select between 1 and 500 vehicles'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_entries) x GROUP BY x->>'tracking_id' HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate vehicle selection'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-autocare-dispatch:'||(ctx->>'dealer_code'),0));
 base:=pdc_sales_private.snapshot_with_autocare();
 FOR requested IN SELECT value FROM jsonb_array_elements(p_entries) LOOP
  IF jsonb_typeof(requested) IS DISTINCT FROM 'object' OR jsonb_typeof(requested->'expected_version') IS DISTINCT FROM 'number'
   OR coalesce(requested->>'expected_version','') !~ '^[0-9]+$' THEN RAISE EXCEPTION 'Vehicle identity and current version required'; END IF;
  id:=(requested->>'tracking_id')::uuid; expected:=(requested->>'expected_version')::integer;
  target:=NULL;SELECT e INTO target FROM jsonb_array_elements(base->'items') e WHERE e->>'tracking_id'=id::text;
  IF target IS NULL OR coalesce((target->>'identity_conflict')::boolean,false) OR nullif(btrim(target->>'order'),'') IS NULL THEN
   RAISE EXCEPTION 'Vehicle is outside your current sales access' USING errcode='42501';
  END IF;
  IF p_dispatched AND lower(coalesce(target->>'toyota_status','')) ~ 'delivered.*dealer|at dealer' THEN
   RAISE EXCEPTION 'A vehicle already delivered to the dealer cannot be marked dispatched';
  END IF;
  order_id:=upper(btrim(target->>'order'));
  SELECT * INTO prior FROM pdc_sales_private.autocare_dispatches WHERE dealer_code=ctx->>'dealer_code' AND order_key=order_id FOR UPDATE;
  -- Identical lost-response retries are safe; other stale changes fail atomically.
  IF prior.order_key IS NOT NULL AND prior.dispatched=p_dispatched AND expected IN(prior.version,prior.version-1) THEN saved:=prior;
  ELSE
   IF expected<>coalesce(prior.version,0) THEN RAISE EXCEPTION 'Dispatch changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
   INSERT INTO pdc_sales_private.autocare_dispatches AS current(dealer_code,order_key,tracking_id,dispatched,transport_number,dispatched_at,updated_by)
   VALUES(ctx->>'dealer_code',order_id,id,p_dispatched,coalesce(target->>'transport_number',''),CASE WHEN p_dispatched THEN clock_timestamp() END,auth.uid())
   ON CONFLICT(dealer_code,order_key) DO UPDATE SET tracking_id=id,dispatched=p_dispatched,transport_number=excluded.transport_number,
    dispatched_at=excluded.dispatched_at,version=current.version+1,updated_at=clock_timestamp(),updated_by=auth.uid()
   WHERE current.version=expected RETURNING * INTO saved;
   IF saved.order_key IS NULL THEN RAISE EXCEPTION 'Dispatch changed elsewhere. Refresh and try again.' USING errcode='40001'; END IF;
   INSERT INTO pdc_sales_private.crm_audit(record_id,kind,actor_id,before_data,after_data)
   VALUES(id,'autocare_dispatch',auth.uid(),CASE WHEN prior.order_key IS NOT NULL THEN to_jsonb(prior) END,to_jsonb(saved));
  END IF;
  result:=result||jsonb_build_array(jsonb_build_object('tracking_id',id,'autocare_dispatched',saved.dispatched,
   'autocare_dispatch_version',saved.version,'autocare_dispatched_at',saved.dispatched_at,'transport_number',coalesce(target->>'transport_number','')));
 END LOOP;
 RETURN jsonb_build_object('items',result);
END $fn$;

CREATE OR REPLACE FUNCTION public.get_broome_sales_snapshot()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='pg_catalog','pdc_sales_private'
AS $fn$ SELECT pdc_sales_private.snapshot_with_autocare(); $fn$;
CREATE FUNCTION public.set_broome_sales_autocare_dispatch(p_entries jsonb,p_dispatched boolean)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path='pg_catalog','pdc_sales_private'
AS $fn$ SELECT pdc_sales_private.set_autocare_dispatch(p_entries,p_dispatched); $fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.snapshot_with_autocare(),pdc_sales_private.set_autocare_dispatch(jsonb,boolean),
 public.set_broome_sales_autocare_dispatch(jsonb,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.snapshot_with_autocare(),pdc_sales_private.set_autocare_dispatch(jsonb,boolean),
 public.set_broome_sales_autocare_dispatch(jsonb,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
