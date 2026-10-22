DO $a$ DECLARE r record; x record; bad int:=0; BEGIN
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE enabled ORDER BY sort_order LOOP
  PERFORM set_config('search_path','pg_catalog',true);
  EXECUTE r.check_sql INTO x;
  RAISE NOTICE 'check % ok=% %', r.check_name, x.ok, left(x.detail,220);
  IF x.ok IS NOT TRUE THEN bad:=bad+1; END IF;
 END LOOP;
 PERFORM set_config('search_path','public',true);
 RAISE NOTICE 'checks failing: %', bad;
END $a$;
