-- Owner-authorised reversible pause. Run only against the working staging DB.
-- No vehicle, job, operation, booking, account or evidence is deleted or changed.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='60s';
SET LOCAL lock_timeout='5s';
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN
  RAISE EXCEPTION 'Working staging project required';
 END IF;
 IF (SELECT count(*) FROM karratha135_pdc.engine_release_135 WHERE singleton
     AND engine_version='pmb-native135-candidate-v1' AND proof_sha256 IS NOT NULL)<>1 THEN
  RAISE EXCEPTION 'Department 135 release metadata differs; review before pausing';
 END IF;
 IF (SELECT count(*) FROM cron.job WHERE jobname='k135-staging-workshop-clock-cascade'
     AND command='SELECT karratha135_pdc.workshop_clock_tick(true,clock_timestamp());')<>1 THEN
  RAISE EXCEPTION 'Exact Department 135 clock missing or changed';
 END IF;
 IF EXISTS(SELECT 1 FROM karratha135_intake.owner_attachment_manifests_20261007 WHERE enabled) THEN
  RAISE EXCEPTION 'Department 135 import is in progress; retry after it finishes';
 END IF;
END $guard$;
CREATE TEMP TABLE pause135_release_before ON COMMIT DROP AS
 SELECT to_jsonb(r) AS original FROM karratha135_pdc.engine_release_135 r WHERE singleton;
CREATE TEMP TABLE pause135_cron_before ON COMMIT DROP AS
 SELECT jobid,to_jsonb(j) AS original FROM cron.job j;
CREATE TEMP TABLE pause135_data_before(schema_name text,table_name text,row_count bigint,digest text) ON COMMIT DROP;
DO $capture$
DECLARE t record;c bigint;d text;
BEGIN
 FOR t IN SELECT schemaname,tablename FROM pg_tables
  WHERE schemaname LIKE 'karratha135_%' AND tablename<>'engine_release_135'
  ORDER BY schemaname,tablename LOOP
  EXECUTE format('SELECT count(*),md5(coalesce(string_agg(to_jsonb(x)::text,E''\n'' ORDER BY to_jsonb(x)::text),'''')) FROM %I.%I x',t.schemaname,t.tablename) INTO c,d;
  INSERT INTO pause135_data_before VALUES(t.schemaname,t.tablename,c,d);
 END LOOP;
END $capture$;
UPDATE karratha135_pdc.engine_release_135 SET ready=false WHERE singleton=true;
SELECT cron.alter_job(job_id := (SELECT jobid FROM cron.job
 WHERE jobname='k135-staging-workshop-clock-cascade'
 AND command='SELECT karratha135_pdc.workshop_clock_tick(true,clock_timestamp());'),
 active := false);
DO $verify$
DECLARE t record;c bigint;d text;
BEGIN
 IF EXISTS(SELECT 1 FROM karratha135_pdc.engine_release_135 r CROSS JOIN pause135_release_before b
  WHERE r.ready OR to_jsonb(r)-'ready' IS DISTINCT FROM b.original-'ready') THEN
  RAISE EXCEPTION 'Pause changed release proof or did not close the gate';
 END IF;
 FOR t IN SELECT * FROM pause135_data_before LOOP
  EXECUTE format('SELECT count(*),md5(coalesce(string_agg(to_jsonb(x)::text,E''\n'' ORDER BY to_jsonb(x)::text),'''')) FROM %I.%I x',t.schema_name,t.table_name) INTO c,d;
  IF c IS DISTINCT FROM t.row_count OR d IS DISTINCT FROM t.digest THEN
   RAISE EXCEPTION 'Department 135 records changed during pause: %.%',t.schema_name,t.table_name;
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pause135_cron_before b FULL JOIN cron.job j USING(jobid)
  WHERE CASE WHEN b.original->>'jobname'='k135-staging-workshop-clock-cascade'
   THEN j.active OR to_jsonb(j)-'active' IS DISTINCT FROM b.original-'active'
   ELSE to_jsonb(j) IS DISTINCT FROM b.original END) THEN
  RAISE EXCEPTION 'Another scheduled job changed during pause';
 END IF;
END $verify$;
SELECT jsonb_build_object('ok',true,'department','135','paused',true,
 'previous_ready',(SELECT original->'ready' FROM pause135_release_before),
 'preserved_tables',(SELECT count(*) FROM pause135_data_before),
 'vehicles',(SELECT count(*) FROM karratha135_pdc.vehicles),
 'operations',(SELECT count(*) FROM karratha135_pdc.pdc_pilbara_service_operations),
 'bookings',(SELECT count(*) FROM karratha135_pdc.workshop_bookings),
 'other_schedules_unchanged',true,'approval_proof_preserved',true) AS pause_receipt;
COMMIT;
