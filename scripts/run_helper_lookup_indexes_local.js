'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const database = 'pdc_helper_lookup_indexes_check';
const forward = fs.readFileSync(path.join(root, 'supabase/migrations/20261019230000_helper_lookup_indexes.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261019230000_helper_lookup_indexes.down.sql'), 'utf8');
const behavior = fs.readFileSync(path.join(root, 'scripts/helper_lookup_indexes_behavior.sql'), 'utf8');

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
psql(database, forward);
psql(database, `
SET enable_seqscan = off;
DO $$
DECLARE plan text;
BEGIN
  plan := public.capture_plan($q$SELECT 1 FROM public.pdc_tune_operation_change_reviews q
    WHERE q.vehicle_id = '11111111-1111-4111-8111-111111111111'::uuid
      AND q.status = 'approved' AND q.change_kind = 'added'$q$);
  IF plan NOT LIKE '%pdc_tune_op_change_reviews_vehicle_idx%' THEN
    RAISE EXCEPTION 'tune reviews did not use the new index: %', plan;
  END IF;
  plan := public.capture_plan($q$SELECT 1 FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id = '22222222-2222-4222-8222-222222222222'::uuid$q$);
  IF plan NOT LIKE '%pdc_authenticated_email_operation_lines_vehicle_idx%' THEN
    RAISE EXCEPTION 'email lines did not use the new index: %', plan;
  END IF;
END $$;
`);
psql(database, `ALTER TABLE public.pdc_tune_operation_change_reviews ALTER COLUMN status TYPE varchar(40);`);
psqlFails(database, forward, 'reviewed_helper_lookup_columns_changed');
psql(database, `ALTER TABLE public.pdc_tune_operation_change_reviews ALTER COLUMN status TYPE text;`);
psql(database, `CREATE TABLE public.pdc_production_environment_sentinel();`);
psqlFails(database, forward, 'staging_only');
psql(database, `DROP TABLE public.pdc_production_environment_sentinel;`);
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;`);
psqlFails(database, down, 'staging_only');
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;`);
psql(database, down);
psql(database, `
DO $$
BEGIN
  IF to_regclass('public.pdc_tune_op_change_reviews_vehicle_idx') IS NOT NULL
     OR to_regclass('public.pdc_authenticated_email_operation_lines_vehicle_idx') IS NOT NULL THEN
    RAISE EXCEPTION 'rollback left an index';
  END IF;
END $$;
`);
console.log('Helper lookup index local check passed.');
