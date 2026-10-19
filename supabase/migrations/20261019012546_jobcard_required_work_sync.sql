-- Canonical jobcard work must not disappear when the materialized requirements are missing.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR NOT pdc_codex_intake_private.management_connection()
 OR auth.uid() IS NOT NULL OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5(pg_get_functiondef('public.pdc_qc_gate_issues(uuid)'::regprocedure))<>'ed193a89b12ace92a32b7cfa36221a41'
 THEN RAISE EXCEPTION 'reviewed_qc_gate_changed'; END IF;
END $guard$;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
RETURNS integer LANGUAGE plpgsql SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE changed integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'staging_required'; END IF;
 -- Existing deferred mutation paths explicitly reconcile their accepted changes.
 IF current_setting('pdc.defer_workshop_required_work_reconcile',true)='407' THEN RETURN 0; END IF;
 PERFORM 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL
  AND v.lifecycle_state='active' AND v.visible_on_board AND v.qc_completed_at IS NULL
  AND upper(coalesce(v.current_location,'')) NOT IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='approved')
  AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.department IN('138','139')) FOR UPDATE;
 IF NOT FOUND THEN RETURN 0; END IF;
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 SELECT DISTINCT p_vehicle_id,s.work_key,true,false,'Required by canonical imported jobcard work'
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','PIT_INSPECTION')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.sync_source_requirements_20261019()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE vid uuid;
BEGIN
 FOR vid IN SELECT DISTINCT vehicle_id FROM inserted_operations WHERE department IN('138','139') AND vehicle_id IS NOT NULL ORDER BY vehicle_id LOOP
  PERFORM pdc_operation_updates_private.ensure_required_work_20261019(vid);
 END LOOP;
 RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.sync_source_requirements_20261019() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER pdc_source_required_work_20261019 AFTER INSERT ON public.pdc_pilbara_service_operations
 REFERENCING NEW TABLE AS inserted_operations FOR EACH STATEMENT EXECUTE FUNCTION pdc_operation_updates_private.sync_source_requirements_20261019();

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.sync_accepted_requirements_20261019()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $fn$
BEGIN
 IF NEW.status='approved' THEN PERFORM pdc_operation_updates_private.ensure_required_work_20261019(NEW.vehicle_id); END IF;
 RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.sync_accepted_requirements_20261019() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER pdc_accepted_required_work_20261019 AFTER INSERT OR UPDATE OF status ON public.pdc_new_vehicle_reviews
 FOR EACH ROW EXECUTE FUNCTION pdc_operation_updates_private.sync_accepted_requirements_20261019();
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.sync_visible_requirements_20261019()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $fn$
BEGIN
 IF NEW.visible_on_board AND NOT OLD.visible_on_board THEN
  PERFORM pdc_operation_updates_private.ensure_required_work_20261019(NEW.id);
 END IF;
 RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.sync_visible_requirements_20261019() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER pdc_visible_required_work_20261019 AFTER UPDATE OF visible_on_board ON public.vehicles
 FOR EACH ROW EXECUTE FUNCTION pdc_operation_updates_private.sync_visible_requirements_20261019();
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.sync_classified_requirements_20261019()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public' AS $fn$
DECLARE vid uuid;
BEGIN
 SELECT vehicle_id INTO vid FROM public.pdc_pilbara_service_operations WHERE operation_id=NEW.operation_id AND department IN('138','139');
 IF vid IS NOT NULL THEN PERFORM pdc_operation_updates_private.ensure_required_work_20261019(vid); END IF;
 RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.sync_classified_requirements_20261019() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER pdc_classified_required_work_20261019 AFTER INSERT OR UPDATE ON public.pdc_pilbara_service_classification_current
 FOR EACH ROW EXECUTE FUNCTION pdc_operation_updates_private.sync_classified_requirements_20261019();
CREATE OR REPLACE FUNCTION public.pdc_qc_gate_issues(p_vehicle_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH vehicle AS (
    SELECT id,upper(btrim(coalesce(current_location,''))) location,
           CASE WHEN regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g')='PITINSPECTION' THEN ''
                ELSE regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g') END stage
    FROM public.vehicles WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL
  ), outstanding AS (
    SELECT string_agg(distinct upper(btrim(wi.work_key)),', ' ORDER BY upper(btrim(wi.work_key))) labels
    FROM public.vehicle_work_items wi
    WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed
      AND regexp_replace(upper(btrim(coalesce(wi.work_key,''))),'[^A-Z0-9]+','','g') NOT IN ('QC','PARTS','PITINSPECTION')
  ), canonical_missing AS (
    SELECT count(*) n FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
    LEFT JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
    WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true' AND coalesce(l->>'completed','false')<>'true'
      AND coalesce(l->>'stage_code','') NOT IN('JOB_CARD_NOTES','PIT_INSPECTION','QC','PARTS')
      AND (s.work_key IS NULL OR NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi
        WHERE wi.vehicle_id=p_vehicle_id AND wi.work_key=s.work_key AND (wi.required OR wi.completed)))
  ), active_planner AS (
    SELECT string_agg(distinct s.code,', ' ORDER BY s.code) labels
    FROM public.workshop_bookings b
    JOIN public.workshop_stages s ON s.id=b.stage_id
    WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL
      AND b.status IN ('queued','planned','started','stoppage') AND s.planner_enabled AND s.code<>'PIT_INSPECTION'
  )
  SELECT array_remove(array[
    CASE WHEN (SELECT n FROM canonical_missing)>0 THEN 'unresolved_jobcard_work' END,
    CASE WHEN NOT EXISTS(SELECT 1 FROM vehicle) THEN 'active_vehicle_required' END,
    CASE WHEN (SELECT location FROM vehicle) NOT IN ('PMB','QC') THEN 'vehicle_must_be_at_pmb_or_qc_gate' END,
    CASE WHEN coalesce((SELECT stage FROM vehicle),'')<>'' THEN 'vehicle_still_in_workshop_stage:'||(SELECT stage FROM vehicle) END,
    CASE WHEN (SELECT labels FROM outstanding) IS NOT NULL THEN 'outstanding_required_work:'||(SELECT labels FROM outstanding) END,
    CASE WHEN (SELECT labels FROM active_planner) IS NOT NULL THEN 'active_workshop_booking:'||(SELECT labels FROM active_planner) END
  ],null::text)
$function$
;
