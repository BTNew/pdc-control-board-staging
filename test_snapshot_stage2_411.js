'use strict';
// r411 (F27): snapshot stage 2. The inner location snapshot layers are collapsed into three segment functions
// (pre_691 = layers 169..691 over pre168, pre_750 = 739+750 over pre_693, pre_pilbara_service_v1 = 82000, ext1300 and
// pilbara over pre_767). Each segment applies every old layer's own per-row expression in the same order, with the
// same joins, filter, appended rows and sorts. The special-case layers pre_693 and pre_767 stay unchanged in the chain.
// Board and location JSON were byte-identical (overall, per department, per vehicle, order; administrator and operator
// logins; with and without the edge fixture) in the rolled-back tests. These checks keep the migration, its undo and
// the comparison builder honest without a database.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const crypto = require('crypto');

const ID = '20261020165112_r411_snapshot_segments_collapsed';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const builder = fs.readFileSync('scripts/build_snapshot_function_compare.py', 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const CLOCK_TICK = '84af7607bfd0ce9907c89bae8644d5b6';
const CHECK_MD5 = '0212fb0a088ccb59178dd1f5fbbafc2c';
const OLD = {
  "public.get_pdc_email_vehicle_location_snapshot_pre_691()": "b6c81f618327621e74d8e24160188516",
  "public.get_pdc_email_vehicle_location_snapshot_pre_750()": "d8dfcd8d9579d379eafe712594304a9c",
  "public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()": "844c796008c0c49e7328779214eae64f"
};
const NEW = {
  "public.get_pdc_email_vehicle_location_snapshot_pre_691()": "775d90e421042423670990b467f157be",
  "public.get_pdc_email_vehicle_location_snapshot_pre_750()": "714fa7a3a5f79e95f2cd891ba96045cc",
  "public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1()": "580bf52022a37d11b78f228c37254c4a"
};
const UNCHANGED = {
  "public.get_pdc_email_vehicle_location_snapshot_pre168()": "d3b6f69bdf3420336403816fc7c60255",
  "public.get_pdc_email_vehicle_location_snapshot_pre_169()": "b9d15c26231ceb6c0284fc7980878a09",
  "public.get_pdc_email_vehicle_location_snapshot_pre_174()": "ff6ff8b4589ce811faeb97662b22a158",
  "public.get_pdc_email_vehicle_location_snapshot_pre_310()": "2cdf8dfb3943babfb18d7476041c92cf",
  "public.get_pdc_email_vehicle_location_snapshot_pre_395()": "8c37da97120ae46764a21c279a622a73",
  "public.get_pdc_email_vehicle_location_snapshot_pre_396()": "c30cb9b0837aa50ac743745a3c7f2616",
  "public.get_pdc_email_vehicle_location_snapshot_pre_399()": "bcca3e5857f70635cf1a3eb2cff64056",
  "public.get_pdc_email_vehicle_location_snapshot_pre_412()": "8d835e24b24cd8dc4eda0e7748857ee8",
  "public.get_pdc_email_vehicle_location_snapshot_pre_422()": "aa2bd6e7335f6bc873b2d91856179a67",
  "public.get_pdc_email_vehicle_location_snapshot_pre_429()": "f3447cc81a348c8202d138cb3b440bdf",
  "public.get_pdc_email_vehicle_location_snapshot_pre_700()": "33deecc1ae222a28984842862199ec2a",
  "public.get_pdc_email_vehicle_location_snapshot_pre_739()": "733c898847d84a79576f028dd9d1fea6",
  "public.get_pdc_email_vehicle_location_snapshot_pre_82000()": "10a51ee7591f9c1ee65e735108ec9ced",
  "public.get_pdc_email_vehicle_location_snapshot_pre_ext1300()": "b1de398abce363b921d916a91892f2d9",
  "public.get_pdc_email_vehicle_location_snapshot_pre_734()": "2ed0984e0f1a6b6e10ac5601a0014e18",
  "public.get_pdc_email_vehicle_location_snapshot_pre_1020()": "623b014b00ab74159639ed23f257f607",
  "public.get_pdc_email_vehicle_location_snapshot_pre_693()": "4f3f4dd8cab754543d3c0cc934ad111f",
  "public.get_pdc_email_vehicle_location_snapshot_pre_767()": "db446d2222101f0028666333779fdf23",
  "public.get_pdc_email_vehicle_location_snapshot()": "09f6a5c2b02dbf9ae993b80d05c69c98",
  "public.get_pdc_email_vehicle_board_snapshot()": "a3a635b978cb6b266ea04f03c876672f"
};
const P = 'public.get_pdc_email_vehicle_location_snapshot_';
const name = sig => sig.slice(0, sig.indexOf('('));
function def(sql, sig) {
  const at = sql.indexOf(`CREATE OR REPLACE FUNCTION ${name(sig)}(`);
  assert.ok(at >= 0, `definition of ${sig}`);
  const s = sql.indexOf('AS $function$', at);
  const b = s + 'AS $function$'.length;
  return { head: sql.slice(at, s), body: sql.slice(b, sql.indexOf('$function$', b)) };
}
const body = k => def(up, `${P}${k}()`).body;
const oldBody = k => def(down, `${P}${k}()`).body;
function checkSql() {
  const m = up.match(/'snapshot_segments_collapsed','F27','(?:[^']|'')*','((?:[^']|'')*)',true,199,'r411'\)/);
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
    assert.doesNotMatch(sql, /DROP FUNCTION/, 'old layers kept');
    assert.ok(!sql.includes('\r'), 'no raw CR bytes');
    for (const v of [...Object.values(OLD), ...Object.values(NEW)]) assert.ok(sql.includes(`'${v}'`), v);
    assert.match(sql, /owner, grants, security, volatility or search_path changed/);
  }
  for (const v of Object.values(UNCHANGED)) assert.ok(up.includes(`'${v}'`), `apply asserts kept layer ${v}`);
  for (const sig of Object.keys(NEW)) {
    assert.strictEqual(md5(def(up, sig).body), NEW[sig], `new ${sig}`);
    assert.strictEqual(md5(def(down, sig).body), OLD[sig], `undo restores ${sig} byte-exact`);
    assert.strictEqual(def(up, sig).head, def(down, sig).head, `${sig}: same signature, security, volatility, search_path`);
  }
  assert.strictEqual((up.match(/CREATE OR REPLACE FUNCTION /g) || []).length, 3);
  assert.strictEqual((down.match(/CREATE OR REPLACE FUNCTION /g) || []).length, 3);
});

