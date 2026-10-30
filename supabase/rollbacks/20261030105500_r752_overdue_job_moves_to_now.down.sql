-- r752 rollback: back to the r431 behaviour (an overdue planned job steps to the next 30 minute mark).
DELETE FROM public.workshop_settings WHERE key = 'clock_overdue_step_minutes';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'overdue_job_moves_to_now_752';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261030105500';
