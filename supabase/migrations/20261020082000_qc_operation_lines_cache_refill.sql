-- Refill QC operation-line cache rows that triggers have deleted.
-- A read still falls through to the uncached body when the row is missing,
-- and nothing was putting those rows back.
-- This adds a separate pg_cron job, every minute, that recomputes a bounded
-- batch of missing vehicle rows.
-- It is not called from workshop_clock_tick and it is not appended to the
-- clock job. The clock holds its advisory transaction lock and its booking
-- and assignment row locks until it returns. Extending that transaction with
-- the recompute would make the next clock wait on this work.
-- The refill never takes that advisory lock or those booking locks.
-- An input change that commits while a batch is between computing and
-- inserting used to find no cache row to delete, and the refill then stored
-- stale lines. Invalidation now also bumps
-- pdc_work_categories_private.qc_operation_lines_cache_epoch. The shared
-- tables and any wipe of every vehicle bump the nil-uuid row. The refill
-- reads the vehicle generation and the global generation before computing,
-- then inserts in one statement only when both are unchanged, taking
-- FOR SHARE on those epoch rows for that insert alone. It does not hold
-- those locks while computing, so the clock waits only for the insert.
-- lock_timeout makes this job give up if the clock already holds an epoch row.
-- Every DELETE and UPDATE has a WHERE clause. pg_safeupdate rejects a bare
-- statement in authenticator sessions, which is what broke the Navision import.
-- Rollback: supabase/rollbacks/20261020082000_qc_operation_lines_cache_refill.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
DECLARE
  clock_command text := 'SELECT public.workshop_clock_tick(true,clock_timestamp());';
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF to_regclass('pdc_work_categories_private.qc_operation_lines_cache') IS NULL
     OR to_regclass('public.vehicles') IS NULL
     OR to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)') IS NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_cache_missing';
  END IF;
  IF (
    SELECT count(*)
    FROM (VALUES ('vehicle_id'), ('lines'), ('computed_at')) AS expected(col)
    JOIN pg_attribute a
      ON a.attrelid = 'pdc_work_categories_private.qc_operation_lines_cache'::regclass
     AND a.attname = expected.col
     AND a.attnum > 0
     AND NOT a.attisdropped
  ) IS DISTINCT FROM 3
  OR NOT EXISTS (
    SELECT 1
    FROM pg_attribute
    WHERE attrelid = 'public.vehicles'::regclass
      AND attname = 'id'
      AND NOT attisdropped
      AND atttypid = 'uuid'::regtype
  )
  OR NOT EXISTS (
    SELECT 1
    FROM pg_proc
    WHERE oid = 'public.pdc_qc_operation_lines_379_uncached(uuid)'::regprocedure
      AND prosecdef
      AND provolatile = 's'
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_cache_missing';
  END IF;
  IF to_regprocedure('pdc_work_categories_private.invalidate_qc_operation_lines_cache()') IS NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_cache_missing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.vehicles WHERE id = '00000000-0000-0000-0000-000000000000'
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_epoch_sentinel_collision';
  END IF;
  IF to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') IS NOT NULL
     OR to_regclass('pdc_work_categories_private.qc_operation_lines_cache_epoch') IS NOT NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_already_installed';
  END IF;
  IF to_regprocedure('cron.schedule(text,text,text)') IS NULL
     OR to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'qc_cache_refill_cron_missing';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-workshop-clock-cascade'
      AND command IS DISTINCT FROM clock_command
  ) THEN
    RAISE EXCEPTION 'workshop_clock_job_changed';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-qc-operation-lines-cache-refill'
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_job_exists';
  END IF;
END
$guard$;

SET LOCAL lock_timeout = '5s';

CREATE TABLE pdc_work_categories_private.qc_operation_lines_cache_epoch (
  vehicle_id uuid PRIMARY KEY,
  gen bigint NOT NULL
);
REVOKE ALL ON TABLE pdc_work_categories_private.qc_operation_lines_cache_epoch FROM PUBLIC;
DO $revoke_epoch$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE 'REVOKE ALL ON TABLE pdc_work_categories_private.qc_operation_lines_cache_epoch FROM ' || quote_ident(role_name);
    END IF;
  END LOOP;
END
$revoke_epoch$;

-- Nil uuid is the generation for shared tables and for a full-cache wipe.
INSERT INTO pdc_work_categories_private.qc_operation_lines_cache_epoch (vehicle_id, gen)
VALUES ('00000000-0000-0000-0000-000000000000', 0);
INSERT INTO pdc_work_categories_private.qc_operation_lines_cache_epoch (vehicle_id, gen)
SELECT v.id, 0
FROM public.vehicles v
ON CONFLICT (vehicle_id) DO NOTHING;

