/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const database = 'pdc_qc_cache_safeupdate_check';
const forward = fs.readFileSync(path.join(root, 'supabase/migrations/20261020075300_fix_375_safeupdate.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261020075300_fix_375_safeupdate.down.sql'), 'utf8');
const behavior = fs.readFileSync(path.join(root, 'scripts/qc_operation_lines_cache_safeupdate_behavior.sql'), 'utf8')
  .replace(
    '\\ir ../supabase/migrations/20261020075300_fix_375_safeupdate.sql',
    `\\ir ${path.join(root, 'supabase/migrations/20261020075300_fix_375_safeupdate.sql')}`
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

execFileSync('bash', [path.join(root, 'scripts/install_pg_safeupdate.sh')], { stdio: 'inherit' });
psqlAdmin(`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${database}' AND pid <> pg_backend_pid()`);
psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
psqlAdmin(`CREATE DATABASE ${database}`);
if (psqlValue('postgres', "SELECT count(*) FROM pg_roles WHERE rolname = 'qc_cache_safeupdate_writer'") !== '1') {
  psqlAdmin('CREATE ROLE qc_cache_safeupdate_writer NOLOGIN');
}
psql(database, behavior);
psqlFails(database, `BEGIN;\n${forward}\nCOMMIT;`, 'reviewed_qc_cache_invalidate_changed');
psql(database, `CREATE TABLE public.pdc_production_environment_sentinel();`);
psqlFails(database, `BEGIN;\n${down}\nCOMMIT;`, 'staging_only');
psql(database, `DROP TABLE public.pdc_production_environment_sentinel;`);
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;`);
psqlFails(database, `BEGIN;\n${down}\nCOMMIT;`, 'staging_only');
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;`);
psql(database, `BEGIN;\n${down}\nCOMMIT;`);
psql(database, `
DO $$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src
  FROM pg_proc
  WHERE oid = 'pdc_work_categories_private.invalidate_qc_operation_lines_cache()'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM '446f28dc70b7a0e5e3ff13462ea29226' THEN
    RAISE EXCEPTION 'rollback md5 %', md5(replace(src, chr(13), ''));
  END IF;
END $$;
`);
psqlFails(database, `
LOAD 'safeupdate';
INSERT INTO pdc_work_categories_private.qc_operation_lines_cache (vehicle_id, lines, computed_at)
VALUES ('00000000-0000-4000-8000-0000000000f2', '[]'::jsonb, statement_timestamp());
INSERT INTO public.navision_backend_records (id) VALUES (2);
`, 'DELETE requires a WHERE clause');
psqlAdmin(`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${database}' AND pid <> pg_backend_pid()`);
psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
psqlAdmin('DROP ROLE IF EXISTS qc_cache_safeupdate_writer');
