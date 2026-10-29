/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');
const stop = require('./pdc-parts-stoppage.js');
const table = require('./pdc-vehicle-locations-table.js');

const up = fs.readFileSync('supabase/migrations/20261027170000_r567_parts_stoppage_eta.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027170000_r567_parts_stoppage_eta.down.sql', 'utf8');
const dollar = (sql, tag) => {
  const open = sql.indexOf(tag);
  const close = sql.indexOf(tag, open + tag.length);
  return sql.slice(open + tag.length, close);
};
const md5 = text => crypto.createHash('md5').update(text).digest('hex');
const VID = '11111111-1111-4111-8111-111111111111';
const today = '2026-10-27';
const card = html => `<details class="incoming-vehicle-card" data-incoming-row="k1"><summary><span class="incoming-card-stock"><span class="vehicle-identity-stack" title="t"><span class="identity-key">1</span><span class="identity-stock">S-NEW</span></span></span>${html}<span class="incoming-card-work-wrap"><span class="pdc-station-strip"></span></span><span class="incoming-card-age">3d</span><span class="incoming-card-status">s</span><span class="incoming-card-action">a</span></summary><div class="incoming-vehicle-detail-grid"><div class="tune-service-location-job pdc-parts-eta-detail">email source</div></div></details>`;

test('a typed parts ETA wins, a cleared date falls back to the email, and the note stays short', () => {
  assert.equal(stop.shownEta({ eta_date: '2026-10-20' }, '2026-11-02'), '2026-10-20');
  assert.equal(stop.shownEta({ eta_date: null, note: 'Bull bar' }, '2026-11-02'), '2026-11-02');
  assert.equal(stop.shownEta(null, '2026-11-02'), '2026-11-02');
  assert.equal(stop.shownEta({ eta_date: '' }, ''), '');
  const long = 'BULLBAR-3421880, TANK TR110, and a second kit waiting on the supplier';
  assert.equal(stop.clip(long).length, 42);
  assert.ok(stop.clip(long).endsWith('…'));
  assert.equal(stop.countdown('2026-10-20', today).state, 'overdue');
  assert.equal(stop.countdown(today, today).state, 'due');
  assert.equal(stop.hasManual({ note: 'Tank' }), true);
  assert.equal(stop.hasManual(null), false);
});

