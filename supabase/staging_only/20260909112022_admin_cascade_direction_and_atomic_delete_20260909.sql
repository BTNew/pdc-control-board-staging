-- STAGING ONLY. Vacate destination intervals in the direction of movement.
DO $repair$
DECLARE d text; p text; preflight text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT pg_get_functiondef('public.workshop_admin_repack_planned(uuid,timestamptz,jsonb)'::regprocedure) INTO d;
 IF md5(d)<>'a4cfd199378fec062f10ba94956fd234' THEN RAISE EXCEPTION 'Admin cascade changed since review'; END IF;
 p:=replace(d,'ORDER BY original_start DESC,kind DESC,id DESC',
  'ORDER BY CASE WHEN final_start<original_start THEN 0 ELSE 1 END,
    CASE WHEN final_start<original_start THEN original_start END ASC,
    CASE WHEN final_start>=original_start THEN original_start END DESC,kind,id');
 p:=replace(p,'-- Reverse order is essential: it vacates later rows before earlier rows are',
 '-- Rightward moves vacate from the back; leftward moves vacate from the front. Rows are');
 IF p=d THEN RAISE EXCEPTION 'Cascade patch mismatch'; END IF;
 EXECUTE p;
 SELECT pg_get_functiondef('public.delete_workshop_admin_block(uuid,integer,text,jsonb)'::regprocedure) INTO d;
 IF md5(d)<>'181233ed07db374f94a63fed9462e4a8' THEN RAISE EXCEPTION 'Admin delete changed since review'; END IF;
 p:=replace(d,E'\r\n',E'\n');
 preflight:=$clock$  v_from:=public.workshop_admin_next_operational_minute(greatest(v_block.scheduled_start_at,date_trunc('minute',clock_timestamp())));
  IF v_from IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_future_operational_minute','no_partial_save',true); END IF;
$clock$;
 IF position(preflight IN p)=0 THEN RAISE EXCEPTION 'Admin delete clock preflight missing'; END IF;
 p:=replace(p,preflight,'');
 p:=replace(p,'  v_before:=public.workshop_admin_block_snapshot(p_block_id);',preflight||'  v_before:=public.workshop_admin_block_snapshot(p_block_id);');
 EXECUTE p;
END $repair$;