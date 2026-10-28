-- r675 rollback: put the conflict raises back to 40001 (not recommended: PostgREST retries 40001) and drop the check.
DO $d$ DECLARE v_old text; v_def text; BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure;
  v_def := regexp_replace(pg_get_functiondef('public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || replace(v_old, 'CONFLICT'' USING errcode=''PT409''', 'CONFLICT'' USING errcode=''40001''') || substring(v_def from '\$[a-zA-Z_]*\$$');
END $d$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'qc_conflict_not_retryable_675';
