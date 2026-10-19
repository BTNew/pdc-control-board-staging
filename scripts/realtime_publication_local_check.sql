-- Local fixture for the realtime publication prune. Not a replay of the live schema.
\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS karratha135_pdc;
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT true $$;
DO $fixture$
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
 item text;
BEGIN
 FOREACH item IN ARRAY expected LOOP
  EXECUTE format('CREATE TABLE %I.%I (id int)', split_part(item, '.', 1), split_part(item, '.', 2));
 END LOOP;
 CREATE PUBLICATION supabase_realtime;
 EXECUTE (
  SELECT 'ALTER PUBLICATION supabase_realtime ADD TABLE ' || string_agg(format('%I.%I', split_part(member, '.', 1), split_part(member, '.', 2)), ', ' ORDER BY member DESC)
  FROM unnest(expected) AS member
 );
 CREATE TABLE public.realtime_prune_untouched (id int);
END $fixture$;
