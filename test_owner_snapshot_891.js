'use strict';
// r891 (F441): owner snapshot page, Craig and Dave only (Craig 31 Oct 2026).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const MIGRATION = 'supabase/migrations/20261031133000_r891_owner_snapshot.sql';
const ROLLBACK = 'supabase/rollbacks/20261031133000_r891_owner_snapshot.down.sql';

test('database: only Craig and Dave are on the owner list and the call refuses everyone else', () => {
  const sql = fs.readFileSync(MIGRATION, 'utf8');
  const insert = sql.match(/INSERT INTO pdc_owner_private\.viewers \(email, note\) VALUES([\s\S]*?)ON CONFLICT/);
  assert.ok(insert);
  const emails = [...insert[1].matchAll(/\('([^']+)'/g)].map((m) => m[1]).sort();
  assert.deepEqual(emails, ['craig.watson@broometoyota.com.au', 'dave@pmgwa.com.au']);
  assert.match(sql, /IF NOT public\.is_pdc_owner_viewer_891\(\) THEN\s+RAISE EXCEPTION 'This page is for owner logins only' USING errcode = '42501'/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.get_pdc_owner_snapshot_891\(\) FROM PUBLIC, anon;/);
  assert.match(sql, /REVOKE ALL ON pdc_owner_private\.viewers FROM PUBLIC, anon, authenticated;/);
  assert.match(sql, /r\.active AND r\.account_status = 'approved'/);
});

test('database: board rules (At PMB = key not WPC, key-date age, read only)', () => {
  const sql = fs.readFileSync(MIGRATION, 'utf8');
  assert.match(sql, /coalesce\(v\.key_number, ''\) <> '' AND upper\(v\.key_number\) <> 'WPC'/);
  assert.match(sql, /pdc_vehicle_key_assigned_562/);
  assert.match(sql, /STABLE SECURITY DEFINER/);
  assert.doesNotMatch(sql, /\b(UPDATE|DELETE FROM)\s+public\./i);
  assert.doesNotMatch(sql, /CREATE TRIGGER/);
  const down = fs.readFileSync(ROLLBACK, 'utf8');
  assert.match(down, /DROP FUNCTION IF EXISTS public\.get_pdc_owner_snapshot_891\(\)/);
  assert.match(down, /DROP SCHEMA IF EXISTS pdc_owner_private/);
});

test('page: one read-only call, no innerHTML, shipped in the pages build', () => {
  const js = fs.readFileSync('owner.js', 'utf8');
  const calls = [...js.matchAll(/\.rpc\('([^']+)'/g)].map((m) => m[1]);
  assert.deepEqual([...new Set(calls)], ['get_pdc_owner_snapshot_891']);
  assert.doesNotMatch(js, /innerHTML/);
  const html = fs.readFileSync('owner.html', 'utf8');
  assert.match(html, /owner\.js\?r891=/);
  assert.doesNotMatch(html, /—/);
  const build = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  for (const f of ["'owner.html'", "'owner.js'", "'owner/index.html'"]) assert.ok(build.includes(f), f);
});
