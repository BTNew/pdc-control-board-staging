-- Preserve Start priority, clock-rebase wrappers and all booking protections.
-- Initialize the temporary plan inside its INSERT, avoiding an unqualified
-- UPDATE rejected by PostgREST's session-loaded safeupdate safeguard.
DO $repair$
DECLARE source text; repaired text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Staging only';
 END IF;
 source:=pg_get_functiondef('public.start_workshop_work_pre_116(uuid,integer,timestamptz,jsonb)'::regprocedure);
 IF md5(source)<>'ff85f53f7e0ef5ec9da6fc97466cf6d0' THEN
  RAISE EXCEPTION 'Unexpected Start definition; review before applying safeupdate repair';
 END IF;
 repaired:=replace(source,
  'final_start,final_end,minutes,version,technicians,movable,changed,apply_order)',
  'final_start,final_end,minutes,version,technicians,movable,changed,apply_order,current_start,current_end)');
 repaired:=replace(repaired,
  'AND bay.is_active AND s.active AND b.bay_id IS NOT NULL,false,NULL',
  'AND bay.is_active AND s.active AND b.bay_id IS NOT NULL,false,NULL,b.scheduled_start_at,e.ends');
 repaired:=replace(repaired,
  E' UPDATE pg_temp.workshop_start_plan SET current_start=original_start,current_end=effective_end;\n','');
 IF repaired=source
 OR position('apply_order,current_start,current_end)' in repaired)=0
 OR position('false,NULL,b.scheduled_start_at,e.ends' in repaired)=0
 OR position('SET current_start=original_start,current_end=effective_end;' in repaired)>0 THEN
  RAISE EXCEPTION 'Start initialization anchors did not match';
 END IF;
 EXECUTE repaired;
END $repair$;
