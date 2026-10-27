/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const jita = require('./pdc-jita-eta.js');

const MIG = 'supabase/migrations/20261023183000_r516_jita_eta_upload.sql';
const DOWN = 'supabase/rollbacks/20261023183000_r516_jita_eta_upload.down.sql';
const sample = fs.readFileSync('fixtures/jita-upload-sample.tsv', 'utf8');

test('sample paste: stock 13102912 is 2026-10-29, other ETA columns ignored', () => {
  const parsed = jita.parseJitaEta(sample);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.rows, 9);
  assert.equal(parsed.bad_date_rows, 0);
  assert.equal(parsed.stocks.length, 1);
  assert.deepEqual(parsed.stocks[0], {
    stock: '13102912',
    eta_date: '2026-10-29',
    rule: 'latest_outstanding',
    source_rows: 9,
    outstanding_rows: 9,
    distinct_outstanding_dates: 1
  });
});

test('latest outstanding date wins; qty 0 falls back to the latest planned date', () => {
  const multi = jita.parseJitaEta('JITA Vehicle\tQty Outstanding\tJITA Planned Delivery Date\n13102912\t1\t29/10/2026\n13102912\t2\t01/11/2026\n');
  assert.equal(multi.stocks[0].eta_date, '2026-11-01');
  assert.equal(multi.stocks[0].rule, 'latest_outstanding');
  assert.equal(multi.stocks[0].distinct_outstanding_dates, 2);
  const fallback = jita.parseJitaEta('JITA Vehicle\tQty Oustanding\tJITA Planned Delivery Date\tLatest ETA\tVehicle ETA at Kewdale\nABC\t0\t15/10/26\t01/12/2026\t20/12/2026\nABC\t1\t\t02/12/2026\t03/12/2026\n');
  assert.equal(fallback.stocks[0].eta_date, '2026-10-15');
  assert.equal(fallback.stocks[0].rule, 'latest_any');
  assert.equal(jita.parseJitaEta('Hello\n13102912').error, 'header');
  assert.equal(jita.parseDate('2/10/2026'), '2026-10-02');
  assert.equal(jita.parseDate('31/02/2026'), null);
});

