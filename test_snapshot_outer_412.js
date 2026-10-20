'use strict';
// r412 (F28): outer location snapshot and per-vehicle helpers. The Pilbara service-line projection (sourced/classified)
// and the dept138 lateral keep OFFSET 0 so each per-operation helper is evaluated once instead of once per reference,
// and five per-vehicle SQL helpers with SET search_path (never inlined, re-planned per call) become PL/pgSQL
// RETURN (same query) so the plan is kept. Board and location JSON were byte-identical (overall, per department, per
// vehicle, order; administrator and operator logins; with and without the edge fixture) in the rolled-back tests.
// No grant, SECURITY DEFINER, owner, volatility or search_path change. These checks need no database.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const crypto = require('crypto');

const ID = '20261020172813_r412_snapshot_outer_single_eval';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const CLOCK_TICK = '84af7607bfd0ce9907c89bae8644d5b6';
const CHECK_MD5 = 'b2c9d23f02bd98b6bb16e15afea82cb3';
const OUTER = 'public.get_pdc_email_vehicle_location_snapshot()';
const CHECKOUT = 'pdc_codex_intake_private.vehicle_tune_checkout(uuid)';
const IMPORTED = 'public.pdc_imported_parts_flags_vehicle_20260912(uuid)';
const OLD = {
  [OUTER]: '09f6a5c2b02dbf9ae993b80d05c69c98',
  [IMPORTED]: '120ba955eace34fbfa7d594815b85485',
  'public.pdc_vehicle_department_membership_20260919(uuid)': '91cda241a3b3c0eb7004ad77e531655f',
  [CHECKOUT]: '916b975cbd9cc8bcda5c745b656addd5',
  'pdc_codex_intake_private.vehicle_service_locations(uuid)': 'cef440c7375636ffaaac0a3e20244cc1',
  'pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)': '6457a23a3036ebce52090e69ada08173'
};
const NEW = {
  [OUTER]: '930f0f56572db71445d7de704f027aa3',
  [IMPORTED]: '79dcb7e2b2eb795efb9e0d7b020dbaaa',
  'public.pdc_vehicle_department_membership_20260919(uuid)': '98c1144e9c0207a29e753913f9f1e7eb',
  [CHECKOUT]: '42da25784d87ac98c76c451d96a603a9',
  'pdc_codex_intake_private.vehicle_service_locations(uuid)': '5c4eb58c5a462cc9f34da1a09a63d4a2',
  'pdc_codex_intake_private.owner_board_hold_active_20261019(uuid,text,uuid)': '81aa51172c34d120101e335dd10e6d2b'
};
const KEPT = {
  'public.get_pdc_email_vehicle_location_snapshot_pre_691()': '775d90e421042423670990b467f157be',
  'public.get_pdc_email_vehicle_location_snapshot_pre_693()': '4f3f4dd8cab754543d3c0cc934ad111f',
  'public.get_pdc_email_vehicle_location_snapshot_pre_767()': 'db446d2222101f0028666333779fdf23',
  'public.get_pdc_email_vehicle_board_snapshot()': 'a3a635b978cb6b266ea04f03c876672f',
  'public.pdc_parts_flags_vehicle_20260911(uuid)': '6c828cb4ffdd7e0717bd5d9f50f4c764',
  'pdc_bus_private.operation_station(uuid)': 'f7ab4745fb8e97fcd58a209145cfab0f',
  'public.pdc_tune_approved_operation_source_20260912(uuid)': '867bb1b1c0afebfb62f45c08ad6b3154'
};
const name = sig => sig.slice(0, sig.indexOf('('));
function def(sql, sig) {
  const at = sql.indexOf(`CREATE OR REPLACE FUNCTION ${name(sig)}(`);
  assert.ok(at >= 0, `definition of ${sig}`);
  const s = sql.indexOf('AS $function$', at);
  const b = s + 'AS $function$'.length;
  return { head: sql.slice(at, s), body: sql.slice(b, sql.indexOf('$function$', b)) };
}
// the old imported-parts body has CRLF line ends, so the undo restores it through base64
const decoded = () => {
  const m = down.match(/EXECUTE convert_from\(decode\('([A-Za-z0-9+/=]+)','base64'\),'UTF8'\);/);
  assert.ok(m, 'base64 restore of the CRLF body');
  return Buffer.from(m[1], 'base64').toString('utf8');
};
const oldDef = sig => def(sig === IMPORTED ? decoded() : down, sig);
const noLang = h => h.replace(/ LANGUAGE (sql|plpgsql)\n/, ' LANGUAGE x\n');
function checkSql() {
  const m = up.match(/'snapshot_outer_single_eval','F28','(?:[^']|'')*','((?:[^']|'')*)',true,200,'r412'\)/);
  assert.ok(m, 'check row');
  return m[1].replace(/''/g, "'");
}
const strip = s => s.replace(/\r/g, '').replace(/^\s+|\s+$/g, '').replace(/;$/, '');

