#!/usr/bin/env node
// Local Postgres evidence for the realtime publication prune. Not part of CI.
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const forward = path.join(root, 'supabase/migrations/20261019141000_realtime_publication_prune.sql');
const down = path.join(root, 'supabase/rollbacks/20261019141000_realtime_publication_prune.down.sql');
const psql = (args) => execFileSync('sudo', ['-u', 'postgres', 'psql', ...args], { stdio: 'inherit' });

psql(['-c', 'DROP DATABASE IF EXISTS pdc_realtime_publication_check']);
psql(['-c', 'CREATE DATABASE pdc_realtime_publication_check']);
psql(['-d', 'pdc_realtime_publication_check', '-v', 'ON_ERROR_STOP=1', '-f', path.join(root, 'scripts/realtime_publication_local_check.sql')]);
psql([
  '-d', 'pdc_realtime_publication_check', '-v', 'ON_ERROR_STOP=1',
  '-v', `forward=${forward}`,
  '-v', `down=${down}`,
  '-f', path.join(root, 'scripts/realtime_publication_local_assert.sql')
]);
