-- r691 rollback: remove the r691 lines from both functions, move both pins back, drop the check.
DO $d$ DECLARE v_old text; v_new text; v_def text; v_m text; s text; BEGIN
  FOREACH s IN ARRAY ARRAY['public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)','public.pdc_workshop_actor_vehicle_allowed(jsonb,uuid,text)'] LOOP
    SELECT prosrc, md5(prosrc) INTO v_old, v_m FROM pg_proc WHERE oid = s::regprocedure;
    v_new := replace(v_old, 'pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,coalesce(v_vehicle_dealer,v_scope->>''dealer_code'')) /* r691 */', 'pdc_workshop_actor_vehicle_allowed(v_scope,p_vehicle_id,v_vehicle_dealer)');
    v_new := regexp_replace(v_new, E'  -- r691 \\(F301\\).*?THEN RETURN true; END IF;\\n', '', 's');
    v_def := regexp_replace(pg_get_functiondef(s::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
    UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = s::regprocedure) WHERE prosrc_md5 = v_m;
  END LOOP;
END $d$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'dealer_scope_board_vehicles_691';
