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

test('JITA chip sits after the email Parts ETA chip and uses its own class', () => {
  const parts = '<span class="pdc-parts-eta pdc-parts-eta-ok" title="Parts ETA"><span class="pdc-parts-eta-k">Parts ETA </span>28/10 · 6 days</span>';
  const html = `<span class="incoming-card-main"><strong>Hilux</strong></span><span class="pdc-parts-eta-wrap"><span class="tune-parts-location">05</span>${parts}</span>`;
  const out = jita.insertChip(html, { eta_date: '2026-10-29' });
  const match = out.match(jita.PARTS_CHIP);
  assert.ok(match);
  assert.ok(out.indexOf('class="pdc-jita-eta"') > out.indexOf(match[0]) + match[0].length - 1);
  assert.match(out, /data-jita-eta="2026-10-29"/);
  assert.match(out, /JITA ETA <\/span>29\/10\/2026/);
  assert.doesNotMatch(jita.chipHtml({ eta_date: '2026-10-29' }), /pdc-parts-eta/);
  const detail = '<div class="incoming-vehicle-detail-grid"><div class="tune-service-location-job pdc-parts-eta-detail"><b>Parts ETA</b><span>28/10/26</span></div></div>';
  const withDetail = jita.insertDetail(detail, { eta_date: '2026-10-29' });
  assert.ok(withDetail.indexOf('pdc-jita-eta-detail') > withDetail.indexOf('pdc-parts-eta-detail'));
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
  assert.match(index, /canonical-entry\.js\?[^"]*parts-eta=2026\.10\.21\.r436&amp;key-number=2026\.10\.22\.r460&amp;sublet-po=/);
  assert.match(index, /&amp;r516=2026\.10\.23\.r516&amp;parts-eta=2026\.10\.21\.r436/);
  assert.match(index, /operation-panels=2026\.10\.21\.r444&amp;sublet-po-attach=2026\.10\.21\.r445"/);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /serviceLocations\.onload = loadPartsEta;/);
  assert.match(entry, /partsEta\.onload = loadJitaEta;\s*partsEta\.onerror = loadJitaEta;/);
  assert.match(entry, /jitaEta\.onload = loadKeyNumber;\s*jitaEta\.onerror = loadKeyNumber;/);
  assert.match(entry, /pdc-jita-eta\.js\?r516=2026\.10\.23\.r516/);
  assert.equal((entry.match(/pdc-key-number\.js/g) || []).length, 1);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-service-locations\.js', 'pdc-parts-eta\.js', 'pdc-sublet-po\.js'/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-key-number\.js', 'pdc-jita-eta\.js'/);
  assert.doesNotMatch(fs.readFileSync('styles.css', 'utf8'), /pdc-jita-eta/);
  assert.doesNotMatch(fs.readFileSync('app.js', 'utf8'), /import_jita_eta_516|pdc-jita-eta|jita-upload-panel/);
  assert.doesNotMatch(fs.readFileSync('pdc-parts-eta.js', 'utf8'), /import_jita_eta_516|pdc_jita_eta/);
  assert.equal(jita.VERSION, '2026.10.23.r516');
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
