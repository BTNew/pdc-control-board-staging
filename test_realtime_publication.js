const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const forwardPath = 'supabase/migrations/20261019141000_realtime_publication_prune.sql';
const downPath = 'supabase/rollbacks/20261019141000_realtime_publication_prune.down.sql';

function names(sql, marker) {
  const match = sql.match(new RegExp(marker + ' text\\[\\] := ARRAY\\[([\\s\\S]*?)\\];'));
  assert.ok(match, marker);
  return match[1].match(/'([a-z0-9_.]+)'/g).map(token => token.slice(1, -1));
}

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    if (['node_modules', 'vendor', 'karratha', '.git'].includes(name)) continue;
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) walk(full, out);
    else if (/\.(js|html)$/.test(name) && !name.startsWith('test_')) out.push(full);
  }
  return out;
}

function subscribedTables() {
  const found = new Set();
  for (const file of walk('.')) {
    const source = fs.readFileSync(file, 'utf8');
    const constants = new Map();
    for (const match of source.matchAll(/const\s+([A-Z0-9_]+)\s*=\s*'([a-z0-9_]+)'/g)) constants.set(match[1], match[2]);
    for (const match of source.matchAll(/postgres_changes[\s\S]{0,400}?table:\s*'([a-z0-9_]+)'/g)) found.add(match[1]);
    for (const match of source.matchAll(/const table = [^;]*'([a-z0-9_]+)'[^;]*'([a-z0-9_]+)'/g)) {
      found.add(match[1]);
      found.add(match[2]);
    }
    for (const match of source.matchAll(/subscribeRealtime\(\s*(?:'([a-z0-9_]+)'|([A-Z0-9_]+))/g)) {
      found.add(match[1] || constants.get(match[2]));
    }
    for (const match of source.matchAll(/createPdcSupabaseTableRealtimeSubscription\(\s*(?:'([a-z0-9_]+)'|([A-Z0-9_]+))/g)) {
      if (match[1] || constants.get(match[2])) found.add(match[1] || constants.get(match[2]));
    }
    if (file.endsWith('workshop-reference-data-service.js')) {
      for (const match of source.matchAll(/table:\s*'([a-z0-9_]+)'/g)) found.add(match[1]);
    }
  }
  found.delete(undefined);
  return found;
}

test('realtime prune drops only tables the front end does not subscribe to', () => {
  const forward = fs.readFileSync(forwardPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  const expected = names(forward, 'expected').sort();
  const drop = names(forward, 'drop_members').sort();
  const restore = names(down, 'drop_members').sort();
  const subscribed = [...subscribedTables()].sort();
  const keep = expected.filter(name => name.startsWith('public.') && !drop.includes(name)).map(name => name.slice('public.'.length));
  assert.deepEqual(drop, restore);
  assert.deepEqual(keep, subscribed);
  assert.equal(drop.length, 36);
  assert.ok(drop.filter(name => name.startsWith('karratha135_pdc.')).length === 14);
  assert.match(forward, /pdc_monitor_staging_guard\(\)/);
  assert.match(forward, /reviewed_publication_changed/);
  assert.match(forward, /ALTER PUBLICATION supabase_realtime DROP TABLE %I\.%I/);
  assert.equal((forward.match(/DROP TABLE/g) || []).length, 1);
  assert.doesNotMatch(forward, /\bDELETE FROM\b/);
  assert.match(down, /ALTER PUBLICATION supabase_realtime ADD TABLE/);
  assert.equal(fs.existsSync(path.join('supabase/migrations', path.basename(downPath))), false);
  for (const table of subscribed) assert.equal(drop.includes(`public.${table}`), false, table);
});
