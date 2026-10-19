'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const database = 'pdc_qc_cache_refill_check';
const forward = fs.readFileSync(path.join(root, 'supabase/migrations/20261019233000_qc_operation_lines_cache_refill.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261019233000_qc_operation_lines_cache_refill.down.sql'), 'utf8');
const behavior = fs.readFileSync(path.join(root, 'scripts/qc_operation_lines_cache_refill_behavior.sql'), 'utf8')
  .replace(
    '\\ir ../supabase/migrations/20261019233000_qc_operation_lines_cache_refill.sql',
    `\\ir ${path.join(root, 'supabase/migrations/20261019233000_qc_operation_lines_cache_refill.sql')}`
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

psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
psqlAdmin(`CREATE DATABASE ${database}`);
psql(database, behavior);
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
END $$;
`);
psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
