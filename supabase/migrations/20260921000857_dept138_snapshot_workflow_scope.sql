-- Additive read projection for scoped Bus4x4 previews; no operational data changes.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR to_regnamespace('pdc_bus_private') IS NULL THEN RAISE EXCEPTION 'Staging Bus workflow required'; END IF;
END $guard$;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));

CREATE INDEX bus_audit_actor_idx ON pdc_bus_private.audit(actor_id);
CREATE INDEX bus_audit_vehicle_idx ON pdc_bus_private.audit(vehicle_id);
CREATE INDEX bus_supplier_booking_idx ON pdc_bus_private.supplier(booking_id);
CREATE INDEX bus_supplier_technician_idx ON pdc_bus_private.supplier(technician_id);
CREATE INDEX bus_supplier_actor_idx ON pdc_bus_private.supplier(updated_by);
CREATE INDEX bus_workflow_actor_idx ON pdc_bus_private.workflow(updated_by);

DO $patch$ DECLARE d text; needle text;
BEGIN
 d:=pg_get_functiondef('pdc_parts_private.planner_search_identity_20260917(uuid)'::regprocedure);
 needle:='RETURN jsonb_build_object(''key_number'',v.key_number,''job_card_numbers'',';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Planner identity projection changed'; END IF;
 d:=replace(d,needle,'RETURN jsonb_build_object(''bus_workflow_department138'',pdc_bus_private.active_vehicle(v.id),''key_number'',v.key_number,''job_card_numbers'',');
 EXECUTE d;
 d:=pg_get_functiondef('public.workshop_overlay_canonical_booking_fields_397(jsonb)'::regprocedure);
 needle:='''default_duration_minutes'',b.default_duration_minutes,';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Canonical booking overlay changed'; END IF;
 d:=replace(d,needle,needle||'''bus_calendar_version'',b.bus_calendar_version,');
 EXECUTE d;
 d:=pg_get_functiondef('public.workshop_booking_snapshot(uuid)'::regprocedure);
 needle:='''default_duration_minutes'', b.default_duration_minutes,';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Booking snapshot projection changed'; END IF;
 d:=replace(d,needle,needle||'''bus_calendar_version'', b.bus_calendar_version,');
 needle:='''permanent_vehicle_id'', v.permanent_vehicle_id,';
 IF strpos(d,needle)=0 THEN RAISE EXCEPTION 'Booking vehicle projection changed'; END IF;
 d:=replace(d,needle,'''bus_workflow_department138'', pdc_bus_private.active_vehicle(v.id),'||needle);
 EXECUTE d;
END $patch$;
NOTIFY pgrst,'reload schema';
