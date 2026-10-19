-- Forward, refusal, and rollback checks for the realtime publication prune.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION public.realtime_members() RETURNS text[]
LANGUAGE sql STABLE AS $$
 SELECT coalesce(array_agg(member ORDER BY member), '{}')
 FROM (
  SELECT n.nspname || '.' || c.relname AS member
  FROM pg_publication_rel pr
  JOIN pg_publication p ON p.oid = pr.prpubid
  JOIN pg_class c ON c.oid = pr.prrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE p.pubname = 'supabase_realtime'
 ) listed;
$$;

CREATE TABLE public.realtime_probe_saved (id text PRIMARY KEY, members text[]);
INSERT INTO public.realtime_probe_saved VALUES ('before', public.realtime_members());

\echo '--- sentinel refusal ---'
CREATE TABLE public.pdc_production_environment_sentinel (id int);
\set ON_ERROR_STOP off
\i :forward
\if :ERROR
 \echo sentinel refusal ok
\else
 \echo sentinel refusal failed
 \quit 1
\endif
\set ON_ERROR_STOP on
DROP TABLE public.pdc_production_environment_sentinel;
DO $$ BEGIN
 IF public.realtime_members() IS DISTINCT FROM (SELECT members FROM public.realtime_probe_saved WHERE id = 'before') THEN
  RAISE EXCEPTION 'refused migration changed publication membership';
 END IF;
END $$;

\echo '--- guard refusal ---'
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT false $$;
\set ON_ERROR_STOP off
\i :forward
\if :ERROR
 \echo guard refusal ok
\else
 \echo guard refusal failed
 \quit 1
\endif
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT true $$;

\echo '--- forward ---'
\i :forward
DO $$
DECLARE
 keep text[] := ARRAY[
  'public.navision_backend_revision',
  'public.pdc_ai_intake_revision',
  'public.pdc_auditor_revision',
  'public.pdc_email_ai_successor_ui_revision',
  'public.pdc_email_vehicle_revision',
  'public.pdc_user_roles',
  'public.salespeople',
  'public.sublet_providers',
  'public.vehicle_lifecycle_resolver_revision',
  'public.workshop_bays',
  'public.workshop_revision',
  'public.workshop_settings',
  'public.workshop_station_revision',
  'public.workshop_technicians'
 ];
 relation_count int;
BEGIN
 IF public.realtime_members() IS DISTINCT FROM (SELECT array_agg(x ORDER BY x) FROM unnest(keep) x) THEN
  RAISE EXCEPTION 'publication after prune %', public.realtime_members();
 END IF;
 SELECT count(*) INTO relation_count
 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname IN ('public','karratha135_pdc') AND c.relkind = 'r';
 IF relation_count <> 52 THEN
  RAISE EXCEPTION 'table count changed to %', relation_count;
 END IF;
 IF EXISTS (
  SELECT 1 FROM pg_publication_rel pr
  JOIN pg_publication p ON p.oid = pr.prpubid
  JOIN pg_class c ON c.oid = pr.prrelid
  WHERE p.pubname = 'supabase_realtime' AND c.relname = 'realtime_prune_untouched'
 ) THEN
  RAISE EXCEPTION 'untouched table entered the publication';
 END IF;
END $$;
INSERT INTO public.realtime_probe_saved VALUES ('after', public.realtime_members());

\echo '--- second forward must stop ---'
\set ON_ERROR_STOP off
\i :forward
\if :ERROR
 \echo second forward refusal ok
\else
 \echo second forward unexpectedly applied
 \quit 1
\endif
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF public.realtime_members() IS DISTINCT FROM (SELECT members FROM public.realtime_probe_saved WHERE id = 'after') THEN
  RAISE EXCEPTION 'rejected re-apply changed membership';
 END IF;
END $$;

\echo '--- rollback ---'
\i :down
DO $$ BEGIN
 IF public.realtime_members() IS DISTINCT FROM (SELECT members FROM public.realtime_probe_saved WHERE id = 'before') THEN
  RAISE EXCEPTION 'rollback membership %', public.realtime_members();
 END IF;
END $$;

\echo '--- forward again ---'
\i :forward
DO $$ BEGIN
 IF public.realtime_members() IS DISTINCT FROM (SELECT members FROM public.realtime_probe_saved WHERE id = 'after') THEN
  RAISE EXCEPTION 'reapplied membership drifted';
 END IF;
END $$;
\echo realtime publication local check passed
SELECT public.realtime_members();
