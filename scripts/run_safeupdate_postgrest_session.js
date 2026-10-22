/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const database = 'pdc_safeupdate_ci_check';
const authenticator = 'pdc_safeupdate_ci_authenticator';
const authenticated = 'pdc_safeupdate_ci_authenticated';
const authenticatorPassword = 'pdc-safeupdate-ci';

function psqlArgs(db, role) {
  const args = ['-v', 'ON_ERROR_STOP=1', '-d', db || 'postgres'];
  if (process.env.PGHOST) {
    args.unshift('-h', process.env.PGHOST, '-U', role || process.env.PGUSER || 'postgres');
    return { cmd: 'psql', args };
  }
  if (role && role !== 'postgres') {
    throw new Error(`PGHOST is required to open a PostgREST session as ${role}`);
  }
  return { cmd: 'sudo', args: ['-u', 'postgres', 'psql', ...args] };
}

function psql(db, sql, role) {
  const spec = psqlArgs(db, role);
  return execFileSync(spec.cmd, [...spec.args, '-c', sql], { encoding: 'utf8' });
}

function psqlFile(db, file, role) {
  const spec = psqlArgs(db, role);
  execFileSync(spec.cmd, [...spec.args, '-f', file], { stdio: 'inherit' });
}

function psqlAuthenticator(db, fileOrSql, file) {
  const host = process.env.PGHOST || '127.0.0.1';
  const args = ['-h', host, '-U', authenticator, '-d', db, '-v', 'ON_ERROR_STOP=1'];
  if (file) args.push('-f', fileOrSql);
  else args.push('-c', fileOrSql);
  return execFileSync('psql', args, {
    encoding: 'utf8',
    env: { ...process.env, PGPASSWORD: authenticatorPassword },
    stdio: file ? 'inherit' : 'pipe',
  });
}

function roleExists(name) {
  const out = psql('postgres', `SELECT CASE WHEN EXISTS(SELECT 1 FROM pg_roles WHERE rolname='${name}') THEN 'yes' ELSE 'no' END`);
  return /\byes\b/.test(out);
}

execFileSync('bash', [path.join(root, 'scripts/install_pg_safeupdate.sh')], { stdio: 'inherit' });

if (!roleExists(authenticated)) psql('postgres', `CREATE ROLE ${authenticated} NOLOGIN NOSUPERUSER NOBYPASSRLS`);
if (!roleExists(authenticator)) psql('postgres', `CREATE ROLE ${authenticator} LOGIN NOSUPERUSER NOBYPASSRLS`);
psql('postgres', `GRANT ${authenticated} TO ${authenticator}`);
psql('postgres', `ALTER ROLE ${authenticator} PASSWORD '${authenticatorPassword}'`);
psql('postgres', `ALTER ROLE ${authenticator} SET session_preload_libraries = 'safeupdate'`);

psql('postgres', `DROP DATABASE IF EXISTS ${database}`);
psql('postgres', `CREATE DATABASE ${database}`);
try {
  psql(database, "LOAD 'safeupdate';");
  psqlFile(database, path.join(root, 'scripts/safeupdate_migration_owner_check.sql'));
  psqlAuthenticator(database, path.join(root, 'scripts/safeupdate_postgrest_session.sql'), true);
} finally {
  psql('postgres', `DROP DATABASE IF EXISTS ${database} WITH (FORCE)`);
  psql('postgres', `DROP ROLE IF EXISTS ${authenticator}`);
  psql('postgres', `DROP ROLE IF EXISTS ${authenticated}`);
}

const suites = [
  ...fs.readdirSync(path.join(root, 'supabase/tests')).filter(name => name.endsWith('.sql')),
];
const pgtap = suites.filter(name => fs.readFileSync(path.join(root, 'supabase/tests', name), 'utf8').includes('SELECT plan('));
if (pgtap.length) {
  throw new Error(`pgTAP files must be added to the PostgREST safeupdate session runner: ${pgtap.join(', ')}`);
}
