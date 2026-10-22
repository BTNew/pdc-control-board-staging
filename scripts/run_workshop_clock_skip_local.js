/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const database = 'pdc_workshop_clock_skip_check';

function psql(db, sql, variables) {
  const args = ['-u', 'postgres', 'psql', '-d', db, '-v', 'ON_ERROR_STOP=1'];
  for (const [key, value] of Object.entries(variables || {})) args.push('-v', `${key}=${value}`);
  if (typeof sql === 'string' && sql.endsWith('.sql')) args.push('-f', sql);
  else args.push('-f', '-');
  execFileSync('sudo', args, {
    input: typeof sql === 'string' && sql.endsWith('.sql') ? undefined : sql,
    stdio: ['pipe', 'inherit', 'inherit']
  });
}
function psqlText(db, sql) {
  return execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', db, '-v', 'ON_ERROR_STOP=1', '-t', '-A', '-f', '-'], {
    input: sql, encoding: 'utf8'
  }).trim();
}
function psqlFails(db, sql, pattern) {
  try {
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
      input: sql, stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (error) {
    const output = `${error.stdout || ''}${error.stderr || ''}`;
    if (!output.includes(pattern)) throw new Error(`Expected ${pattern} but got ${output}`);
    return;
  }
  throw new Error(`Expected failure ${pattern}`);
}
function extractFunction(file, signature) {
  const sql = fs.readFileSync(path.join(root, file), 'utf8');
  const start = sql.indexOf(signature);
  if (start < 0) throw new Error(`missing ${signature} in ${file}`);
  const asAt = sql.indexOf('AS $', start);
  const tagMatch = sql.slice(asAt).match(/^AS (\$[A-Za-z0-9_]*\$)/);
  if (!tagMatch) throw new Error(`no dollar tag for ${signature}`);
  const tag = tagMatch[1];
  const closeAt = sql.indexOf(tag, asAt + tagMatch[0].length);
  let end = closeAt + tag.length;
  while (end < sql.length && /\s/.test(sql[end])) end += 1;
  if (sql[end] !== ';') throw new Error(`no semicolon after ${signature}`);
  return sql.slice(start, end + 1);
}

const slices = [
  ['supabase/migrations/20260913222020_workshop_operational_calendar_intervals.sql', 'CREATE OR REPLACE FUNCTION public.workshop_add_operational_minutes'],
  ['supabase/migrations/20260914030349_workshop_booking_validation_performance.sql', 'CREATE OR REPLACE FUNCTION public.workshop_operational_minutes_between'],
  ['supabase/migrations/20260922203826_dept138_team_and_planning_clarifications.sql', 'CREATE OR REPLACE FUNCTION pdc_bus_private.minute_available'],
  ['supabase/migrations/20260920231044_dept138_supplier_workflow.sql', 'CREATE FUNCTION pdc_bus_private.add_minutes'],
  ['supabase/migrations/20260921012441_workshop_bus_clock_calendar.sql', 'CREATE FUNCTION pdc_bus_private.clock_next_minute'],
  ['supabase/migrations/20260921012441_workshop_bus_clock_calendar.sql', 'CREATE FUNCTION pdc_bus_private.clock_add_minutes'],
  ['supabase/migrations/20260921012441_workshop_bus_clock_calendar.sql', 'CREATE FUNCTION pdc_bus_private.clock_minutes_between'],
  ['supabase/migrations/20261018124219_clock_plan_calendar_reuse.sql', 'CREATE OR REPLACE FUNCTION public.workshop_clock_plan'],
  ['supabase/migrations/20261019044410_workshop_clock_arrival_floor.sql', 'CREATE OR REPLACE FUNCTION public.workshop_booking_effective_end_at'],
  ['supabase/migrations/20261019044410_workshop_clock_arrival_floor.sql', 'CREATE OR REPLACE FUNCTION public.workshop_clock_tick']
];

execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', `DROP DATABASE IF EXISTS ${database}`], { stdio: 'inherit' });
execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', `CREATE DATABASE ${database}`], { stdio: 'inherit' });

let failed = true;
try {
  psql(database, path.join(root, 'scripts/workshop_clock_skip_schema.sql'));
  const calendarMd5 = psqlText(database, "SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_calendar_minute_available(timestamptz)'::regprocedure;");
  const nextMd5 = psqlText(database, "SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_next_minute(timestamptz)'::regprocedure;");
  if (calendarMd5 !== '6b53f98e01026e379d5498d668ec6cbd') throw new Error(`calendar body ${calendarMd5}`);
  if (nextMd5 !== '6849b6c6eb2360f04a7f66a3828a351a') throw new Error(`clock_next_minute body ${nextMd5}`);
  for (const [file, signature] of slices) {
    const body = extractFunction(file, signature);
    console.log(`install ${signature} (${body.length} bytes)`);
    psql(database, body);
  }
  psql(database, path.join(root, 'supabase/migrations/20261019052824_workshop_clock_unallocated_scope.sql'));
  const baseline = psqlText(database, "SELECT md5(replace(prosrc, chr(13), '')) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;");
  if (baseline !== 'a7cd97007e7fdd96b01c90929d42fe2d') throw new Error(`live clock precondition ${baseline}`);
  psql(database, path.join(root, 'scripts/workshop_clock_skip_behavior.sql'));
  psql(database, `
DO $check$ BEGIN
 IF public.workshop_calendar_minute_available('2026-10-17 12:00:00+08')
  OR public.workshop_calendar_minute_available('2026-10-18 12:00:00+08')
  OR public.workshop_calendar_minute_available('2026-10-19 05:59:00+08')
  OR public.workshop_calendar_minute_available('2026-10-19 16:30:00+08')
  OR NOT public.workshop_calendar_minute_available('2026-10-19 06:00:00+08')
  OR NOT public.workshop_calendar_minute_available('2026-10-19 16:29:00+08') THEN
  RAISE EXCEPTION 'ordinary calendar is not weekdays 06:00-16:30';
 END IF;
 IF public.workshop_add_operational_minutes('2026-10-16 16:00:00+08', 60) IS DISTINCT FROM '2026-10-19 06:30:00+08'::timestamptz THEN
  RAISE EXCEPTION 'operational minute walk changed';
 END IF;
 IF public.workshop_clock_next_minute('2026-10-17 12:00:00+08') IS DISTINCT FROM '2026-10-19 06:00:00+08'::timestamptz THEN
  RAISE EXCEPTION 'clock floor did not skip the weekend';
 END IF;
 IF pdc_bus_private.minute_available('2026-10-17 12:00:00+08', '20000000-0000-4000-8000-000000000008')
  OR NOT pdc_bus_private.minute_available('2026-10-19 06:00:00+08', '20000000-0000-4000-8000-000000000008')
  OR pdc_bus_private.minute_available('2026-10-19 15:00:00+08', '20000000-0000-4000-8000-000000000008') THEN
  RAISE EXCEPTION 'bus calendar is not weekdays 06:00-15:00';
 END IF;
END $check$;
`);
  const capture = path.join(root, 'scripts/workshop_clock_skip_capture.sql');
  psql(database, capture, { phase: 'before', time: 'yes' });
  psql(database, path.join(root, 'supabase/migrations/20261019143000_workshop_clock_skip_unchanged.sql'));
  const rewritten = psqlText(database, "SELECT md5(replace(prosrc, chr(13), '')) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;");
  if (rewritten !== '84af7607bfd0ce9907c89bae8644d5b6') throw new Error(`rewritten clock ${rewritten}`);
  psql(database, capture, { phase: 'after', time: 'yes' });
  psql(database, 'SELECT probe_compare();');
  psqlFails(database, fs.readFileSync(path.join(root, 'supabase/migrations/20261019143000_workshop_clock_skip_unchanged.sql'), 'utf8'), 'reviewed_clock_changed');
  psql(database, "CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $g$ SELECT false $g$;");
  psqlFails(database, fs.readFileSync(path.join(root, 'supabase/migrations/20261019143000_workshop_clock_skip_unchanged.sql'), 'utf8'), 'staging_only');
  psql(database, `
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $g$ SELECT true $g$;
CREATE TABLE public.pdc_production_environment_sentinel();
`);
  psqlFails(database, fs.readFileSync(path.join(root, 'supabase/migrations/20261019143000_workshop_clock_skip_unchanged.sql'), 'utf8'), 'staging_only');
  psqlFails(database, fs.readFileSync(path.join(root, 'supabase/rollbacks/20261019143000_workshop_clock_skip_unchanged.down.sql'), 'utf8'), 'staging_only');
  psql(database, 'DROP TABLE public.pdc_production_environment_sentinel;');
  psql(database, path.join(root, 'supabase/rollbacks/20261019143000_workshop_clock_skip_unchanged.down.sql'));
  const restored = psqlText(database, "SELECT md5(replace(prosrc, chr(13), '')) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;");
  if (restored !== 'a7cd97007e7fdd96b01c90929d42fe2d') throw new Error(`rollback checksum ${restored}`);
  psql(database, capture, { phase: 'rollback', time: 'no' });
  psql(database, 'SELECT probe_compare_rollback();');
  psqlFails(database, fs.readFileSync(path.join(root, 'supabase/rollbacks/20261019143000_workshop_clock_skip_unchanged.down.sql'), 'utf8'), 'reviewed_clock_changed');
  psql(database, path.join(root, 'supabase/migrations/20261019143000_workshop_clock_skip_unchanged.sql'));
  psql(database, `
SELECT phase || ' ' || kind || ' ' || avg_ms::text || ' ms (' || samples::text || ' samples)'
FROM public.probe_timing ORDER BY kind, phase;
`);
  failed = false;
  console.log('Workshop clock skip local check passed.');
} finally {
  if (!failed) {
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', `DROP DATABASE IF EXISTS ${database}`], { stdio: 'inherit' });
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', 'DROP DATABASE IF EXISTS pdc_clock_checksum_probe'], { stdio: 'inherit' });
  }
}
