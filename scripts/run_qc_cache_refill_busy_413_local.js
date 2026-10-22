/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r413 (F29) proof on a throwaway local database (CI service Postgres via PGHOST, or sudo -u postgres psql):
// the pre-r413 refill (body from the r413 rollback) and the r413 refill (body from the r413 migration) run against the
// same minimal QC cache schema while a second session holds a lock the refill needs. Old: the run fails with
// "canceling statement due to lock timeout"; r413: returns -1 (busy). Both store nothing, and the next run fills the
// same rows. Without contention both return the same count and store identical rows; other errors still fail.
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const ID = '20261020182014_r413_qc_cache_refill_busy_skip';
const database = 'pdc_qc_cache_refill_busy_413';
const up = fs.readFileSync(path.join(root, `supabase/migrations/${ID}.sql`), 'utf8');
const down = fs.readFileSync(path.join(root, `supabase/rollbacks/${ID}.down.sql`), 'utf8');

function functionDef(sql) {
  const start = sql.indexOf('CREATE OR REPLACE FUNCTION pdc_work_categories_private.refill_qc_operation_lines_cache(');
  const end = sql.indexOf('$function$;', sql.indexOf('AS $function$', start) + 13);
  if (start < 0 || end < 0) throw new Error('refill definition not found');
  return sql.slice(start, end + '$function$;'.length);
}
const DEFS = { old: functionDef(down), new: functionDef(up) };