CREATE FUNCTION pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(p_vehicle_ids uuid[], p_global boolean)
 RETURNS void
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $bump$
BEGIN
  INSERT INTO pdc_work_categories_private.qc_operation_lines_cache_epoch AS e (vehicle_id, gen)
  SELECT DISTINCT x.id, 1
  FROM unnest(coalesce(p_vehicle_ids, ARRAY[]::uuid[])) AS x(id)
  WHERE x.id IS NOT NULL
    AND x.id <> '00000000-0000-0000-0000-000000000000'::uuid
  ON CONFLICT (vehicle_id) DO UPDATE
    SET gen = e.gen + 1
    WHERE true;
  IF p_global THEN
    INSERT INTO pdc_work_categories_private.qc_operation_lines_cache_epoch AS e (vehicle_id, gen)
    VALUES ('00000000-0000-0000-0000-000000000000'::uuid, 1)
    ON CONFLICT (vehicle_id) DO UPDATE
      SET gen = e.gen + 1
      WHERE true;
  END IF;
END
$bump$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[], boolean) FROM PUBLIC;
DO $revoke_bump$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE 'REVOKE ALL ON FUNCTION pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(uuid[], boolean) FROM ' || quote_ident(role_name);
    END IF;
  END LOOP;
END
$revoke_bump$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $invalidate$
DECLARE
  op_id uuid;
BEGIN
  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN ('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'pdc_pilbara_service_import_batches', 'workshop_stage_aliases', 'workshop_stages') THEN
    PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(NULL, true);
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;
    RETURN NULL;
  END IF;
  IF TG_TABLE_NAME = 'vehicles' THEN
    IF TG_OP = 'INSERT' THEN
      PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ARRAY[NEW.id], false);
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = NEW.id;
    ELSIF TG_OP = 'UPDATE' THEN
      PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ARRAY[OLD.id, NEW.id], false);
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id IN (OLD.id, NEW.id);
    ELSE
      PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ARRAY[OLD.id], false);
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = OLD.id;
    END IF;
    RETURN NULL;
  END IF;
  IF TG_TABLE_NAME IN ('operation_routing_history_20261015', 'pdc_pilbara_service_classification_current', 'pdc_pilbara_service_classification_history', 'pdc_pilbara_service_operation_history') THEN
    IF TG_OP = 'DELETE' THEN op_id := OLD.operation_id; ELSE op_id := NEW.operation_id; END IF;
    IF TG_OP = 'UPDATE' AND OLD.operation_id IS DISTINCT FROM NEW.operation_id THEN
      PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(
        ARRAY(
          SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o
          WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
        ),
        NOT EXISTS (
          SELECT 1 FROM public.pdc_pilbara_service_operations o
          WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
        )
      );
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id IN (
        SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o
        WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
      );
      IF NOT EXISTS (
        SELECT 1 FROM public.pdc_pilbara_service_operations o
        WHERE o.operation_id IN (OLD.operation_id, NEW.operation_id)
      ) THEN
        DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;
      END IF;
    ELSIF EXISTS (
      SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
    ) THEN
      PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(
        ARRAY(
          SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o
          WHERE o.operation_id = op_id
        ),
        false
      );
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id IN (
        SELECT o.vehicle_id FROM public.pdc_pilbara_service_operations o WHERE o.operation_id = op_id
      );
    ELSE
      PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(NULL, true);
      DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;
    END IF;
    RETURN NULL;
  END IF;
  IF TG_OP = 'INSERT' THEN
    PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ARRAY[NEW.vehicle_id], false);
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = NEW.vehicle_id;
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ARRAY[OLD.vehicle_id, NEW.vehicle_id], false);
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id IN (OLD.vehicle_id, NEW.vehicle_id);
  ELSE
    PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ARRAY[OLD.vehicle_id], false);
    DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = OLD.vehicle_id;
  END IF;
  RETURN NULL;
END
$invalidate$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache() FROM PUBLIC;

CREATE FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(p_batch integer DEFAULT 20)
 RETURNS integer
 LANGUAGE plpgsql
 VOLATILE
 SECURITY DEFINER
 SET statement_timeout TO '4s'
 SET lock_timeout TO '250ms'
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  ids uuid[] := ARRAY[]::uuid[];
  payloads jsonb[] := ARRAY[]::jsonb[];
  vehicle_gens bigint[] := ARRAY[]::bigint[];
  global_gens bigint[] := ARRAY[]::bigint[];
  v_started timestamptz := clock_timestamp();
  global_id constant uuid := '00000000-0000-0000-0000-000000000000';
  vehicle uuid;
  v_gen bigint;
  g_gen bigint;
  filled integer;
