-- r591 (F205) / sort 362. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Admin Upload preview. The parser lives in the edge function. This migration does not import a report.
-- Kajel's rows function 9be0883b1a555f48f3c1ba9fa111c891 and apply function b62fb7c29ffd2a1629f214f696e5cb14 stay byte-identical.
-- r588 / F202 / sort 360 is the hoist preview (PR #572). r589 / F203 / sort 361 is the Parts ETA preview (PR #571).
-- r590 / F204 is the QC sign-off preview. This release takes the next free triple: r591 / F205 / sort 362.
-- Pin count stays 241. No new pin. Department 135 stays fd05b9eef69498002ac06dd68e01cdff.
-- Apply stays refused until Craig approves go-live. The seen table is created empty and nothing in this migration writes a row to it.
-- Undo: supabase/rollbacks/20261028080000_r591_revolution_upload.down.sql
SET LOCAL lock_timeout = '8s';
DO $g$
DECLARE
  awst time;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '12:20' AND time '12:40'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r591: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r591: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r591: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r591: pin count is not 241'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=359 AND fault_id='F201' AND check_name='board_qc_nesting_587' AND added_in='r587') THEN RAISE EXCEPTION 'r591: r587 is not in the ledger'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=362 OR fault_id='F205' OR check_name='revolution_upload_591' OR added_in='r591') THEN RAISE EXCEPTION 'r591: sort 362 / F205 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r591: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r591: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r591: department 135 changed'; END IF;
  IF to_regprocedure('public.pdc_revolution_upload_gate_591(integer,integer,boolean,text)') IS NOT NULL THEN RAISE EXCEPTION 'r591: gate already exists'; END IF;
END $g$;

CREATE TABLE pdc_codex_intake_private.revolution_upload_seen (
  sha256 text PRIMARY KEY,
  md5 text NOT NULL,
  filename text,
  report_kind text,
  uploader text,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_codex_intake_private.revolution_upload_seen ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_codex_intake_private.revolution_upload_seen FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_codex_intake_private.revolution_upload_apply_591(p_batch uuid, p_actor text, p_file_sha text)
RETURNS jsonb
LANGUAGE plpgsql
AS $apply$
BEGIN
  RAISE EXCEPTION 'Craig has not approved go-live. Sales boards 37047 and 14450 are not changed by the PMB archive rule. Status 99 is skipped. A vehicle with an open job card is not archived.';
END;
$apply$;

REVOKE ALL ON FUNCTION pdc_codex_intake_private.revolution_upload_apply_591(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.pdc_revolution_upload_gate_591(p_new integer, p_archived integer, p_confirm boolean, p_sha text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pdc_codex_intake_private, pdc_ops, pg_catalog, public
AS $gate$
  SELECT jsonb_build_object(
    'apply_enabled', false,
    'reason', 'Craig has not approved go-live',
    'needs_admin_confirm', coalesce(p_new, 0) > 15 OR coalesce(p_archived, 0) > 15,
    'admin_confirm', coalesce(p_confirm, false),
    'duplicate_file', EXISTS (
      SELECT 1 FROM pdc_codex_intake_private.revolution_upload_seen s
      WHERE s.sha256 = lower(coalesce(p_sha, ''))
    ),
    'pins_ok',
      (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
      AND (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) = '9be0883b1a555f48f3c1ba9fa111c891'
      AND (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) = 'b62fb7c29ffd2a1629f214f696e5cb14'
      AND (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff',
    'status_99', 'skipped',
    'sales_boards_left_alone', jsonb_build_array('37047', '14450'),
    'open_job_card', 'not archived'
  );
$gate$;

REVOKE ALL ON FUNCTION public.pdc_revolution_upload_gate_591(integer, integer, boolean, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_revolution_upload_gate_591(integer, integer, boolean, text) TO service_role;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('revolution_upload_591', 'F205', 'Revolution upload stays a dry run. Kajel rows and apply stay pinned. Status 99 is skipped, sales boards 37047 and 14450 stay out of the PMB archive rule, and an open job card is not archived.',
$chk591$SELECT
  (quiet.payload->>'apply_enabled') = 'false'
  AND (quiet.payload->>'reason') = 'Craig has not approved go-live'
  AND (quiet.payload->>'pins_ok') = 'true'
  AND (quiet.payload->>'duplicate_file') = 'false'
  AND (loud.payload->>'needs_admin_confirm') = 'true'
  AND (loud.payload->>'apply_enabled') = 'false'
  AND position('Craig has not approved go-live' IN apply.prosrc) > 0
  AND position('37047' IN apply.prosrc) > 0
  AND position('14450' IN apply.prosrc) > 0
  AND position('Status 99' IN apply.prosrc) > 0
  AND position('open job card' IN apply.prosrc) > 0
  AND gate.provolatile = 's'
  AND rows_fn.md5 = '9be0883b1a555f48f3c1ba9fa111c891'
  AND apply_fn.md5 = 'b62fb7c29ffd2a1629f214f696e5cb14'
  AND dept.md5 = 'fd05b9eef69498002ac06dd68e01cdff'
  AND NOT EXISTS (
    SELECT 1 FROM pdc_ops.expected_function_md5 pin
    WHERE pin.signature LIKE '%revolution_upload%'
  )
 AS ok,
 'Revolution upload gate is a dry run' AS detail
 FROM (SELECT public.pdc_revolution_upload_gate_591(0, 0, false, 'abc') AS payload) quiet
 CROSS JOIN (SELECT public.pdc_revolution_upload_gate_591(16, 0, false, 'abc') AS payload) loud
 CROSS JOIN (
  SELECT p.prosrc FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_upload_apply_591(uuid,text,text)')
 ) apply
 CROSS JOIN (
  SELECT p.provolatile FROM pg_catalog.pg_proc p
  WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_revolution_upload_gate_591(integer,integer,boolean,text)')
 ) gate
 CROSS JOIN (SELECT md5(p.prosrc) AS md5 FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) rows_fn
 CROSS JOIN (SELECT md5(p.prosrc) AS md5 FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) apply_fn
 CROSS JOIN (SELECT md5(p.prosrc) AS md5 FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) dept
$chk591$,
true, 362, 'r591');

DO $p$
BEGIN
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='revolution_upload_591' AND fault_id='F205' AND sort_order=362 AND added_in='r591' AND enabled)<>1 THEN RAISE EXCEPTION 'r591: check missing'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r591: pin count changed'; END IF;
  IF (SELECT count(*) FROM pdc_codex_intake_private.revolution_upload_seen)<>0 THEN RAISE EXCEPTION 'r591: the ledger was not created empty'; END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid=to_regprocedure('public.pdc_revolution_upload_gate_591(integer,integer,boolean,text)')) IS DISTINCT FROM 's' THEN RAISE EXCEPTION 'r591: gate is not stable'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)')) IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'r591: Kajel rows changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)')) IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN RAISE EXCEPTION 'r591: Kajel apply changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r591: department 135 changed'; END IF;
  IF position('Craig has not approved go-live' IN (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_upload_apply_591(uuid,text,text)'))) = 0 THEN RAISE EXCEPTION 'r591: apply does not refuse go-live'; END IF;
END $p$;
