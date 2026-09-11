-- STAGING only. Sublet approval preserves recorded hours and does not require them.
DO $migration$
DECLARE definition text;
 old_gate text := 'WHERE public.pdc_review_positive_hours_20260911(l,x) IS NULL';
 old_write text := 'IF (line->>''estimated_hours'')::numeric IS DISTINCT FROM public.pdc_review_positive_hours_20260911(line,assignment) THEN';
 old_readback text := 'newl->''estimated_hours''=to_jsonb(public.pdc_review_positive_hours_20260911(oldline,chosen))';
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
 definition := pg_get_functiondef('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure);
 IF position(old_gate in definition)=0 OR position(old_write in definition)=0 OR position(old_readback in definition)=0
 THEN RAISE EXCEPTION 'approval_definition_changed'; END IF;
 definition := replace(definition,old_gate,'WHERE (x->>''stage_code'' <> ''SUBLET'' AND public.pdc_review_positive_hours_20260911(l,x) IS NULL)');
 definition := replace(definition,old_write,'IF assignment->>''stage_code'' <> ''SUBLET'' AND (line->>''estimated_hours'')::numeric IS DISTINCT FROM public.pdc_review_positive_hours_20260911(line,assignment) THEN');
 definition := replace(definition,old_readback,'(newl->''estimated_hours'' IS NOT DISTINCT FROM CASE WHEN chosen->>''stage_code'' = ''SUBLET'' THEN oldline->''estimated_hours'' ELSE to_jsonb(public.pdc_review_positive_hours_20260911(oldline,chosen)) END)');
 EXECUTE definition;
END $migration$;
