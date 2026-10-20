'use strict';

const { execFileSync } = require('node:child_process');
const path = require('node:path');

const root = path.join(__dirname, '..');
const database = 'pdc_navision_delivery_skip_check';

function psql(db, sql, options = {}) {
  const file = options === true || options.file === true;
  const args = ['-v', 'ON_ERROR_STOP=1', '-d', db];
  if (process.env.PGHOST) args.unshift('-h', process.env.PGHOST, '-U', process.env.PGUSER || 'postgres');
  if (file) args.push('-f', sql);
  else args.push('-c', sql);
  const cmd = process.env.PGHOST ? 'psql' : 'sudo';
  const full = process.env.PGHOST ? args : ['-u', 'postgres', 'psql', ...args];
  const stdio = options.stdio || (file ? 'inherit' : 'pipe');
  return execFileSync(cmd, full, { encoding: 'utf8', stdio });
}

function ensureRole(name) {
  const out = psql('postgres', `SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${name}') THEN 'yes' ELSE 'no' END`);
  if (!/\byes\b/.test(out)) psql('postgres', `CREATE ROLE ${name} NOLOGIN NOSUPERUSER NOBYPASSRLS`);
}

execFileSync('bash', [path.join(root, 'scripts/install_pg_safeupdate.sh')], { stdio: 'inherit' });
for (const role of ['anon', 'authenticated', 'service_role']) ensureRole(role);
psql('postgres', `DROP DATABASE IF EXISTS ${database}`);
psql('postgres', `CREATE DATABASE ${database}`);
try {
  psql(database, path.join(root, 'scripts/navision_delivery_skip_setup.sql'), true);
  psql(database, path.join(root, 'supabase/migrations/20261020123000_navision_delivery_skip_deleted_vehicle.sql'), true);
  psql(database, path.join(root, 'scripts/navision_delivery_skip_proof.sql'), true);
  let second = '';
  try {
    psql(database, path.join(root, 'supabase/migrations/20261020123000_navision_delivery_skip_deleted_vehicle.sql'), { file: true, stdio: 'pipe' });
  } catch (error) {
    second = `${error.stdout || ''}\n${error.stderr || ''}`;
  }
  if (!second.includes('navision_delivery_skip_trigger_changed')) {
    throw new Error(`second apply did not reject the changed trigger: ${second}`);
  }
  psql(database, path.join(root, 'supabase/rollbacks/20261020123000_navision_delivery_skip_deleted_vehicle.down.sql'), true);
  psql(database, `
DO $restored$
BEGIN
  UPDATE public.navision_backend_records
  SET normalized_data = normalized_data || jsonb_build_object('toyotaStatus', 'Delivered - At Dealer')
  WHERE id = '6906a7ff-a37f-4bd7-a177-131569874804';
  RAISE EXCEPTION 'restored trigger did not abort';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%navision_dealer_delivery_failed: delivery_vehicle_not_found%' THEN
      RAISE EXCEPTION 'restored trigger raised %', SQLERRM;
    END IF;
    IF (SELECT deleted_at FROM public.vehicles WHERE id = 'f63ee01e-091c-4f67-95a2-5013ceb0c3f8')
       IS DISTINCT FROM '2026-10-19 07:25:52.425943+00' THEN
      RAISE EXCEPTION 'rollback changed the soft-deleted vehicle';
    END IF;
END
$restored$;
`);
} finally {
  psql('postgres', `DROP DATABASE IF EXISTS ${database} WITH (FORCE)`);
}
