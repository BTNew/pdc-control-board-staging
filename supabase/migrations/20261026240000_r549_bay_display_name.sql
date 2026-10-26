-- r549 (F163). PREVIEW. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Craig wants a Hoist bay to read 'Bay 8' on screen. The change is the label only.
-- public.workshop_bays.display_name is the label. id, code, bay_number, ordering and bookings stay.
-- r546 and r547 were undone attempts. #529 is going live as r548 or later.
-- #529 went live as r548 / F162 / sort 324 (ledger 20261026074912).
-- This is r549 / F163 / sort 325. Pin count stays 241. No pinned function is replaced.
-- Undo: supabase/rollbacks/20261026240000_r549_bay_display_name.down.sql
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r549: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r549: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r549: pin count is not 241'; END IF;
 IF pg_catalog.to_regprocedure('public.set_workshop_bay_display_name(uuid,integer,text)') IS NOT NULL THEN RAISE EXCEPTION 'r549: rename function already exists'; END IF;
 IF pg_catalog.to_regprocedure('public.workshop_bay_display_label(uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r549: label resolver already exists'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=325 OR fault_id='F163' OR check_name='bay_display_name_visual_only' OR added_in='r549') THEN RAISE EXCEPTION 'r549: sort 325 / F163 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='unallocated_bay_rechain_548' AND fault_id='F162' AND sort_order=324 AND added_in='r548') THEN RAISE EXCEPTION 'r549: r548 / F162 sort 324 is not the live check'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_bay_default_label(p_stage_name pg_catalog.text, p_bay_number pg_catalog.int4)
 RETURNS pg_catalog.text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO pg_catalog
AS $r549def$
 SELECT pg_catalog.btrim(pg_catalog.coalesce(p_stage_name, '')) || ' - Bay ' || pg_catalog.lpad(p_bay_number::pg_catalog.text, 2, '0');
$r549def$;

CREATE OR REPLACE FUNCTION public.workshop_bay_display_label(p_bay_id pg_catalog.uuid)
 RETURNS pg_catalog.text
 LANGUAGE sql
 STABLE
 SET search_path TO pg_catalog, public
AS $r549label$
 SELECT CASE
   WHEN pg_catalog.btrim(pg_catalog.coalesce(b.display_name, '')) <> '' THEN pg_catalog.btrim(b.display_name)
   ELSE public.workshop_bay_default_label(s.display_name, b.bay_number)
 END
 FROM public.workshop_bays b
 JOIN public.workshop_stages s ON s.id = b.stage_id
 WHERE b.id = p_bay_id;
$r549label$;

CREATE OR REPLACE FUNCTION public.set_workshop_bay_display_name(p_bay_id pg_catalog.uuid, p_expected_version pg_catalog.int4, p_display_name pg_catalog.text)
 RETURNS pg_catalog.jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $r549$
DECLARE
  v_before public.workshop_bays%ROWTYPE;
  v_after public.workshop_bays%ROWTYPE;
  v_name pg_catalog.text := pg_catalog.btrim(pg_catalog.coalesce(p_display_name, ''));
