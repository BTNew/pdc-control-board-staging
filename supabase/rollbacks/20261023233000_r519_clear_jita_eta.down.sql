-- r519 undo (F133). Staging cdsmnqxtyyoeoznmbidd only. Run between :02 and :45.
-- Restores the JITA ETA rows this release superseded. Does not change public.pdc_parts_eta,
-- public.vehicle_parts_updates, set_parts_eta, or the r518 Parts Jita tick.
-- Refuses when a vehicle already has a newer current JITA ETA.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r519 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r519 undo: staging only'; END IF;
 IF to_regclass('pdc_ops.r519_jita_eta_clear') IS NULL THEN RAISE EXCEPTION 'r519 undo: archive is missing'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r519 undo: set_parts_eta is not the r436 body'; END IF;
 IF to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)') IS NULL THEN RAISE EXCEPTION 'r519 undo: r518 tick is missing'; END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_ops.r519_jita_eta_clear c
   JOIN public.pdc_jita_eta e ON e.vehicle_id=c.vehicle_id AND NOT e.superseded
 ) THEN RAISE EXCEPTION 'r519 undo: a current JITA ETA was written after the clear'; END IF;
 PERFORM set_config('pdc.r519_parts',(SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(id::text||':'||coalesce(eta_date::text,'')||':'||superseded::text))::text,'0')) FROM public.pdc_parts_eta),true);
 PERFORM set_config('pdc.r519_worst',(SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(vehicle_id::text||':'||coalesce(worst_eta::text,'')||':'||parts_received::text||':'||coalesce(parts_ordered::text,'')))::text,'0')) FROM public.vehicle_parts_updates),true);
 PERFORM set_config('pdc.r519_n',(SELECT count(*)::text FROM pdc_ops.r519_jita_eta_clear),true);
END $g$;

UPDATE public.pdc_jita_eta e
SET superseded = false, superseded_at = NULL, superseded_by = NULL
FROM pdc_ops.r519_jita_eta_clear c
WHERE e.id = c.jita_eta_id
  AND e.superseded
  AND e.superseded_by = 'a5190519-0519-4519-8519-000000000519'::uuid
  AND e.eta_date = c.eta_date
  AND e.stock_number = c.stock_number
  AND e.vehicle_id = c.vehicle_id;

DELETE FROM public.pdc_jita_eta_audit WHERE status='cleared_r519' AND actor='r519' AND actor_role='staging-clear';

DO $g$ BEGIN
 IF (SELECT count(*) FROM public.pdc_jita_eta e
     JOIN pdc_ops.r519_jita_eta_clear c ON c.jita_eta_id=e.id
     WHERE NOT e.superseded AND e.eta_date=c.eta_date)::text IS DISTINCT FROM current_setting('pdc.r519_n')
  THEN RAISE EXCEPTION 'r519 undo: not every archived JITA ETA was restored'; END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_jita_eta WHERE superseded_by='a5190519-0519-4519-8519-000000000519'::uuid) THEN RAISE EXCEPTION 'r519 undo: sentinel rows remain'; END IF;
 IF (SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(id::text||':'||coalesce(eta_date::text,'')||':'||superseded::text))::text,'0')) FROM public.pdc_parts_eta) IS DISTINCT FROM current_setting('pdc.r519_parts') THEN RAISE EXCEPTION 'r519 undo: pdc_parts_eta changed'; END IF;
 IF (SELECT md5(count(*)::text||':'||coalesce(sum(hashtext(vehicle_id::text||':'||coalesce(worst_eta::text,'')||':'||parts_received::text||':'||coalesce(parts_ordered::text,'')))::text,'0')) FROM public.vehicle_parts_updates) IS DISTINCT FROM current_setting('pdc.r519_worst') THEN RAISE EXCEPTION 'r519 undo: vehicle_parts_updates changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r519 undo: set_parts_eta changed'; END IF;
END $g$;

DROP TABLE pdc_ops.r519_jita_eta_clear;
