-- r807b (F423): Craig 1 Nov 2026 20:28 AWST (screenshot): Email salesperson on WPC still said "PMB must mark this vehicle RFT'd
-- before emailing the salesperson." r807 changed the draft writers but missed the two readers the button calls first:
-- read_rft_transport_booking_context_739 and read_rft_transport_draft_739 still required RFT'd. Both now only need the sign-off.
DO $r807b$
DECLARE
  r record; v_old text; v_new text; v_def text; n int;
  a1 text := ' OR v.rft_confirmed_at IS NULL OR v.rft_confirmed_at<v.qc_completed_at THEN RETURN jsonb_build_object(''ok'',false,''code'',''rft_confirmation_required''); END IF;';
  b1 text := ' THEN RETURN jsonb_build_object(''ok'',false,''code'',''qc_signoff_required''); END IF; -- r807b (F423): email before RFT''d';
  a2 text := E'\n   AND v.rft_confirmed_at IS NOT NULL AND v.rft_confirmed_at>=v.qc_completed_at)\n   THEN RETURN jsonb_build_object(''ok'',false,''code'',''rft_confirmation_required''); END IF;';
  b2 text := E')\n   THEN RETURN jsonb_build_object(''ok'',false,''code'',''qc_signoff_required''); END IF; -- r807b (F423): email before RFT''d';
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE added_in = 'r807b') THEN RAISE EXCEPTION 'r807b: already applied'; END IF;
  FOR r IN SELECT x.oid, x.a, x.b FROM (VALUES
      ('public.read_rft_transport_booking_context_739(uuid)'::regprocedure, a1, b1),
      ('public.read_rft_transport_draft_739(uuid)'::regprocedure, a2, b2)) x(oid, a, b) LOOP
    SELECT prosrc INTO v_old FROM pg_proc WHERE oid = r.oid;
    n := (length(v_old) - length(replace(v_old, r.a, ''))) / length(r.a);
    IF n <> 1 THEN RAISE EXCEPTION 'r807b: anchor found % times in %', n, r.oid::regprocedure; END IF;
    v_new := replace(v_old, r.a, r.b);
    v_def := regexp_replace(pg_get_functiondef(r.oid), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
    IF (SELECT prosrc FROM pg_proc WHERE oid = r.oid) <> v_new THEN RAISE EXCEPTION 'r807b: readback differs %', r.oid::regprocedure; END IF;
    UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
    UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
  END LOOP;
  -- The r807 check now covers every public function: none may still ask for RFT'd before the email.
  UPDATE pdc_ops.regression_checks SET added_in = 'r807b', check_sql = $chk$
SELECT strpos(c.src, 'email_salesperson_required') > 0 AND strpos(c.src, 'pdc_rft_transport_email_drafts_739') > 0
   AND NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.prosrc LIKE '%rft_confirmation_required%') AS ok,
 'email before RFT''d' AS detail
FROM (SELECT prosrc src FROM pg_proc WHERE oid = to_regprocedure('public.set_rft_confirmation_736(uuid,integer,boolean,uuid)')) c
$chk$ WHERE check_name = 'email_before_rft_807';
END $r807b$;
