/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const test = require('node:test');

const MIG = 'supabase/migrations/20261024090000_r523_perth_delivery_sublet.sql';
const DOWN = 'supabase/rollbacks/20261024090000_r523_perth_delivery_sublet.down.sql';

function perth(description, code = '') {
  const text = `${description} ${code}`.toUpperCase().replace(/\s+/g, ' ');
  return text.includes('PERTH DELIVERY');
}

function body(sql, tag) {
  const open = sql.indexOf(tag);
  assert.notEqual(open, -1, tag);
  const start = open + tag.length;
  const end = sql.indexOf(tag, start);
  assert.notEqual(end, -1, tag);
  return sql.slice(start, end);
}

function md5(text) {
  return crypto.createHash('md5').update(text).digest('hex');
}

test('r523 wording matches a line containing PERTH DELIVERY and skips other notes', () => {
  assert.equal(perth('PERTH DELIVERY'), true);
  assert.equal(perth('Perth Delivery'), true);
  assert.equal(perth('PERTH  DELIVERY'), true);
  assert.equal(perth('TO PERTH DELIVERY'), true);
  assert.equal(perth('Pre-Delivery (Commercial) PERTH DELIVERY'), true);
  assert.equal(perth('radio quote', 'PERTH DELIVERY'), true);
  assert.equal(perth('KARRATHA DELIVERY'), false);
  assert.equal(perth('PRE-DELIVERY'), false);
  assert.equal(perth('Pre-Delivery (Commercial)'), false);
  assert.equal(perth('Pit Fee for fuel Tank Certification'), false);
  assert.equal(perth('PITS - REFER BRYCE IF REQUIRED'), false);
  assert.equal(perth('DELIVERY TO PERTH'), false);
  assert.equal(perth('PERTH'), false);
});

test('r523 migration routes PERTH DELIVERY to SUBLET and does not add a station or replace approve', () => {
  const sql = fs.readFileSync(MIG, 'utf8');
  const down = fs.readFileSync(DOWN, 'utf8');
  assert.match(sql, /cdsmnqxtyyoeoznmbidd/);
  assert.match(sql, /pdc_production_environment_sentinel/);
  assert.match(sql, /perth_delivery_sublet_523/);
  assert.match(sql, /note_fee_sublet_521/);
  assert.match(sql, /'F137'/);
  assert.match(sql, /sort_order,added_in\) VALUES\n \('perth_delivery_sublet_523','F137'/);
  assert.match(sql, /,true,307,'r523'\)/);
  assert.match(sql, /information_only',false/);
  assert.match(sql, /742f3544-a3d4-41fb-87a2-4897609c506c/);
  assert.match(sql, /9df31e06-91e5-42d0-9ef9-64dfbf0f7a02/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\.approve_pdc_new_vehicle_review\b/);
  assert.doesNotMatch(sql, /INSERT INTO public\.workshop_stages/);
  assert.doesNotMatch(sql, /karratha135/);
  assert.doesNotMatch(sql, /CREATE FUNCTION pdc_work_categories_private\.note_fee_sublet_521/);
  assert.match(sql, /CREATE FUNCTION pdc_work_categories_private\.perth_delivery_sublet_523/);
  const helper = body(sql, '$r523h$');
  assert.match(helper, /PERTH DELIVERY/);
  assert.doesNotMatch(helper, /po_details/);
  assert.equal(md5(helper), '2944c99ffc3c4ce09704b00d66f9fdc4');
  assert.equal(md5(body(sql, '$r523s$')), '5adf2ee5c2dc8c11199d314be477a6c1');
  assert.equal(md5(body(sql, '$r523e$')), 'c8d16e91e728540542c843751c311a97');
  assert.equal(md5(body(sql, '$r523b$')), '82c809d15c382e73c0ae5bf135293ebe');
  assert.equal(md5(body(sql, '$r523r$')), 'f60ac3617342e6317107e84e014c4c36');
  assert.equal(md5(body(sql, '$r523p$')), 'bae621855931cc4bca6e326037559da2');
  assert.equal(md5(body(sql, '$r523v$')), '0d71cc4ee105b90fa970622a3f4deb5d');
  assert.equal(md5(body(down, '$r521s$')), '7d941ee91841523ad880d18eb374d13b');
  assert.equal(md5(body(down, '$r521e$')), 'c12f8b4d2615e097f2730fd96a7a95d3');
  assert.equal(md5(body(down, '$r521b$')), '4e8f82866367021e75a1be4b4b6c2b36');
  assert.equal(md5(body(down, '$r521r$')), '6c9ebde7c5f1da217ccec3d3d63d5286');
  assert.equal(md5(body(down, '$r521p$')), '266421b0f3dcef1325dc594b7495c096');
  assert.equal(md5(body(down, '$r521v$')), '698f4db6c24d2528f72fa222fb6f404f');
  assert.match(down, /DROP FUNCTION pdc_work_categories_private\.perth_delivery_sublet_523/);
  assert.match(down, /pin count is not 234/);
  assert.match(down, /834ecf512acbb23bf2c8741cc18eb265/);
  assert.match(down, /fe80b070e1248b9ccaca66bb6d2fc1d8/);
  assert.doesNotMatch(down, /DROP FUNCTION pdc_work_categories_private\.note_fee_sublet_521/);
});
