DO $d$ DECLARE v text; d text; BEGIN
  SELECT prosrc INTO v FROM pg_proc WHERE oid = 'public.pmb_transfer_vehicle(uuid,integer)'::regprocedure;
  d := regexp_replace(pg_get_functiondef('public.pmb_transfer_vehicle(uuid,integer)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE d || replace(v, $b$  if v_location = '' and ( -- r722 (F332): Other is an incoming location for every vehicle$b$, $a$  if v_location in ('OTHER','') and ($a$) || substring(d from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'to_pmb_from_other_722';
END $d$;