BEGIN
  IF p_batch IS NULL OR p_batch < 1 OR p_batch > 40 THEN
    RAISE EXCEPTION 'qc_cache_refill_batch_out_of_range';
  END IF;
  -- The CI proof sets this so it can commit an input change after compute
  -- and before insert. Production leaves it unset and takes no advisory lock.
  -- The key is not the workshop clock lock.
  IF coalesce(current_setting('pdc.qc_cache_refill_after_compute', true), '') = 'wait' THEN
    PERFORM set_config('lock_timeout', '30s', true);
    PERFORM set_config('statement_timeout', '30s', true);
  END IF;
  -- Missing rows are the refill set. Read both generations before computing.
  -- Calling the wrapper would just miss again.
  FOR vehicle IN
    SELECT v.id
    FROM public.vehicles v
    WHERE NOT EXISTS (
      SELECT 1
      FROM pdc_work_categories_private.qc_operation_lines_cache c
      WHERE c.vehicle_id = v.id
    )
    ORDER BY v.id
    LIMIT p_batch
  LOOP
    EXIT WHEN clock_timestamp() > v_started + interval '3 seconds';
    SELECT e.gen INTO v_gen
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
    WHERE e.vehicle_id = vehicle;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    SELECT e.gen INTO g_gen
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
    WHERE e.vehicle_id = global_id;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;
    ids := ids || ARRAY[vehicle];
    vehicle_gens := vehicle_gens || ARRAY[v_gen];
    global_gens := global_gens || ARRAY[g_gen];
    payloads := payloads || ARRAY[public.pdc_qc_operation_lines_379_uncached(vehicle)];
  END LOOP;
  IF cardinality(ids) = 0 THEN
    RETURN 0;
  END IF;
  IF coalesce(current_setting('pdc.qc_cache_refill_after_compute', true), '') = 'wait' THEN
    PERFORM pg_advisory_lock(hashtextextended('pdc:qc-cache-refill:test-gate', 0));
    PERFORM pg_advisory_unlock(hashtextextended('pdc:qc-cache-refill:test-gate', 0));
  END IF;
  INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
  SELECT batch.id, batch.lines, statement_timestamp()
  FROM unnest(ids, payloads, vehicle_gens, global_gens) AS batch(id, lines, vehicle_gen, global_gen)
  WHERE (
    SELECT e.gen
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
    WHERE e.vehicle_id = batch.id
    FOR SHARE OF e
  ) IS NOT DISTINCT FROM batch.vehicle_gen
  AND (
    SELECT e.gen
    FROM pdc_work_categories_private.qc_operation_lines_cache_epoch e
    WHERE e.vehicle_id = global_id
    FOR SHARE OF e
  ) IS NOT DISTINCT FROM batch.global_gen
  ON CONFLICT (vehicle_id) DO NOTHING;
  GET DIAGNOSTICS filled = ROW_COUNT;
  RETURN filled;
END
$function$;

REVOKE ALL ON FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(integer) FROM PUBLIC;
DO $revoke_refill$
DECLARE role_name text;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE 'REVOKE ALL ON FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(integer) FROM ' || quote_ident(role_name);
    END IF;
  END LOOP;
END
$revoke_refill$;

COMMENT ON FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(integer) IS
  'Recompute missing QC operation-line cache rows in a bounded batch. Separate from the workshop clock.';

DO $schedule$
DECLARE
  refill_command text := 'SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);';
  clock_command text := 'SELECT public.workshop_clock_tick(true,clock_timestamp());';
BEGIN
  PERFORM cron.schedule(
    'staging-qc-operation-lines-cache-refill',
    '* * * * *',
    refill_command
  );
  IF NOT EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-qc-operation-lines-cache-refill'
      AND schedule = '* * * * *'
      AND command = refill_command
      AND active IS TRUE
  ) THEN
    RAISE EXCEPTION 'qc_cache_refill_schedule_mismatch';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM cron.job
    WHERE jobname = 'staging-workshop-clock-cascade'
      AND command IS DISTINCT FROM clock_command
  ) THEN
    RAISE EXCEPTION 'workshop_clock_job_changed';
  END IF;
  IF (
    SELECT proconfig
    FROM pg_proc
    WHERE oid = 'pdc_work_categories_private.refill_qc_operation_lines_cache(integer)'::regprocedure
  ) IS DISTINCT FROM ARRAY['statement_timeout=4s', 'lock_timeout=250ms', 'search_path=pg_catalog'] THEN
    RAISE EXCEPTION 'qc_cache_refill_schedule_mismatch';
  END IF;
END
$schedule$;