test('migration and undo are staging-only, windowed, and pin every md5 before and after', () => {
  for (const sql of [up, down]) {
    assert.match(sql, /pdc_monitor_staging_guard\(\)/);
    assert.match(sql, /project_ref='cdsmnqxtyyoeoznmbidd'/);
    assert.match(sql, /pdc_production_environment_sentinel/);
    assert.match(sql, /SET LOCAL lock_timeout = '2s';/);
    assert.match(sql, /NOT BETWEEN 2 AND 45/, 'release-test window');
    assert.ok(sql.includes(`'${CLOCK_TICK}'`), 'clock tick asserted unchanged');
    assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/, 'clock tick not redefined');
    assert.doesNotMatch(sql, /\b(GRANT|REVOKE)\b/, 'no permission changes (stage 4, for Craig)');
    assert.doesNotMatch(sql, /ALTER FUNCTION|SECURITY INVOKER/, 'no security or owner change');
    assert.doesNotMatch(sql, /@[a-z0-9.-]+\.(com|au|invalid)/i, 'no email addresses');
    assert.doesNotMatch(sql, /DROP FUNCTION/);
    assert.ok(!sql.includes('\r'), 'no raw CR bytes');
    for (const v of [...Object.values(OLD), ...Object.values(NEW)]) assert.ok(sql.includes(`'${v}'`), v);
  }
  for (const v of Object.values(KEPT)) assert.ok(up.includes(`'${v}'`), `apply asserts kept ${v}`);
  for (const sig of Object.keys(NEW)) {
    assert.strictEqual(md5(def(up, sig).body), NEW[sig], `new ${sig}`);
    assert.strictEqual(md5(oldDef(sig).body), OLD[sig], `undo restores ${sig} byte-exact`);
    assert.strictEqual(noLang(def(up, sig).head), noLang(oldDef(sig).head.replace(/\r/g, '')), `${sig}: same signature, security, volatility, search_path`);
  }
  assert.strictEqual((up.match(/CREATE OR REPLACE FUNCTION /g) || []).length, 6);
});

test('outer: three OFFSET 0 fences added, nothing else changed', () => {
  const n = def(up, OUTER).body, o = def(down, OUTER).body;
  assert.match(n, /WHERE o\.vehicle_id=\(row_value->>'id'\)::uuid\n        OFFSET 0\n      \) sourced\n      OFFSET 0\n    \) classified/);
  assert.match(n, /WHERE btrim\(op->>'department'\)='138'\n     OFFSET 0\n   \) dept138 ON true/);
  const cleaned = n.replace(/\n  -- r412 \(F28\)[^\n]*(\n  --[^\n]*)*/, '').replace(/\n +OFFSET 0(?=\n)/g, '');
  assert.strictEqual(cleaned, o, 'only the comment and the three OFFSET 0 lines differ');
  assert.ok(!n.includes('13000765') && !n.includes('d777b071'));
});

test('helpers: plpgsql RETURN (same query); LIMIT 1 only where the SQL form took the first row', () => {
  for (const sig of Object.keys(NEW)) {
    if (sig === OUTER) continue;
    assert.match(def(up, sig).head, / LANGUAGE plpgsql\n/);
    assert.match(oldDef(sig).head, / LANGUAGE sql\n/);
    const b = def(up, sig).body;
    const m = b.match(/^\nBEGIN\n -- r412 \(F28\)[^\n]*\n -- [^\n]*\n RETURN \(\n([\s\S]*?)\);\nEND\n$/);
    assert.ok(m, `${sig} shape`);
    let q = m[1];
    if (sig === CHECKOUT) { assert.match(q, /\n LIMIT 1$/); q = q.replace(/\n LIMIT 1$/, ''); }
    else assert.doesNotMatch(q, /\n LIMIT 1$/);
    assert.strictEqual(strip(q), strip(oldDef(sig).body), `${sig}: same query`);
  }
});

test('pins and the F28 regression check; undo removes them', () => {
  const pins = up.match(/INSERT INTO pdc_ops\.expected_function_md5\(signature,prosrc_md5,release,note\) VALUES\n([\s\S]*?);\n/);
  assert.ok(pins);
  for (const [sig, m] of Object.entries(NEW)) assert.ok(pins[1].includes(`('${sig}','${m}','r412'`), sig);
  assert.strictEqual((pins[1].match(/,'r412',/g) || []).length, 6);
  assert.strictEqual(md5(checkSql()), CHECK_MD5);
  assert.ok(up.includes(`'${CHECK_MD5}'`));
  assert.match(up, /check_name='snapshot_segments_collapsed'\) INTO r;\n IF NOT r\.ok THEN RAISE EXCEPTION 'r412: r411 check not ok/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='snapshot_outer_single_eval' AND added_in='r412';/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r412';/);
});

test('FAULT_LOG has F28 right after F27', () => {
  const at = id => log.indexOf(`| ${id} |`);
  assert.ok(at('F27') > 0 && at('F27') < at('F28'));
  const row = log.split('\n').find(l => l.startsWith('| F28 |'));
  for (const s of ['snapshot_outer_single_eval', `${ID}.down.sql`, 'test_snapshot_outer_412.js']) assert.ok(row.includes(s), s);
  assert.doesNotMatch(log.slice(at('F27'), at('F28')), /\n\n\| F28 \|/);
});
