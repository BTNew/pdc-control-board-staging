-- r801 (F416). Staging cdsmnqxtyyoeoznmbidd only. Check text only; no function or data changes.
-- Craig 1 Nov 2026 08:27 AWST (chat "PMB vehicle status rules"): "only vehicles that we tick To PMB can enter PMB... remove that
-- rule that At Body Builder goes to PMB". That session (migration remove_bodybuilder_to_pmb_rule_20261101) removed the r574
-- Body Builder -> PMB rule from the Navision projection and closed 13033311's hold with release_action 'bb_rule_removed'.
-- bodybuilder_new_to_pmb_574 still tested the old rule (projection phrase) and counted that closure as a slip.
-- Now it tests the new rule: no body-builder car reaches PMB without To PMB; a hold closed by the rule removal is allowed;
-- the projection is no longer required to carry the old phrase.
DO $r801$
DECLARE n integer;
  a1 text := $q$AND h.release_action IS DISTINCT FROM 'key_number' /* r785: r745 key release */$q$;
  b1 text := $q$AND h.release_action IS DISTINCT FROM 'key_number' /* r785: r745 key release */ AND h.release_action IS DISTINCT FROM 'bb_rule_removed' /* r801: Craig removed the BB rule 1 Nov */$q$;
  a2 text := $q$  AND loc.phrases
  AND proj.phrases
$q$;
  b2 text := $q$  /* r801: loc/proj phrases no longer required (BB -> PMB rule removed 1 Nov 2026) */
$q$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r801: staging only'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql, a1, b1), a2, b2),
    description = description || ' r801: Craig removed the At Body Builder to PMB rule on 1 Nov 2026; the check now guards To PMB as the only way in.'
  WHERE check_name = 'bodybuilder_new_to_pmb_574'
    AND (length(check_sql) - length(replace(check_sql, a1, ''))) / length(a1) = 1
    AND (length(check_sql) - length(replace(check_sql, a2, ''))) / length(a2) = 1;
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r801: check not updated'; END IF;
END $r801$;
