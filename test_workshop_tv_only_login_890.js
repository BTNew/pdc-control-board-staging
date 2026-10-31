'use strict';
// r890 (F440): the workshop TV login presses Tyre / Tint Start / Stop only (Craig 31 Oct 2026).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const MIGRATION = 'supabase/migrations/20261031093000_r890_workshop_tv_only_login.sql';
const ROLLBACK = 'supabase/rollbacks/20261031093000_r890_workshop_tv_only_login.down.sql';

function hookAllowlist(sql, marker) {
  const at = sql.indexOf(marker);
  assert.ok(at >= 0, `missing ${marker}`);
  const m = sql.slice(at).match(/path NOT IN \(([^)]*)\)/);
  assert.ok(m, 'allowlist not found');
  return m[1].split(',').map(s => s.trim().replace(/^'rpc\/|'$/g, '').replace(/^'/, ''));
}

test('database: TV branch allows only the three TV calls plus login records', () => {
  const sql = fs.readFileSync(MIGRATION, 'utf8');
  assert.match(sql, /INSERT INTO pdc_tv_private\.displays[\s\S]{0,80}'workshopdisplay@pmgwa\.com\.au'/);
  const list = hookAllowlist(sql, 'IF pdc_tv_private.is_tv_request_890() THEN');
  assert.deepEqual(list.sort(), ['complete_workshop_work', 'get_pdc_workshop_tv_605', 'record_pdc_login', 'record_pdc_usage_20260914', 'start_workshop_work']);
  assert.match(sql, /This account can access the workshop TV only/);
});

test('database: TV status changes refused outside TINT and TYRE', () => {
  const sql = fs.readFileSync(MIGRATION, 'utf8');
  assert.match(sql, /IF OLD\.status IS NOT DISTINCT FROM NEW\.status THEN RETURN NEW; END IF;/);
  assert.match(sql, /NOT IN \('TINT','TYRE'\)/);
  assert.match(sql, /CREATE TRIGGER workshop_booking_047_tv_tyre_tint_890\s+BEFORE UPDATE ON public\.workshop_bookings/);
});

test('database: fitter, MMT and PSC branches are unchanged and the undo restores the r711 hook', () => {
  const sql = fs.readFileSync(MIGRATION, 'utf8');
  const down = fs.readFileSync(ROLLBACK, 'utf8');
  for (const text of [sql, down]) {
    assert.match(text, /This account can access Fitters bay only/);
    assert.match(text, /rpc\/get_pdc_mmt_sublet_board_642','rpc\/set_pdc_mmt_sublet_tick_642'/);
    assert.match(text, /rpc\/get_pdc_psc_sublet_board_711','rpc\/set_pdc_psc_sublet_tick_711'/);
  }
  assert.deepEqual(hookAllowlist(sql, "role::text='fitter') THEN\n  IF path='pdc_user_roles'"), hookAllowlist(down, "role::text='fitter') THEN\n  IF path='pdc_user_roles'"));
  assert.doesNotMatch(down, /is_tv_request_890\(\) THEN/);
  assert.match(down, /DROP TRIGGER IF EXISTS workshop_booking_047_tv_tyre_tint_890/);
});

test('browser: TV login refuses other RPCs locally and is sent to the TV page', () => {
  const auth = fs.readFileSync('pdc-auth.js', 'utf8');
  assert.match(auth, /TV_LOGINS = Object\.freeze\(new Set\(\['workshopdisplay@pmgwa\.com\.au'\]\)\)/);
  assert.match(auth, /isTvSession\(\) && !TV_RPC_ALLOWLIST\.has/);
  assert.match(auth, /if \(routeTvLogin\(session\?\.user\?\.email\)\) return false;\n\s+const salesLinked = await loadControllerSalesLink/);
  // The browser list matches the database hook.
  const sql = fs.readFileSync(MIGRATION, 'utf8');
  const db = hookAllowlist(sql, 'IF pdc_tv_private.is_tv_request_890() THEN').sort();
  const m = auth.match(/TV_RPC_ALLOWLIST = Object\.freeze\(new Set\(\[([\s\S]*?)\]\)\)/);
  const browser = m[1].split(',').map(s => s.trim().replace(/'/g, '')).filter(Boolean).sort();
  assert.deepEqual(browser, db);
});

test('TV page only calls what the TV login is allowed', () => {
  const tv = fs.readFileSync('workshop-tv.js', 'utf8');
  const calls = [...tv.matchAll(/\.rpc\('([a-z0-9_]+)'/g)].map(m => m[1]);
  assert.ok(calls.length >= 3);
  for (const name of calls) assert.ok(['get_pdc_workshop_tv_605', 'start_workshop_work', 'complete_workshop_work'].includes(name), name);
  assert.doesNotMatch(tv, /\.from\('/);
});
