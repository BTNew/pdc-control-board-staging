CREATE OR REPLACE FUNCTION pdc_parts_private.planner_search_identity_20260917(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog,public AS $fn$
DECLARE v public.vehicles%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 PERFORM public.require_pdc_role('viewer');
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL AND lifecycle_state='active';
 -- Caller is a private overlay of already authorised snapshot rows. Do not add
 -- auditor-only scope requirements to workshop operators such as Bhavesh.
 IF NOT FOUND THEN RETURN '{}'::jsonb; END IF;
 RETURN jsonb_build_object('key_number',v.key_number,'job_card_numbers',
  coalesce((SELECT jsonb_agg(DISTINCT j.ro_number ORDER BY j.ro_number)
   FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL
    AND j.stock_number=v.stock_number AND j.source_system='tune_pmg'),'[]'::jsonb));
END $fn$;
REVOKE ALL ON FUNCTION pdc_parts_private.planner_search_identity_20260917(uuid) FROM PUBLIC,anon,authenticated;

