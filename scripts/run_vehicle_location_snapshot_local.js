/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const database = 'pdc_vehicle_location_snapshot_check';
const root = require('node:path').resolve(__dirname, '..');

function psql(db, sql) {
  execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
    input: sql,
    stdio: ['pipe', 'inherit', 'inherit']
  });
}
function psqlFails(db, sql, pattern) {
  try {
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
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

const down = fs.readFileSync(root + '/supabase/rollbacks/20261019142000_vehicle_location_snapshot_helpers.down.sql', 'utf8');
const oldFunction = down.slice(down.indexOf('CREATE OR REPLACE FUNCTION'), down.indexOf('\nDO $check$'));
const forward = fs.readFileSync(root + '/supabase/migrations/20261019142000_vehicle_location_snapshot_helpers.sql', 'utf8');
const behavior = fs.readFileSync(root + '/scripts/vehicle_location_snapshot_behavior.sql', 'utf8');

execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', `DROP DATABASE IF EXISTS ${database}`], { stdio: 'inherit' });
execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', `CREATE DATABASE ${database}`], { stdio: 'inherit' });
psql(database, `
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
${oldFunction}
`);
psql(database, forward);
psql(database, behavior);
psqlFails(database, forward, 'reviewed_snapshot_changed');
psql(database, `CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;`);
psqlFails(database, forward, 'staging_only');
psql(database, `
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE TABLE public.pdc_production_environment_sentinel();
`);
psqlFails(database, forward, 'staging_only');
psql(database, `DROP TABLE public.pdc_production_environment_sentinel;`);
psql(database, down);
psql(database, `
DO $$ DECLARE src text; BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE oid = 'public.get_pdc_email_vehicle_location_snapshot()'::regprocedure;
  IF md5(replace(src, chr(13), '')) IS DISTINCT FROM 'b10abea382e64c014e7e8577832712d7' THEN
    RAISE EXCEPTION 'rollback_md5';
  END IF;
END $$;
`);
psql(database, forward);
console.log('Vehicle location snapshot local check passed.');
