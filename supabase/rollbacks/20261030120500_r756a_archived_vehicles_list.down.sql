-- r756a rollback.
DROP FUNCTION IF EXISTS public.list_archived_vehicles_756();
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'archived_vehicles_visible_756';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261030120500';
