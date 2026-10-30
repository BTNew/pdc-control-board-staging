-- r764b (F421): the r764 daily check must name its columns ok and detail (regression_checks_self_test).
UPDATE pdc_ops.regression_checks SET check_sql=$c$WITH n AS (
   SELECT pg_catalog.count(*) AS noise FROM pdc_sales_private.crm_timeline
   WHERE event_type='workshop_changed' AND occurred_at>pg_catalog.now()-interval '7 days'
     AND pdc_sales_private.crm_workshop_compare(details->'before') IS NOT DISTINCT FROM pdc_sales_private.crm_workshop_compare(details->'after')),
 s AS (SELECT coalesce(pg_catalog.sum(pg_catalog.octet_length(t.details::text)),0) AS bytes
   FROM (SELECT details FROM pdc_sales_private.crm_timeline ORDER BY occurred_at DESC LIMIT 3000) t)
 SELECT (n.noise=0 AND s.bytes<4000000) AS ok,
  'noise alerts 7d='||n.noise||', latest 3000 events='||s.bytes||' bytes (limit 4000000)' AS detail
 FROM n,s$c$
WHERE check_name='sales_workspace_size_764';
