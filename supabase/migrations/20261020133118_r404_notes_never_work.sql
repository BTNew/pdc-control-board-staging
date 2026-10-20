-- r404 (F13) Job-card notes lines are never re-filed as work. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig's rule (r400): notes lines never block QC. A line the routing table files as JOB_CARD_NOTES used to stay
-- on a work stage (BUS_4X4, SUBLET, ...) once anything on the vehicle "preserved" routing: a completed work item for
-- that stage (e.g. the bus4x4 line ticked), a stage booking, a source baseline or an automatic lock. It then sat on
-- the QC checklist and blocked sign-off (Key 340). Decision 20 Oct 21:18 AWST: the 18 Oct automatic SUBLET locks give
-- way; manual_operator locks, QC-ticked lines, owner overrides/reviews and non-active vehicles stay as they are.
-- 1. pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb): when a notes line must route as notes.
-- 2. public.pdc_qc_operation_lines_379_uncached: preserve flag is ANDed with NOT job_card_note_forced_404.
-- 3. Cached QC lines that now differ are invalidated (epoch bump + delete); the 20 s cron refills them.
-- 4. Pins and check notes_lines_never_on_qc_checklist (F13).
DO $g$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r404: staging cdsmnqxtyyoeoznmbidd only'; END IF;
END $g$;
DO $b$
BEGIN
 IF to_regprocedure('pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r404: already applied'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure)<>'b677d7bfdf67c046fd05922da249325c' THEN RAISE EXCEPTION 'r404: uncached before md5 mismatch'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r404: fault_regression_check md5 mismatch'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='notes_lines_never_on_qc_checklist') THEN RAISE EXCEPTION 'r404: check exists'; END IF;
END $b$;

CREATE FUNCTION pdc_work_categories_private.job_card_note_forced_404(p_vehicle_id uuid, l jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog'
AS $r404h$
 -- r404 (F13): true when the curated routing table files this line as JOB_CARD_NOTES and nothing a person
 -- decided should keep it as work. Notes are information only and never block QC (Craig, r400).
 -- Kept as they are: QC-ticked, rejected or inactive lines; owner overrides (category_version>0) and owner
 -- reviews; manual_operator locks; vehicles that are not active (completed or RFT history is not rewritten).
 -- Automatic locks (ai_auditor, no origin), source baselines, completed work items and stage bookings
 -- no longer freeze a notes line onto a work stage.
 SELECT coalesce((l->>'active')::boolean,true)
  AND NOT coalesce((l->>'completed')::boolean,false)
  AND NOT coalesce((l->>'rejected')::boolean,false)
  AND coalesce((l->>'category_version')::integer,0)=0
  AND EXISTS(SELECT 1 FROM public.vehicles v
   WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active')
  AND EXISTS(SELECT 1 FROM pdc_operation_updates_private.ai_routing_20261019 r
   WHERE r.department=l->>'department' AND r.category='JOB_CARD_NOTES'
    AND r.description_hash=pdc_work_categories_private.import_description_hash_20261017(l->>'description'))
  AND NOT EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments a
   WHERE a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
    AND a.manual_assignment_locked AND a.correction_origin='manual_operator')
  AND NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.owner_line_reviews o
   WHERE o.vehicle_id=p_vehicle_id AND o.line_identity=l->>'line_identity')
$r404h$;
ALTER FUNCTION pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379_uncached(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $r404u$
 WITH source AS MATERIALIZED(
  SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id)) WITH ORDINALITY x(l,ord)
 ), routed AS(
 SELECT ord,pdc_work_categories_private.route_import_line_20261017(
  CASE WHEN a.manual_assignment_locked IS FALSE AND a.correction_origin='job_card_source_correction'
   THEN l||jsonb_build_object('estimated_hours',a.estimated_hours,
    'zero_hour_task',a.estimated_hours=0 AND EXISTS(SELECT 1 FROM pdc_work_categories_private.import_rules_20261017 r
     WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(l->>'description') AND r.category='BUS_QA'))
   ELSE l END,
  -- r404 (F13): a job-card notes line is never preserved as work; see job_card_note_forced_404.
  (h.source_signature=pdc_work_categories_private.source_signature(l)
  OR coalesce((l->>'category_version')::integer,0)>0
  OR coalesce(a.manual_assignment_locked,false)
  OR EXISTS(SELECT 1 FROM pdc_work_categories_private.owner_line_reviews r
   WHERE r.vehicle_id=p_vehicle_id AND r.line_identity=l->>'line_identity'
   AND r.source_signature=pdc_work_categories_private.source_signature(l))
  OR EXISTS(SELECT 1 FROM public.vehicle_work_items w JOIN public.workshop_stages s ON s.work_key=w.work_key
   WHERE w.vehicle_id=p_vehicle_id AND w.completed AND s.code=l->>'stage_code')
  OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
    AND ((b.work_category IS NOT NULL AND b.work_category_scope ? (l->>'line_identity'))
     OR (b.work_category IS NULL AND s.code=l->>'stage_code'
      AND NOT (a.manual_assignment_locked IS FALSE AND a.correction_origin='job_card_source_correction' AND EXISTS(
       SELECT 1 FROM public.pdc_tune_operation_change_reviews q
       WHERE q.vehicle_id=p_vehicle_id AND 'source:'||q.source_operation_id::text=l->>'line_identity'
        AND q.change_kind='added' AND q.status='approved' AND q.approved_at>b.created_at))))))
  AND NOT pdc_work_categories_private.job_card_note_forced_404(p_vehicle_id,l)
 ) l
 FROM source
 LEFT JOIN pdc_work_categories_private.import_baseline_20261017 h ON h.vehicle_id=p_vehicle_id AND h.line_identity=l->>'line_identity'
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
 ) SELECT coalesce(jsonb_agg(l ORDER BY ord),'[]'::jsonb) FROM routed
