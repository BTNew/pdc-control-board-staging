-- Add two Navision upload scopes. Leading zeros are part of their identity.
-- Existing account permissions, actor dealer scopes and import protections are preserved.
SET lock_timeout = '10s';
DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.navision_canonical_dealer_code(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE
SET search_path = pg_catalog
AS $code$
 SELECT CASE regexp_replace(btrim(coalesce(p_value,'')),'^0+','')
   WHEN '2345' THEN '002345'
   WHEN '1234' THEN '001234'
   ELSE regexp_replace(btrim(coalesce(p_value,'')),'^0+','') END
$code$;
REVOKE ALL ON FUNCTION public.navision_canonical_dealer_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.navision_canonical_dealer_code(text) TO authenticated, service_role;

-- Patch only the reviewed import/read functions, keeping their ACLs and all
-- revision, identity, first-snapshot approval and atomic-save checks intact.
DO $patch$
DECLARE target record; replacement record; definition text; occurrences integer;
BEGIN
 FOR target IN SELECT * FROM jsonb_to_recordset($targets$[{"name":"apply_navision_backend_import","sig":"public.apply_navision_backend_import(text,jsonb,text,text,text,timestamp with time zone,text,text,bigint)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1}]},{"name":"approve_navision_initial_scope","sig":"public.approve_navision_initial_scope(jsonb,text,text)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1},{"old":"regexp_replace(btrim(coalesce(p_dealer_code,'')),'^0+','')","value":"public.navision_canonical_dealer_code(p_dealer_code)","count":1}]},{"name":"navision_backend_preview_internal","sig":"public.navision_backend_preview_internal(jsonb,text,text,text,timestamp with time zone)","pairs":[{"old":"'14450', '37047'","value":"'14450', '37047','002345','001234'","count":1}]},{"name":"navision_import_candidate_preflight_770","sig":"public.navision_import_candidate_preflight_770(jsonb,text,text)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1}]},{"name":"get_navision_backend_snapshot","sig":"public.get_navision_backend_snapshot(text,text,text,uuid,integer,bigint)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1}]},{"name":"get_navision_visible_snapshot_pre_82000","sig":"public.get_navision_visible_snapshot_pre_82000(text,text,uuid,integer,bigint)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1}]},{"name":"get_pdc_navision_retention_readback_20260903","sig":"public.get_pdc_navision_retention_readback_20260903(text,text,uuid)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1}]},{"name":"navision_scope_rows_for_selected_dealer","sig":"public.navision_scope_rows_for_selected_dealer(jsonb,text,text)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":3},{"old":"regexp_replace(btrim(coalesce(p_dealer_code,'')),'^0+','')","value":"public.navision_canonical_dealer_code(p_dealer_code)","count":1}]},{"name":"navision_row_declared_dealer_code","sig":"public.navision_row_declared_dealer_code(jsonb)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1},{"old":"regexp_replace(source_value,'^0+','')","value":"public.navision_canonical_dealer_code(source_value)","count":3}]},{"name":"navision_import_safety_assessment","sig":"public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1},{"old":"regexp_replace(btrim(coalesce(p_dealer_code,'')),'^0+','')","value":"public.navision_canonical_dealer_code(p_dealer_code)","count":1}]},{"name":"navision_import_safety_assessment_pre079","sig":"public.navision_import_safety_assessment_pre079(jsonb,text,text,text,jsonb)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1},{"old":"regexp_replace(btrim(coalesce(p_dealer_code,'')), '^0+', '')","value":"public.navision_canonical_dealer_code(p_dealer_code)","count":1}]},{"name":"navision_import_safety_assessment_pre072","sig":"public.navision_import_safety_assessment_pre072(jsonb,text,text,text,jsonb)","pairs":[{"old":"'14450', '37047'","value":"'14450', '37047','002345','001234'","count":1},{"old":"  v_filename_scope_match :=\n    (v_dealer_code = '14450' and v_source_name ~ '(^|[^0-9])14450([^0-9]|$)')\n    or (v_dealer_code = '37047' and v_source_name ~ '(^|[^0-9])37047([^0-9]|$)');\n\n  -- A filename containing the other known dealer code is direct contrary scope evidence.\n  v_filename_scope_mismatch :=\n    (v_dealer_code = '14450' and v_source_name ~ '(^|[^0-9])37047([^0-9]|$)')\n    or (v_dealer_code = '37047' and v_source_name ~ '(^|[^0-9])14450([^0-9]|$)');\n\n","value":"  v_filename_scope_match := v_source_name ~ ('(^|[^0-9])' || v_dealer_code || '([^0-9]|$)');\n  -- Reject a filename explicitly naming another supported dealer.\n  v_filename_scope_mismatch := EXISTS (\n    SELECT 1 FROM unnest(ARRAY['14450','37047','002345','001234']) code\n    WHERE code <> v_dealer_code AND v_source_name ~ ('(^|[^0-9])' || code || '([^0-9]|$)')\n  );\n\n","count":1}]},{"name":"pdc_lifecycle_history_latch_82000","sig":"public.pdc_lifecycle_history_latch_82000(uuid,text,timestamp with time zone,text,text,jsonb)","pairs":[{"old":"'14450','37047'","value":"'14450','37047','002345','001234'","count":1}]}]$targets$::jsonb) AS t(name text,sig text,pairs jsonb)
 LOOP
   definition:=pg_get_functiondef(target.sig::regprocedure);
   FOR replacement IN SELECT * FROM jsonb_to_recordset(target.pairs) AS p(old text,value text,count integer)
   LOOP
     occurrences:=(length(definition)-length(replace(definition,replacement.old,'')))/length(replacement.old);
     IF occurrences<>replacement.count THEN RAISE EXCEPTION 'Unexpected definition for %',target.sig; END IF;
     definition:=replace(definition,replacement.old,replacement.value);
   END LOOP;
   EXECUTE definition;
 END LOOP;
END $patch$;

ALTER TABLE public.navision_initial_scope_approvals DROP CONSTRAINT navision_initial_scope_approvals_dealer_code_check;
ALTER TABLE public.navision_initial_scope_approvals ADD CONSTRAINT navision_initial_scope_approvals_dealer_code_check CHECK ((dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text])));
ALTER TABLE public.navision_import_batches DROP CONSTRAINT navision_import_batches_dealer_code_check;
ALTER TABLE public.navision_import_batches ADD CONSTRAINT navision_import_batches_dealer_code_check CHECK ((dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text, 'LEGACY_UNSCOPED'::text])));
ALTER TABLE public.navision_backend_records DROP CONSTRAINT navision_backend_records_dealer_code_check;
ALTER TABLE public.navision_backend_records ADD CONSTRAINT navision_backend_records_dealer_code_check CHECK ((dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text, 'LEGACY_UNSCOPED'::text])));
ALTER TABLE public.pdc_navision_applicable_updates_20260903 DROP CONSTRAINT pdc_navision_applicable_updates_20260903_dealer_code_check;
ALTER TABLE public.pdc_navision_applicable_updates_20260903 ADD CONSTRAINT pdc_navision_applicable_updates_20260903_dealer_code_check CHECK ((dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text])));
ALTER TABLE public.pdc_navision_retention_observations_20260903 DROP CONSTRAINT pdc_navision_retention_observations_20260903_dealer_code_check;
ALTER TABLE public.pdc_navision_retention_observations_20260903 ADD CONSTRAINT pdc_navision_retention_observations_20260903_dealer_code_check CHECK ((dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text])));
ALTER TABLE public.pdc_vehicle_lifecycle_history_events_82000 DROP CONSTRAINT pdc_vehicle_lifecycle_history_events_82000_dealer_code_check;
ALTER TABLE public.pdc_vehicle_lifecycle_history_events_82000 ADD CONSTRAINT pdc_vehicle_lifecycle_history_events_82000_dealer_code_check CHECK (((dealer_code IS NULL) OR (dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text]))));
ALTER TABLE public.pdc_navision_retention_canonical_observations_20260903 DROP CONSTRAINT pdc_navision_retention_canonical_observations_dealer_code_check;
ALTER TABLE public.pdc_navision_retention_canonical_observations_20260903 ADD CONSTRAINT pdc_navision_retention_canonical_observations_dealer_code_check CHECK ((dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text])));
ALTER TABLE public.pdc_navision_retention_reconciliation_receipts_20260903 DROP CONSTRAINT pdc_navision_retention_reconciliation_receipt_dealer_code_check;
ALTER TABLE public.pdc_navision_retention_reconciliation_receipts_20260903 ADD CONSTRAINT pdc_navision_retention_reconciliation_receipt_dealer_code_check CHECK ((dealer_code = ANY (ARRAY['14450'::text, '37047'::text, '002345'::text, '001234'::text])));
