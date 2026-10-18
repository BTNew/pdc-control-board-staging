-- Staging only: planner reads must not run or serialize with the mutation clock.
-- The existing per-minute server clock and every scheduling mutation guard remain unchanged.
DO $migration$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
  OR NOT pdc_codex_intake_private.management_connection() THEN
  RAISE EXCEPTION 'Staging management connection required';
 END IF;
 IF md5(pg_get_functiondef('public.get_station_workshop_snapshot_pre_397(text,date,date)'::regprocedure))<>'12125994adc093098cd0629575d850b1'
 OR md5(pg_get_functiondef('public.get_station_workshop_snapshot(text,date,date)'::regprocedure))<>'04740441290de8545969e6ca2d016e28' THEN
  RAISE EXCEPTION 'Station wrapper changed; review before deploying';
 END IF;
END $migration$;

CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot_pre_397(
 p_stage_code text,p_date_from date,p_date_to date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE v_snapshot jsonb;v_stage text;v_from timestamptz;v_to timestamptz;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 -- Read canonical persisted rows immediately. The scheduled clock owns
 -- automatic movement; planner mutations retain their locks and validation.
 v_snapshot:=public.get_station_workshop_snapshot_pre_170(p_stage_code,p_date_from,p_date_to);
 v_stage:=v_snapshot#>>'{scope,stage_code}';
 v_from:=p_date_from::timestamp AT TIME ZONE 'Australia/Perth';
 v_to:=(p_date_to+1)::timestamp AT TIME ZONE 'Australia/Perth';
 RETURN v_snapshot||jsonb_build_object('admin_blocks',(
  SELECT coalesce(jsonb_agg(public.workshop_admin_block_snapshot(a.id) ORDER BY a.scheduled_start_at,a.id),'[]'::jsonb)
  FROM public.workshop_admin_blocks a JOIN public.workshop_stages s ON s.id=a.stage_id
  WHERE a.deleted_at IS NULL AND s.code=v_stage
   AND a.scheduled_start_at<v_to AND a.scheduled_end_at>v_from));
END $function$;
ALTER FUNCTION public.get_station_workshop_snapshot(text,date,date) STABLE;
