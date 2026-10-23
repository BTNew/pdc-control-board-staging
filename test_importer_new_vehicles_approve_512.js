'use strict';
const assert = require('node:assert');
const crypto = require('node:crypto');
const fs = require('node:fs');
const test = require('node:test');

const page = fs.readFileSync('pdc-new-vehicles.js', 'utf8');
const karratha = fs.readFileSync('karratha/pdc-new-vehicles.js', 'utf8');
const entry = fs.readFileSync('canonical-entry.js', 'utf8');
const karrathaEntry = fs.readFileSync('karratha/canonical-entry.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');
const up = fs.readFileSync('supabase/migrations/20261023153000_r512_importer_new_vehicles_approve.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261023153000_r512_importer_new_vehicles_approve.down.sql', 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');

const pairs = [
  ['public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)', 'f099baf746f35b500389749ac844bc2f', 'bb8b90544975b50bf9dad84d036473e0'],
  ['public.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)', 'c393460c311134c1b7fcdfa02f68b0a7', 'b23c4aca36597cbee7a0c7a56933c075'],
  ['karratha135_pdc.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)', 'd4661aa5e0527e92aa1e52d446cd27d3', '0a8b5810af1b1ff60345172bf6ae1165'],
  ['karratha135_pdc.approve_pdc_tune_operation_change_with_schedule(uuid,text,text,numeric,uuid)', '2daae464df647572030a4c5ee5d75828', 'd027211f713bf0edb2b993cf2ade86ff'],
];

test('New Vehicles writable includes importer and retry stays controller-only', () => {
  assert.match(page, /const writable=\(\)=>\['operator','importer','administrator'\]\.includes\(window\.PDC_AUTH_CONTEXT\?\.role\);/);
  assert.match(page, /const readable=\(\)=>\['viewer','operator','importer','administrator'\]\.includes\(window\.PDC_AUTH_CONTEXT\?\.role\);/);
  assert.match(page, /const retryWritable=\(\)=>\['operator','administrator'\]\.includes\(window\.PDC_AUTH_CONTEXT\?\.role\);/);
  assert.match(page, /retryWritable\(\)\?'<button data-update-retry/);
  assert.match(page, /if\(saving\|\|loading\|\|!retryWritable\(\)\)return;/);
  assert.doesNotMatch(page, /writable\(\)\?'<button data-update-retry/);
  assert.match(page, /PDC_NEW_VEHICLES_VERSION='2026\.10\.23\.r512'/);
  assert.match(page, /const APPROVE_RPC = 'approve_pdc_new_vehicle_review_446'/);
  assert.match(page, /rpc\('approve_pdc_tune_operation_change_with_schedule'/);
  assert.match(karratha, /const writable=\(\)=>\['operator','importer','administrator'\]\.includes\(window\.PDC_AUTH_CONTEXT\?\.role\);/);
  assert.match(karratha, /rpc\('approve_pdc_new_vehicle_review'/);
  assert.match(karratha, /PDC_NEW_VEHICLES_VERSION='2026\.10\.23\.r512'/);
  assert.doesNotMatch(karratha, /retryWritable/);
  assert.match(entry, /pdc-new-vehicles\.js\?[^']*r512=2026\.10\.23\.r512/);
  assert.match(entry, /r459=2026\.10\.22\.r459/);
  assert.doesNotMatch(karrathaEntry, /r512=2026\.10\.23\.r512/);
  assert.match(html, /canonical-entry\.js\?[^"]*r512=2026\.10\.23\.r512/);
  assert.match(html, /app\.js\?[^"]*&amp;r510=2026\.10\.23\.r510"/);
});

test('the migration widens only the four approval role gates and the undo puts them back', () => {
  assert.match(up, /Already applied as r512_importer_new_vehicles_approve version 20261023055815/);
  assert.match(up, /Do not re-apply/);
  assert.doesNotMatch(up, /PREVIEW/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.is_pdc_role/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.workshop_is_planner_operator/);
  assert.match(up, /public\.workshop_is_planner_operator\(\)/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.approve_pdc_new_vehicle_review_446/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.approve_pdc_tune_operation_change\(/);
  assert.match(up, /a50e6a6988ae3a106f959e3163b4121c/);
  assert.match(up, /39a794b23d1d63117cf549d78acba4de\|r421/);
  for (const [sig, before, after] of pairs) {
    assert.ok(up.includes(sig), sig);
    assert.ok(up.includes(before), before);
    assert.ok(up.includes(after), after);
    assert.ok(down.includes(sig), 'down ' + sig);
    assert.ok(down.includes(before), 'down ' + before);
    assert.ok(down.includes(after), 'down ' + after);
  }
  assert.match(up, /\$q\$role IN\('operator','importer','administrator'\)\$q\$/);
  assert.match(up, /chr\(39\) \|\| 'importer'/);
  assert.match(down, /chr\(39\) \|\| 'operator' \|\| chr\(39\) \|\| ',' \|\| chr\(39\) \|\| 'administrator'/);
  assert.doesNotMatch(up, /SELECT md5\(p\.prosrc\),/);
  assert.doesNotMatch(down, /SELECT md5\(p\.prosrc\),/);
  assert.match(up, /EXECUTE def;\n    SELECT p\.prosrc,/);
  assert.match(down, /EXECUTE def;\n    SELECT p\.prosrc,/);
  assert.match(up, /importer_new_vehicles_approve_512/);
  assert.match(up, /true, 297, 'r512'/);
  assert.match(up, /'F125'/);
  const check = up.split('$chk$')[1];
  assert.equal(crypto.createHash('md5').update(check).digest('hex'), '0e0c5e74794aa8337c9906007cb0d71d');
  assert.match(up, /sort_order, added_in\) VALUES/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks/);
  assert.match(down, /WHERE check_name='importer_new_vehicles_approve_512'/);
  assert.match(down, /fault_id='F125'/);
  assert.match(down, /sort_order=297/);
  assert.match(up, /WHERE signature='public\.approve_pdc_new_vehicle_review\(uuid,text,jsonb,uuid\)'/);
  assert.match(down, /release='r446'/);
  assert.ok(log.indexOf('| F123 |') < log.indexOf('| F124 |'));
  assert.ok(log.indexOf('| F124 |') < log.indexOf('| F125 |'));
  assert.match(log, /\| F125 \|/);
});
