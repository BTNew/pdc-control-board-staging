'use strict';
// r475 (F88, Craig 22 Oct 2026 10:51 AWST): parts ETA from free-form emails, with a days countdown and the source email on hover,
// in the Table view's own "Parts ETA" column and in the vehicle details (drop-down card / slide-out panel).
// Database behaviour is proven by tests/r475_local_harness/run.sh (throwaway local PostgreSQL) and daily on staging by
// parts_eta_email_source_475 (sort 275). Synthetic data only; no stock numbers, customer names or addresses in Git.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto');
const eta = require('./pdc-parts-eta.js');
const table = require('./pdc-vehicle-locations-table.js');
const MIG = 'supabase/migrations/20261022031500_r475_parts_eta_email_source.sql';
const DOWN = 'supabase/rollbacks/20261022031500_r475_parts_eta_email_source.down.sql';
const mig = fs.readFileSync(MIG, 'utf8'), down = fs.readFileSync(DOWN, 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const WRAP = 'public.set_parts_eta_from_email(text,date,text,text,timestamp with time zone,text,text,text,text,integer,text,text,text,text,boolean)';
const BOARD = 'public.get_pdc_parts_eta_board_v2()';

const part = { part: 'Parts (per email)', eta_date: '2026-10-29', ro: 'J1', sender: 'parts.manager@example.com.au', sender_name: 'Parts Manager',
  message_at: '2026-10-22T01:15:00Z', subject: 'RE: Job Card for CUSTOMER S-OLD changed to new batch number S-NEW', quote: 'PARTS DELAY ETA NOW 29/10/26',
  source_kind: 'free_form', previous_stock: 'S-OLD' };
const board = { today: '2026-10-22', version: 'r475', vehicles: [{ vehicle_id: 'aaaaaaaa-0000-4000-8000-000000000001', stock_number: 'S-NEW', latest_eta: '2026-10-29', count: 1, overdue_count: 0, parts: [part] }] };
const idx = eta.indexBoard(board);

test('countdown: "dd/mm · N days", "today" amber, "N days overdue" red, 1 day singular (Perth calendar dates)', () => {
  const s = eta.summarise(eta.entryFor(idx, { stock: 's-new' }), '2026-10-22');
  assert.equal(s.label, 'Parts ETA 29/10 · 7 days'); assert.equal(s.value, '29/10 · 7 days'); assert.equal(s.state, 'ok'); assert.equal(s.days, 7);
  assert.equal(eta.summarise(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-10-28').value, '29/10 · 1 day');
  const due = eta.summarise(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-10-29'); assert.equal(due.value, '29/10 · today'); assert.equal(due.state, 'due');
  const late = eta.summarise(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-11-01'); assert.equal(late.value, '29/10 · 3 days overdue'); assert.equal(late.state, 'overdue');
  assert.equal(eta.summarise(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-10-30').value, '29/10 · 1 day overdue');
  assert.match(eta.chipHtml(late), /class="pdc-parts-eta pdc-parts-eta-overdue"/);
  assert.equal(eta.daysUntil('2027-01-02', '2026-12-30'), 3, 'across a year end');
  assert.equal(eta.daysUntil('2026-10-29', ''), null);
});

test('hover names the source email: from, sent (Perth time), subject, quoted line and the renumbered stock; escaped', () => {
  const s = eta.summarise(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-10-22');
  assert.match(s.title, /^Parts ETA \(Perth\), latest 29\/10\/26 · 7 days\n/);
  assert.match(s.title, /Parts \(per email\): 29\/10\/26 · R\/O J1/);
  assert.match(s.title, /From: Parts Manager <parts\.manager@example\.com\.au>/);
  assert.match(s.title, /Sent: Thu 22\/10\/26 9:15 am AWST/);
  assert.match(s.title, /Subject: RE: Job Card for CUSTOMER S-OLD changed to new batch number S-NEW/);
  assert.match(s.title, /“PARTS DELAY ETA NOW 29\/10\/26”/);
  assert.match(s.title, /Email also names stock S-OLD \(renumbered\)/);
  const chip = eta.chipHtml(s);
  assert.match(chip, /title="[^"]*From: Parts Manager &lt;parts\.manager@example\.com\.au&gt;/);
  assert.match(chip, /data-parts-eta="2026-10-29" data-parts-eta-days="7"><span class="pdc-parts-eta-k">Parts ETA <\/span>29\/10 · 7 days<\/span>$/);
  // An r436 row (no source fields) still gets the countdown and no source lines.
  const plain = eta.summarise({ latest_eta: '2026-10-29', count: 1, parts: [{ part: 'Seal', eta_date: '2026-10-29' }] }, '2026-10-22');
  assert.equal(plain.title, 'Parts ETA (Perth), latest 29/10/26 · 7 days\nSeal: 29/10/26');
  assert.deepEqual(eta.sourceLines({ sender: 'a@b.au', sender_name: 'A@B.AU' }), ['From: a@b.au']);
});

test('sent time and today are Perth whatever the device time zone', () => {
  assert.equal(eta.sentLabel('2026-10-21T16:30:00Z'), 'Thu 22/10/26 12:30 am AWST');
  assert.equal(eta.sentLabel('nope'), '');
  assert.equal(eta.perthToday(new Date('2026-10-21T16:30:00Z')), '2026-10-22');
  assert.equal(eta.perthToday(new Date('2026-10-22T15:59:00Z')), '2026-10-22');
  assert.equal(eta.perthToday(new Date('2026-10-22T16:00:00Z')), '2026-10-23');
});

test('vehicle details (drop-down card and slide-out panel) show the countdown and the source in full', () => {
  const html = eta.detailHtml(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-10-22');
  assert.match(html, /^<div class="tune-service-location-job pdc-parts-eta-detail" title="Parts ETA \(Perth\)/);
  assert.match(html, /<span class="pdc-parts-eta-countdown pdc-parts-eta-ok">29\/10\/26 · 7 days<\/span>/);
  assert.match(html, /<small class="pdc-parts-eta-source">From: Parts Manager &lt;parts\.manager@example\.com\.au&gt;<\/small>/);
  assert.match(html, /<small class="pdc-parts-eta-source">“PARTS DELAY ETA NOW 29\/10\/26”<\/small>/);
  assert.match(eta.detailHtml(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-11-02'), /pdc-parts-eta-countdown pdc-parts-eta-overdue">29\/10\/26 · 4 days overdue/);
});

test('Table view: the chip moves verbatim into its own Parts ETA column; the Vehicle cell keeps the rest; "—" without one', () => {
  const s = eta.summarise(eta.entryFor(idx, { stock: 'S-NEW' }), '2026-10-22');
  const unit = '<span class="incoming-card-main"><strong>HiLux</strong><span class="tune-parts-location" title="Parts location: 05E2A">05E2A</span><em>meta</em></span>';
  const decorated = eta.decorateRow(unit, s);
  const card = `<details class="incoming-vehicle-card" data-incoming-row="k1"><summary><span class="incoming-card-stock"><span class="vehicle-identity-stack" title="t"><span class="identity-key">1</span><span class="identity-stock">S-NEW</span></span></span>${decorated}<span class="incoming-card-work-wrap"><span class="pdc-station-strip"></span></span><span class="incoming-card-age">3d</span><span class="incoming-card-status">s</span><span class="incoming-card-action">a</span></summary></details>`;
  const row = table.tableRowHtml(card, 'pmb', { key: 'k1' });
  const cell = cls => (new RegExp(`<td class="${cls}">([\\s\\S]*?)</td>`).exec(row) || [])[1];
  assert.equal(cell('c-eta'), eta.chipHtml(s), 'chip copied byte for byte');
  assert.match(cell('c-ploc'), /^<span class="tune-parts-location" title="Parts location: 05E2A">05E2A<\/span>$/);
  assert.doesNotMatch(cell('c-unit'), /pdc-parts-eta/); assert.match(cell('c-unit'), /<strong>HiLux<\/strong>/); assert.match(cell('c-unit'), /<em>meta<\/em>/);
  assert.match(row, /data-vlt-parts-eta="2026-10-29"/);
  assert.deepEqual(row.match(/<td class="c-[a-z]+"/g).map(x => x.slice(11, -1)), ['c-sel', 'c-key', 'c-stock', 'c-job', 'c-cust', 'c-unit', 'c-ploc', 'c-pit', 'c-eta', 'c-work', 'c-age', 'c-status', 'c-action']); // r604 adds Pit
  const none = table.tableRowHtml(card.replace(decorated, unit), 'pmb', { key: 'k1' });
  assert.match(none, /<td class="c-eta"><span class="vlt-subtle-dash" title="No parts ETA">—<\/span><\/td>/);
  // r436 chip markup (no inner label span) is lifted the same way.
  const old = '<span class="incoming-card-main"><strong>HiLux</strong><span class="pdc-parts-eta-wrap"><span class="pdc-parts-eta pdc-parts-eta-due" title="x" aria-label="x">Parts ETA 22/10</span></span></span>';
  const lifted = table.extractPartsEta(old);
  assert.equal(lifted.span, '<span class="pdc-parts-eta pdc-parts-eta-due" title="x" aria-label="x">Parts ETA 22/10</span>');
  assert.equal(lifted.unit, '<span class="incoming-card-main"><strong>HiLux</strong></span>');
});

test('Table view column set, widths, header and CSS (compact; word "Parts ETA" hidden in the cell)', () => {
  assert.deepEqual(table.COLUMNS.eta, { label: 'Parts ETA', width: 96, min: 56 });
  assert.deepEqual(Object.keys(table.COLUMNS), ['key', 'stock', 'job', 'cust', 'unit', 'ploc', 'pit', 'eta', 'work', 'age', 'status', 'action']); // r604 adds pit
  const src = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8'), css = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  assert.match(src, /<col class="c-ploc"><col class="c-pit"><col class="c-eta"><col class="c-work">/);
  assert.match(src, /<th class="c-eta"><span title="[^"]+">Parts ETA<\/span>\$\{grip\('eta'\)\}<\/th>/);
  assert.match(src, /<td colspan="12" class="vlt-empty">/);
  assert.match(css, /\.vlt-table col\.c-eta \{ width: var\(--vlt-w-eta, 96px\); \}/);
  assert.match(css, /\.vlt-table td\.c-eta \.pdc-parts-eta-k \{ display: none; \}/);
  assert.match(table.widthStyle({ eta: 120 }), /--vlt-w-eta:120px/);
  assert.equal(table.VERSION, '2026.10.28.r593'); // r481 (F94), r485 (F98), r557 (F171) New to PMB, r562 (F176) key gate, r563 (F177) arrival age, r566 (F180) planner search, r593 (F207) New to PMB view
});

test('board read: v2 first, falls back to the r436 read when v2 is not there yet (404), and decorates rows', async () => {
  const calls = []; let refreshed = 0;
  const ctx = { window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, __pdcCachedAccessToken: 't' },
    document: { visibilityState: 'visible', createElement: () => ({}), head: { appendChild: () => {} }, addEventListener: () => {} },
    setInterval: () => 0, clearInterval: () => {}, setTimeout: () => 0, refreshAllViews: () => { refreshed++; }, Intl, Date,
    fetch: async url => { calls.push(url); return /_v2$/.test(url) ? { ok: false, status: 404, text: async () => '' } : { ok: true, status: 200, text: async () => JSON.stringify(board) }; },
    incomingVehicleDetailRow: () => '<span class="incoming-card-main"><strong>Hilux</strong></span><div class="incoming-vehicle-detail-grid">' };
  ctx.window.document = ctx.document;
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-parts-eta.js'), 'utf8'), ctx);
  for (let i = 0; i < 6; i++) await new Promise(r => setImmediate(r));
  assert.deepEqual(calls.map(u => u.split('/').pop()), ['get_pdc_parts_eta_board_v2', 'get_pdc_parts_eta_board']);
  assert.equal(refreshed, 1);
  assert.equal(ctx.window.PDC_PARTS_ETA.rpc(), 'get_pdc_parts_eta_board');
  const row = ctx.incomingVehicleDetailRow({ stock: 'S-NEW' });
  assert.match(row, /pdc-parts-eta pdc-parts-eta-(ok|due|overdue)/); assert.match(row, /pdc-parts-eta-detail/);
});

test('loader and cache bust: r475 tags on the parts ETA script, the table module and index.html', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-parts-eta\.js\?parts-eta=2026\.10\.21\.r436&r475=2026\.10\.22\.r475(&r\d+=[0-9.]+r\d+)*'/); // r482 (F95) appends its own tag after r475
  assert.match(entry, /pdc-vehicle-locations-table\.js\?vehicle-locations-table=2026\.10\.22\.r461&r462=2026\.10\.22\.r462&r463=2026\.10\.22\.r463&r476=2026\.10\.22\.r476&r475=2026\.10\.22\.r475&r481=2026\.10\.22\.r481&r485=2026\.10\.22\.r485&r557=2026\.10\.27\.r557&r562=2026\.10\.27\.r562&r563=2026\.10\.27\.r563&r567=2026\.10\.27\.r567&r566=2026\.10\.27\.r566&r593=2026\.10\.28\.r593(?:&r604=2026\.10\.28\.r604)?(?:&r613=2026\.10\.28\.r613)?(?:&r618=2026\.10\.28\.r618)?(?:&r622=2026\.10\.28\.r622)?(?:&r672=2026\.10\.28\.r672)?(?:&r685=2026\.10\.29\.r685)?(?:&r693=2026\.10\.29\.r693)?(?:&r698=2026\.10\.29\.r698)?(?:&r707=2026\.10\.29\.r707)?(?:&r745=2026\.10\.30\.r745)?'/); // r604 (F218) appends the Pit column tag; r567 typed Parts ETA, then r566 planner search boxes, then r586 New to PMB view
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*r475=2026\.10\.22\.r475/);
  for (const locked of ['styles.css', 'app.js']) assert.doesNotMatch(fs.readFileSync(locked, 'utf8'), /r475|pdc-parts-eta-k|c-eta/);
});

test('migration: guarded, staging only, r436 untouched, pins match the shipped bodies, check at sort 275 (F88), undo complete', () => {
  for (const s of [mig, down]) { assert.match(s, /SET LOCAL lock_timeout = '2s'/); assert.match(s, /NOT BETWEEN 2 AND 45/); assert.match(s, /staging only/); assert.match(s, /pdc\.r475_tick/); }
  assert.doesNotMatch(mig, /FUNCTION public\.workshop_clock_tick|FUNCTION pdc_ops\.fault_regression_check/i);
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.(set_parts_eta|get_pdc_parts_eta_board)\(/, 'r436 functions are not replaced');
  assert.match(mig, /IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'/); assert.match(mig, /IS DISTINCT FROM 'decd9053241b3fe8ede99bd231ad98ec'/);
  assert.doesNotMatch(mig, /^(UPDATE|DELETE FROM|INSERT INTO)\s+public\.(pdc_parts_eta|vehicles)\b/im, 'no ETA or vehicle row is written by the migration');
  const bodies = [...mig.matchAll(/AS \$f\$([\s\S]*?)\$f\$;/g)].map(m => md5(m[1]));
  assert.equal(bodies.length, 2);
  assert.ok(mig.includes(`('${WRAP}','${bodies[0]}','r475'`)); assert.ok(mig.includes(`('${BOARD}','${bodies[1]}','r475'`));
  assert.ok(down.includes(`IS DISTINCT FROM '${bodies[0]}'`) && down.includes(`IS DISTINCT FROM '${bodies[1]}'`), 'undo refuses over unknown changes');
  const chk = /\$chk\$([\s\S]*?)\$chk\$/.exec(mig)[1];
  assert.ok(mig.includes(`IS DISTINCT FROM '${md5(chk)}'`), 'apply verifies the check body');
  assert.match(mig, /\('parts_eta_email_source_475','F88',/); assert.match(mig, /\$chk\$,true,275,'r475'\)/);
  assert.match(mig, /EXECUTE x\.check_sql INTO y; IF y\.ok IS NOT TRUE/);
  assert.match(mig, /REVOKE ALL ON FUNCTION public\.set_parts_eta_from_email\([^)]*\) FROM PUBLIC, anon;/);
  assert.match(mig, /CHECK \(action IN \('set_parts_eta','sender_domain_set','set_parts_eta_from_email'\)\)/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r475'/);
  assert.match(down, /DROP COLUMN previous_stock, DROP COLUMN source_quote, DROP COLUMN source_subject, DROP COLUMN source_from_name, DROP COLUMN source_kind/);
  assert.match(down, /UPDATE public\.pdc_parts_eta_audit SET action='set_parts_eta', result=result\|\|jsonb_build_object\('via','set_parts_eta_from_email'\)/);
  assert.ok(fs.existsSync('tests/r475_local_harness/run.sh'));
});

test('wrapper contract: R/O from the stock (one open job), previous stock only as a fallback, default part, r436 call unchanged', () => {
  const body = /CREATE FUNCTION public\.set_parts_eta_from_email[\s\S]*?\$f\$;/.exec(mig)[0];
  assert.match(body, /v_part text := coalesce\(nullif\([^;]+\),'Parts \(per email\)'\);/);
  assert.match(body, /IF v_nveh=0 AND v_prev IS NOT NULL AND v_prev<>v_stock/);
  assert.match(body, /IF v_nopen=1 THEN\s+v_ro_from_stock := true;/);
  assert.match(body, /v_res := public\.set_parts_eta\(v_use, v_ro, p_line_no, v_part, p_eta_date, p_bay, p_notes, v_msg, p_sender, v_dry, p_message_at\);/);
  assert.match(body, /v_role IN \('importer','operator','administrator'\)/);
  assert.match(body, /'more_than_one_open_job_on_stock_send_ro'/);
  assert.doesNotMatch(body, /INSERT INTO public\.(vehicles|pdc_parts_eta\b)|pdc_parts_private\.jobs\s+SET|INSERT INTO pdc_parts_private/i, 'never creates vehicles, jobs or ETA rows itself');
});

test('no stock numbers or job card numbers in the r475 files', () => {
  const files = [MIG, DOWN, 'test_parts_eta_email_source_475.js', 'tests/r475_local_harness/stubs.sql', 'tests/r475_local_harness/e2e.sql', 'tests/r475_local_harness/run.sh', 'pdc-parts-eta.js'];
  for (const f of files) {
    const s = fs.readFileSync(f, 'utf8');
    assert.doesNotMatch(s, /\b1[0-9]{7}\b/, `${f}: stock number`);
    assert.doesNotMatch(s, /J1391\d{5}/, `${f}: job card`);
  }
});
