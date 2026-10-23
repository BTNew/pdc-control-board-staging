/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');

const MIG = 'supabase/migrations/20261024003000_r522_note_fee_sublet.sql';
const DOWN = 'supabase/rollbacks/20261024003000_r522_note_fee_sublet.down.sql';
const PATTERN = /(^|[^A-Z0-9])PIT FEES?([^A-Z0-9]|$)|(^|[^A-Z0-9])WEIGH([^A-Z0-9]|$)|(WEIGH|WAY)BRIDGE|FULL TANK OF FUEL|FUEL TANK CERTIF/;

function fee(description, code = '') {
  const text = `${description} ${code}`.toUpperCase().replace(/\s+/g, ' ');
  return PATTERN.test(text);
}

test('r522 fee wording matches Craig\'s note and fee lines and skips workshop installs', () => {
  assert.equal(fee('Pit Fee for fuel Tank Certification'), true);
  assert.equal(fee('PIT FEES'), true);
  assert.equal(fee('weighbridge'), true);
  assert.equal(fee('Waybridge'), true);
  assert.equal(fee('WEIGH THE VEHICLE'), true);
  assert.equal(fee('Complementary Full Tank of Fuel'), true);
  assert.equal(fee('COMLEIMANTARY FULL TANK OF FUEL'), true);
  assert.equal(fee('fuel tank certification'), true);
  assert.equal(fee('radio quote', 'PITFEE'), false);
  assert.equal(fee('Leaf springs', 'PIT FEE'), true);
  assert.equal(fee('PITS - REFER BRYCE IF REQUIRED'), false);
  assert.equal(fee('ARB Long Range Fuel Tank'), false);
  assert.equal(fee('Certified Mesh Cab Rack Barrier Rated To 60kg With Certification Plate'), false);
  assert.equal(fee('PERTH DELIVERY'), false);
  assert.equal(fee('Brown Davis 87 Litre sub tank'), false);
  assert.equal(fee('SPITWEIGHT'), false);
  assert.equal(fee('TRANSPORT TO PITS'), false);
});

test('r522 migration routes those lines to SUBLET and does not add a station or replace approve', () => {
  const sql = fs.readFileSync(MIG, 'utf8');
  const down = fs.readFileSync(DOWN, 'utf8');
  assert.match(sql, /cdsmnqxtyyoeoznmbidd/);
  assert.match(sql, /pdc_production_environment_sentinel/);
  assert.match(sql, /note_fee_sublet_522/);
  assert.match(sql, /'F136'/);
  assert.match(sql, /sort_order,added_in\) VALUES\n \('note_fee_sublet_522','F136'/);
  assert.match(sql, /,true,306,'r522'\)/);
  assert.match(sql, /information_only',false/);
  assert.match(sql, /Pit Fee for fuel Tank Certification/);
  assert.match(sql, /0028f027-5896-4699-8096-98813c106ca7/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\.approve_pdc_new_vehicle_review\b/);
  assert.doesNotMatch(sql, /INSERT INTO public\.workshop_stages/);
  assert.match(sql, /CREATE FUNCTION pdc_work_categories_private\.note_fee_sublet_522/);
  const helper = sql.split('$r522h$')[1];
  assert.match(helper, /PIT FEES\?/);
  assert.match(helper, /FULL TANK OF FUEL/);
  assert.match(helper, /FUEL TANK CERTIF/);
  assert.doesNotMatch(helper, /po_details/);
  assert.match(down, /DROP FUNCTION pdc_work_categories_private\.note_fee_sublet_522/);
  assert.match(down, /pin count is not 230/);
  assert.match(down, /1e4b22a822531ba2c4b90668e8202c01/);
});
