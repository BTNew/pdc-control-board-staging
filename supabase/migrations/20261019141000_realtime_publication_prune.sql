-- Staging only. Remove supabase_realtime members the live front end does not
-- subscribe to. This does not drop tables, delete rows, or resume Department 135.
-- Every karratha135_pdc table that is in the publication is in drop_members.
-- The tables, their data, history and migrations stay. Restore them with
-- supabase/rollbacks/20261019141000_realtime_publication_prune.down.sql.
-- That undo file is not under supabase/migrations.
DO $migration$
DECLARE
 expected text[] := ARRAY[
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
  'public.navision_backend_revision',
  'public.pdc_ai_intake_revision',
  'public.pdc_auditor_revision',
  'public.pdc_auditor_workshop_revisions',
  'public.pdc_email_ai_successor_ui_revision',
  'public.pdc_email_monitor_status',
  'public.pdc_email_vehicle_revision',
  'public.pdc_online_state_revision',
  'public.pdc_supervised_revision',
  'public.pdc_user_roles',
  'public.salespeople',
  'public.sublet_providers',
  'public.vehicle_aliases',
  'public.vehicle_intelligence_revisions',
  'public.vehicle_intelligence_summaries',
  'public.vehicle_lifecycle_resolver_revision',
  'public.vehicle_master_revision',
  'public.vehicle_movements',
  'public.vehicle_parts_updates',
  'public.vehicle_work_items',
  'public.vehicle_workshop_line_adjustments',
  'public.vehicles',
  'public.workshop_bays',
  'public.workshop_booking_assignments',
  'public.workshop_booking_history',
  'public.workshop_bookings',
  'public.workshop_revision',
  'public.workshop_settings',
  'public.workshop_stages',
  'public.workshop_station_revision',
  'public.workshop_technicians'
 ];
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
 current text[];
 item text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'staging_only';
 END IF;
 SELECT coalesce(array_agg(member ORDER BY member), '{}')
 INTO current
 FROM (
  SELECT n.nspname || '.' || c.relname AS member
  FROM pg_publication_rel pr
  JOIN pg_publication p ON p.oid = pr.prpubid
  JOIN pg_class c ON c.oid = pr.prrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE p.pubname = 'supabase_realtime'
 ) listed;
 IF current IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(expected) x) THEN
  RAISE EXCEPTION 'reviewed_publication_changed: %', current;
 END IF;
 FOREACH item IN ARRAY drop_members LOOP
  EXECUTE format('ALTER PUBLICATION supabase_realtime DROP TABLE %I.%I', split_part(item, '.', 1), split_part(item, '.', 2));
 END LOOP;
 IF EXISTS (
  SELECT 1
  FROM pg_publication_rel pr
  JOIN pg_publication p ON p.oid = pr.prpubid
  JOIN pg_class c ON c.oid = pr.prrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE p.pubname = 'supabase_realtime'
    AND n.nspname = 'karratha135_pdc'
 ) THEN
  RAISE EXCEPTION 'karratha_publication_remains';
 END IF;
END $migration$;
