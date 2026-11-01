-- r807c (F423): with RFT'd no longer first, Email salesperson on 13047122 stopped at qc_items_required: the booking context read
-- every line (pdc_qc_operation_lines_379), including the unticked PIT AND WEIGH sublet line that Final check never shows (r400,
-- r401: Pit never blocks). The draft writer already uses the checkable lines; the context now uses the same list.
DO $r807c$
DECLARE
  sig regprocedure := 'public.read_rft_transport_booking_context_739(uuid)'::regprocedure;
  v_old text; v_new text; v_def text;
  a1 text := $a$lines:=coalesce(public.pdc_qc_operation_lines_379(v.id),'[]'::jsonb);$a$;
  b1 text := $b$lines:=coalesce((SELECT jsonb_agg(line) FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(v.id)) line WHERE coalesce((line->>'active')::boolean,false)),'[]'::jsonb); -- r807c (F423)$b$;
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r807c: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r807c: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
END $r807c$;
