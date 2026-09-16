-- Department 138 belongs exclusively to Bus 4x4.
-- Preserve source hours and work history; correct only active, unbooked routing.
-- No booking is created, moved, deleted or completed by this release.
DO $staging$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'department_138_migration_requires_staging'; END IF;
END $staging$;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
LOCK TABLE public.vehicle_workshop_line_adjustments IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.workshop_bookings IN SHARE ROW EXCLUSIVE MODE;

CREATE TEMP TABLE dept138_before ON COMMIT DROP AS
SELECT v.id vehicle_id, l->>'line_identity' line_identity, l line
FROM public.vehicles v
CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
WHERE v.deleted_at IS NULL AND EXISTS (
 SELECT 1 FROM public.pdc_pilbara_service_operations o
 WHERE o.vehicle_id=v.id AND btrim(o.department)='138'
);

CREATE TEMP TABLE dept138_repair_vehicles ON COMMIT DROP AS
SELECT DISTINCT b.vehicle_id FROM dept138_before b JOIN public.vehicles v ON v.id=b.vehicle_id
WHERE v.lifecycle_state='active' AND b.line->>'department'='138'
 AND (b.line->>'active')::boolean IS TRUE AND b.line->>'stage_code' IS DISTINCT FROM 'BUS_4X4';

CREATE TEMP TABLE dept138_adjustments_before ON COMMIT DROP AS
SELECT a.adjustment_id,a.vehicle_id,a.stage_code,a.version
FROM public.vehicle_workshop_line_adjustments a
JOIN dept138_repair_vehicles r ON r.vehicle_id=a.vehicle_id
JOIN public.pdc_pilbara_service_operations o
 ON o.vehicle_id=a.vehicle_id AND a.line_key='source:'||o.operation_id::text
WHERE btrim(o.department)='138' AND a.active AND a.stage_code IS DISTINCT FROM 'BUS_4X4';

DO $guard$
BEGIN
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b
  JOIN dept138_repair_vehicles r ON r.vehicle_id=b.vehicle_id) THEN
  RAISE EXCEPTION 'department_138_repair_requires_booking_review';
 END IF;
END $guard$;

-- Preserve the complete existing reviewed-hour catalogue and all early returns.
-- The wrapper changes the station after that existing calculation has finished.
ALTER FUNCTION public.pdc_pending_work_category_20260912(jsonb)
 RENAME TO pdc_pending_work_category_before_dept138_20260916;

CREATE FUNCTION public.pdc_pending_work_category_20260912(p_line jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE
SET search_path TO pg_catalog, public
AS $function$
 SELECT public.pdc_pending_work_category_before_dept138_20260916(p_line)
 || CASE WHEN btrim(coalesce(p_line->>'department',''))='138'
 THEN jsonb_build_object('stage_code','BUS_4X4','routing_rule','dept138_bus4x4')
 ELSE '{}'::jsonb END
$function$;
REVOKE ALL ON FUNCTION public.pdc_pending_work_category_20260912(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pdc_pending_work_category_20260912(jsonb) TO service_role;

DO $patch$
DECLARE definition text; previous text; needle text;
BEGIN
 definition:=pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure);
 previous:=definition;
 needle:='CASE WHEN a.active AND a.manual_assignment_locked THEN a.stage_code WHEN o.department=''138'' THEN ''BUS_4X4''';
 IF (length(definition)-length(replace(definition,needle,'')))/length(needle)<>2 THEN
  RAISE EXCEPTION 'department_138_canonical_patch_anchor_changed';
 END IF;
 definition:=replace(definition,needle,
  'CASE WHEN btrim(o.department)=''138'' THEN ''BUS_4X4'' WHEN a.active AND a.manual_assignment_locked THEN a.stage_code');
 EXECUTE definition;

 definition:=pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure);
 needle:='CASE WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'department_138_snapshot_patch_anchor_changed'; END IF;
 definition:=replace(definition,needle,
  'CASE WHEN btrim(op->>''department'')=''138'' THEN op||jsonb_build_object(''work_key'',''bus4x4'',''classification'',''BUS_4X4'',''station_assignment_source'',''department_138'') WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(');
 needle:='''operation_line_id'',o.operation_id,';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'department_138_snapshot_department_anchor_changed'; END IF;
 definition:=replace(definition,needle,needle||'''department'',o.department,');
 EXECUTE definition;

 definition:=pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure);
 needle:='''source_kind'',a.source_kind,''stage_code'',a.stage_code,';
 IF strpos(definition,needle)=0 THEN RAISE EXCEPTION 'department_138_detail_patch_anchor_changed'; END IF;
 definition:=replace(definition,needle,needle||
  '''department'',(SELECT o.department FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=a.vehicle_id AND a.line_key=''source:''||o.operation_id::text LIMIT 1),');
 EXECUTE definition;
