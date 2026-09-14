-- STAGING ONLY: bay capacity is independent of quoted operation hours.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
  OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Bay capacity is available on staging only.';
 END IF;
END $guard$;

ALTER TABLE public.workshop_bays
 ADD COLUMN efficiency_percent integer NOT NULL DEFAULT 100
 CONSTRAINT workshop_bay_efficiency_range CHECK (efficiency_percent BETWEEN 10 AND 200);
COMMENT ON COLUMN public.workshop_bays.efficiency_percent IS
 '100 is normal. Allocated minutes = ceil(base work minutes * 100 / efficiency). Changes are applied through the capacity preview/apply RPC.';

-- list_workshop_bays already returns SETOF workshop_bays, so the new field is
-- present without replacing its authorization or projection.
CREATE OR REPLACE FUNCTION public.get_workshop_capacity_configuration(p_stage_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,public AS $function$
DECLARE sid uuid; stage text;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 stage:=public.workshop_canonical_stage_code(p_stage_code);
 SELECT id INTO sid FROM public.workshop_stages
 WHERE code=stage AND active AND planner_enabled AND is_physical AND NOT is_sublet AND code<>'SUBLET';
 IF sid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','station_unavailable'); END IF;
 RETURN jsonb_build_object('ok',true,'stage_code',stage,'bays',coalesce((
  SELECT jsonb_agg(jsonb_build_object('bay_id',b.id,'bay_number',b.bay_number,
    'efficiency_percent',b.efficiency_percent,'version',b.version) ORDER BY b.bay_number,b.id)
  FROM public.workshop_bays b WHERE b.stage_id=sid AND b.is_active AND NOT b.is_sublet_row),'[]'::jsonb));
END $function$;
REVOKE ALL ON FUNCTION public.get_workshop_capacity_configuration(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_workshop_capacity_configuration(text) TO authenticated;
