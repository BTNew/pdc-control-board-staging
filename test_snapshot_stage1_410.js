/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r410 (F26): snapshot stage 1. Proven-redundant work removed from the location snapshot chain (pre_734 and
// pre_1020 become pass-throughs, pre_739 no longer computes pdc_lifecycle per row, the pilbara layer reuses
// external_completion from pdc_lifecycle) and seven hot LANGUAGE sql helpers become PL/pgSQL with the same
// expression. Board and location JSON were byte-identical (overall, per department, per vehicle, administrator
// and operator logins, edge fixture) in the rolled-back tests. These checks keep the migration, its undo and the
// stage 0 harness honest without a database.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const crypto = require('crypto');

const ID = '20261020161315_r410_snapshot_redundant_passes_removed';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const harness = fs.readFileSync('scripts/snapshot_equivalence_harness.sql', 'utf8');
const fixture = fs.readFileSync('scripts/snapshot_edge_fixture.sql', 'utf8');
const builder = fs.readFileSync('scripts/build_snapshot_equivalence_test.py', 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const CLOCK_TICK = '84af7607bfd0ce9907c89bae8644d5b6';
const CHECK_MD5 = 'e9c666e0e1548ed62c97d964e5fc08fe';
const OLD = {
  "public.get_pdc_email_vehicle_location_snapshot_pre_734()": "f2fdaab192cabddc1415818c2a3b123b",
  "public.get_pdc_email_vehicle_location_snapshot_pre_739()": "9c27e4da08f6ba975d3d15a2768bcc0d",
  "public.get_pdc_email_vehicle_location_snapshot_pre_1020()": "532d487eb41805833e31504cd126af4d",
  "public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()": "092301d0e275176b27740b1cc7501972",
  "public.pdc_is_pre_delivery_20260910(text)": "055281182d5c51f94291a8f5a9826c9f",
  "pdc_work_categories_private.import_description_hash_20261017(text)": "136099468c385ae09aab4e43879cfa9e",
  "pdc_work_categories_private.stage(text)": "622bea0ee56932c041c057927549c678",
  "public.pdc_department138_station_20260917(text)": "0109ed60a4ea2feb71835633653640a4",
  "public.pdc_standard_operation_display_20260910(jsonb)": "87169699a45421aa51b80ed658718e4e",
  "pdc_parts_private.service_scope(jsonb,text,text)": "848892cd570ddfb6bd787af9f0266c56",
  "pdc_bus_private.operation_station(uuid)": "a63c9309fd6ae046d37709cfb3666019"
};
const NEW = {
  "public.get_pdc_email_vehicle_location_snapshot_pre_734()": "2ed0984e0f1a6b6e10ac5601a0014e18",
  "public.get_pdc_email_vehicle_location_snapshot_pre_739()": "733c898847d84a79576f028dd9d1fea6",
  "public.get_pdc_email_vehicle_location_snapshot_pre_1020()": "623b014b00ab74159639ed23f257f607",
  "public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()": "844c796008c0c49e7328779214eae64f",
  "public.pdc_is_pre_delivery_20260910(text)": "e672cbcbdda24268013a30401b68d5b0",
  "pdc_work_categories_private.import_description_hash_20261017(text)": "2077a9f7f13668245b302b2ae80cb965",
  "pdc_work_categories_private.stage(text)": "91e0fc2be1c7bb92a8f98d2baa0f0b6e",
  "public.pdc_department138_station_20260917(text)": "9f1cf3370971e3a77f5335632d4f3f8c",
  "public.pdc_standard_operation_display_20260910(jsonb)": "ef6301a91e9fcbb7a663c2319c5bef9d",
  "pdc_parts_private.service_scope(jsonb,text,text)": "1db89bd7bae513ec6f165dc0b1a87a80",
  "pdc_bus_private.operation_station(uuid)": "f7ab4745fb8e97fcd58a209145cfab0f"
};
const HELPERS = Object.keys(NEW).filter(s => !s.includes('get_pdc_email_vehicle_location_snapshot'));

// Old bodies with CRLF line endings are restored from base64 in the undo; decode them for the checks.
const downText = down + '\n' + [...down.matchAll(/convert_from\(decode\('([A-Za-z0-9+\/=]+)','base64'\),'UTF8'\)/g)]
  .map(m => Buffer.from(m[1], 'base64').toString('utf8') + ';').join('\n');
const name = sig => sig.slice(0, sig.indexOf('('));
function def(sql, sig) {
  const at = sql.indexOf(`CREATE OR REPLACE FUNCTION ${name(sig)}(`);
  assert.ok(at >= 0, `definition of ${sig}`);
  const s = sql.indexOf('AS $function$', at);
  const b = s + 'AS $function$'.length;
  return { head: sql.slice(at, s), body: sql.slice(b, sql.indexOf('$function$', b)) };
}
function checkSql() {
  const m = up.match(/'snapshot_redundant_passes_removed','F26','(?:[^']|'')*','((?:[^']|'')*)',true,198,'r410'\)/);
  assert.ok(m, 'check row');
  return m[1].replace(/''/g, "'");
}

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
    assert.doesNotMatch(sql, /@[a-z0-9.-]+\.(com|au|invalid)/i, 'no email addresses');
    assert.ok(!sql.includes('vjdtsswhroyguxyfjdkt'));
    for (const v of [...Object.values(OLD), ...Object.values(NEW)]) assert.ok(sql.includes(`'${v}'`), v);
  }
  assert.ok(!up.includes('\r') && !down.includes('\r'), 'no raw CR bytes; CRLF bodies travel as base64');
  for (const sig of Object.keys(NEW)) {
    assert.strictEqual(md5(def(up, sig).body), NEW[sig], `new ${sig}`);
    assert.strictEqual(md5(def(downText, sig).body), OLD[sig], `undo restores ${sig} byte-exact`);
  }
  assert.strictEqual((up.match(/CREATE OR REPLACE FUNCTION /g) || []).length, 11);
});

