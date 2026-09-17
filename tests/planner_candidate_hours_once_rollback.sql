-- Run as a single transaction. Pre-apply verification may insert the migration
-- immediately after BEGIN; the final ROLLBACK reverts it together with temp helpers.
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- INSERT MIGRATION UNDER TEST HERE FOR PRE-APPLY VERIFICATION.

CREATE TEMP TABLE planner_hours_checks(check_name text PRIMARY KEY, passed boolean, detail jsonb) ON COMMIT DROP;
CREATE TEMP TABLE planner_hours_benchmark(stage_code text, pass integer, execution_order text, old_ms numeric, new_ms numeric, candidate_count integer) ON COMMIT DROP;
CREATE TEMP TABLE planner_hours_before(footprint jsonb) ON COMMIT DROP;
CREATE FUNCTION pg_temp.planner_hours_assert(ok boolean,label text,body jsonb DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $assert$
BEGIN
 IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'planner_hours_verification_failed: %: %',label,body; END IF;
 INSERT INTO planner_hours_checks VALUES(label,true,body);
END $assert$;
CREATE FUNCTION pg_temp.planner_hours_footprint() RETURNS jsonb LANGUAGE sql STABLE AS $footprint$
 SELECT jsonb_build_object(
 'bookings',(SELECT md5(coalesce(string_agg(md5(to_jsonb(b)::text),'' ORDER BY b.id),'')) FROM public.workshop_bookings b),
 'vehicles',(SELECT md5(coalesce(string_agg(md5(jsonb_build_array(v.id,v.version,v.updated_at,v.current_location,v.workshop_status,v.active_workshop_booking_id)::text),'' ORDER BY v.id),'')) FROM public.vehicles v),
 'work_items',(SELECT md5(coalesce(string_agg(md5(to_jsonb(w)::text),'' ORDER BY w.vehicle_id,w.work_key),'')) FROM public.vehicle_work_items w),
 'adjustments',(SELECT md5(coalesce(string_agg(md5(to_jsonb(a)::text),'' ORDER BY a.adjustment_id),'')) FROM public.vehicle_workshop_line_adjustments a),
 'fitter_progress',(SELECT md5(coalesce(string_agg(md5(to_jsonb(p)::text),'' ORDER BY to_jsonb(p)::text),'')) FROM pdc_fitter_private.operation_progress p)
 );
$footprint$;
INSERT INTO planner_hours_before SELECT pg_temp.planner_hours_footprint();

CREATE OR REPLACE FUNCTION pg_temp.planner_hours_previous(p_snapshot jsonb)
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

  SELECT coalesce(jsonb_agg(
    candidate || jsonb_build_object(
      'estimated_hours',coalesce(to_jsonb(authority.estimated_hours),'null'::jsonb),
      'schedule_enabled',CASE
        WHEN authority.estimated_hours IS NULL THEN false
        ELSE coalesce((candidate->>'schedule_enabled')::boolean,false)
      END,
      'disabled_reason',CASE
        WHEN authority.estimated_hours IS NULL
          THEN coalesce(nullif(candidate->>'disabled_reason',''),'estimated_duration_missing')
        ELSE candidate->>'disabled_reason'
      END
    )
    ORDER BY ordinal
  ),'[]'::jsonb)
  INTO v_candidates
  FROM jsonb_array_elements(p_snapshot->'outstanding_candidates') WITH ORDINALITY item(candidate,ordinal)
  CROSS JOIN LATERAL (
    SELECT public.workshop_vehicle_stage_estimated_hours((candidate->>'vehicle_id')::uuid,v_stage) estimated_hours
  ) authority;

  RETURN jsonb_set(jsonb_set(p_snapshot,'{outstanding_candidates}',v_candidates,false),'{vehicles}',
    coalesce((SELECT jsonb_agg(x||jsonb_build_object('qc_rework',public.pdc_qc_rework_scope_20260909((x->>'id')::uuid)))
      FROM jsonb_array_elements(coalesce(p_snapshot->'vehicles','[]'::jsonb)) x),'[]'::jsonb),false);
END
$function$;


DO $verify$
DECLARE actor uuid; actor_email text; code text; body jsonb; expected jsonb; actual jsonb; input jsonb;
 started timestamptz; old_ms numeric; new_ms numeric; pass integer; f regprocedure:='public.workshop_overlay_authoritative_candidate_hours_175(jsonb)'::regprocedure;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'planner_hours_verification_requires_staging'; END IF;
 PERFORM pg_temp.planner_hours_assert(position('WITH candidate_hours AS MATERIALIZED' in pg_get_functiondef(f))>0,'optimized helper is installed');
 PERFORM pg_temp.planner_hours_assert((SELECT proacl::text='{postgres=X/postgres}' AND proowner::regrole::text='postgres'
  AND prosecdef AND provolatile='s' AND proconfig=ARRAY['search_path=pg_catalog, public']::text[] FROM pg_proc WHERE oid=f),'owner, private grants and function properties unchanged');
 PERFORM pg_temp.planner_hours_assert(NOT has_function_privilege('anon',f,'execute')
  AND NOT has_function_privilege('authenticated',f,'execute')
  AND NOT has_function_privilege('service_role',f,'execute'),'API roles cannot execute private helper');

 SELECT r.auth_user_id,r.email INTO STRICT actor,actor_email
 FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role='administrator'
 ORDER BY r.created_at,r.id LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','email',actor_email)::text,true);

 -- The pre-170 reader is deliberately used here: the public station endpoint
 -- also ticks the workshop clock and can move real bookings.
 FOR code IN SELECT s.code FROM public.workshop_stages s WHERE s.active AND s.planner_enabled ORDER BY s.sort_order,s.code LOOP
  body:=public.get_station_workshop_snapshot_pre_170(code,(now() AT TIME ZONE 'Australia/Perth')::date,(now() AT TIME ZONE 'Australia/Perth')::date);
  body:=public.workshop_overlay_canonical_booking_fields_397(body);
  expected:=pg_temp.planner_hours_previous(body);
  actual:=public.workshop_overlay_authoritative_candidate_hours_175(body);
  PERFORM pg_temp.planner_hours_assert(actual=expected,'exact station JSON: '||code,
    jsonb_build_object('candidates',jsonb_array_length(actual->'outstanding_candidates'),'bookings',jsonb_array_length(actual->'bookings')));
 END LOOP;

 -- Both orders are measured to distinguish a calculation saving from warm-cache bias.
 body:=public.get_station_workshop_snapshot_pre_170('FITTING',(now() AT TIME ZONE 'Australia/Perth')::date,(now() AT TIME ZONE 'Australia/Perth')::date);
 FOR pass IN 1..4 LOOP
  IF pass%2=1 THEN
   started:=clock_timestamp();expected:=pg_temp.planner_hours_previous(body);old_ms:=extract(epoch FROM clock_timestamp()-started)*1000;
   started:=clock_timestamp();actual:=public.workshop_overlay_authoritative_candidate_hours_175(body);new_ms:=extract(epoch FROM clock_timestamp()-started)*1000;
  ELSE
   started:=clock_timestamp();actual:=public.workshop_overlay_authoritative_candidate_hours_175(body);new_ms:=extract(epoch FROM clock_timestamp()-started)*1000;
   started:=clock_timestamp();expected:=pg_temp.planner_hours_previous(body);old_ms:=extract(epoch FROM clock_timestamp()-started)*1000;
  END IF;
  PERFORM pg_temp.planner_hours_assert(actual=expected,'benchmark exact JSON: pass '||pass);
  INSERT INTO planner_hours_benchmark VALUES('FITTING',pass,CASE WHEN pass%2=1 THEN 'old,new' ELSE 'new,old' END,old_ms,new_ms,jsonb_array_length(body->'outstanding_candidates'));
 END LOOP;

 FOR input IN SELECT x FROM jsonb_array_elements('[
  null,{},{"scope":{"stage_code":"FITTING"}},{"scope":null,"outstanding_candidates":[]},
  {"scope":{},"outstanding_candidates":[]},{"scope":{"stage_code":"FITTING"},"outstanding_candidates":{}},
  {"scope":{"stage_code":"FITTING"},"outstanding_candidates":[],"vehicles":[]},
  {"scope":{"stage_code":"FITTING"},"outstanding_candidates":[
   {"vehicle_id":"00000000-0000-0000-0000-000000000000","schedule_enabled":true,"disabled_reason":""},
   {"vehicle_id":"00000000-0000-0000-0000-000000000000","schedule_enabled":false,"disabled_reason":"preserved-existing-reason"}
  ],"vehicles":[]}
 ]'::jsonb) x LOOP
  expected:=pg_temp.planner_hours_previous(input);
  actual:=public.workshop_overlay_authoritative_candidate_hours_175(input);
  PERFORM pg_temp.planner_hours_assert(actual IS NOT DISTINCT FROM expected,'shape parity: '||md5(input::text));
 END LOOP;
 PERFORM pg_temp.planner_hours_assert(
  public.workshop_overlay_authoritative_candidate_hours_175(NULL) IS NULL,'SQL NULL unchanged');
 PERFORM pg_temp.planner_hours_assert(
  public.workshop_overlay_authoritative_candidate_hours_175(jsonb_build_object('scope',jsonb_build_object('stage_code','FITTING'),'outstanding_candidates','[]'::jsonb))->'outstanding_candidates'='[]'::jsonb,'empty array unchanged');
END $verify$;

-- Actual role execution checks, not only an ACL inspection.
SET LOCAL ROLE anon;
DO $denied$ BEGIN
 BEGIN PERFORM public.workshop_overlay_authoritative_candidate_hours_175(NULL);
  RAISE EXCEPTION 'anonymous helper execution unexpectedly permitted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denied$;
RESET ROLE;
INSERT INTO planner_hours_checks VALUES('anonymous execution denied',true,NULL);
SET LOCAL ROLE authenticated;
DO $denied$ BEGIN
 BEGIN PERFORM public.workshop_overlay_authoritative_candidate_hours_175(NULL);
  RAISE EXCEPTION 'authenticated helper execution unexpectedly permitted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denied$;
RESET ROLE;
INSERT INTO planner_hours_checks VALUES('authenticated direct execution denied',true,NULL);
SET LOCAL ROLE service_role;
DO $denied$ BEGIN
 BEGIN PERFORM public.workshop_overlay_authoritative_candidate_hours_175(NULL);
  RAISE EXCEPTION 'service helper execution unexpectedly permitted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denied$;
RESET ROLE;
INSERT INTO planner_hours_checks VALUES('service direct execution denied',true,NULL);

SELECT pg_temp.planner_hours_assert((SELECT footprint FROM planner_hours_before)=pg_temp.planner_hours_footprint(),'business rows unchanged');
SELECT jsonb_build_object(
 'checks',(SELECT count(*) FROM planner_hours_checks),
 'all_passed',(SELECT bool_and(passed) FROM planner_hours_checks),
 'results',(SELECT jsonb_agg(to_jsonb(c) ORDER BY check_name) FROM planner_hours_checks c),
 'timings',(SELECT jsonb_agg(to_jsonb(b) ORDER BY pass) FROM planner_hours_benchmark b)
) verification;
ROLLBACK;
