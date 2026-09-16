-- Bound these three combined-upload RPCs within the REST API's one-minute limit.
-- Do not change role-wide or other application query timeouts.
ALTER FUNCTION public.preview_navision_combined_import(jsonb,text,timestamptz) SET statement_timeout='60s';
ALTER FUNCTION public.approve_navision_combined_initial_scopes(jsonb) SET statement_timeout='60s';
ALTER FUNCTION public.apply_navision_combined_import(text,jsonb,text,timestamptz,text,text,bigint) SET statement_timeout='60s';
NOTIFY pgrst,'reload schema';
