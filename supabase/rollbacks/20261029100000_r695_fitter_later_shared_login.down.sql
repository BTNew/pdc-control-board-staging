-- r695 rollback: put the old login-id assignment check back and drop the check.
DO $d$ DECLARE v_old text; v_def text; BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.set_line_later_627(uuid,text,text,text)'::regprocedure;
  v_def := regexp_replace(pg_get_functiondef('public.set_line_later_627(uuid,text,text,text)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, 'NOT EXISTS (SELECT 1 FROM public.workshop_technicians t WHERE t.active AND pdc_fitter_private.assigned(p_booking_id, t.id))', 'NOT pdc_fitter_private.assigned(p_booking_id, v_uid)') || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'fitter_later_shared_login_695';
END $d$;