BEGIN
  -- The planner calls a controller an operator. Administrator passes the same gate.
  -- Viewers, fitters and importers do not. Same gate as other controller bay settings.
  PERFORM public.require_pdc_role('operator'::public.pdc_role);
  IF pg_catalog.char_length(v_name) > 40 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'display_name_length');
  END IF;
  SELECT * INTO v_before FROM public.workshop_bays WHERE id = p_bay_id FOR UPDATE;
  IF NOT FOUND THEN RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'not_found'); END IF;
  IF v_name = '' THEN
    SELECT public.workshop_bay_default_label(s.display_name, v_before.bay_number) INTO v_name
      FROM public.workshop_stages s WHERE s.id = v_before.stage_id;
  END IF;
  IF pg_catalog.char_length(v_name) < 1 OR pg_catalog.char_length(v_name) > 40 THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'display_name_length');
  END IF;
  IF v_before.version <> p_expected_version THEN
    IF v_before.display_name = v_name THEN
      RETURN pg_catalog.jsonb_build_object('ok', true, 'idempotent', true, 'bay', pg_catalog.to_jsonb(v_before));
    END IF;
    RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', pg_catalog.to_jsonb(v_before));
  END IF;
  IF v_before.display_name = v_name THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'idempotent', true, 'bay', pg_catalog.to_jsonb(v_before));
  END IF;
  UPDATE public.workshop_bays
     SET display_name = v_name,
         version = version + 1,
         updated_by = auth.uid(),
         updated_at = pg_catalog.now()
   WHERE id = p_bay_id
     AND version = p_expected_version
   RETURNING * INTO v_after;
  IF NOT FOUND THEN RETURN pg_catalog.jsonb_build_object('ok', false, 'error', 'version_conflict'); END IF;
  -- workshop_bays has no display-name history table. The technician history trigger
  -- watches default_technician_id only. The audit row is the history for this change.
  PERFORM public.audit_pdc_event(
    'reference_change'::public.audit_action,
    'workshop_bays',
    v_after.id,
    NULL::pg_catalog.uuid,
    pg_catalog.to_jsonb(v_before),
    pg_catalog.to_jsonb(v_after),
    pg_catalog.jsonb_build_object('action', 'set_workshop_bay_display_name', 'release', 'r549'));
  RETURN pg_catalog.jsonb_build_object('ok', true, 'idempotent', false, 'bay', pg_catalog.to_jsonb(v_after));
END
$r549$;