test('JITA ETA sits at the bottom of the Parts ETA box, not beside the vehicle name', () => {
  const detail = '<div class="incoming-vehicle-detail-grid"><span class="incoming-card-main"><strong>Hilux DCC</strong></span><div class="tune-service-location-job pdc-parts-eta-detail"><b>Parts ETA</b><span class="pdc-parts-eta-countdown pdc-parts-eta-ok">28/10/26</span><small>From parts staff emails (Perth dates)</small></div></div>';
  const withDetail = jita.insertDetail(detail, { eta_date: '2027-03-11' });
  const partsAt = withDetail.indexOf('pdc-parts-eta-detail');
  const emailAt = withDetail.indexOf('From parts staff emails');
  const jitaAt = withDetail.indexOf('pdc-jita-eta-in-parts');
  assert.ok(partsAt > 0 && emailAt > partsAt && jitaAt > emailAt, 'email Parts ETA stays above JITA inside the same box');
  assert.ok(withDetail.indexOf('</div>', jitaAt) < withDetail.indexOf('incoming-vehicle-detail-grid') + withDetail.length);
  assert.match(withDetail, /data-jita-eta="2027-03-11"/);
  assert.match(withDetail, /<b>JITA ETA<\/b><span>11\/03\/2027<\/span>/);
  assert.equal((withDetail.match(/pdc-parts-eta-detail/g) || []).length, 1);
  assert.doesNotMatch(withDetail, /<strong>Hilux DCC<\/strong><div class="pdc-jita-eta/);
  const onlyJita = jita.insertDetail('<div class="incoming-vehicle-detail-grid"><span class="incoming-card-main"><strong>Hilux</strong></span></div>', { eta_date: '2027-03-11' });
  assert.match(onlyJita, /pdc-parts-eta-detail pdc-jita-eta-only"><div class="pdc-jita-eta-in-parts"/);
  assert.doesNotMatch(onlyJita, /<strong>Hilux<\/strong><div class="pdc-jita/);
  assert.doesNotMatch(jita.inPartsHtml({ eta_date: '2027-03-11' }), /pdc-parts-eta-k|set_parts_eta|pdc_parts_eta/);
});

test('apply result uses the Navision success panel; preview stays the lighter check', () => {
  const applied = jita.renderUploadResult({
    ok: true,
    dry_run: false,
    rows: 9,
    results: [
      { stock: '13094083', status: 'applied', eta_date: '2027-03-11', rule: 'latest_outstanding' },
      { stock: '13094088', status: 'replaced', eta_date: '2026-10-22', previous_eta: '2026-10-18' },
      { stock: '13094124', status: 'unchanged', eta_date: '2026-10-22' },
      { stock: '13064911', status: 'skipped_unknown', eta_date: '2026-11-19' }
    ]
  });
  assert.match(applied, /class="navision-import-success"/);
  assert.match(applied, /navision-import-success-tick/);
  assert.match(applied, /<strong>JITA upload complete<\/strong>/);
  assert.match(applied, /2 vehicle dates saved/);
  assert.match(applied, /The email Parts ETA was not changed/);
  assert.match(applied, /class="scot-summary-grid navision-human-summary"/);
  assert.match(applied, /<span>Dates saved<\/span><strong>2<\/strong>/);
  assert.match(applied, /<span>Not on the board<\/span><strong>1<\/strong>/);
  assert.match(applied, /<h3>JITA ETA set<\/h3>[\s\S]*<strong>13094083<\/strong><span>JITA ETA 11\/03\/2027<\/span>/);
  assert.match(applied, /13094088<\/strong><span>JITA ETA 22\/10\/2026 \(was 18\/10\/2026\)/);
  assert.ok(applied.indexOf('<h3>JITA ETA set</h3>') < applied.indexOf('<h3>Not on the board</h3>'));
  assert.match(applied, /<strong>13064911<\/strong><span>JITA ETA 19\/11\/2026<\/span>/);
  const preview = jita.renderUploadResult({ ok: true, dry_run: true, rows: 2, results: [{ stock: '13094083', status: 'would_apply', eta_date: '2027-03-11' }] });
  assert.doesNotMatch(preview, /navision-import-success/);
  assert.match(preview, /<strong>JITA file checked and ready<\/strong>/);
  assert.match(preview, /Preview only. Nothing has been saved/);
  assert.match(preview, /<span>Would be saved<\/span><strong>1<\/strong>/);
  const src = fs.readFileSync('pdc-jita-eta.js', 'utf8');
  assert.match(src, /show\(renderUploadResult\(payload\)\)/);
  assert.doesNotMatch(src, /insertChip|function chipHtml/);
});

test('page wiring: JITA Upload under Navision Uploads, loader after parts ETA, parts ETA files untouched', () => {
  const index = fs.readFileSync('index.html', 'utf8');
  const importAt = index.indexOf('id="import"');
  const jitaAt = index.indexOf('id="jita-upload-panel"');
  const navAt = index.indexOf('id="navision-paste"');
  assert.ok(importAt > 0 && navAt > importAt && jitaAt > navAt);
  assert.ok(jitaAt < index.indexOf('id="vehicle-modal"'));
  assert.match(index, /<h2>JITA Upload<\/h2>/);
  assert.match(index, /id="jita-paste"/);
  assert.match(index, /id="jita-upload-panel" hidden>/);
  assert.match(index, /canonical-entry\.js\?[^"]*parts-eta=2026\.10\.21\.r436&amp;key-number=2026\.10\.22\.r460&amp;sublet-po=/);
  assert.match(index, /&amp;r516=2026\.10\.23\.r516&amp;r517=2026\.10\.23\.r517&amp;r519=2026\.10\.23\.r519&amp;parts-eta=2026\.10\.21\.r436/);
  assert.match(index, /operation-panels=2026\.10\.21\.r444&amp;sublet-po-attach=2026\.10\.21\.r445"/);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /serviceLocations\.onload = loadPartsEta;/);
  assert.match(entry, /partsEta\.onload = loadJitaEta;\s*partsEta\.onerror = loadJitaEta;/);
  assert.match(entry, /jitaEta\.onload = loadWorkshopVehicleSearch;\s*jitaEta\.onerror = loadWorkshopVehicleSearch;/);
  assert.match(entry, /pdc-workshop-vehicle-search\.js\?r566=2026\.10\.27\.r566/);
  assert.match(entry, /pdc-jita-eta\.js\?r516=2026\.10\.23\.r516&r517=2026\.10\.23\.r517&r519=2026\.10\.23\.r519/);
  assert.equal((entry.match(/pdc-key-number\.js/g) || []).length, 1);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-service-locations\.js', 'pdc-parts-eta\.js', 'pdc-sublet-po\.js'/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-key-number\.js', 'pdc-jita-eta\.js'/);
  assert.doesNotMatch(fs.readFileSync('styles.css', 'utf8'), /pdc-jita-eta/);
  assert.doesNotMatch(fs.readFileSync('app.js', 'utf8'), /import_jita_eta_516|pdc-jita-eta|jita-upload-panel/);
  assert.doesNotMatch(fs.readFileSync('pdc-parts-eta.js', 'utf8'), /import_jita_eta_516|pdc_jita_eta/);
  assert.equal(jita.VERSION, '2026.10.23.r519');
  assert.equal(jita.SHOW_JITA_ETA, false);
});

test('r519 hides the paste and does not nest a JITA ETA; the clear leaves the email ETA and the r518 tick', () => {
  const vm = require('node:vm');
  const panel = { hidden: false };
  let hooked = false;
  const sandbox = {
    window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd' } },
    document: {
      getElementById(id) { return id === 'jita-upload-panel' ? panel : null; },
      head: { appendChild() { hooked = true; } },
      addEventListener() { hooked = true; },
      getElementByIdCalls: 0
    }
  };
  sandbox.window.document = sandbox.document;
  vm.runInNewContext(fs.readFileSync('pdc-jita-eta.js', 'utf8'), sandbox, { filename: 'pdc-jita-eta.js' });
  assert.equal(panel.hidden, true);
  assert.equal(sandbox.window.PDC_JITA_ETA.hidden, true);
  assert.equal(sandbox.window.PDC_JITA_ETA.VERSION, '2026.10.23.r519');
  assert.equal(hooked, false, 'hidden mode does not style, poll, or decorate');
  const src = fs.readFileSync('pdc-jita-eta.js', 'utf8');
  const hideAt = src.indexOf('if (!SHOW_JITA_ETA)');
  const bindAt = src.indexOf('function bindUpload');
  assert.ok(hideAt > 0 && bindAt > hideAt);
  assert.match(src, /panel\.hidden = true/);
  assert.doesNotMatch(fs.readFileSync('app.js', 'utf8'), /SHOW_JITA_ETA/);
  assert.match(fs.readFileSync('app.js', 'utf8'), /Parts Jita complete\. Navision JITA number/);
  const clear = fs.readFileSync('supabase/staging_only/20261023233000_r519_clear_jita_eta.sql', 'utf8');
  const down = fs.readFileSync('supabase/rollbacks/20261023233000_r519_clear_jita_eta.down.sql', 'utf8');
  assert.match(clear, /cdsmnqxtyyoeoznmbidd/);
  assert.match(clear, /NOT BETWEEN 2 AND 45/);
  assert.match(clear, /pdc_production_environment_sentinel/);
  assert.match(clear, /UPDATE public\.pdc_jita_eta/);
  assert.match(clear, /a5190519-0519-4519-8519-000000000519/);
  assert.doesNotMatch(clear, /UPDATE public\.pdc_parts_eta|UPDATE public\.vehicle_parts_updates|DROP FUNCTION public\.tick_parts_jita_from_navision_518|DROP TABLE public\.pdc_jita_eta/);
  assert.match(clear, /88d31cbd6ca5ddd372e3143d5f8c013f/);
  assert.match(clear, /tick_parts_jita_from_navision_518/);
  assert.match(down, /superseded = false/);
  assert.match(down, /DROP TABLE pdc_ops\.r519_jita_eta_clear/);
  assert.doesNotMatch(down, /UPDATE public\.pdc_parts_eta|DROP FUNCTION public\.tick_parts_jita_from_navision_518/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\n\| F133 \|/);
});

test('migration does not replace set_parts_eta and the undo drops only the JITA objects', () => {
  const mig = fs.readFileSync(MIG, 'utf8');
  const down = fs.readFileSync(DOWN, 'utf8');
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.set_parts_eta/);
  assert.match(mig, /88d31cbd6ca5ddd372e3143d5f8c013f/);
  assert.match(mig, /decd9053241b3fe8ede99bd231ad98ec/);
  assert.match(mig, /jita_eta_upload_516/);
  assert.match(mig, /'F130'/);
  assert.match(mig, /true,303,'r516'/);
  assert.match(mig, /latest_outstanding/);
  assert.doesNotMatch(mig, /11111111111111111111111111111111|22222222222222222222222222222222|33333333333333333333333333333333|44444444444444444444444444444444/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='jita_eta_upload_516'/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r516'/);
  assert.match(down, /88d31cbd6ca5ddd372e3143d5f8c013f/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\n\| F130 \|/);
  assert.match(mig, /UPDATE public\.pdc_jita_eta SET superseded=true[\s\S]*?WHERE id=v_cur\.id AND NOT superseded/);
});
