-- r820 (F458): Craig 2 Nov 08:23 "im trying to save hours on 13109751 - wont save". The vehicle slide-out sent lines that
-- already had a saved adjustment with no adjustment id and version 0 (it never read line_adjustments), so the server refused
-- every such save as "changed in another session" (405 board cars have adjustments). Client fixed in pdc-vehicle-slideout.js;
-- the server also accepts a row with no id / version 0 when the vehicle version matches (every hours save moves it).
DO $r820$
DECLARE sig regprocedure := 'public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure;
  v_old text; v_new text; v_def text;
  a1 text := $a$     OR a.adjustment_id IS DISTINCT FROM r.adjustment_id OR coalesce(a.version,0)<>r.expected_line_version;$a$;
  b1 text := $b$     OR ((a.adjustment_id IS DISTINCT FROM r.adjustment_id OR coalesce(a.version,0)<>r.expected_line_version)
       -- r820 (F458): a screen that did not know the line's saved adjustment (no id, version 0) may still save it: the
       -- vehicle version was checked above, and every hours save moves it, so nobody changed these hours since it loaded.
       AND NOT (r.adjustment_id IS NULL AND r.expected_line_version=0));$b$;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued','running','loading')) THEN RAISE EXCEPTION 'r820: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r820: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r820: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE strpos(check_sql, md5(v_old)) > 0;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = md5(v_old);
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('hours_save_known_adjustment_820', 'F458',
    'Hours (r820): a slide-out hours save for a line with a saved adjustment is accepted (no false "changed in another session"), and refused conflicts are logged.',
    $chk$
SELECT strpos(p.prosrc, 'AND NOT (r.adjustment_id IS NULL AND r.expected_line_version=0))') > 0
   AND strpos(p.prosrc, 'pdc_ops.hours_batch_conflicts_819') > 0
 AS ok, 'hours save accepts the current adjustment' AS detail
FROM pg_proc p WHERE p.oid = 'public.save_vehicle_workshop_line_hours_batch_768(uuid,text,text,bigint,jsonb,uuid)'::regprocedure
$chk$, true, 607, 'r820');
END $r820$;