test('the call chain: pre168 -> pre_691 -> pre_693 -> pre_750 -> pre_767 -> pilbara; replaced layers are skipped', () => {
  assert.match(body('pre_691'), /v_base:=public\.get_pdc_email_vehicle_location_snapshot_pre168\(\);/);
  assert.match(body('pre_750'), /r:=public\.get_pdc_email_vehicle_location_snapshot_pre_693\(\);/);
  assert.match(body('pre_pilbara_service_v1'), /base:=public\.get_pdc_email_vehicle_location_snapshot_pre_767\(\);/);
  assert.match(oldBody('pre_691'), /get_pdc_email_vehicle_location_snapshot_pre_700\(\)/);
  assert.match(oldBody('pre_750'), /get_pdc_email_vehicle_location_snapshot_pre_739\(\)/);
  assert.match(oldBody('pre_pilbara_service_v1'), /get_pdc_email_vehicle_location_snapshot_pre_ext1300\(\)/);
  for (const k of ['pre_691', 'pre_750', 'pre_pilbara_service_v1']) {
    const calls = body(k).match(/get_pdc_email_vehicle_location_snapshot_\w+\(\)/g);
    assert.strictEqual(calls.length, 1, `${k} calls exactly one layer`);
    assert.match(body(k), /IF NOT coalesce\(\((v_base|r|base)->>'ok'\)::boolean,false\) THEN RETURN (v_base|r|base); END IF;/);
    assert.match(body(k), /-- r411 \(F27\)/);
  }
});

