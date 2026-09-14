-- STAGING ONLY: one elapsed hour between the same vehicle's workshop bookings.
-- Changes the booking/search, import cascade, capacity and clock paths together.
-- Existing bookings, quoted hours, bay efficiency and historical receipts are retained.
-- CREATE OR REPLACE preserves function ownership, grants and authorization checks.
DO $migration$
DECLARE item record; definition text; updated_definition text;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
      WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'One-hour workshop handover is STAGING only';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 FOR item IN SELECT * FROM (VALUES
  ('public.book_all_vehicle_stations(uuid,integer)', '473ec74b6549058c528223cddd8b531a', 3, 2),
  ('public.get_pdc_vehicle_planning_windows(uuid,timestamp with time zone)', '3648806adbf00610cae9212a21155e08', 1, 1),
  ('public.pdc_tune_reconcile_booking_plan_20260913(uuid,text[],uuid)', 'e362f4abbd3c8859cd4fa5ed6f31cdd7', 3, 4),
  ('public.replan_workshop_capacity(text,integer,integer,boolean,text,uuid)', '17318396e139d1dbeaaad5018ecc348e', 0, 1),
  ('public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)', 'bc70bf248859d31bdd59c0264526ac6e', 4, 0),
  ('public.workshop_clock_tick(boolean,timestamp with time zone)', 'bc2e58368ae8a860f3a143eac8189e40', 3, 0)
 ) expected(signature, definition_md5, interval_count, metadata_count)
 LOOP
  IF to_regprocedure(item.signature) IS NULL THEN
   RAISE EXCEPTION 'Missing expected workshop function: %',item.signature;
  END IF;
  definition:=pg_get_functiondef(to_regprocedure(item.signature));
  IF md5(definition)<>item.definition_md5 THEN
   RAISE EXCEPTION 'Workshop function changed; review before migrating: %',item.signature;
  END IF;
  IF (length(definition)-length(replace(definition,$old$interval '5 hours'$old$,'')))/length($old$interval '5 hours'$old$)<>item.interval_count
     OR (length(definition)-length(replace(definition,$old$'buffer_minutes',300$old$,'')))/length($old$'buffer_minutes',300$old$)<>item.metadata_count THEN
   RAISE EXCEPTION 'Unexpected handover expressions: %',item.signature;
  END IF;
  updated_definition:=replace(definition,$old$interval '5 hours'$old$,$new$interval '1 hour'$new$);
  updated_definition:=replace(updated_definition,$old$'buffer_minutes',300$old$,$new$'buffer_minutes',60$new$);
  updated_definition:=replace(updated_definition,'The vehicle needs five hours between workshop jobs.','The vehicle needs one hour between workshop jobs.');
  IF updated_definition=definition THEN RAISE EXCEPTION 'Handover function was not changed: %',item.signature; END IF;
  EXECUTE updated_definition;
 END LOOP;
 PERFORM public.workshop_bump_revision();
END $migration$;
