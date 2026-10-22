/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const root = path.join(__dirname, '..');
const database = 'pdc_bus4x4_conversion_tick_check';

function psql(db, sql, options = {}) {
  const file = options.file === true;
  const args = ['-v', 'ON_ERROR_STOP=1', '-d', db];
  if (process.env.PGHOST) args.unshift('-h', process.env.PGHOST, '-U', process.env.PGUSER || 'postgres');
  if (file) args.push('-f', sql);
  else args.push('-c', sql);
  const cmd = process.env.PGHOST ? 'psql' : 'sudo';
  const full = process.env.PGHOST ? args : ['-u', 'postgres', 'psql', ...args];
  return execFileSync(cmd, full, { encoding: 'utf8', stdio: options.stdio || (file ? 'inherit' : 'pipe') });
}

function slice(file, start, end) {
  const text = fs.readFileSync(path.join(root, file), 'utf8');
  const from = text.indexOf(start);
  const to = text.indexOf(end);
  if (from < 0 || to < from) throw new Error(`missing markers in ${file}`);
  return text.slice(from, to);
}

const script = [
  fs.readFileSync(path.join(root, 'scripts/bus4x4_conversion_tick_setup.sql'), 'utf8'),
  fs.readFileSync(path.join(root, 'scripts/bus4x4_conversion_tick_before.sql'), 'utf8'),
  slice('supabase/migrations/20261020140000_bus4x4_conversion_simple_tick.sql', '-- SIMPLE TICK APPLY', '-- END SIMPLE TICK APPLY'),
  fs.readFileSync(path.join(root, 'scripts/bus4x4_conversion_tick_before.sql'), 'utf8'),
  fs.readFileSync(path.join(root, 'scripts/bus4x4_conversion_tick_after.sql'), 'utf8'),
  fs.readFileSync(path.join(root, 'supabase/rollbacks/20261020140000_bus4x4_conversion_simple_tick.down.sql'), 'utf8'),
  fs.readFileSync(path.join(root, 'scripts/bus4x4_conversion_tick_restored.sql'), 'utf8'),
].join('\n');

const file = path.join(os.tmpdir(), `bus4x4-conversion-tick-${process.pid}.sql`);
fs.writeFileSync(file, script);
psql('postgres', `DROP DATABASE IF EXISTS ${database}`);
psql('postgres', `CREATE DATABASE ${database}`);
try {
  psql(database, file, { file: true });
} finally {
  psql('postgres', `DROP DATABASE IF EXISTS ${database} WITH (FORCE)`);
  fs.unlinkSync(file);
}
