/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r584 (F198): MMT seat covers, IVMS, RADLINK and reflective stripes are external sublets. Preview only. Not applied.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ID = '20261028040000_r584_named_external_sublet';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const PATTERN = "MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES";
const SIX = [
  '5adf2ee5c2dc8c11199d314be477a6c1',
  'c8d16e91e728540542c843751c311a97',
  '82c809d15c382e73c0ae5bf135293ebe',
  'f60ac3617342e6317107e84e014c4c36',
  'bae621855931cc4bca6e326037559da2',
  '0d71cc4ee105b90fa970622a3f4deb5d'
];

function named(description, operationCode) {
  const text = `${description || ''} ${operationCode || ''}`.toUpperCase().replace(/\s+/g, ' ');
  return new RegExp(PATTERN).test(text);
}

test('migration files are LF only and name staging only', () => {
  assert.equal(up.includes('\r'), false);
  assert.equal(down.includes('\r'), false);
  assert.equal(up.includes('Production vjdtsswhroyguxyfjdkt is not a target.'), true);
  assert.equal(up.replace('Production vjdtsswhroyguxyfjdkt is not a target.', '').includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(up.includes('cdsmnqxtyyoeoznmbidd'), true);
  assert.equal(up.includes('PREVIEW'), true);
  assert.equal(up.includes('Do not merge'), true);
  assert.equal(up.includes('Do not apply'), true);
  assert.equal(up.slice(0, 400).includes('Specialise Pty Ltd'), false);
});

test('the four phrases match the whole line, not a PO item and not near-misses', () => {
  assert.equal(up.includes(PATTERN), true);
  assert.equal(down.includes(PATTERN), true);
  for (const phrase of ['MMT Seat Covers', 'MMT SEAT COVERS', 'mmt seat cover', 'MMT CLOTH/COMMUTER SEAT COVERS', 'Fit Navman IVMS', 'FMG IVMS to be fitted', 'IVMS', 'RADLINK quote', 'Radlink', 'reflective stripes', 'Reflective Stripes - Yellow', 'REFLECTIVE   STRIPES WHITE']) {
    assert.equal(named(phrase), true, phrase);
  }
  assert.equal(named('Leaf springs', 'RADLINK'), true);
  assert.equal(named('radio quote', 'radlink'), true);
  assert.equal(named('Canvas seat covers'), false);
  assert.equal(named('seat covers'), false);
  assert.equal(named('DIVMS unit'), false);
  assert.equal(named('reflective striping'), false);
  assert.equal(named('IVMSX'), false);
  assert.equal(named('Leaf springs', 'SPRING'), false);
  const hookStart = up.indexOf('AS $function$');
  const hookEnd = up.indexOf('$function$;');
  const hook = up.slice(hookStart, hookEnd);
  assert.equal(hook.includes('po_details'), false);
  assert.equal(up.includes("position('po_details' in h)=0"), true);
  assert.equal(up.includes('{"description":"Leaf springs","operation_code":"SPRING","po_details":"IVMS"}'), true);
});

test('the hook changes and the six r523 bodies are not replaced', () => {
  for (const name of [
    'pdc_work_categories_private.suggest',
    'pdc_operation_updates_private.ensure_required_work_20261019',
    'pdc_work_categories_private.before_import_rules_20261017',
    'pdc_work_categories_private.route_import_line_20261017',
    'public.pdc_pending_work_category_20260912',
    'pdc_work_categories_private.reviewed_import_choice_139_20261018'
  ]) {
    assert.equal(up.includes(`CREATE OR REPLACE FUNCTION ${name}`), false, name);
    assert.equal(down.includes(`CREATE OR REPLACE FUNCTION ${name}`), false, name);
  }
  assert.equal(up.includes('CREATE FUNCTION pdc_work_categories_private.named_external_sublet_584'), false);
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION pdc_work_categories_private.note_fee_sublet_521'), true);
  assert.equal(down.includes('CREATE OR REPLACE FUNCTION pdc_work_categories_private.note_fee_sublet_521'), true);
  assert.equal(up.includes('ca08696ffbe6a1834e63f8b8faf246e1'), true);
  assert.equal(up.includes('2813508255aa6f65c7490e54c76cd564'), true);
  assert.equal(down.includes('2813508255aa6f65c7490e54c76cd564'), true);
  for (const md5 of SIX) {
    assert.equal(up.includes(md5), true, md5);
    assert.equal(down.includes(md5), true, md5);
  }
  assert.equal(up.includes("<>'r523'"), true);
  assert.equal(up.includes("release='r521'"), true);
  assert.equal(up.includes("WHERE release='r584')<>0"), true);
  assert.equal(/SET[^;]*release='r584'/.test(up), false);
  assert.equal(up.includes('480bc6eb72a1585a2b909bb7a478585a'), false);
  assert.equal(up.includes('286cf6f7ac9831817d48388c75b69dec'), false);
});

test('the two stored checks keep the six checksums and take the new hook md5', () => {
  assert.equal(up.includes("check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523')"), true);
  assert.equal(up.includes("replace(check_sql, '2813508255aa6f65c7490e54c76cd564', 'ca08696ffbe6a1834e63f8b8faf246e1')"), true);
  assert.equal(down.includes("replace(check_sql, 'ca08696ffbe6a1834e63f8b8faf246e1', '2813508255aa6f65c7490e54c76cd564')"), true);
  assert.equal(up.includes("<>'82c809d15c382e73c0ae5bf135293ebe'"), true);
  assert.equal(up.includes("->>'routing_rule'='note_fee_sublet_521'"), true);
  assert.equal(up.includes("WHEN 'SUBLET' THEN 'named_external_sublet_584'"), false);
  assert.equal(up.includes('7e10e4f66633cf5129c5b2c21aa905e0'), true);
  assert.equal(up.includes('2944c99ffc3c4ce09704b00d66f9fdc4'), true);
});

test('work-item writes are sublet only and the down file reverses them', () => {
  assert.equal(up.includes('ensure_required_work_20261019(vid)'), false);
  assert.equal(up.includes('CREATE TABLE pdc_ops.named_external_work_touch_584'), true);
  assert.equal(up.includes("SELECT t.vehicle_id, 'sublet', true, false, 'Required by canonical imported jobcard work'"), true);
  assert.equal(up.includes('pdc_qc_operation_lines_379_uncached(t.vehicle_id)'), true);
  assert.equal(down.includes('pdc_qc_operation_lines_379_uncached(x.vehicle_id)'), true);
  const dis = down.indexOf('DISABLE TRIGGER pdc_772_work_item_no_delete');
  const del = down.indexOf('DELETE FROM public.vehicle_work_items');
  const en = down.indexOf('ENABLE TRIGGER pdc_772_work_item_no_delete');
  assert.ok(dis > 0 && del > dis && en > del);
  assert.equal(down.includes("w.work_key='sublet'"), true);
  assert.equal(down.includes('DROP FUNCTION pdc_work_categories_private.named_external_sublet_584(jsonb)'), false);
  assert.equal(down.includes('DROP TABLE pdc_ops.named_external_work_touch_584'), true);
  const restore = down.indexOf('CREATE OR REPLACE FUNCTION pdc_work_categories_private.note_fee_sublet_521');
  assert.ok(restore > 0 && restore < dis);
});

test('regression check named_external_sublet_584 is F198 sort 356', () => {
  assert.equal(up.includes("('named_external_sublet_584','F198'"), true);
  assert.equal(up.includes(',true,356,\'r584\''), true);
  assert.equal(up.includes('r583 / F197 / sort 355'), true);
  assert.equal(log.includes('| F198 |'), true);
  assert.equal(log.includes('| F130 |'), true);
  assert.equal(log.includes('named_external_sublet_584'), true);
  assert.equal(log.includes('<<<<<<<'), false);
  assert.equal(log.includes('named_external_sublet_516'), false);
  assert.equal(log.includes('ca08696ffbe6a1834e63f8b8faf246e1'), true);
  assert.equal(log.includes('82c809d15c382e73c0ae5bf135293ebe'), true);
  assert.equal(fs.existsSync('pdc-vehicle-sublets.js'), true);
  assert.equal(up.includes('pdc-vehicle-sublets.js'), false);
  assert.equal(fs.existsSync('supabase/migrations/20261023180000_r516_named_external_sublet.sql'), false);
});
