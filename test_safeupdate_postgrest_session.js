/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';

const test = require('node:test');
const { execFileSync } = require('node:child_process');
const path = require('node:path');

function postgresAvailable() {
  if (process.env.PGHOST) return true;
  try {
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-c', 'SELECT 1'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

test('migrations and SQL sessions run with pg_safeupdate and a PostgREST authenticated role', { skip: postgresAvailable() ? false : 'no local Postgres' }, () => {
  execFileSync(process.execPath, [path.join('scripts', 'run_safeupdate_postgrest_session.js')], {
    stdio: 'inherit',
  });
});