$r404u$;

-- Invalidate exactly the cached QC line sets that the change alters; the cron refill recomputes them.
DO $c$
DECLARE ids uuid[];
BEGIN
 SELECT coalesce(array_agg(c.vehicle_id ORDER BY c.vehicle_id),ARRAY[]::uuid[]) INTO ids
 FROM pdc_work_categories_private.qc_operation_lines_cache c
 WHERE c.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379_uncached(c.vehicle_id);
 PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ids,false);
 DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = ANY(ids);
 RAISE NOTICE 'r404: % cached QC line sets invalidated', cardinality(ids);
END $c$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb)','cfe0fd4c29d9eaf82c06ed1d0ffdd541','r404','Job-card notes line routes as notes unless a person kept it as work'),
 ('public.pdc_qc_operation_lines_379_uncached(uuid)','97fc4caaf7b462163d35b4a3511bc487','r404','QC lines; notes never preserved as work (F13)')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now() WHERE true;
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('notes_lines_never_on_qc_checklist','F13','No unticked job-card notes line (routing table JOB_CARD_NOTES) is on an active vehicle''s QC checklist, unless a manual_operator lock, owner override or owner review keeps it as work; QC lines are wired through job_card_note_forced_404 (r404).',$c404$WITH notes AS (
  SELECT department, description_hash FROM pdc_operation_updates_private.ai_routing_20261019 WHERE category='JOB_CARD_NOTES'
), v AS (
  SELECT x.id FROM public.vehicles x WHERE x.deleted_at IS NULL AND x.lifecycle_state='active'
), bad AS (
  SELECT v.id, q.line
  FROM v CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(v.id)) q(line)
  JOIN notes n ON n.department=q.line->>'department'
   AND n.description_hash=pdc_work_categories_private.import_description_hash_20261017(q.line->>'description')
  WHERE coalesce((q.line->>'active')::boolean,true)
    AND NOT coalesce((q.line->>'completed')::boolean,false)
    AND coalesce((q.line->>'category_version')::integer,0)=0
    AND NOT EXISTS (SELECT 1 FROM public.vehicle_workshop_line_adjustments a
      WHERE a.vehicle_id=v.id AND a.line_key=q.line->>'line_identity' AND a.manual_assignment_locked AND a.correction_origin='manual_operator')
    AND NOT EXISTS (SELECT 1 FROM pdc_work_categories_private.owner_line_reviews o
      WHERE o.vehicle_id=v.id AND o.line_identity=q.line->>'line_identity')
), w AS (
  SELECT position('job_card_note_forced_404' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure))>0 AS wired
)
SELECT (SELECT count(*) FROM bad)=0 AND w.wired AS ok,
  CASE WHEN (SELECT count(*) FROM bad)=0 THEN 'no unticked job-card notes line is on an active vehicle''s QC checklist'
  ELSE (SELECT count(*) FROM bad)||' unticked job-card notes line(s) on QC checklists, '||(SELECT count(DISTINCT id) FROM bad)||' vehicle(s); stages: '
    ||(SELECT string_agg(DISTINCT coalesce(line->>'stage_code','?'),', ') FROM bad) END
  ||'; routing wired '||w.wired AS detail
FROM w$c404$,true,185,'r404');

DO $p$
DECLARE r record;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb)'::regprocedure)<>'cfe0fd4c29d9eaf82c06ed1d0ffdd541' THEN RAISE EXCEPTION 'r404: helper md5'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure)<>'97fc4caaf7b462163d35b4a3511bc487' THEN RAISE EXCEPTION 'r404: uncached md5'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='pdc_work_categories_private.job_card_note_forced_404(uuid,jsonb)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r404: helper ACL'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r404: uncached ACL'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='notes_lines_never_on_qc_checklist')<>'1e4b22a822531ba2c4b90668e8202c01' THEN RAISE EXCEPTION 'r404: check md5'; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='notes_lines_never_on_qc_checklist') INTO r;
 IF r.ok IS NOT TRUE THEN RAISE EXCEPTION 'r404: new check not ok: %',r.detail; END IF;
END $p$;
