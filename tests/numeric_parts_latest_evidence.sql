 WITH evidence(operation_id,repair_order_number,original_line_number,company,division,raw_row,created_at,history_id) AS (VALUES
 ('00000000-0000-4000-8000-000000000001'::uuid,'TEST-RO',1,'A','D1','{"Parts Attached":1,"Parts on Backorder":1,"Backorder with PO (1=Yes, 0=No)":1}'::jsonb,'2026-09-01'::timestamptz,1),
 ('00000000-0000-4000-8000-000000000001'::uuid,'TEST-RO',1,'A','D1','{"Parts Attached":0,"Parts on Backorder":0,"Backorder with PO (1=Yes, 0=No)":0}'::jsonb,'2026-09-02'::timestamptz,2),
 ('00000000-0000-4000-8000-000000000002'::uuid,'TEST-RO',2,'A','D1','{"Parts Attached":1,"Parts on Backorder":0,"Backorder with PO (1=Yes, 0=No)":0}'::jsonb,'2026-09-01'::timestamptz,3)
 ), latest AS (
 SELECT DISTINCT ON(company,division,repair_order_number,original_line_number) * FROM evidence
 ORDER BY company,division,repair_order_number,original_line_number,created_at DESC,history_id DESC
 ), flags AS (
 SELECT *,public.pdc_numeric_parts_flag_20260911(raw_row->'Parts Attached') a,
 public.pdc_numeric_parts_flag_20260911(raw_row->'Parts on Backorder') b,
 public.pdc_numeric_parts_flag_20260911(raw_row->'Backorder with PO (1=Yes, 0=No)') p FROM latest
 ), jobs AS (
 SELECT company,division,repair_order_number,max(created_at) imported_at,
 CASE WHEN bool_or(a IS NULL OR b IS NULL OR p IS NULL OR (p=1 AND b=0)) THEN public.pdc_parts_flags_status_20260911(NULL,NULL,NULL)
 ELSE public.pdc_parts_flags_status_20260911(max(a),max(b),max(p)) END status,
 max(b) job_backorder,max(p) job_po FROM flags GROUP BY company,division,repair_order_number
 ), ops AS (
 SELECT f.operation_id,CASE WHEN j.status->>'colour'='review' THEN public.pdc_parts_flags_status_20260911(NULL,NULL,NULL) ELSE public.pdc_parts_flags_status_20260911(f.a,j.job_backorder,j.job_po) END||jsonb_build_object(
 'job_label',CASE WHEN j.job_backorder=1 THEN 'Job has outstanding parts' WHEN j.status->>'colour'='review' THEN 'Job parts need review' ELSE 'Job has no recorded backorders' END,
 'last_successful_import_at',f.created_at,'job_number',f.repair_order_number,'line_number',f.original_line_number,
 'company',f.company,'division',f.division) status
 FROM flags f JOIN jobs j USING(company,division,repair_order_number)
 )
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM flags) THEN NULL ELSE jsonb_build_object(
 'jobs',(SELECT jsonb_agg(status||jsonb_build_object('job_number',repair_order_number,'company',company,'division',division,'last_successful_import_at',imported_at)) FROM jobs),
 'operations',(SELECT jsonb_object_agg(operation_id::text,status) FROM ops),
 'last_successful_import_at',(SELECT max(created_at) FROM flags),
 'colour',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'colour' FROM jobs) ELSE 'review' END,
 'label',CASE WHEN (SELECT count(*) FROM jobs)=1 THEN (SELECT status->>'label' FROM jobs) ELSE 'Multiple jobs — review each job parts status' END,
 'meaning','Attached means at least one operation has parts recorded; PO means at least one outstanding part has a PO. Neither proves every required part is available.') END

