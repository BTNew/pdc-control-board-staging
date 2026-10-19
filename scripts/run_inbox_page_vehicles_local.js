'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const database = 'pdc_inbox_page_vehicles_check';
const forward = fs.readFileSync(path.join(root, 'supabase/migrations/20261019231000_inbox_page_vehicles.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261019231000_inbox_page_vehicles.down.sql'), 'utf8');
const behavior = fs.readFileSync(path.join(root, 'scripts/inbox_page_vehicles_behavior.sql'), 'utf8')
  .replace(
    '\\ir ../supabase/migrations/20261019231000_inbox_page_vehicles.sql',
    `\\ir ${path.join(root, 'supabase/migrations/20261019231000_inbox_page_vehicles.sql')}`
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
psql(database, `BEGIN;\n${forward}\nCOMMIT;`);
psqlFails(database, `BEGIN;\n${forward}\nCOMMIT;`, 'reviewed_inbox_v2_changed');
psql(database, `CREATE TABLE public.pdc_production_environment_sentinel();`);
psqlFails(database, down, 'staging_only');
psql(database, `DROP TABLE public.pdc_production_environment_sentinel;`);
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;`);
psqlFails(database, down, 'staging_only');
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;`);
psql(database, `BEGIN;\n${down}\nCOMMIT;`);
psql(database, `
DO $$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src
  FROM pg_proc
  WHERE oid = 'public.get_pdc_email_ai_transaction_successor_inbox_v2(jsonb,integer)'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '6f2c14b914643a93e53dfb9339de9dca' THEN
    RAISE EXCEPTION 'restored inbox md5 %', md5(replace(src, chr(13), ''));
  END IF;
  IF to_regprocedure('public.pdc_email_inbox_snapshot_vehicle(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'page lookup survived rollback';
  END IF;
  IF to_regprocedure('public.get_pdc_email_ai_transaction_successor_inbox(timestamptz,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'v1 was created by this proof';
  END IF;
END $$;
`);
psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