function command(db) {
  if (process.env.PGHOST) {
    return { file: 'psql', args: ['-h', process.env.PGHOST, '-U', process.env.PGUSER || 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1'] };
  }
  return { file: 'sudo', args: ['-u', 'postgres', 'psql', '-d', db, '-v', 'ON_ERROR_STOP=1'] };
}
function psql(db, sql) {
  const run = command(db);
  execFileSync(run.file, [...run.args, '-q', '-f', '-'], { input: sql, stdio: ['pipe', 'pipe', 'inherit'] });
}
function psqlValue(db, sql) {
  const run = command(db);
  return execFileSync(run.file, [...run.args, '-t', '-A', '-c', sql], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}
function psqlError(db, sql) {
  try {
    return { value: psqlValue(db, sql) };
  } catch (error) {
    return { error: `${error.stdout || ''}${error.stderr || ''}` };
  }
}
function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

const V = [1, 2, 3, 4, 5].map(i => `00000000-0000-4000-8000-0000000000${String(i).padStart(2, '0')}`);
const X = V[2];
const G = '00000000-0000-0000-0000-000000000000';
function schema(which) {
  return `
DROP SCHEMA IF EXISTS pdc_work_categories_private CASCADE;
DROP TABLE IF EXISTS public.vehicles;
DROP FUNCTION IF EXISTS public.pdc_qc_operation_lines_379_uncached(uuid);
CREATE SCHEMA pdc_work_categories_private;
CREATE TABLE public.vehicles(id uuid PRIMARY KEY);
CREATE TABLE pdc_work_categories_private.qc_operation_lines_cache(vehicle_id uuid PRIMARY KEY, lines jsonb NOT NULL, computed_at timestamptz NOT NULL);
CREATE TABLE pdc_work_categories_private.qc_operation_lines_cache_epoch(vehicle_id uuid PRIMARY KEY, gen bigint NOT NULL);
CREATE FUNCTION public.pdc_qc_operation_lines_379_uncached(v uuid) RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
BEGIN
  IF current_setting('proof.null_lines', true) = 'on' THEN RETURN NULL; END IF;
  RETURN jsonb_build_array(jsonb_build_object('vehicle', v, 'gen',
    (SELECT gen FROM pdc_work_categories_private.qc_operation_lines_cache_epoch WHERE vehicle_id = v)));
END $f$;
INSERT INTO public.vehicles SELECT unnest(ARRAY['${V.join("','")}']::uuid[]);
INSERT INTO pdc_work_categories_private.qc_operation_lines_cache_epoch SELECT unnest(ARRAY['${V.join("','")}','${G}']::uuid[]), 1;
${DEFS[which]}
`;
}
const REFILL = 'SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(40)';
const STORED = "SELECT count(*)::text || ':' || coalesce(md5(string_agg(vehicle_id::text || lines::text, ',' ORDER BY vehicle_id)), '-') FROM pdc_work_categories_private.qc_operation_lines_cache";

function holder(sql) {
  const run = command(database);
  const child = spawn(run.file, [...run.args, '-q', '-c', `BEGIN; ${sql}; SELECT pg_sleep(3); ROLLBACK;`], { stdio: 'ignore' });
  const started = Date.now();
  while (psqlValue(database, "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid() AND state = 'active' AND query LIKE '%pg_sleep(3)%'") !== '1') {
    if (Date.now() - started > 10000) throw new Error('lock holder did not start');
    sleepMs(50);
  }
  sleepMs(150);
  return child;
}
function waitExit(child) {
  return new Promise(resolve => { if (child.exitCode !== null) resolve(); else child.on('exit', resolve); });
}

async function main() {
  const admin = command('postgres');
  execFileSync(admin.file, [...admin.args, '-q', '-c', `DROP DATABASE IF EXISTS ${database}`], { stdio: 'ignore' });
  execFileSync(admin.file, [...admin.args, '-q', '-c', `CREATE DATABASE ${database}`], { stdio: 'ignore' });
  const results = {};
  try {
    for (const which of ['old', 'new']) {
      psql(database, schema(which));
      const plain = { first: psqlValue(database, REFILL), stored: psqlValue(database, STORED), second: psqlValue(database, REFILL) };
      const busy = {};
      for (const [name, lock] of [
        ['vehicle_epoch', `UPDATE pdc_work_categories_private.qc_operation_lines_cache_epoch SET gen = gen + 1 WHERE vehicle_id = '${X}'`],
        ['global_epoch', `UPDATE pdc_work_categories_private.qc_operation_lines_cache_epoch SET gen = gen + 1 WHERE vehicle_id = '${G}'`],
        ['cache_unique_check', `INSERT INTO pdc_work_categories_private.qc_operation_lines_cache VALUES ('${X}', '[]', now())`]
      ]) {
        psql(database, 'DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;');
        const child = holder(lock);
        const during = psqlError(database, REFILL);
        const storedDuring = psqlValue(database, STORED);
        await waitExit(child);
        busy[name] = { during, storedDuring, next: psqlValue(database, REFILL), storedAfter: psqlValue(database, STORED) };
      }
      psql(database, 'DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE true;');
      const other = psqlError(database, `SET proof.null_lines = 'on'; ${REFILL}`);
      results[which] = { plain, busy, other };
    }
  } finally {
    execFileSync(admin.file, [...admin.args, '-q', '-c', `DROP DATABASE IF EXISTS ${database}`], { stdio: 'ignore' });
  }
  const { old: o, new: n } = results;
  const fail = message => { throw new Error(`${message}\n${JSON.stringify(results, null, 1)}`); };
  if (o.plain.first !== '5' || n.plain.first !== '5' || o.plain.second !== '0' || n.plain.second !== '0') fail('plain refill counts differ');
  if (o.plain.stored !== n.plain.stored) fail('plain refill stored different rows');
  for (const name of Object.keys(o.busy)) {
    const a = o.busy[name];
    const b = n.busy[name];
    if (!a.during.error || !a.during.error.includes('canceling statement due to lock timeout')) fail(`${name}: old refill did not fail on the lock`);
    if (b.during.value !== '-1') fail(`${name}: r413 refill did not return -1 (busy)`);
    if (a.storedDuring !== '0:-' || b.storedDuring !== '0:-') fail(`${name}: something was stored while busy`);
    if (a.next !== '5' || b.next !== '5' || a.storedAfter !== b.storedAfter || a.storedAfter !== o.plain.stored) fail(`${name}: next run differs`);
  }
  for (const r of [o.other, n.other]) {
    if (!r.error || !r.error.includes('violates not-null constraint')) fail('a non-lock error was swallowed');
  }
  console.log('r413 refill busy proof: old fails on the lock, r413 returns -1; same rows stored otherwise');
}
main().catch(error => { console.error(error.message); process.exit(1); });
