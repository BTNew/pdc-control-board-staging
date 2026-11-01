-- r812 (F450): night review 1 Nov 2026. r791 (F399) / r796 (F406) treated Navision location status 'OD' as "delivered to dealer".
-- It is not: OD is on nearly every PMB car ("Delivered - At Body Builder", "Despatched - From TWA", "Ready For Transport ..."),
-- 232 visible board cars on 1 Nov. With OD in the rule, board_every_stock_674 would never bring a hidden car back from the import
-- when its Navision location was OD. Craig's rule (1 Nov 06:56) is "Delivered - At Dealer" only. The check follows.
DO $r812$
DECLARE
  sig regprocedure := 'pdc_import_620.board_every_stock_674(uuid,boolean)'::regprocedure;
  v_old text; v_new text; v_def text;
  a1 text := $a$ WHERE n.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer' OR n.normalized_data->>'navisionLocationStatus' = 'OD')$a$;
  b1 text := $b$ WHERE n.normalized_data->>'toyotaStatus' = 'Delivered - At Dealer') -- r812 (F450): OD is not delivered$b$;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r812: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r812: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r812: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
  UPDATE pdc_ops.regression_checks
     SET check_sql = replace(check_sql, $q$ OR n.normalized_data->>'navisionLocationStatus' = 'OD')$q$, ')')
   WHERE check_name = 'delivered_stays_completed_791';
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_sql LIKE '%''OD''%') THEN RAISE EXCEPTION 'r812: a check still uses OD'; END IF;
END $r812$;