test('segment 1: eleven per-row steps in layer order, each evaluated once, with the 399 filter and 422/429 joins', () => {
  const b = body('pre_691');
  const steps = [...b.matchAll(/CROSS JOIN LATERAL \(SELECT ([\s\S]*?) OFFSET 0\) (l\d+)(?:\n|;\n)/g)];
  assert.deepStrictEqual(steps.map(s => s[2]), ['l1','l2','l3','l4','l5','l6','l7','l8','l9','l10','l11']);
  const marks = ['sublet_bookings', 'pdc_vehicle_milestone_json', 'pdc_vehicle_key_number_json', 'pdc_vehicle_sales_dashboard_json',
    'pdc_qc_operation_lines_379', 'pdc_owner_supplied_document_undo_receipts_396', 'qc_finalization', 'rft_transport_booked_at',
    'pmb_stoppage_reason', 'intercept_receipt_id', 'pdc_final_lifecycle_overlay_700'];
  steps.forEach((s, i) => assert.ok(s[1].includes(marks[i]), `step ${i + 1} is ${marks[i]}`));
  for (let i = 2; i <= 11; i++) assert.ok(steps[i - 1][1].includes(`(SELECT coalesce(l${i - 1}.o,'null'::jsonb) AS `), `l${i} reads l${i - 1}, a JSON null kept as 'null'`);
  assert.match(steps[5][1], /^vehicle AS o FROM \(SELECT coalesce\(l5\.o,'null'::jsonb\) AS vehicle\) rw\n  WHERE NOT EXISTS\(/, '399 filter drops the row');
  for (const i of [7, 8]) assert.match(steps[i][1], /\) x JOIN public\.vehicles v ON v\.id=\(x->>'id'\)::uuid$/, `l${i + 1} inner join`);
  assert.match(b, /jsonb_agg\(l11\.o ORDER BY coalesce\(coalesce\(l10\.o,'null'::jsonb\)->>'stock_number',coalesce\(l10\.o,'null'::jsonb\)->>'vin',coalesce\(l10\.o,'null'::jsonb\)->>'id'\)\)/, '691 sort');
  const tail = s => s.slice(s.indexOf('  SELECT coalesce(jsonb_agg(jsonb_build_object('), s.indexOf('  rows:=rows||collected_rows;'));
  assert.strictEqual(tail(b), tail(oldBody('pre_691')), 'the appended Collected rows are verbatim');
  const op = oldBody('pre_691');
  assert.ok(steps[10][1].startsWith(op.slice(op.indexOf('jsonb_agg(') + 10, op.indexOf(' ORDER BY coalesce('))), '691 per-row merge verbatim');
});

test('segment 2: pre_739 verbatim, then pre_750 over it in array order', () => {
  const b = body('pre_750'), o = oldBody('pre_750');
  const e750 = o.slice(o.indexOf('jsonb_agg(') + 10, o.indexOf(" ORDER BY x->>'stock_number'"));
  assert.ok(b.includes(`jsonb_agg(${e750} ORDER BY x->>'stock_number' )`), '750 per-row merge and sort verbatim');
  assert.match(b, /FROM \(SELECT x FROM jsonb_array_elements\(rows\|\|coalesce\(appended,'\[\]'::jsonb\)\) WITH ORDINALITY e\(x,ord\) ORDER BY ord\) x;/);
  assert.match(b, /ORDER BY coalesce\(x->>'stock_number',x->>'vin',x->>'id'\)\),'\[\]'::jsonb\) INTO rows/, '739 sort');
  assert.match(b, /pdc_vehicle_effective_salesperson_json_386/, '739 appended rows');
  assert.match(b, /NOT EXISTS\(SELECT 1 FROM jsonb_array_elements\(rows\) x WHERE \(x->>'id'\)=v\.id::text\);/);
});

test('segment 3: 82000 and ext1300 per row, ext1300 appended rows, then validated source and pilbara; pilbara tail verbatim', () => {
  const b = body('pre_pilbara_service_v1'), o = oldBody('pre_pilbara_service_v1');
  assert.match(b, /LEFT JOIN LATERAL \(\n[\s\S]*?ORDER BY z\.created_at DESC,z\.receipt_id DESC LIMIT 1\n  \) q ON true OFFSET 0\) l1/, '82000 rejection receipt');
  assert.match(b, /LEFT JOIN LATERAL public\.pdc_lifecycle_history_payload_82000\(\(x->>'id'\)::uuid\) h ON true OFFSET 0\) l2/);
  assert.match(b, /INTO ext_appended\n FROM public\.vehicles v\n LEFT JOIN LATERAL public\.pdc_lifecycle_history_payload_82000\(v\.id\) h ON tru/);
  assert.match(b, /FROM jsonb_array_elements\(rows\|\|coalesce\(ext_appended,'\[\]'::jsonb\)\) WITH ORDINALITY e\(x0,ord\)/);
  assert.match(b, /'validated_operation_source',public\.pdc_email_ai_v2_validated_operation_source_20260902/);
  assert.match(b, /CROSS JOIN LATERAL \(SELECT public\.pdc_rft_transport_lifecycle_state_734\(\(x->>'id'\)::uuid\) AS v OFFSET 0\) lc OFFSET 0\) l4;/);
  const e = o.slice(o.indexOf('jsonb_agg(x||jsonb_build_object(') + 10, o.indexOf(" ORDER BY coalesce(x->>'stock_number',x->>'id')"));
  assert.ok(b.includes(e), 'pilbara per-row merge verbatim');
  const tail = s => s.slice(s.indexOf("  SELECT coalesce(jsonb_agg(jsonb_build_object(\n    'id',v.id")).replace(/END\s*$/, '');
  assert.strictEqual(tail(b), tail(o), 'the appended external completions and the return are verbatim');
  assert.match(b, /jsonb_agg\(l4\.o ORDER BY coalesce\(coalesce\(l3\.o,'null'::jsonb\)->>'stock_number',coalesce\(l3\.o,'null'::jsonb\)->>'id'\)\)/);
});

