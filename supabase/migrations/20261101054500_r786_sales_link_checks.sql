-- r786 (F394). Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 05:36 AWST: "go fix and merge" (last red health checks).
-- Check text only; nobody's access changes.
--   controller_sales_link: Scott Lovett's controller login (scott.lovett@pmgwa.com.au) was linked to his own salesperson record on
--     21 Oct with Craig's approval (r432, matched by email then). r495 (23 Oct) changed that record's email to scott@karrathatoyota.com.au,
--     so the same-email rule turned red. A link now also passes when the names match and Craig's audited approval names that record.
--   sales_branch_495: "branch leaks" allowed only Clint Franklin and Scott Lovett at Karratha by name, so Joel Sutton (Karratha
--     salesperson, enabled for 14450) counted as a leak. A Karratha scope now passes when its salesperson is enabled for 14450.
DO $r786$
DECLARE n integer;
  a1 text := $q$count(*) FILTER (WHERE s.id IS NULL OR lower(btrim(coalesce(s.email,'')))<>lower(btrim(r.email))) bad$q$;
  b1 text := $q$count(*) FILTER (WHERE s.id IS NULL OR (lower(btrim(coalesce(s.email,'')))<>lower(btrim(r.email))
     AND NOT (lower(btrim(s.name))=lower(btrim(coalesce(r.full_name,'')))  /* r786: same person, Craig-approved link */
       AND EXISTS (SELECT 1 FROM public.audit_events ae WHERE ae.table_name='pdc_sales_private.account_scopes'
         AND lower(ae.actor_email)='craig.watson@broometoyota.com.au' AND ae.after_data->>'salesperson_id'=s.id::text
         AND lower(ae.metadata->>'target_email')=lower(r.email))))) bad$q$;
  a2 text := $q$OR (a.dealer_code='14450' AND NOT (upper(btrim(s.code)) IN ('CF','SL') AND lower(btrim(s.name)) IN ('clint franklin','scott lovett')))$q$;
  b2 text := $q$OR (a.dealer_code='14450' AND NOT EXISTS (SELECT 1 FROM pdc_sales_private.salesperson_branches mb  /* r786: any enabled Karratha salesperson */
                 WHERE mb.salesperson_id=s.id AND mb.dealer_code='14450' AND mb.enabled))$q$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r786: staging only'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, a1, b1)
  WHERE check_name = 'controller_sales_link' AND (length(check_sql) - length(replace(check_sql, a1, ''))) / length(a1) = 1;
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r786: controller_sales_link not updated'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, a2, b2)
  WHERE check_name = 'sales_branch_495' AND (length(check_sql) - length(replace(check_sql, a2, ''))) / length(a2) = 1;
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r786: sales_branch_495 not updated'; END IF;
END $r786$;
