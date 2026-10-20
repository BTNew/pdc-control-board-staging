-- r400 QC sign-off: Pit inspection and job-card notes no longer block QC (Bhavesh, Key 208 / 13017935, 19:04 AWST 20 Oct 2026).
-- Staging cdsmnqxtyyoeoznmbidd only.
-- Cause: the 15-16 Oct job-card category rule gives Dept 138 "PIT AND WEIGH" stage PIT_INSPECTION and
-- notes stage JOB_CARD_NOTES. QC's "not checkable" rule (r10700) only knew Pit lines from the old email
-- source (work_key pitinspection). These lines were therefore required for sign-off but can never be
-- ticked (pdc_qc_operation_completions_379 stage check), so sign-off was impossible.
-- Fix: one helper decides "QC cannot tick this line" (Pit inspection, job-card notes, old email Pit) and
-- both the tick guard and the checkable list use it. Pit stays on the job (Bus Pit list) after QC.
DO $g$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r400: staging cdsmnqxtyyoeoznmbidd only'; END IF;
 IF to_regprocedure('public.pdc_qc_line_not_checkable_400(uuid,jsonb)') IS NOT NULL THEN RAISE EXCEPTION 'r400: already applied'; END IF;
 IF to_regnamespace('pdc_ops') IS NULL THEN RAISE EXCEPTION 'r400: needs r399 pdc_ops'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)'::regprocedure)<>'1eb0c057769f8107e6c6d6f8adce87a6'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_checkable_operation_lines_10700(uuid)'::regprocedure)<>'60b9186e12175da61df9857e79fa8f46'
  THEN RAISE EXCEPTION 'r400: before md5 mismatch'; END IF;
END $g$;

CREATE FUNCTION public.pdc_qc_line_not_checkable_400(p_vehicle_id uuid, p_line jsonb)
 RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $r400h$
  -- r400: lines QC cannot tick. Pit inspection is the external Department of
  -- Transport check after QC; job-card notes are information only. Both were
  -- missed for job-card category lines (stage_code), so they blocked sign-off.
  SELECT upper(btrim(coalesce(p_line->>'stage_code',''))) IN ('PIT_INSPECTION','JOB_CARD_NOTES')
  OR EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line->>'line_identity','')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$r400h$;
ALTER FUNCTION public.pdc_qc_line_not_checkable_400(uuid,jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.pdc_qc_line_not_checkable_400(uuid,jsonb) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_line_is_deferred_pit_10700(p_vehicle_id uuid, p_line_identity text)
 RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $r400d$
  SELECT EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line_identity,'')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  ) OR EXISTS(
    SELECT 1
    FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
    WHERE l->>'line_identity'=lower(btrim(coalesce(p_line_identity,'')))
      AND public.pdc_qc_line_not_checkable_400(p_vehicle_id,l)
  )
$r400d$;

CREATE OR REPLACE FUNCTION public.pdc_qc_checkable_operation_lines_10700(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $r400c$
  SELECT coalesce(jsonb_agg(line ORDER BY ordinal),'[]'::jsonb)
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY projected(line,ordinal)
  WHERE NOT public.pdc_qc_line_not_checkable_400(p_vehicle_id,line)
$r400c$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.pdc_qc_line_not_checkable_400(uuid,jsonb)','eac292a1d85506a02a6b5143d979a632','r400','QC cannot tick Pit inspection / job-card notes'),
 ('public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)','f5981a43eeee9ddb3e029fe1f8f6a0bf','r400','tick guard: Pit / notes refused with PDC_10700_DEFERRED_PIT_NOT_CHECKABLE'),
 ('public.pdc_qc_checkable_operation_lines_10700(uuid)','3b2995e11939cd2dbcd4edf2fdd307d0','r400','QC checklist used by sign-off, reject, rework and RFT')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now() WHERE true;
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('qc_checklist_has_only_tickable_lines','F09','No open QC checklist line has a stage QC cannot tick (Pit inspection, job-card notes, or any future stage missing from the QC tick table)',$c$WITH veh AS (
  SELECT v.id FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.lifecycle_state='active' AND upper(btrim(coalesce(v.current_location,''))) IN ('QC','PMB','IT','YH','OTHER')
), allowed AS (
  SELECT array_agg(m[1]) a FROM pg_catalog.pg_constraint c, regexp_matches(pg_catalog.pg_get_constraintdef(c.oid),'''([A-Z0-9_]+)''','g') m
  WHERE c.conrelid='public.pdc_qc_operation_completions_379'::regclass AND c.conname='pdc_qc_operation_completions_379_stage_code_check'
), bad AS (
  SELECT veh.id, l->>'stage_code' st
  FROM veh CROSS JOIN allowed
  CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(veh.id)) l
  WHERE coalesce((l->>'active')::boolean,false) AND NOT coalesce((l->>'completed')::boolean,false)
    AND coalesce(l->>'stage_code','') <> 'UNALLOCATED_MAPPING_REVIEW'
    AND NOT (coalesce(l->>'stage_code','') = ANY(allowed.a))
), wiring AS (
  SELECT position('is_deferred_pit_10700' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure))>0
     AND position('checkable_operation_lines_10700' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure))>0
     AND public.pdc_qc_line_not_checkable_400(NULL,'{"stage_code":"PIT_INSPECTION"}'::jsonb)
     AND public.pdc_qc_line_not_checkable_400(NULL,'{"stage_code":"JOB_CARD_NOTES"}'::jsonb)
     AND NOT public.pdc_qc_line_not_checkable_400(NULL,'{"stage_code":"BUS_4X4"}'::jsonb) AS w
)
SELECT (SELECT count(*) FROM bad)=0 AND (SELECT a FROM allowed) IS NOT NULL AND (SELECT w FROM wiring) AS ok,
  format('%s open QC checklist lines on %s vehicles have a stage QC cannot tick%s; Pit/notes rule wired: %s',
    (SELECT count(*) FROM bad),(SELECT count(DISTINCT id) FROM bad),
    coalesce(' ('||(SELECT string_agg(DISTINCT st,', ') FROM bad)||')',''),(SELECT w FROM wiring)) AS detail$c$,true,170,'r400');

DO $p$
DECLARE want jsonb:='{"public.pdc_qc_line_not_checkable_400(uuid,jsonb)": "eac292a1d85506a02a6b5143d979a632", "public.pdc_qc_operation_line_is_deferred_pit_10700(uuid,text)": "f5981a43eeee9ddb3e029fe1f8f6a0bf", "public.pdc_qc_checkable_operation_lines_10700(uuid)": "3b2995e11939cd2dbcd4edf2fdd307d0"}'::jsonb; k text;
BEGIN
 FOR k IN SELECT jsonb_object_keys(want) LOOP
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=k::regprocedure)<>want->>k THEN RAISE EXCEPTION 'r400: post md5 mismatch %',k; END IF;
 END LOOP;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r400: helper ACL %',(SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure); END IF;
END $p$;