test('hard-coded vehicle special cases, the outer functions and the old layers are untouched', () => {
  for (const keep of ['pre_693', 'pre_767', 'pre_739', 'pre_82000', 'pre_ext1300', 'pre168', 'pre_734', 'pre_1020'])
    assert.ok(!up.includes(`CREATE OR REPLACE FUNCTION ${P}${keep}(`), keep);
  assert.ok(!up.includes('CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()'));
  assert.ok(!up.includes('CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_board_snapshot()'));
  const bodies = Object.keys(NEW).map(s => def(up, s).body).join('\n');
  assert.ok(!bodies.includes('13000765') && !bodies.includes('d777b071'), 'no special-case vehicle in any new body');
  for (const sig of [`${P}pre_693()`, `${P}pre_767()`]) assert.ok(up.includes(`('${sig}','${UNCHANGED[sig]}','r411'`), `${sig} pinned unchanged`);
});

test('pins and the F27 regression check; undo removes them and restores the r410 pilbara pin', () => {
  const pins = up.match(/INSERT INTO pdc_ops\.expected_function_md5\(signature,prosrc_md5,release,note\) VALUES\n([\s\S]*?);\n/);
  assert.ok(pins);
  for (const [sig, m] of Object.entries(NEW)) assert.ok(pins[1].includes(`('${sig}','${m}','r411'`), sig);
  assert.strictEqual((pins[1].match(/,'r411',/g) || []).length, 5);
  assert.match(up, /DELETE FROM pdc_ops\.expected_function_md5 WHERE signature='public\.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1\(\)' AND release='r410';/);
  assert.strictEqual(md5(checkSql()), CHECK_MD5);
  assert.ok(up.includes(`'${CHECK_MD5}'`), 'post-check asserts the stored check md5');
  const sql = checkSql();
  assert.match(sql, /kept\.n = 13 AS ok/);
  assert.match(sql, /13000765/); assert.match(sql, /d777b071-a2b0-5367-893b-aa83a07fcfce/);
  assert.match(up, /EXECUTE \(SELECT check_sql FROM pdc_ops\.regression_checks WHERE check_name='snapshot_segments_collapsed'\) INTO r;\n IF NOT r\.ok/);
  assert.match(up, /check_name='snapshot_redundant_passes_removed'\) INTO r;\n IF NOT r\.ok THEN RAISE EXCEPTION 'r411: r410 check not ok/, 'r410 check still holds');
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='snapshot_segments_collapsed' AND added_in='r411';/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r411';/);
  const pil = `${P}pre_pilbara_service_v1()`;
  assert.ok(down.includes(`('${pil}','${OLD[pil]}','r410'`));
});

test('function comparison builder: same statement, rolled back, windowed, no email', () => {
  assert.match(builder, /rolled_back_test_window\.sql/);
  assert.match(builder, /'ROLLBACK;'\]/);
  assert.doesNotMatch(builder, /COMMIT\b(?! DROP)/);
  assert.match(builder, /CREATE FUNCTION pg_temp\.cand_\{name\}\(\)/);
  assert.match(builder, /md5\(public\.\{n\}\(\)::text\)/);
  assert.match(builder, /CREATE TEMP TABLE snapfn_cmp ON COMMIT DROP AS SELECT/);
  assert.doesNotMatch(builder, /@[a-z0-9.-]+\.(com|au|invalid)/i);
});

test('FAULT_LOG has F27 right after F26', () => {
  const at = id => log.indexOf(`| ${id} |`);
  assert.ok(at('F26') > 0 && at('F26') < at('F27'));
  const row = log.split('\n').find(l => l.startsWith('| F27 |'));
  for (const s of ['snapshot_segments_collapsed', `${ID}.down.sql`, 'test_snapshot_stage2_411.js', 'scripts/build_snapshot_function_compare.py'])
    assert.ok(row.includes(s), s);
  assert.doesNotMatch(log.slice(at('F26'), at('F27')), /\n\n\| F27 \|/, 'table rows are contiguous');
});
