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
  const quoted = [...up.matchAll(/~ '([^']+)'/g)].map((m) => m[1]);
  assert.ok(quoted.includes(PATTERN));
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
  assert.equal(up.includes('po_details'), true);
  assert.equal(up.includes("position('po_details' in h)=0"), true);
});

test('the new rule sits after the pit rule and before the department gate', () => {
  const pit = up.indexOf('PIT[[:space:]]*(INSPECTION|AND[[:space:]]*(WEIGH|WAY))|(WEIGH|WAY)BRIDGE|DEPARTMENT OF TRANSPORT.*INSPECTION');
  const namedIf = up.indexOf("IF pdc_work_categories_private.named_external_sublet_584(line) THEN RETURN 'SUBLET'; END IF;");
  const gate = up.indexOf("IF line->>'department' IS DISTINCT FROM '138'");
  assert.ok(pit > 0 && namedIf > pit && gate > namedIf);
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION public.pdc_line_is_pit_401'), false);
  assert.equal(up.includes('7e10e4f66633cf5129c5b2c21aa905e0'), true);
  assert.equal(down.includes('CREATE OR REPLACE FUNCTION public.pdc_line_is_pit_401'), false);
  const seatCover = up.indexOf("IF d ~ 'ACCESSOR|SEAT COVER|FLOOR MAT|CARGO BARRIER|ROOF RACK'");
  assert.ok(seatCover > namedIf);
});

test('import, route and pending call the helper, and a person lock still wins', () => {
  const whenAt = up.indexOf('WHEN NOT protected_booking AND NOT coalesce(manual_assignment_locked,false) AND pdc_work_categories_private.named_external_sublet_584(l)');
  const unallocated = up.indexOf("WHEN l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW'");
  assert.ok(whenAt > 0 && whenAt < unallocated);
  assert.ok(up.includes('WHEN NOT protected_booking AND NOT coalesce(manual_assignment_locked,false) AND (pdc_work_categories_private.note_fee_sublet_521(l) OR pdc_work_categories_private.perth_delivery_sublet_523(l))'));
  const routeFn = up.indexOf('CREATE OR REPLACE FUNCTION pdc_work_categories_private.route_import_line_20261017');
  const routeAt = up.indexOf('IF pdc_work_categories_private.named_external_sublet_584(line) THEN', routeFn);
  const aiAt = up.indexOf('SELECT * INTO r FROM pdc_operation_updates_private.ai_routing_20261019', routeFn);
  assert.ok(routeAt > routeFn && routeAt < aiAt);
  const pendingFn = up.indexOf('FUNCTION public.pdc_pending_work_category_20260912');
  const pendingAt = up.indexOf('named_external_sublet_584(p_line)', pendingFn);
  const hoursAt = up.indexOf('service_catalogue_hours_20260917', pendingFn);
  assert.ok(pendingAt > pendingFn && pendingAt < hoursAt);
  const reviewedFn = up.indexOf('FUNCTION pdc_work_categories_private.reviewed_import_choice_139_20261018');
  const reviewedAt = up.indexOf('named_external_sublet_584(p_line) THEN RETURN base', reviewedFn);
  const rulesAt = up.indexOf('import_rules_139', reviewedFn);
  assert.ok(reviewedAt > reviewedFn && reviewedAt < rulesAt);
  assert.ok(up.includes('Put them back on Sublet after that overwrite'));
  assert.equal(up.includes("WHEN 'SUBLET' THEN 'note_fee_sublet_521'"), true);
  assert.equal(up.includes("WHEN 'SUBLET' THEN 'named_external_sublet_584'"), false);
});

test('the before_import pin stays r523 and the two stored checks move with the new bodies', () => {
  assert.equal(up.includes("prosrc_md5='286cf6f7ac9831817d48388c75b69dec', release='r523'"), true);
  assert.equal(up.includes("signature='pdc_work_categories_private.before_import_rules_20261017(uuid)' AND prosrc_md5='82c809d15c382e73c0ae5bf135293ebe' AND release='r523'"), true);
  for (const signature of [
    'pdc_work_categories_private.suggest(jsonb)',
    'pdc_operation_updates_private.ensure_required_work_20261019(uuid)',
    'pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)',
    'public.pdc_pending_work_category_20260912(jsonb)',
    'pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'
  ]) {
    const at = up.indexOf(`signature='${signature}'`);
    const upd = up.lastIndexOf('UPDATE pdc_ops.expected_function_md5', at);
    assert.ok(at > 0 && upd > 0, signature);
    assert.equal(up.slice(upd, at).includes("release='r584'"), true, signature);
  }
  assert.equal(up.includes("check_name IN ('note_fee_sublet_521','perth_delivery_sublet_523')"), true);
  assert.equal(up.includes("'5adf2ee5c2dc8c11199d314be477a6c1','480bc6eb72a1585a2b909bb7a478585a'"), true);
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
  assert.equal(down.includes('DROP FUNCTION pdc_work_categories_private.named_external_sublet_584(jsonb)'), true);
  assert.equal(down.includes('5adf2ee5c2dc8c11199d314be477a6c1'), true);
  assert.equal(down.includes('ee799302c1bdd37bcfba15837859e200'), false);
  assert.equal(down.includes('DROP TABLE pdc_ops.named_external_work_touch_584'), true);
});

test('regression check named_external_sublet_584 is F198 sort 356', () => {
  assert.equal(up.includes("('named_external_sublet_584','F198'"), true);
  assert.equal(up.includes(",true,356,'r584'"), true);
  assert.equal(up.includes('r583 / F197 / sort 355'), true);
  assert.equal(log.includes('| F198 |'), true);
  assert.equal(log.includes('| F130 |'), true);
  assert.equal(log.includes('named_external_sublet_584'), true);
  assert.equal(log.includes('<<<<<<<'), false);
  assert.equal(log.includes('named_external_sublet_516'), false);
  assert.equal(fs.existsSync('pdc-vehicle-sublets.js'), true);
  assert.equal(up.includes('pdc-vehicle-sublets.js'), false);
  assert.equal(fs.existsSync('supabase/migrations/20261023180000_r516_named_external_sublet.sql'), false);
});
