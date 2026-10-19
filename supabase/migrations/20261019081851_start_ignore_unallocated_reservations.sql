-- Returned work retains its dates/history but reserves no bay, vehicle or mechanic.
-- Keep the existing start cascade, running/stopped protections and write ordering.
DO $guard$
DECLARE definition text; old_clause text := $old$WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND s.is_physical AND NOT s.is_sublet;$old$;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Wrong environment: staging only';
 END IF;
 SELECT replace(pg_get_functiondef('public.start_workshop_work_pre_116(uuid,integer,timestamptz,jsonb)'::regprocedure),chr(13),'') INTO definition;
 IF md5(definition)<>'a36becd3f4a6b5c7f31da1cb2b8222e6' THEN
  RAISE EXCEPTION 'source_version_changed: start_workshop_work_pre_116';
 END IF;
 IF (length(definition)-length(replace(definition,old_clause,'')))/length(old_clause)<>1 THEN
  RAISE EXCEPTION 'start_plan_selection_anchor_changed';
 END IF;
 EXECUTE replace(definition,old_clause,
  $new$WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND s.is_physical AND NOT s.is_sublet
   AND NOT (b.status='queued' AND b.bay_id IS NULL);$new$);
END $guard$;

NOTIFY pgrst, 'reload schema';