REVOKE ALL ON FUNCTION public.workshop_bay_default_label(pg_catalog.text, pg_catalog.int4) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.workshop_bay_display_label(pg_catalog.uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_workshop_bay_display_name(pg_catalog.uuid, pg_catalog.int4, pg_catalog.text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.workshop_bay_display_label(pg_catalog.uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_workshop_bay_display_name(pg_catalog.uuid, pg_catalog.int4, pg_catalog.text) TO authenticated;

-- Rolled-back proof used by fault_regression_check. Not granted to the website.
CREATE OR REPLACE FUNCTION public.workshop_bay_display_name_probe_549()
 RETURNS pg_catalog.bool
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $r549probe$
DECLARE
  v_id pg_catalog.uuid := '24b02c9b-e40f-46ba-93ba-37ec37d174ea'::pg_catalog.uuid;
  v_code pg_catalog.text;
  v_number pg_catalog.int4;
  v_name pg_catalog.text;
  v_id_after pg_catalog.uuid;
  v_code_after pg_catalog.text;
  v_number_after pg_catalog.int4;
  v_bookings pg_catalog.int8;
  v_bookings_after pg_catalog.int8;
  v_label pg_catalog.text;
  v_audits pg_catalog.int8;
  v_audits_after pg_catalog.int8;
BEGIN
  SELECT b.id, b.code, b.bay_number, b.display_name,
         (SELECT count(*) FROM public.workshop_bookings w WHERE w.bay_id = b.id),
         (SELECT count(*) FROM public.audit_events a WHERE a.table_name = 'workshop_bays' AND a.row_id = b.id)
    INTO v_id, v_code, v_number, v_name, v_bookings, v_audits
    FROM public.workshop_bays b
   WHERE b.id = v_id;
  IF v_code IS DISTINCT FROM 'HOIST-BAY-02' OR v_number IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'r549 probe: hoist bay 2 changed';
  END IF;
  BEGIN
    UPDATE public.workshop_bays
       SET display_name = 'Bay 8',
           version = version + 1
     WHERE id = v_id
       AND code = 'HOIST-BAY-02'
       AND bay_number = 2;
    SELECT b.id, b.code, b.bay_number,
           (SELECT count(*) FROM public.workshop_bookings w WHERE w.bay_id = b.id),
           public.workshop_bay_display_label(b.id),
           (SELECT count(*) FROM public.audit_events a WHERE a.table_name = 'workshop_bays' AND a.row_id = b.id)
      INTO v_id_after, v_code_after, v_number_after, v_bookings_after, v_label, v_audits_after
      FROM public.workshop_bays b
     WHERE b.id = v_id;
    IF v_id_after IS DISTINCT FROM v_id
       OR v_code_after IS DISTINCT FROM v_code
       OR v_number_after IS DISTINCT FROM v_number
       OR v_bookings_after IS DISTINCT FROM v_bookings
       OR v_label IS DISTINCT FROM 'Bay 8'
       OR v_audits_after IS DISTINCT FROM v_audits THEN
      RAISE EXCEPTION 'r549 probe failed' USING ERRCODE = 'P0001';
    END IF;
    PERFORM public.audit_pdc_event(
      'reference_change'::public.audit_action,
      'workshop_bays',
      v_id,
      NULL::pg_catalog.uuid,
      pg_catalog.jsonb_build_object('display_name', v_name),
      pg_catalog.jsonb_build_object('display_name', 'Bay 8'),
      pg_catalog.jsonb_build_object('action', 'set_workshop_bay_display_name', 'release', 'r549', 'probe', true));
    IF (SELECT count(*) FROM public.audit_events a WHERE a.table_name = 'workshop_bays' AND a.row_id = v_id) <> v_audits + 1 THEN
      RAISE EXCEPTION 'r549 probe audit missing' USING ERRCODE = 'P0001';
    END IF;
    RAISE EXCEPTION 'r549 probe rollback' USING ERRCODE = 'P0001';
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM IS DISTINCT FROM 'r549 probe rollback' THEN
        RAISE;
      END IF;
  END;
  IF (SELECT b.display_name FROM public.workshop_bays b WHERE b.id = v_id) IS DISTINCT FROM v_name
     OR (SELECT count(*) FROM public.workshop_bookings w WHERE w.bay_id = v_id) IS DISTINCT FROM v_bookings
     OR (SELECT count(*) FROM public.audit_events a WHERE a.table_name = 'workshop_bays' AND a.row_id = v_id) IS DISTINCT FROM v_audits THEN
    RAISE EXCEPTION 'r549 probe did not roll back';
  END IF;
  RETURN true;
END
$r549probe$;

REVOKE ALL ON FUNCTION public.workshop_bay_display_name_probe_549() FROM PUBLIC;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
 ('bay_display_name_visual_only', 'F163',
  'Renaming a bay inside a rolled-back test leaves the id, code, bay_number and booking count unchanged. The label resolver returns the new name. The rename function updates display_name only and uses the controller role.',
 $c549$
SELECT
 public.workshop_bay_display_name_probe_549()
 AND pg_catalog.strpos(fn.prosrc, 'require_pdc_role(''operator''::public.pdc_role)') > 0
 AND pg_catalog.strpos(fn.prosrc, 'set display_name = v_name') > 0
 AND pg_catalog.strpos(fn.prosrc, 'audit_pdc_event') > 0
 AND pg_catalog.strpos(fn.prosrc, 'set code') = 0
 AND pg_catalog.strpos(fn.prosrc, 'bay_number =') = 0
 AND fn.prosecdef
 AND pg_catalog.strpos(pg_catalog.array_to_string(fn.proconfig, ','), 'search_path=pg_catalog, public') > 0
 AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'bay display name is visual only' AS detail
 FROM pg_catalog.pg_proc fn
 WHERE fn.oid = pg_catalog.to_regprocedure('public.set_workshop_bay_display_name(uuid,integer,text)')
$c549$,
 true, 325, 'r549');

DO $p$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r549: pin count changed'; END IF;
 IF pg_catalog.to_regprocedure('public.set_workshop_bay_display_name(uuid,integer,text)') IS NULL THEN RAISE EXCEPTION 'r549: rename function missing'; END IF;
 IF NOT public.workshop_bay_display_name_probe_549() THEN RAISE EXCEPTION 'r549: visual-only probe failed'; END IF;
END $p$;
