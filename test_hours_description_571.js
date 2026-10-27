/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

const up = fs.readFileSync('supabase/migrations/20261027235000_r571_hours_description_limit.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027235000_r571_hours_description_limit.down.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const karrathaApp = fs.readFileSync('karratha/app.js', 'utf8');
const faults = fs.readFileSync('docs/REPORTED_FAULTS.md', 'utf8');

test('r573 is the go-live identity and leaves r571 unused', () => {
  assert.match(up, /r573 \(F187\) \/ sort 344\. Go-live\./);
  assert.match(up, /service_card_stack_572/);
  assert.match(up, /parent r572 \/ F186 sort 342 is not applied/);
  assert.doesNotMatch(up, /sort_order=343 OR fault_id='F185'/);
  assert.doesNotMatch(up, /added_in='r571'/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt is not a target/);
  assert.match(up, /sort_order=344 OR fault_id='F187'/);
  assert.match(up, /bay_job_pause_569/);
  assert.match(up, /<>241/);
  assert.match(up, /length\(description\) <= 2000/);
  assert.match(up, /8255bcf5461babcc01714481fcd8cbe0/);
  assert.match(up, /e21c5c8901714498c71b75ea9caaf812/);
  assert.match(up, /78c1833ad4db912bd0f7bf2772ecb548/);
  assert.match(up, /hours_description_fits_573/);
  assert.match(up, /13077205/);
  assert.doesNotMatch(up, /ALTER TABLE karratha135_pdc/);
  assert.doesNotMatch(up, /styles\.css/);
  assert.match(down, /e21c5c8901714498c71b75ea9caaf812/);
  assert.match(down, /length\(description\) <= 180/);
  assert.match(down, /Leave the 2000 limit in place/);
  assert.doesNotMatch(down, /UPDATE public\.vehicles/);
  assert.doesNotMatch(down, /UPDATE public\.pdc_pilbara_service_operations/);
});

test('the screen names a wording that cannot be stored', () => {
  const start = app.indexOf('function vehicleWorkshopHoursBatchError');
  const end = app.indexOf('async function saveVehicleWorkshopLineHoursBatch', start);
  const fn = app.slice(start, end);
  const result = vm.runInNewContext(`${fn}\nvehicleWorkshopHoursBatchError`, {});
  const named = result({
    code: 'hours_description_rejected',
    message: 'The hours were not saved. Job wording on 10 is longer than 2000 characters.',
  });
  assert.match(named, /Job wording on 10/);
  assert.match(result({ code: 'hours_description_rejected' }), /longer than 2000 characters/);
  assert.match(result({ code: 'vehicle_version_conflict' }), /another session/);
  assert.match(app, /between 1 and 2000 characters/);
  assert.match(service, /hours_description_rejected/);
  assert.match(service, /vehicle_workshop_line_adjustments_description_check/);
  assert.match(karrathaApp, /between 1 and 180 characters/);
  assert.doesNotMatch(karrathaApp, /hours_description_rejected/);
});

test('the reported fault names the cause, the fix and the check', () => {
  assert.match(faults, /13077205 hours won't change/);
  assert.match(faults, /180 characters/);
  assert.match(faults, /hours_description_fits_573/);
  assert.match(faults, /34 stocks/);
  assert.match(faults, /r573 \/ F187 \/ sort 344/);
});
