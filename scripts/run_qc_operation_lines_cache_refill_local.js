/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');
const os = require('node:os');

const root = path.resolve(__dirname, '..');
const database = 'pdc_qc_cache_refill_check';
const forward = fs.readFileSync(path.join(root, 'supabase/migrations/20261020082000_qc_operation_lines_cache_refill.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261020082000_qc_operation_lines_cache_refill.down.sql'), 'utf8');
const behavior = fs.readFileSync(path.join(root, 'scripts/qc_operation_lines_cache_refill_behavior.sql'), 'utf8')
  .replace(
    '\\ir ../supabase/migrations/20261020082000_qc_operation_lines_cache_refill.sql',
    `\\ir ${path.join(root, 'supabase/migrations/20261020082000_qc_operation_lines_cache_refill.sql')}`
  );

function command(db) {
  if (process.env.PGHOST) {
    return {
      file: 'psql',
      args: ['-h', process.env.PGHOST, '-U', process.env.PGUSER || 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1']
    };
  }
  return { file: 'sudo', args: ['-u', 'postgres', 'psql', '-d', db, '-v', 'ON_ERROR_STOP=1'] };
}
function psql(db, sql) {
  const run = command(db);
  execFileSync(run.file, [...run.args, '-f', '-'], {
    input: sql,
    stdio: ['pipe', 'inherit', 'inherit']
  });
}
function psqlFails(db, sql, pattern) {
  const run = command(db);
  try {
    execFileSync(run.file, [...run.args, '-f', '-'], {
      input: sql,
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (error) {
    const output = `${error.stdout || ''}${error.stderr || ''}`;
    if (!output.includes(pattern)) throw new Error(`Expected ${pattern} but got ${output}`);
    return;
  }
  throw new Error(`Expected failure ${pattern}`);
}
function psqlAdmin(sql) {
  const run = command('postgres');
  execFileSync(run.file, [...run.args, '-c', sql], { stdio: 'inherit' });
}
function psqlValue(db, sql) {
  const run = command(db);
  return execFileSync(run.file, [...run.args, '-t', '-A', '-c', sql], { encoding: 'utf8' }).trim();
}
function sleep(seconds) {
  execFileSync('sleep', [String(seconds)]);
}
function quote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}
function startScript(db, sql) {
  const run = command(db);
  const file = path.join(os.tmpdir(), `qc-cache-refill-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}.sql`);
  const log = `${file}.log`;
  const codeFile = `${file}.code`;
  fs.writeFileSync(file, sql);
  const psqlCmd = [run.file, ...run.args, '-f', file].map(quote).join(' ');
  const child = spawn('bash', ['-c', `${psqlCmd} > ${quote(log)} 2>&1; echo $? > ${quote(codeFile)}`], {
    stdio: 'ignore',
    detached: true
  });
  return {
    child,
    log,
    codeFile,
    output: () => {
      try {
        return fs.readFileSync(log, 'utf8');
      } catch (error) {
        return String(error);
      }
    }
  };
}
function stopChild(handle) {
  try {
    process.kill(-handle.child.pid, 'SIGTERM');
  } catch (error) {
    try {
      handle.child.kill('SIGTERM');
    } catch (inner) {
      // The session already exited.
    }
  }
}
function waitChild(handle, timeoutMs) {
  const start = Date.now();
  while (!fs.existsSync(handle.codeFile)) {
    if (Date.now() - start > timeoutMs) {
      stopChild(handle);
      throw new Error(`child timed out\n${handle.output()}`);
    }
    sleep(0.05);
  }
  const code = fs.readFileSync(handle.codeFile, 'utf8').trim();
  if (code !== '0') throw new Error(`child exited ${code}\n${handle.output()}`);
}
function waitUntil(label, predicate, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (predicate()) return;
    sleep(0.05);
  }
  throw new Error(`timed out waiting for ${label}`);
}
function runRace(db) {
  const holder = startScript(db, `
SET application_name = 'qc_cache_refill_holder';
LOAD 'safeupdate';
SELECT pg_advisory_lock(hashtextextended('pdc:qc-cache-refill:test-gate', 0));
INSERT INTO public.refill_test_signal(step) VALUES ('held');
DO $wait$
DECLARE
  started timestamptz := clock_timestamp();
BEGIN
  LOOP
    EXIT WHEN EXISTS (SELECT 1 FROM public.refill_test_signal WHERE step = 'go');
    PERFORM pg_sleep(0.02);
    IF clock_timestamp() > started + interval '20 seconds' THEN
      RAISE EXCEPTION 'refill race gate timed out';
    END IF;
  END LOOP;
END
$wait$;
UPDATE public.refill_probe
SET note = 'after'
WHERE vehicle_id = '00000000-0000-4000-8000-0000000000aa';
SELECT pg_advisory_unlock(hashtextextended('pdc:qc-cache-refill:test-gate', 0));
`);
  try {
    waitUntil('holder', () => psqlValue(db, "SELECT count(*) FROM public.refill_test_signal WHERE step = 'held'") === '1', 10000);
    const racing = startScript(db, `
SET application_name = 'qc_cache_refill_race';
LOAD 'safeupdate';
SET pdc.qc_cache_refill_after_compute = 'wait';
SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);
`);
    try {
      waitUntil('refill waiting on the test gate', () => psqlValue(db, `
        SELECT count(*) FROM pg_stat_activity
        WHERE application_name = 'qc_cache_refill_race'
          AND wait_event_type = 'Lock'
          AND wait_event = 'advisory'
      `) === '1', 10000);
      psql(db, "INSERT INTO public.refill_test_signal(step) VALUES ('go');");
      waitChild(racing, 15000);
      waitChild(holder, 15000);
      const stale = psqlValue(db, "SELECT count(*) FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = '00000000-0000-4000-8000-0000000000aa'");
      if (stale !== '0') throw new Error(`stale cache row was inserted (${stale})\nrace: ${racing.output()}\nholder: ${holder.output()}`);
      const gen = psqlValue(db, "SELECT gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch WHERE vehicle_id = '00000000-0000-4000-8000-0000000000aa'");
      if (gen !== '3') throw new Error(`expected epoch gen 3 after the committed edit, got ${gen}`);
      const fresh = psqlValue(db, 'SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20)');
      if (fresh !== '1') throw new Error(`expected the next refill to store the fresh row, got ${fresh}`);
    } catch (error) {
      stopChild(racing);
      throw new Error(`${error.message}\nrace: ${racing.output()}\nholder: ${holder.output()}`);
    }
  } catch (error) {
    stopChild(holder);
    throw error;
  }
}

execFileSync('bash', [path.join(root, 'scripts/install_pg_safeupdate.sh')], { stdio: 'inherit' });
psqlAdmin(`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${database}' AND pid <> pg_backend_pid()`);
psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
psqlAdmin(`CREATE DATABASE ${database}`);
if (psqlValue('postgres', "SELECT count(*) FROM pg_roles WHERE rolname = 'qc_cache_refill_writer'") !== '1') {
  psqlAdmin('CREATE ROLE qc_cache_refill_writer NOLOGIN');
}
psql(database, behavior);
runRace(database);
psqlFails(database, `BEGIN;\n${forward}\nCOMMIT;`, 'qc_cache_refill_already_installed');
psql(database, `CREATE TABLE public.pdc_production_environment_sentinel();`);
psqlFails(database, `BEGIN;\n${down}\nCOMMIT;`, 'staging_only');
psql(database, `DROP TABLE public.pdc_production_environment_sentinel;`);
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;`);
psqlFails(database, `BEGIN;\n${down}\nCOMMIT;`, 'staging_only');
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;`);
psql(database, `BEGIN;\n${down}\nCOMMIT;`);
psql(database, `
DO $$
BEGIN
  IF to_regprocedure('pdc_work_categories_private.refill_qc_operation_lines_cache(integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'refill function survived rollback';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'staging-qc-operation-lines-cache-refill') THEN
    RAISE EXCEPTION 'refill job survived rollback';
  END IF;
  IF (
    SELECT command FROM cron.job WHERE jobname = 'staging-workshop-clock-cascade'
  ) IS DISTINCT FROM 'SELECT public.workshop_clock_tick(true,clock_timestamp());' THEN
    RAISE EXCEPTION 'workshop clock command changed';
  END IF;
  IF to_regclass('pdc_work_categories_private.qc_operation_lines_cache') IS NULL THEN
    RAISE EXCEPTION 'cache table was dropped';
  END IF;
  IF to_regprocedure('public.pdc_qc_operation_lines_379_uncached(uuid)') IS NULL THEN
    RAISE EXCEPTION 'uncached function was dropped';
  END IF;
  IF to_regclass('pdc_work_categories_private.qc_operation_lines_cache_epoch') IS NOT NULL THEN
    RAISE EXCEPTION 'epoch table survived rollback';
  END IF;
  IF position('qc_operation_lines_cache_epoch' IN (
    SELECT prosrc FROM pg_proc
    WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure
  )) > 0 THEN
    RAISE EXCEPTION 'invalidate function still bumps epoch';
  END IF;
  IF position('qc_operation_lines_cache WHERE true' IN (
    SELECT prosrc FROM pg_proc
    WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure
  )) = 0 THEN
    RAISE EXCEPTION 'rollback restored a bare cache wipe';
  END IF;
END $$;
`);
psqlAdmin(`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${database}' AND pid <> pg_backend_pid()`);
psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
psqlAdmin('DROP ROLE IF EXISTS qc_cache_refill_writer');
