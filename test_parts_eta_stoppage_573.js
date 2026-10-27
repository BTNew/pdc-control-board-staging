/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');
const stop = require('./pdc-parts-stoppage.js');
const jita = require('./pdc-jita-eta.js');

const REPORTED_FAULTS = Object.freeze([
  'A parts ETA can be placed as a vehicle STOPPAGE until 06:00 Perth on the ETA date.',
  'Clearing the ETA, unticking Place as STOPPAGE, or receiving the parts lifts it.',
  'Later jobs are pushed back. A raw exclusion error is returned as push_failed.',
  'A vehicle stoppage still occupies the vehicle, including when the bay is empty.',
  'The change is audited as place or lift and can be reversed.',
  'Pins stay 241. The r567 manual save, the email ETA, the clock and department 135 stay as they are.',
  'The control is blue. Department 135 files are not edited.',
]);

const up = fs.readFileSync('supabase/migrations/20261027240000_r573_parts_eta_stoppage.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027240000_r573_parts_eta_stoppage.down.sql', 'utf8');
const dollar = (sql, tag) => {
  const open = sql.indexOf(tag);
  const close = sql.indexOf(tag, open + tag.length);
  return sql.slice(open + tag.length, close);
};
const md5 = text => crypto.createHash('md5').update(text).digest('hex');
const VID = '11111111-1111-4111-8111-111111111111';

