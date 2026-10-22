#!/usr/bin/env node
/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// Local Postgres evidence for the RLS initplan migration.
// Not named test_*.js: GitHub Actions has no Postgres, and this script is not part of CI.
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const forward = path.join(root, 'supabase/migrations/20261019140000_rls_auth_initplan_and_overlapping_policies.sql');
const down = path.join(root, 'supabase/rollbacks/20261019140000_rls_auth_initplan_and_overlapping_policies.down.sql');
const psql = (args) => execFileSync('sudo', ['-u', 'postgres', 'psql', ...args], { stdio: 'inherit' });

psql(['-c', 'DROP DATABASE IF EXISTS pdc_rls_initplan_check']);
psql(['-c', 'CREATE DATABASE pdc_rls_initplan_check']);
psql(['-d', 'pdc_rls_initplan_check', '-v', 'ON_ERROR_STOP=1', '-f', path.join(root, 'scripts/rls_initplan_local_check.sql')]);
psql([
  '-d', 'pdc_rls_initplan_check', '-v', 'ON_ERROR_STOP=1',
  '-v', `forward=${forward}`,
  '-v', `down=${down}`,
  '-f', path.join(root, 'scripts/rls_initplan_local_assert.sql')
]);
