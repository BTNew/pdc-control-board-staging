-- Undo 20261019141000_realtime_publication_prune.sql.
-- Puts the removed tables back into supabase_realtime. Does not create or drop tables.
DO $rollback$
DECLARE
 drop_members text[] := ARRAY[
  'karratha135_pdc.navision_backend_revision',
  'karratha135_pdc.pdc_ai_intake_revision',
  'karratha135_pdc.pdc_auditor_revision',
  'karratha135_pdc.pdc_email_ai_successor_ui_revision',
  'karratha135_pdc.pdc_email_vehicle_revision',
  'karratha135_pdc.pdc_user_roles',
  'karratha135_pdc.salespeople',
  'karratha135_pdc.sublet_providers',
  'karratha135_pdc.vehicle_lifecycle_resolver_revision',
  'karratha135_pdc.workshop_bays',
  'karratha135_pdc.workshop_revision',
  'karratha135_pdc.workshop_settings',
  'karratha135_pdc.workshop_station_revision',
  'karratha135_pdc.workshop_technicians',
  'public.ai_email_intake',
  'public.ai_proposed_actions',
  'public.ai_review_items',
  'public.ai_workshop_commands',
  'public.label_print_events',
  'public.pdc_auditor_workshop_revisions',
  'public.pdc_email_monitor_status',
  'public.pdc_online_state_revision',
  'public.pdc_supervised_revision',
  'public.vehicle_aliases',
  'public.vehicle_intelligence_revisions',
  'public.vehicle_intelligence_summaries',
  'public.vehicle_master_revision',
  'public.vehicle_movements',
  'public.vehicle_parts_updates',
  'public.vehicle_work_items',
  'public.vehicle_workshop_line_adjustments',
  'public.vehicles',
  'public.workshop_booking_assignments',
  'public.workshop_booking_history',
  'public.workshop_bookings',
  'public.workshop_stages'
 ];
 item text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'staging_only';
 END IF;
 FOREACH item IN ARRAY drop_members LOOP
  IF to_regclass(item) IS NULL THEN
   RAISE EXCEPTION 'rollback_table_missing: %', item;
  END IF;
  IF NOT EXISTS (
   SELECT 1
   FROM pg_publication_rel pr
   JOIN pg_publication p ON p.oid = pr.prpubid
   JOIN pg_class c ON c.oid = pr.prrelid
   JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE p.pubname = 'supabase_realtime'
     AND n.nspname = split_part(item, '.', 1)
     AND c.relname = split_part(item, '.', 2)
  ) THEN
   EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I.%I', split_part(item, '.', 1), split_part(item, '.', 2));
  END IF;
 END LOOP;
END $rollback$;
