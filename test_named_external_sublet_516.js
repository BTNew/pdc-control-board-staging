/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r516 (F130): MMT seat covers, IVMS, RADLINK and reflective stripes are external sublets. SQL only. Not applied.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ID = '20261023180000_r516_named_external_sublet';
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
  assert.equal(up.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(up.includes('cdsmnqxtyyoeoznmbidd'), true);
  assert.equal(up.includes('PREVIEW'), true);
  assert.equal(up.includes('Do not merge'), true);
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
  const namedIf = up.indexOf("IF pdc_work_categories_private.named_external_sublet_516(line) THEN RETURN 'SUBLET'; END IF;");
  const gate = up.indexOf("IF line->>'department' IS DISTINCT FROM '138'");
  assert.ok(pit > 0 && namedIf > pit && gate > namedIf);
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION public.pdc_line_is_pit_401'), false);
  assert.equal(up.includes('7e10e4f66633cf5129c5b2c21aa905e0'), true);
  assert.equal(down.includes('7e10e4f66633cf5129c5b2c21aa905e0'), true);
  const seatCover = up.indexOf("IF d ~ 'ACCESSOR|SEAT COVER|FLOOR MAT|CARGO BARRIER|ROOF RACK'");
  assert.ok(seatCover > namedIf);
});

test('import, route and pending all call the helper, and a person lock still wins', () => {
  const whenAt = up.indexOf('WHEN NOT protected_booking AND NOT coalesce(manual_assignment_locked,false) AND pdc_work_categories_private.named_external_sublet_516(l)');
  const unallocated = up.indexOf("WHEN l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW'");
  assert.ok(whenAt > 0 && whenAt < unallocated);
  assert.ok(up.includes('override_category,booked_category,owner_reviewed_category,CASE'));
  const routeAt = up.indexOf('IF pdc_work_categories_private.named_external_sublet_516(line) THEN');
  const aiAt = up.indexOf('SELECT * INTO r FROM pdc_operation_updates_private.ai_routing_20261019');
  assert.ok(routeAt > 0 && routeAt < aiAt);
  const pendingAt = up.indexOf('named_external_sublet_516(p_line)');
  const hoursAt = up.indexOf('service_catalogue_hours_20260917');
  assert.ok(pendingAt > 0 && pendingAt < hoursAt);
  assert.ok(up.indexOf('import_rules_139_20261018') > up.lastIndexOf('named_external_sublet_516(p_line) THEN RETURN base'));
  assert.equal(up.includes("WHEN 'SUBLET' THEN 'named_external_sublet_516'"), true);
});

test('regression check named_external_sublet_516 is F130 sort 302', () => {
  assert.equal(up.includes("('named_external_sublet_516','F130'"), true);
  assert.equal(up.includes(',true,302,\'r516\''), true);
  assert.equal(log.includes('| F130 |'), true);
  assert.equal(log.includes('named_external_sublet_516'), true);
  assert.equal(down.includes('DELETE FROM public.vehicle_work_items'), false);
  assert.equal(down.includes('DROP FUNCTION pdc_work_categories_private.named_external_sublet_516(jsonb)'), true);
  assert.equal(down.includes('ee799302c1bdd37bcfba15837859e200'), true);
  assert.equal(fs.existsSync('pdc-vehicle-sublets.js'), true);
  assert.equal(up.includes('pdc-vehicle-sublets.js'), false);
});