test('signatures, volatility, security and search_path are unchanged; helpers only switch to PL/pgSQL', () => {
  for (const sig of Object.keys(NEW)) {
    const a = def(up, sig).head, b = def(downText, sig).head;
    if (HELPERS.includes(sig)) {
      assert.match(b, /\n LANGUAGE sql\n/, `${sig} was sql`);
      assert.strictEqual(a, b.replace('\n LANGUAGE sql\n', '\n LANGUAGE plpgsql\n'), sig);
    } else {
      assert.strictEqual(a, b, sig);
    }
  }
});

test('the helpers return the same expression; operation_station keeps the SQL first-row rule', () => {
  for (const sig of HELPERS) {
    const n = def(up, sig).body, o = def(downText, sig).body;
    assert.match(n, /^\nBEGIN\n -- r410 \(F26\)/, sig);
    const expr = o.replace(/\r/g, '').trim().replace(/;$/, '').replace(/^SELECT /, '');
    assert.ok(n.includes(expr), `${sig} keeps its expression`);
  }
  const st = def(up, 'pdc_bus_private.operation_station(uuid)').body;
  assert.match(st, /RETURN \(\n-- r407 \(F21\)[\s\S]*\n SELECT coalesce\(h\.stage_code/);
  assert.match(st, /WHERE o\.operation_id=p_operation_id\n LIMIT 1\);\nEND\n$/);
});

test('pre_734 and pre_1020 are pass-throughs; pre_739 and the pilbara layer keep everything else', () => {
  const p734 = def(up, 'public.get_pdc_email_vehicle_location_snapshot_pre_734()').body;
  const p1020 = def(up, 'public.get_pdc_email_vehicle_location_snapshot_pre_1020()').body;
  assert.match(p734, /RETURN public\.get_pdc_email_vehicle_location_snapshot_pre_693\(\);/);
  assert.match(p1020, /RETURN public\.get_pdc_email_vehicle_location_snapshot_pre_82000\(\);/);
  for (const b of [p734, p1020]) assert.doesNotMatch(b, /jsonb_agg|jsonb_set|SELECT/);
  const o739 = def(downText, 'public.get_pdc_email_vehicle_location_snapshot_pre_739()').body;
  const n739 = def(up, 'public.get_pdc_email_vehicle_location_snapshot_pre_739()').body;
  const removed = "'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid),";
  assert.ok(o739.includes(removed) && !n739.includes(removed));
  assert.strictEqual(n739.replace(/  -- r410 \(F26\)[^\n]*\n  -- [^\n]*\n  /, '  '), o739.replace(removed, ''), 'only that key goes');
  assert.strictEqual((n739.match(/pdc_rft_transport_lifecycle_state_734\(/g) || []).length, 1, 'appended rows keep pdc_lifecycle');
  const np = def(up, 'public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()').body;
  assert.match(np, /CROSS JOIN LATERAL \(SELECT public\.pdc_rft_transport_lifecycle_state_734\(\(x->>'id'\)::uuid\) AS v OFFSET 0\) lc;/);
  assert.match(np, /'external_completion',CASE WHEN lc\.v \? 'external_completion' THEN lc\.v->'external_completion'\n\s+ELSE public\.pdc_external_completion_json_20260903\(\(x->>'id'\)::uuid\) END/);
  const op = def(downText, 'public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()').body;
  const tail = s => s.slice(s.indexOf('  SELECT coalesce(jsonb_agg(jsonb_build_object('));
  assert.strictEqual(tail(np), tail(op), 'the appended Completed rows are unchanged');
});

test('hard-coded vehicle special cases and the old layer chain are untouched', () => {
  for (const keep of ['pre_693', 'pre_767', 'pre_82000', 'pre_ext1300', 'pre168', 'get_pdc_email_vehicle_location_snapshot()', 'get_pdc_email_vehicle_board_snapshot()'])
    assert.ok(!up.includes(`CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot_${keep}`) && !up.includes(`CREATE OR REPLACE FUNCTION public.${keep}`), keep);
  assert.doesNotMatch(up, /DROP FUNCTION/);
  const bodies = Object.keys(NEW).map(s => def(up, s).body).join('\n');
  assert.ok(!bodies.includes("'13000765'") && !bodies.includes('d777b071'), 'no special-case vehicle in any new body');
});

test('pins and the F26 regression check; undo removes them and restores the r407 pin', () => {
  const pins = up.match(/INSERT INTO pdc_ops\.expected_function_md5\(signature,prosrc_md5,release,note\) VALUES\n([\s\S]*?);\n/);
  assert.ok(pins);
  for (const [sig, m] of Object.entries(NEW)) assert.ok(pins[1].includes(`('${sig}','${m}','r410'`), sig);
  assert.strictEqual((pins[1].match(/,'r410',/g) || []).length, 11);
  assert.match(up, /DELETE FROM pdc_ops\.expected_function_md5 WHERE signature='pdc_bus_private\.operation_station\(uuid\)' AND release='r407';/);
  assert.strictEqual(md5(checkSql()), CHECK_MD5);
  assert.ok(up.includes(`'${CHECK_MD5}'`), 'post-check asserts the stored check md5');
  const sql = checkSql();
  assert.match(sql, /bad_fn = 0 AND coalesce\(s\.layers_ok, false\) AND eq\.bad = 0 AS ok/);
  for (const sig of Object.keys(NEW)) assert.ok(sql.includes(`('${sig}','plpgsql'`), sig);
  assert.match(up, /EXECUTE \(SELECT check_sql FROM pdc_ops\.regression_checks WHERE check_name='snapshot_redundant_passes_removed'\) INTO r;\n IF NOT r\.ok/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='snapshot_redundant_passes_removed' AND added_in='r410';/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r410';/);
  assert.ok(down.includes(`('pdc_bus_private.operation_station(uuid)','${OLD['pdc_bus_private.operation_station(uuid)']}','r407'`));
});

test('stage 0 harness: rolled back, windowed, overall + per-department + per-vehicle md5s, edge fixture', () => {
  assert.match(harness, /CREATE TEMP TABLE t_veh\(run text, ord bigint, id text, depts text\[\], m text, v jsonb\) ON COMMIT DROP;/);
  for (const s of ["'md5', md5(s::text)", "'depts'", "'vehicles_md5'", "'order_md5'", "'envelope_md5'", 'get_pdc_email_vehicle_board_snapshot()', 'get_pdc_email_vehicle_location_snapshot()', 'PERFORM pg_temp.deadline();'])
    assert.ok(harness.includes(s), s);
  assert.match(harness, /'identical', ra->>'md5' = rb->>'md5' AND ra->'depts' = rb->'depts' AND ra->>'vehicles_md5' = rb->>'vehicles_md5'/);
  assert.match(harness, /'first_differences', diff/);
  assert.doesNotMatch(harness, /\b(INSERT|UPDATE|DELETE)\s+(INTO\s+)?(public|pdc_)/i, 'harness writes temp tables only');
  for (const f of ['F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8']) assert.match(fixture, new RegExp(`-- ${f} `), f);
  assert.match(fixture, /EXCEPTION WHEN OTHERS THEN log := log \|\|/);
  assert.doesNotMatch(fixture, /'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'/, 'rows picked by rule, not by id');
  assert.match(builder, /rolled_back_test_window\.sql/);
  assert.match(builder, /'ROLLBACK;'\]/);
  assert.doesNotMatch(builder, /COMMIT/);
});

test('FAULT_LOG has F26 right after F25', () => {
  const at = id => log.indexOf(`| ${id} |`);
  assert.ok(at('F25') > 0 && at('F25') < at('F26'));
  const row = log.split('\n').find(l => l.startsWith('| F26 |'));
  for (const s of ['snapshot_redundant_passes_removed', `${ID}.down.sql`, 'test_snapshot_stage1_410.js', 'scripts/build_snapshot_equivalence_test.py'])
    assert.ok(row.includes(s), s);
  assert.doesNotMatch(log.slice(at('F25'), at('F26')), /\n\n\| F26 \|/, 'table rows are contiguous');
});
