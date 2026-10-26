/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r540 (F154): a Workshop Planner chip double-click opens the Vehicle Locations side panel.
// The centred station job modal is not drawn. Department 135 keeps that modal.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const grab = name => {
  const i = planner.indexOf(`function ${name}(`);
  assert.ok(i >= 0, name);
  let depth = 0;
  const j = planner.indexOf('{', planner.indexOf(')', i));
  for (let k = j; k < planner.length; k++) {
    if (planner[k] === '{') depth++;
    else if (planner[k] === '}') { depth--; if (!depth) return planner.slice(i, k + 1); }
  }
  throw new Error(name);
};

function run(key, rows) {
  const calls = { opened: [], notes: [] };
  const ctx = {
    window: { PDC_VEHICLE_SLIDEOUT: { open: (id, bucket) => calls.opened.push({ id, bucket }) } },
    document: { querySelector: () => null, body: { classList: { remove() {} } } },
    vehicleLocationsScreenRows: () => rows,
    vehicleKey: row => String(row.stock || row.id || ''),
    incomingBucketForVehicle: () => 'pmb',
    workshopNotify: message => calls.notes.push(message),
  };
  vm.createContext(ctx);
  vm.runInContext([grab('workshopLocationsVehicle'), grab('openWorkshopVehicleJob')].join('\n'), ctx);
  const opened = ctx.openWorkshopVehicleJob(key, 'FITTING', 'plan-248');
  return { calls, opened };
}

test('a planner chip opens the locations panel for the same stock key', () => {
  const result = run('13047270', [{ stock: '13047270', stock_number: '13047270' }]);
  assert.equal(result.opened, true);
  assert.deepEqual(result.calls.opened, [{ id: '13047270', bucket: 'pmb' }]);
  assert.equal(result.calls.notes.length, 0);
  const dbl = planner.slice(planner.indexOf("addEventListener('dblclick'"), planner.indexOf("addEventListener('dblclick'") + 400);
  assert.match(dbl, /openWorkshopVehicleJob/);
  assert.match(planner, /double-click to open the vehicle/);
  assert.doesNotMatch(grab('openWorkshopVehicleJob'), /workshop-job-card|Fitting vehicle job|data-workshop-job-overlay =/);
});

test('a vehicle that is not on Vehicle Locations is named, and the modal is not drawn', () => {
  const result = run('missing', []);
  assert.equal(result.opened, false);
  assert.deepEqual(result.calls.opened, []);
  assert.match(result.calls.notes[0], /not on Vehicle Locations/);
});

test('the drawer still has Open Vehicle, Manage sublets, station groups and Edit', () => {
  const slide = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  const sublets = fs.readFileSync('pdc-vehicle-sublets.js', 'utf8');
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(slide, /button\.textContent = 'Open Vehicle'/);
  assert.match(slide, /data-vso-edit-toggle>Edit</);
  assert.match(sublets, /button\.textContent = 'Manage sublets'/);
  assert.match(sublets, /\.vso-open-row/);
  assert.match(app, /authenticated-operation-station-grid/);
  assert.match(app, /totalHoursLabel/);
  // Team notes are not in the drawer. They stay on the vehicle card opened by Open Vehicle.
  assert.doesNotMatch(slide, /Team notes/);
  assert.match(app, /<form class="notes-form" data-notes-form>/);
  assert.match(app, /<div class="muted-label">Team notes<\/div>/);
});

test('Department 135 keeps the centred job modal and is not cache-busted', () => {
  const frozen = fs.readFileSync('karratha/workshop-planner.js', 'utf8');
  assert.match(frozen, /workshop-job-overlay/);
  assert.match(frozen, /vehicle job/);
  assert.doesNotMatch(frozen, /r540/);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('r540=2026.10.26.r540'), false);
  const root = fs.readFileSync('app.js', 'utf8');
  assert.equal(root.split('r540=2026.10.26.r540').length - 1, 2);
});