test('the cell and the side panel edit the same date and note, and leave the email detail in place', () => {
  const unit = '<span class="incoming-card-main"><strong>Coaster</strong><span class="pdc-parts-eta-wrap"><span class="tune-parts-location" title="Parts location: 05B3A">05B3A</span><span class="pdc-parts-eta pdc-parts-eta-ok" title="email" aria-label="email" data-parts-eta="2026-11-02" data-parts-eta-days="6"><span class="pdc-parts-eta-k">Parts ETA </span>02/11 · 6 days</span></span></span>';
  const state = {
    vehicleId: VID, canEdit: true, today, emailEta: '2026-11-02', jitaEta: '2026-11-04',
    manual: { eta_date: '2026-10-20', note: 'BULLBAR-3421880, TANK TR110', last_checked_on: '2026-10-26', set_by_actor: 'parts@pmg.example' }
  };
  const decorated = stop.decorateCard(card(unit), state);
  assert.match(decorated, /class="tune-service-location-job pdc-parts-eta-detail"/);
  assert.match(decorated, /email source/);
  assert.equal((decorated.match(/pdc-parts-eta-detail/g) || []).length, 1);
  assert.match(decorated, /class="tune-service-location-job pdc-parts-stoppage-detail"/);
  assert.doesNotMatch(decorated, /class="[^"]*pdc-parts-stoppage-detail[^"]*pdc-parts-eta-detail/);
  // r739 (F344): a typed date is the only ETA shown. The email line goes and the old email block is hidden by CSS.
  assert.doesNotMatch(decorated, /parts staff email/);
  assert.match(decorated, /data-pdc-stoppage-manual="1"/);
  assert.ok(decorated.indexOf('pdc-parts-eta-detail">email source</div><div class="tune-service-location-job pdc-parts-stoppage-detail"') > 0, 'typed block sits right after the email block so the :has() rule hides it');
  assert.match(decorated, /JITA ETA 04\/11\/26 · JITA paste/);
  assert.match(decorated, /Last checked 26\/10\/26/);
  assert.match(decorated, /data-pdc-stoppage-history=/);
  assert.match(decorated, /is-overdue/);
  assert.match(decorated, /BULLBAR-3421880/);
  const row = table.tableRowHtml(decorated, 'pmb', { key: 'k1' });
  const cell = cls => (new RegExp(`<td class="${cls}">([\\s\\S]*?)</td>`).exec(row) || [])[1];
  assert.match(cell('c-eta'), /class="pdc-parts-stoppage-slot"/);
  assert.match(cell('c-eta'), /is-overdue/);
  assert.match(cell('c-eta'), /<span class="pdc-parts-stoppage-open/);
  assert.doesNotMatch(cell('c-eta'), /data-pdc-stoppage-edit=|<button|type="date"|Place as STOPPAGE/);
  assert.doesNotMatch(cell('c-unit'), /pdc-parts-stoppage-slot|pdc-parts-eta /);
  assert.match(cell('c-ploc'), /05B3A/);
  assert.match(row, /data-vlt-parts-eta="2026-10-20"/);
  const cellSlot = stop.slotHtml({ ...state, editing: true, canEdit: true });
  assert.doesNotMatch(cellSlot, /type="date"|data-pdc-stoppage-edit=|<button/);
  assert.equal((cellSlot.match(/<div/g) || []).length, 1, 'the slot the table lifts has no nested div');
  const editing = stop.editorHtml({ ...state, editing: true });
  assert.match(editing, /type="date"/);
  assert.match(editing, /type="text"/);
  assert.match(editing, /data-pdc-stoppage-clear=/);
  assert.match(editing, /data-pdc-stoppage-checked=/);
  assert.match(editing, /Place as STOPPAGE/);
  assert.equal((editing.match(/<div/g) || []).length, 0, 'the panel form is not a table slot');
  const panel = stop.detailHtml(state);
  assert.match(panel, /Set date|Change/);
  assert.match(panel, /data-pdc-stoppage-place-now=/);
  assert.match(panel, /Place as STOPPAGE/);
  const readOnly = stop.slotHtml({ ...state, canEdit: false });
  assert.doesNotMatch(readOnly, /type="date"|data-pdc-stoppage-edit=/);
  assert.match(readOnly, /<span class="pdc-parts-stoppage-open is-overdue"/);
  const untouched = stop.decorateCard(card(unit), { vehicleId: VID, canEdit: false, today, manual: null });
  assert.equal(untouched, card(unit));
  const emailOnly = table.extractPartsEta(unit.replace(/<div class="pdc-parts-stoppage-slot"[\s\S]*?<\/div>/, ''));
  assert.match(emailOnly.span, /^<span class="pdc-parts-eta /);
  assert.equal(emailOnly.eta, '2026-11-02');
});

test('a chip-only Vehicle cell is lifted exactly as before, and a missing editor does not replace it', () => {
  const old = '<span class="incoming-card-main"><strong>HiLux</strong><span class="pdc-parts-eta-wrap"><span class="pdc-parts-eta pdc-parts-eta-due" title="x" aria-label="x">Parts ETA 22/10</span></span></span>';
  const lifted = table.extractPartsEta(old);
  assert.equal(lifted.span, '<span class="pdc-parts-eta pdc-parts-eta-due" title="x" aria-label="x">Parts ETA 22/10</span>');
  assert.equal(lifted.unit, '<span class="incoming-card-main"><strong>HiLux</strong></span>');
  assert.equal(lifted.eta, '');
  assert.deepEqual(table.COLUMNS.eta, { label: 'Parts ETA', width: 96, min: 56 });
  assert.equal(table.VERSION, '2026.10.28.r593'); // r567 stays on the loader; r586 New to PMB view bumps this module
});

test('a booking before a typed date warns, and a vehicle with no typed date keeps the email warning', () => {
  const warning = stop.manualWarning(
    { eta_date: '2026-11-02', note: 'TANK TR110' },
    [{ start: '2026-10-28T01:00:00Z' }],
    'Stock S-NEW',
    today
  );
  assert.equal(warning.eta, '2026-11-02');
  assert.equal(warning.parts[0].part, 'TANK TR110');
  assert.equal(warning.before.length, 1);
  assert.equal(stop.manualWarning({ eta_date: null, note: 'kept' }, [{ start: '2026-10-28T01:00:00Z' }], 'Stock S-NEW', today), null);
  assert.equal(stop.manualBookAllWarning({ eta_date: '2026-11-02' }, today, 'Stock S-NEW').bookAll, true);
  assert.equal(stop.manualBookAllWarning({ eta_date: '2026-10-20' }, today, 'Stock S-NEW'), null);
  const history = stop.historyHtml([{ action: 'set', old_eta: null, new_eta: '2026-10-20', new_note: 'Tank', by: 'parts', at: '2026-10-27T02:00:00Z' }]);
  assert.match(history, /— → 20\/10\/26/);
  assert.match(history, /set by parts/);
});

test('r567 is the go-live: new objects only, pins unchanged, check under pg_catalog', () => {
  assert.match(up, /Go-live/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt/);
  assert.match(up, /Pin count stays 241/);
  assert.match(up, /sort 338/);
  assert.match(up, /parts_stoppage_manual_567/);
  assert.match(up, /'F181'/);
  assert.match(up, /88d31cbd6ca5ddd372e3143d5f8c013f/);
  assert.match(up, /decd9053241b3fe8ede99bd231ad98ec/);
  assert.match(up, /6a0046123aeb862667dce68884318850/);
  assert.match(up, /a81b786bfc7868c3217d827933299678/);
  assert.match(up, /29dcb35956acd61b6a8aa2ca07a80182/);
  assert.doesNotMatch(up, /pg_catalog\.coalesce/);
  assert.doesNotMatch(up, /::(?:pg_catalog\.)?regprocedure/);
  assert.doesNotMatch(dollar(up, '$set564$'), /DELETE FROM|UPDATE public\.vehicles|INSERT INTO public\.vehicles|pdc_parts_eta|pdc_jita_eta/);
  assert.doesNotMatch(dollar(up, '$board564$'), /DELETE FROM|UPDATE public\.vehicles|pdc_parts_eta/);
  assert.doesNotMatch(dollar(up, '$hist564$'), /DELETE FROM|UPDATE public\.vehicles/);
  assert.match(dollar(up, '$set564$'), /deleted_at IS NULL/);
  assert.match(dollar(up, '$set564$'), /importer/);
  assert.match(up, /PERFORM set_config\('search_path','pg_catalog',true\)/);
  assert.match(up, /PERFORM set_config\('request\.jwt\.claims','',true\)/);
  assert.match(up, /parts_stoppage_manual_567/);
  assert.equal(md5(dollar(up, '$set564$')), 'fa275b45be296e9021f9f4dc570f5751');
  assert.equal(md5(dollar(up, '$board564$')), '89a8b409650f95c59f459c8b2ff31e60');
  assert.equal(md5(dollar(up, '$hist564$')), 'db31f96870cb5478e5f25426249a7e3e');
  assert.equal(md5(dollar(up, '$chk$')), 'a4fdf46d7a6f6dbc6ff158e0d138e6f2');
  assert.equal((up.match(/\$set564\$/g) || []).length, 2);
  assert.equal((up.match(/\$chk\$/g) || []).length, 2);
  assert.equal(scanSql(up).length, 0);
  assert.match(down, /DROP FUNCTION public\.set_pdc_parts_stoppage_564/);
  assert.match(down, /DROP TABLE public\.pdc_parts_stoppage_564/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='parts_stoppage_manual_567'/);
  assert.doesNotMatch(down, /DROP TABLE public\.vehicles|DELETE FROM public\.vehicles|DROP TABLE public\.pdc_parts_eta|DROP TABLE public\.pdc_jita_eta/);
  assert.match(down, /88d31cbd6ca5ddd372e3143d5f8c013f/);
  assert.equal(scanSql(down).length, 0);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /keyNumber\.onload = loadPartsStoppage/);
  assert.match(entry, /stoppage\.onload = loadVehicleLocationsTable/);
  assert.match(entry, /pdc-parts-stoppage\.js\?r567=2026\.10\.27\.r567/);
  assert.match(entry, /jitaEta\.onload = loadWorkshopVehicleSearch/);
  assert.match(entry, /search\.onload = loadKeyNumber/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*r567=2026\.10\.27\.r567/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*r564=2026\.10\.27\.r564/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-parts-stoppage\.js'/);
  assert.equal(fs.readFileSync('karratha/canonical-entry.js', 'utf8').includes('pdc-parts-stoppage'), false);
  assert.equal(fs.readFileSync('karratha/index.html', 'utf8').includes('r567=2026.10.27.r567'), false);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F181 \|/);
  assert.match(up, /One date per vehicle|not stored here/);
});
