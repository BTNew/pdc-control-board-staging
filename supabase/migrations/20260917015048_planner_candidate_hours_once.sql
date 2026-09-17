-- Planner refresh: evaluate approved candidate hours once per row.
-- Existing helper only; preserve its signature, owner, volatility and private ACL.
DO $guard$
DECLARE f regprocedure:='public.workshop_overlay_authoritative_candidate_hours_175(jsonb)'::regprocedure;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'planner_candidate_hours_once_requires_staging'; END IF;
  IF md5(pg_get_functiondef(f)) <> 'd5e89cfd5f832e45279040c27ac1276e' THEN
    RAISE EXCEPTION 'planner_candidate_hours_definition_changed';
  END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid=f) IS DISTINCT FROM '{postgres=X/postgres}'
     OR (SELECT proowner::regrole::text FROM pg_proc WHERE oid=f) IS DISTINCT FROM 'postgres'
  THEN RAISE EXCEPTION 'planner_candidate_hours_authority_changed'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_overlay_authoritative_candidate_hours_175(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_stage text;
  v_candidates jsonb;
BEGIN
  IF p_snapshot IS NULL
     OR jsonb_typeof(p_snapshot->'outstanding_candidates') IS DISTINCT FROM 'array'
     OR jsonb_typeof(p_snapshot->'scope') IS DISTINCT FROM 'object'
  THEN RETURN p_snapshot; END IF;

  v_stage:=public.workshop_canonical_stage_code(p_snapshot->'scope'->>'stage_code');
  IF v_stage IS NULL OR v_stage='' THEN RETURN p_snapshot; END IF;

  -- Fence this projection so PostgreSQL evaluates the approved-hours helper once
  -- per candidate, rather than repeating it for each JSON field below.
  WITH candidate_hours AS MATERIALIZED (
    SELECT candidate, ordinal,
      public.workshop_vehicle_stage_estimated_hours(
        (candidate->>'vehicle_id')::uuid,v_stage
      ) estimated_hours
    FROM jsonb_array_elements(p_snapshot->'outstanding_candidates')
      WITH ORDINALITY item(candidate,ordinal)
  )
  SELECT coalesce(jsonb_agg(
    candidate || jsonb_build_object(
      'estimated_hours',coalesce(to_jsonb(estimated_hours),'null'::jsonb),
      'schedule_enabled',CASE
        WHEN estimated_hours IS NULL THEN false
        ELSE coalesce((candidate->>'schedule_enabled')::boolean,false)
      END,
      'disabled_reason',CASE
        WHEN estimated_hours IS NULL
          THEN coalesce(nullif(candidate->>'disabled_reason',''),'estimated_duration_missing')
        ELSE candidate->>'disabled_reason'
      END
    )
    ORDER BY ordinal
  ),'[]'::jsonb)
  INTO v_candidates
  FROM candidate_hours;

  RETURN jsonb_set(jsonb_set(p_snapshot,'{outstanding_candidates}',v_candidates,false),'{vehicles}',
    coalesce((SELECT jsonb_agg(x||jsonb_build_object('qc_rework',public.pdc_qc_rework_scope_20260909((x->>'id')::uuid)))
      FROM jsonb_array_elements(coalesce(p_snapshot->'vehicles','[]'::jsonb)) x),'[]'::jsonb),false);
END
$function$;

-- CREATE OR REPLACE preserves the existing owner and ACL. Do not grant this
-- private helper to API roles or replace the surrounding snapshot authorization.
DO $verify$
DECLARE f regprocedure:='public.workshop_overlay_authoritative_candidate_hours_175(jsonb)'::regprocedure;
BEGIN
  IF (SELECT proacl::text FROM pg_proc WHERE oid=f) IS DISTINCT FROM '{postgres=X/postgres}'
     OR (SELECT proowner::regrole::text FROM pg_proc WHERE oid=f) IS DISTINCT FROM 'postgres'
     OR has_function_privilege('anon',f,'execute')
     OR has_function_privilege('authenticated',f,'execute')
     OR has_function_privilege('service_role',f,'execute')
  THEN RAISE EXCEPTION 'planner_candidate_hours_authority_not_preserved'; END IF;
END $verify$;