END $patch$;

-- A source-bound write guard covers normal editing, new-vehicle approval, Tune
-- change approval and direct internal inserts. Other departments remain movable.
CREATE FUNCTION public.pdc_require_department138_bus_20260916()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, public
AS $function$
BEGIN
 IF NEW.active AND NEW.stage_code IS DISTINCT FROM 'BUS_4X4' AND EXISTS (
  SELECT 1 FROM public.pdc_pilbara_service_operations o
  WHERE o.vehicle_id=NEW.vehicle_id AND btrim(o.department)='138'
   AND NEW.line_key='source:'||o.operation_id::text
 ) THEN
  RAISE EXCEPTION 'department_138_requires_bus_4x4'
   USING ERRCODE='23514', HINT='Department 138 jobs must be assigned to Bus 4x4.';
 END IF;
 RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION public.pdc_require_department138_bus_20260916() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER pdc_department138_bus_route
BEFORE INSERT OR UPDATE OF vehicle_id,line_key,stage_code,active
ON public.vehicle_workshop_line_adjustments
FOR EACH ROW EXECUTE FUNCTION public.pdc_require_department138_bus_20260916();

-- These active vehicles have never had bookings (asserted above). Keep adjustment
-- identity, description, approved hours, source provenance and completion data.
-- Keep the approval timestamp: estimate provenance is bound to that timestamp.
-- The separate audit event timestamps this station-only correction.
SELECT set_config('pdc.defer_workshop_adjustment_reconcile','407',true);
SELECT set_config('pdc.defer_workshop_required_work_reconcile','407',true);
UPDATE public.vehicle_workshop_line_adjustments a
SET stage_code='BUS_4X4', version=a.version+1
FROM public.pdc_pilbara_service_operations o, dept138_repair_vehicles r
WHERE a.vehicle_id=r.vehicle_id AND o.vehicle_id=a.vehicle_id
 AND a.line_key='source:'||o.operation_id::text AND btrim(o.department)='138'
 AND a.active AND a.stage_code IS DISTINCT FROM 'BUS_4X4';
DO $audit$
DECLARE change record;
BEGIN
 FOR change IN SELECT before.*,a.stage_code new_stage,a.version new_version
 FROM dept138_adjustments_before before
 JOIN public.vehicle_workshop_line_adjustments a USING(adjustment_id)
 LOOP
  PERFORM public.audit_pdc_event('update','vehicle_workshop_line_adjustments',
   change.adjustment_id,change.vehicle_id,
   jsonb_build_object('stage_code',change.stage_code,'version',change.version),
   jsonb_build_object('stage_code',change.new_stage,'version',change.new_version),
   jsonb_build_object('source','department138_bus_bays_migration',
    'reason','Owner rule: all department 138 jobs use Bus 4x4',
    'hours_and_progress_unchanged',true));
 END LOOP;
END $audit$;
SELECT set_config('pdc.defer_workshop_adjustment_reconcile','',true);
SELECT set_config('pdc.defer_workshop_required_work_reconcile','',true);
SELECT public.pdc_auditor_recalculate_required_work_226(
 coalesce((SELECT array_agg(vehicle_id) FROM dept138_repair_vehicles),'{}'::uuid[])
);

DO $verify$
DECLARE after_line jsonb; before_row record;
BEGIN
 FOR before_row IN SELECT * FROM dept138_before LOOP
  SELECT l INTO after_line
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(before_row.vehicle_id)) l
  WHERE l->>'line_identity'=before_row.line_identity;
  IF after_line IS NULL THEN RAISE EXCEPTION 'department_138_repair_lost_line'; END IF;
  IF (before_row.line->'estimated_hours',before_row.line->'source_estimated_hours',
      before_row.line->'description',before_row.line->'active',before_row.line->'completed',
      before_row.line->'hours_provenance',before_row.line->'estimate_basis',before_row.line->'review_note')
   IS DISTINCT FROM
     (after_line->'estimated_hours',after_line->'source_estimated_hours',
      after_line->'description',after_line->'active',after_line->'completed',
      after_line->'hours_provenance',after_line->'estimate_basis',after_line->'review_note') THEN
   RAISE EXCEPTION 'department_138_repair_changed_work_content';
  END IF;
  IF btrim(before_row.line->>'department')='138' AND after_line->>'stage_code' IS DISTINCT FROM 'BUS_4X4' THEN
   RAISE EXCEPTION 'department_138_station_verification_failed';
  END IF;
  IF btrim(coalesce(before_row.line->>'department',''))<>'138'
   AND before_row.line->'stage_code' IS DISTINCT FROM after_line->'stage_code' THEN
   RAISE EXCEPTION 'department_138_repair_changed_other_department';
  END IF;
 END LOOP;
END $verify$;
NOTIFY pgrst, 'reload schema';
