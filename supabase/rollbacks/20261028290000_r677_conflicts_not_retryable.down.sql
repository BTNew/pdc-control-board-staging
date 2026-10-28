-- r677 rollback (not recommended: PostgREST retries 40001). Puts PT409 back to 40001 in every function except
-- set_pdc_qc_operation_completion_379 (r675), moves the two tick pins back, and drops the check.
DO $d$ DECLARE r record; v_def text; v_old text; BEGIN
  FOR r IN SELECT p.oid, p.prosrc, md5(p.prosrc) m FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE p.prosrc ~ 'errcode\s*=\s*''PT409''' AND n.nspname NOT LIKE 'karratha%' AND p.proname <> 'set_pdc_qc_operation_completion_379' LOOP
    v_def := regexp_replace(pg_get_functiondef(r.oid), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || regexp_replace(r.prosrc, '(errcode\s*=\s*)''PT409''', '\1''40001''', 'g') || substring(v_def from '\$[a-zA-Z_]*\$$');
    UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.oid) WHERE prosrc_md5 = r.m;
  END LOOP;
END $d$;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'conflicts_not_retryable_677';
