-- r807 (F423): Craig 1 Nov 2026 19:47 AWST (screenshot, WPC tile): "i dont want Mark Collected on this page, it needs to be an option
-- in the RFT Page. And email sales person needs to be done before we click RFT."
-- Order is now: Final check sign-off (WPC) -> Email salesperson (draft with QC photo) -> Mark RFT'd (RFT page) -> Mark collected.
-- book_rft_transport_734 / book_rft_transport_email_draft_739 no longer need RFT'd first; set_rft_confirmation_736 now needs the
-- salesperson email draft for this sign-off. Collection rules are unchanged (needs RFT'd and the email).
DO $r807$
DECLARE
  r record; v_old text; v_new text; v_def text; n int;
  a1 text := ' OR v.rft_confirmed_at IS NULL OR v.rft_confirmed_at<v.qc_completed_at THEN RETURN jsonb_build_object(''ok'',false,''code'',''rft_confirmation_required''); END IF;';
  b1 text := ' THEN RETURN jsonb_build_object(''ok'',false,''code'',''qc_signoff_required''); END IF; -- r807 (F423): email before RFT''d';
  a2 text := E'  IF p_confirmed AND (v.qc_completed_at IS NULL OR v.rft_transferred_at IS NULL) THEN RETURN jsonb_build_object(''ok'',false,''code'',''qc_signoff_required''); END IF;\n';
  b2 text := a2 || E'  -- r807 (F423): Email salesperson comes before RFT''d.\n'
          || E'  IF p_confirmed AND NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_drafts_739 d WHERE d.vehicle_id=v.id AND d.created_at>=v.qc_completed_at) THEN RETURN jsonb_build_object(''ok'',false,''code'',''email_salesperson_required''); END IF;\n';
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 586 OR fault_id = 'F423' OR added_in = 'r807') THEN RAISE EXCEPTION 'r807: sort 586 or F423 is taken'; END IF;
  FOR r IN SELECT x.oid, x.a, x.b FROM (VALUES
      ('public.book_rft_transport_734(uuid,integer,uuid)'::regprocedure, a1, b1),
      ('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)'::regprocedure, a1, b1),
      ('public.set_rft_confirmation_736(uuid,integer,boolean,uuid)'::regprocedure, a2, b2)) x(oid, a, b) LOOP
    SELECT prosrc INTO v_old FROM pg_proc WHERE oid = r.oid;
    n := (length(v_old) - length(replace(v_old, r.a, ''))) / length(r.a);
    IF n <> 1 THEN RAISE EXCEPTION 'r807: anchor found % times in %', n, r.oid::regprocedure; END IF;
    v_new := replace(v_old, r.a, r.b);
    v_def := regexp_replace(pg_get_functiondef(r.oid), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
    IF (SELECT prosrc FROM pg_proc WHERE oid = r.oid) <> v_new THEN RAISE EXCEPTION 'r807: readback differs %', r.oid::regprocedure; END IF;
    UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
    UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
  END LOOP;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('email_before_rft_807', 'F423',
    'RFT (r807): Email salesperson comes before RFT''d. The email draft no longer needs RFT''d; RFT''d needs the email draft for this sign-off.',
    $chk$
SELECT strpos(c.src, 'email_salesperson_required') > 0 AND strpos(c.src, 'pdc_rft_transport_email_drafts_739') > 0
   AND strpos(b.src, 'rft_confirmation_required') = 0 AND strpos(d.src, 'rft_confirmation_required') = 0 AS ok,
 'email before RFT''d' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.set_rft_confirmation_736(uuid,integer,boolean,uuid)')) c,
     (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.book_rft_transport_734(uuid,integer,uuid)')) b,
     (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.book_rft_transport_email_draft_739(uuid,integer,uuid,uuid,text,text,text,integer,text,text)')) d
$chk$, true, 586, 'r807');
END $r807$;
