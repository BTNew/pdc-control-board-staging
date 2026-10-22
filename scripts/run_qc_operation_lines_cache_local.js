/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const database = 'pdc_qc_operation_lines_cache_check';
const forward = fs.readFileSync(path.join(root, 'supabase/migrations/20261019232000_qc_operation_lines_cache.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261019232000_qc_operation_lines_cache.down.sql'), 'utf8');
const behavior = fs.readFileSync(path.join(root, 'scripts/qc_operation_lines_cache_behavior.sql'), 'utf8')
  .replace(
    '\\ir ../supabase/migrations/20261019232000_qc_operation_lines_cache.sql',
    `\\ir ${path.join(root, 'supabase/migrations/20261019232000_qc_operation_lines_cache.sql')}`
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
psqlFails(database, `BEGIN;\n${forward}\nCOMMIT;`, 'reviewed_qc_operation_lines_changed');
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
  WHERE oid = 'public.pdc_qc_operation_lines_379(uuid)'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM 'b677d7bfdf67c046fd05922da249325c' THEN
    RAISE EXCEPTION 'restored qc lines md5 %', md5(replace(src, chr(13), ''));
  END IF;
  IF to_regclass('pdc_work_categories_private.qc_operation_lines_cache') IS NOT NULL THEN
    RAISE EXCEPTION 'cache table survived rollback';
  END IF;
END $$;
`);
psqlAdmin(`DROP DATABASE IF EXISTS ${database}`);
