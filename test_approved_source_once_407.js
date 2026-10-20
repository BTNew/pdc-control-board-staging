'use strict';
// r407 (F21): pdc_tune_approved_operation_source_20260912 ran 36,036 times per board
// snapshot as a LANGUAGE sql function with SET search_path (never inlined, re-planned on
// every nested call), and operation_station looked it up twice per operation. The helper is
// now PL/pgSQL (plan kept) and operation_station looks it up once. Board and location
// snapshot JSON were byte-identical (md5, per department) in the rolled-back test.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const crypto = require('crypto');

const ID = '20261020145404_r407_approved_source_lookup_once';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const md5 = s => crypto.createHash('md5').update(s).digest('hex');
const CHECK_MD5 = '3065f403b5945c40cc864958ecc5dfe2';
const OLD = { helper: '157311e04f989c5c8a47c8894bd3a278', station: '415c4a6993e8693f155c1c3fa4824d5e' };
const NEW = { helper: '867bb1b1c0afebfb62f45c08ad6b3154', station: 'a63c9309fd6ae046d37709cfb3666019' };
const CLOCK_TICK = '84af7607bfd0ce9907c89bae8644d5b6';

function body(sql, sig) {
  const at = sql.indexOf(`CREATE OR REPLACE FUNCTION ${sig}`);
  assert.ok(at >= 0, sig);
  const s = sql.indexOf('$function$', at) + '$function$'.length;
  return sql.slice(s, sql.indexOf('$function$', s));
}
function checkSql() {
  const m = up.match(/'approved_source_lookup_once','F21','(?:[^']|'')*','((?:[^']|'')*)',true,197,'r407'\)/);
  assert.ok(m, 'check row');
  return m[1].replace(/''/g, "'");
}

test('migration is staging-only, windowed, and asserts every md5 before and after', () => {
  for (const sql of [up, down]) {
    assert.match(sql, /pdc_monitor_staging_guard\(\)/);
    assert.match(sql, /project_ref='cdsmnqxtyyoeoznmbidd'/);
    assert.match(sql, /pdc_production_environment_sentinel/);
    assert.match(sql, /SET LOCAL lock_timeout = '2s';/);
    assert.match(sql, /NOT BETWEEN 2 AND 45/, 'release-test window');
    assert.ok(sql.includes(`'${CLOCK_TICK}'`), 'clock tick asserted unchanged');
    assert.ok(!sql.includes('vjdtsswhroyguxyfjdkt'));
    assert.doesNotMatch(sql, /@[a-z0-9.-]+\.(com|au)/i, 'no email addresses');
  }
  assert.doesNotMatch(up + down, /workshop_clock_tick\(boolean,timestamptz\)\s*\n?\s*RETURNS|CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/, 'clock tick not redefined');
  assert.strictEqual(md5(body(up, 'public.pdc_tune_approved_operation_source_20260912(oid uuid)')), NEW.helper);
  assert.strictEqual(md5(body(up, 'pdc_bus_private.operation_station(p_operation_id uuid)')), NEW.station);
  for (const v of [OLD.helper, OLD.station, NEW.helper, NEW.station]) assert.ok(up.includes(`'${v}'`) && down.includes(`'${v}'`), v);
  assert.strictEqual(md5(checkSql()), CHECK_MD5);
  assert.ok(up.includes(`'${CHECK_MD5}'`) && down.includes(`'${CHECK_MD5}'`));
});

test('helper keeps its signature, volatility and search_path; station looks it up once', () => {
  const h = up.slice(up.indexOf('CREATE OR REPLACE FUNCTION public.pdc_tune_approved_operation_source_20260912'));
  assert.match(h, /^CREATE OR REPLACE FUNCTION public\.pdc_tune_approved_operation_source_20260912\(oid uuid\)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE\n SET search_path TO 'pg_catalog', 'public'/);
  assert.match(body(up, 'public.pdc_tune_approved_operation_source_20260912(oid uuid)'), /WHERE r\.source_operation_id = \$1 AND r\.status = 'approved'\s+ORDER BY r\.approved_at DESC, r\.change_id DESC LIMIT 1\)/);
  const st = body(up, 'pdc_bus_private.operation_station(p_operation_id uuid)');
  assert.strictEqual((st.match(/pdc_tune_approved_operation_source_20260912\(/g) || []).length, 1);
  assert.match(st, /OFFSET 0\) d/);
  assert.match(up, /STABLE SECURITY DEFINER\n SET search_path TO 'pg_catalog'/);
  assert.match(up, /'\{postgres=X\/postgres,service_role=X\/postgres\}'/, 'grants asserted');
});

test('pins and the regression check are added; undo restores byte-exact and removes them', () => {
  assert.match(up, /INSERT INTO pdc_ops\.expected_function_md5\(signature,prosrc_md5,release,note\) VALUES\n\('public\.pdc_tune_approved_operation_source_20260912\(uuid\)','867bb1b1c0afebfb62f45c08ad6b3154','r407'/);
  assert.match(up, /\('pdc_bus_private\.operation_station\(uuid\)','a63c9309fd6ae046d37709cfb3666019','r407'/);
  const sql = checkSql();
  assert.match(sql, /lanname = 'plpgsql'/);
  assert.match(sql, /search_path=pg_catalog, public/);
  assert.match(sql, /os\.refs, 0\) = 1/);
  assert.match(sql, /eq\.bad = 0 AS ok/);
  assert.strictEqual(md5(body(down, 'public.pdc_tune_approved_operation_source_20260912(oid uuid)')), OLD.helper);
  const b64 = down.match(/decode\('([A-Za-z0-9+\/=]+)','base64'\)/);
  assert.ok(b64, 'old operation_station restored from base64 (its body has CRLF line endings)');
  const old = Buffer.from(b64[1], 'base64').toString('utf8');
  const s = old.indexOf('$function$') + 10;
  assert.strictEqual(md5(old.slice(s, old.indexOf('$function$', s))), OLD.station);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r407'/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='approved_source_lookup_once' AND added_in='r407';/);
});

test('FAULT_LOG has F19, F20 and F21 after F18', () => {
  const at = id => log.indexOf(`| ${id} |`);
  assert.ok(at('F18') > 0 && at('F18') < at('F19') && at('F19') < at('F20') && at('F20') < at('F21'));
  const row = id => log.split('\n').find(l => l.startsWith(`| ${id} |`));
  assert.ok(row('F19').includes('test_location_age_timezones_407.js'));
  assert.ok(row('F20').includes('test_planner_toasts_407.js'));
  for (const s of ['approved_source_lookup_once', `${ID}.down.sql`, 'test_approved_source_once_407.js']) assert.ok(row('F21').includes(s), s);
  assert.doesNotMatch(log.slice(at('F18'), at('F21')), /\n\n\| F(19|2[01]) \|/, 'table rows are contiguous');
});