test('REPORTED_FAULTS: placing a parts ETA is a blue STOPPAGE choice and the section names it', () => {
  assert.equal(REPORTED_FAULTS.length, 7);
  const editing = stop.slotHtml({
    vehicleId: VID, canEdit: true, editing: true, today: '2026-10-27', placed: true,
    manual: { eta_date: '2026-11-02', note: 'Bull bar' }, draftEta: '2026-11-02', draftNote: 'Bull bar'
  });
  assert.match(editing, /Place as STOPPAGE/);
  assert.match(editing, /data-pdc-stoppage-place=/);
  assert.match(editing, /checked/);
  assert.equal((editing.match(/<div/g) || []).length, 1);
  assert.doesNotMatch(editing, /danger-button|#f97316|orange/i);
  assert.deepEqual(stop.placePayload('save', { eta: '2026-11-02', note: 'Bull bar' }, true, false), {
    p_place: true, p_eta: '2026-11-02', p_note: 'Bull bar'
  });
  assert.deepEqual(stop.placePayload('save', { eta: '2026-11-02', note: 'Bull bar' }, false, true), { p_place: false });
  assert.equal(stop.placePayload('check', { eta: '2026-11-02' }, true, true), null);
  assert.equal(stop.placePayload('clear', { eta: '' }, true, false), null);
  assert.deepEqual(stop.placePayload('clear', { eta: '' }, true, true), { p_place: false });
  assert.match(stop.placeMessage({ error: 'push_failed' }), /could not be moved/);
  assert.match(stop.placeMessage({ code: 'eta_reached' }), /already here/);
  const empty = stop.plannerSectionHtml();
  assert.match(empty, /aria-label="Stoppage"/);
  assert.match(empty, /No parts ETA is placed as STOPPAGE/);
  assert.doesNotMatch(empty, /Bull bar|11111111/);
  const filled = stop.plannerSectionHtml([{
    vehicle_id: VID, stock_number: '13057027', key_number: '209', eta_date: '2026-11-02',
    note: 'Bull bar', reason: 'STOPPAGE · Parts ETA 02/11/26 · Bull bar', set_by_actor: 'parts@pmg.example'
  }]);
  assert.match(filled, />STOPPAGE</);
  assert.match(filled, /13057027/);
  assert.match(filled, /Key 209/);
  assert.match(filled, /Bull bar/);
  assert.match(filled, /parts@pmg\.example/);
  assert.deepEqual(jita.placeTargets([
    { status: 'applied', vehicle_id: VID, eta_date: '2026-11-02' },
    { status: 'unchanged', vehicle_id: VID, eta_date: '2026-11-02' },
    { status: 'applied', vehicle_id: 'not-a-uuid', eta_date: '2026-11-02' }
  ], true), [{ vehicle_id: VID, eta_date: '2026-11-02' }]);
  assert.deepEqual(jita.placeTargets([{ status: 'applied', vehicle_id: VID, eta_date: '2026-11-02' }], false), []);
});

test('r580 go-live SQL is the next free check and does not retouch the live bodies', () => {
  assert.match(up, /r580 \(F193\) \/ sort 351/);
  assert.doesNotMatch(up, /PREVIEW|Do not apply/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt/);
  assert.match(up, /'F193'/);
  assert.match(up, /sort_order=351/);
  assert.match(up, /parts_eta_stoppage_573/);
  assert.match(up, /true, 351, 'r580'/);
  assert.match(up, /release = 'r580'/);
  assert.match(up, /c\.conrelid = 'public\.workshop_bookings'::regclass/);
  assert.doesNotMatch(up, /sort_order=344|fault_id='F187'|added_in='r573'|release = 'r573'|release='r573'/);
  assert.match(up, /fa275b45be296e9021f9f4dc570f5751/);
  assert.match(up, /88d31cbd6ca5ddd372e3143d5f8c013f/);
  assert.match(up, /83a2c8d5ff85b5a295343e5f3ef66ded/);
  assert.match(up, /4eb5baf999b849d174880a1e261fcbf2/);
  assert.match(up, /8976b0adba341dc35723bab724ff0f1e/);
  assert.match(up, /WITH reported_faults AS/);
  assert.match(up, /AS ok/);
  assert.match(up, /AS detail/);
  assert.match(up, /pg_catalog\.strpos/);
  assert.doesNotMatch(up, /pg_catalog\.coalesce|::regprocedure|pg_catalog\.position\(/);
  assert.equal((up.match(/INSERT INTO pdc_ops\.expected_function_md5/g) || []).length, 0);
  assert.match(up, /Pin count stays 241|pin count is not 241/);
  assert.match(dollar(up, '$place573$'), /Australia\/Perth/);
  assert.match(dollar(up, '$place573$'), /workshop_add_operational_minutes/);
  assert.match(dollar(up, '$place573$'), /exclusion_violation/);
  assert.match(dollar(up, '$place573$'), /parts_eta_stoppage_573/);
  assert.doesNotMatch(dollar(up, '$place573$'), /karratha135|UPDATE public\.vehicles/);
  assert.match(dollar(up, '$recv573$'), /parts_received/);
  assert.match(dollar(up, '$end573$'), /'lift'/);
  assert.equal(scanSql(up).length, 0, scanSql(up).join('\n'));
  assert.match(down, /parts_eta_stoppage_573/);
  assert.match(down, /fault_id='F193' AND sort_order=351 AND added_in='r580'/);
  assert.doesNotMatch(down, /added_in='r573'|fault_id='F187'|sort_order=344/);
  assert.match(down, /action IN \('place', 'lift'\)/);
  assert.doesNotMatch(down, /DROP TABLE public\.pdc_parts_stoppage_564|DROP TABLE public\.vehicles|UPDATE public\.vehicles|UPDATE public\.pdc_parts_eta|DROP TABLE public\.pdc_jita_eta/);
  assert.equal(scanSql(down).length, 0, scanSql(down).join('\n'));
  const app = fs.readFileSync('app.js', 'utf8');
  const planner = fs.readFileSync('workshop-planner.js', 'utf8');
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(app, /data-parts-place-stoppage/);
  assert.match(app, /class="parts-place-stoppage"/);
  assert.doesNotMatch(app.slice(app.indexOf('data-parts-place-stoppage') - 80, app.indexOf('data-parts-place-stoppage') + 160), /danger-button/);
  assert.equal((app.match(/r573=2026\.10\.27\.r573/g) || []).length, 2);
  assert.match(planner, /workshop-parts-stoppage/);
  assert.match(planner, /aria-label="Stoppage"/);
  assert.match(entry, /pdc-parts-stoppage\.js\?r567=2026\.10\.27\.r567&r573=2026\.10\.27\.r573/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /id="jita-place-stoppage"/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /id="jita-upload-panel" hidden>/);
  assert.match(fs.readFileSync('styles.css', 'utf8'), /#parts \.parts-place-stoppage[\s\S]*#1d4ed8/);
  assert.match(fs.readFileSync('workshop-planner.css', 'utf8'), /\.workshop-parts-stoppage-card[\s\S]*#dbeafe/);
  for (const file of ['karratha/app.js', 'karratha/workshop-planner.js', 'karratha/index.html', 'karratha/styles.css', 'karratha/workshop-planner.css']) {
    assert.equal(fs.readFileSync(file, 'utf8').includes('r573'), false, file);
    assert.equal(fs.readFileSync(file, 'utf8').includes('place_parts_eta_stoppage_573'), false, file);
  }
  assert.equal(md5(dollar(up, '$place573$')).length, 32);
});
