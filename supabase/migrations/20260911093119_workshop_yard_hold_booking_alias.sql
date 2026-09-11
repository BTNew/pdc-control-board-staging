-- Keep imported location evidence intact; Yard Hold and YH mean the same booking location.
CREATE FUNCTION public.workshop_location_code(p_location text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE
SET search_path=pg_catalog
AS $function$
 SELECT CASE upper(btrim(coalesce(p_location,'')))
   WHEN 'YARD HOLD' THEN 'YH'
   ELSE upper(btrim(coalesce(p_location,'')))
 END
$function$;
REVOKE ALL ON FUNCTION public.workshop_location_code(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.workshop_location_code(text) TO authenticated,service_role;

-- Change only location interpretation in the existing, guarded scheduling functions.
-- No vehicle, source, ETA, booking or workflow data is rewritten.
DO $patch$
DECLARE
 f record; before_definition text; after_definition text;
 expression text; changed integer:=0; replacements integer:=0;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'staging_only'; END IF;
 FOR f IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN(
   'book_all_vehicle_stations','workshop_station_eligibility','workshop_validate_booking',
   'workshop_prevent_disabled_planner_booking_mutation','workshop_require_booking_restore_eligibility')
 LOOP
  before_definition:=pg_get_functiondef(f.oid); after_definition:=before_definition;
  FOREACH expression IN ARRAY ARRAY[
   'upper(btrim(v.current_location))',
   'upper(btrim(coalesce(v.current_location,'''')))',
   'upper(btrim(coalesce(v_vehicle.current_location,'''')))',
   'upper(btrim(coalesce(current_location,'''')))'
  ] LOOP
   replacements:=replacements+(length(after_definition)-length(replace(after_definition,expression,'')))/length(expression);
   after_definition:=replace(after_definition,expression,
    CASE expression
     WHEN 'upper(btrim(v.current_location))' THEN 'public.workshop_location_code(v.current_location)'
     WHEN 'upper(btrim(coalesce(v.current_location,'''')))' THEN 'public.workshop_location_code(v.current_location)'
     WHEN 'upper(btrim(coalesce(v_vehicle.current_location,'''')))' THEN 'public.workshop_location_code(v_vehicle.current_location)'
     ELSE 'public.workshop_location_code(current_location)' END);
  END LOOP;
  IF after_definition IS DISTINCT FROM before_definition THEN EXECUTE after_definition; changed:=changed+1; END IF;
 END LOOP;
 IF changed<>5 OR replacements<>10 THEN
  RAISE EXCEPTION 'Unexpected booking function definitions: changed %, replacements %',changed,replacements;
 END IF;
 IF public.workshop_location_code(' Yard Hold ')<>'YH'
  OR public.workshop_location_code('yh')<>'YH'
  OR public.workshop_location_code(NULL)<>''
  OR public.workshop_location_code('IT')<>'IT'
  OR public.workshop_location_code('QC')<>'QC'
  OR public.workshop_location_code('Not Yard Hold')<>'NOT YARD HOLD' THEN
  RAISE EXCEPTION 'Location normalization assertion failed';
 END IF;
END $patch$;

