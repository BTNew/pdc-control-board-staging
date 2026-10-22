/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r492 (F105): the Sublet provider email draft carries the key number (yard bay), VIN / serial, the sublet work
// and the due-back date, so the agent can find the car (Bhavesh 21 Oct). Still a reviewable mailto draft only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
function extract(name) {
  const start = source.search(new RegExp('(?:async )?function ' + name + '\\('));
  assert.ok(start >= 0, name);
  const rest = source.slice(start); const end = rest.slice(1).search(/\n(?:async )?function /);
  return end < 0 ? rest : rest.slice(0, end + 1);
}
function draft(vehicle, key = '') {
  const audits = [];
  const c = {
    cleanNavisionText: s => String(s || '').trim(), plainDateValue: s => String(s || '').slice(0, 10),
    subletVehicleByKey: () => vehicle, subletProviderContact: () => ({ name: 'Provider One', email: 'one@example.com' }),
    subletProviderEmailValid: () => true, pdcNotify: m => audits.push(['notify', m]),
    displayStockNumber: () => 'S0001', vehicleEmailLines: () => ['Stock number: S0001', 'Vehicle: Test ute'],
    vehicleJobcardNumber: () => 'JC0001', vehicleKeyNumber: () => key, pmbBaySubletProvider: () => 'Provider One',
    recordVehicleAudit: (...a) => audits.push(['audit', ...a]), saveVehicleEdits: (...a) => audits.push(['save', ...a]),
    getCurrentOperatorName: () => 'Tester', nowIsoString: () => '2026-10-23T00:00:00Z',
    window: { location: { href: '' } },
  };
  vm.createContext(c);
  for (const name of ['subletProviderEmailVehicleLines', 'draftSubletProviderEmail']) vm.runInContext(extract(name), c);
  c.draftSubletProviderEmail('k');
  const url = new URL(c.window.location.href);
  return { url, body: url.searchParams.get('body'), audits };
}

test('vehicle in the yard: key number, VIN, sublet work and due back are in the draft', () => {
  const { url, body } = draft({ __emailVehicleServerAuthoritative: true, vin: 'jtest0000000000001', __subletOperationDescription: 'SIGNAGE - DOORS', pmbSubletBookingDate: '2026-10-24', pmbSubletExpectedReturnDate: '2026-10-28', pmbSubletNotes: '' }, '214');
  assert.equal(url.protocol, 'mailto:');
  assert.equal(url.searchParams.get('subject'), 'Sublet booking - S0001');
  assert.match(body, /^Hello Provider One,/);
  assert.match(body, /\nKey number \(yard bay\): 214\n/);
  assert.match(body, /\nVIN \/ serial: JTEST0000000000001\n/);
  assert.match(body, /\nSublet work: SIGNAGE - DOORS\n/);
  assert.match(body, /\nThe vehicle is in our yard at key 214\.\n/);
  assert.match(body, /\nBooking date: 2026-10-24\nDue back: 2026-10-28\n/);
  assert.ok(body.indexOf('Stock number: S0001') < body.indexOf('Key number'), 'existing lines first, order kept');
});

test('not yet in the yard: key shows TBA, no yard sentence, optional lines left out', () => {
  const { body } = draft({ __emailVehicleServerAuthoritative: true, pmbSubletBookingDate: '', pmbSubletExpectedReturnDate: '' }, '');
  assert.match(body, /Key number \(yard bay\): TBA - not yet in our yard/);
  assert.doesNotMatch(body, /in our yard at key|VIN \/ serial|Sublet work:|Due back:/);
  assert.match(body, /Booking date: TBA/);
});

test('draft only: no send, no new server call; cache bust', () => {
  const fn = extract('draftSubletProviderEmail') + extract('subletProviderEmailVehicleLines');
  assert.doesNotMatch(fn, /fetch\(|\.rpc\(|send_mail|sendMail/);
  assert.match(fn, /window\.location\.href = `mailto:/);
  assert.match(index, /app\.js\?[^"]*sublet-email=2026\.10\.23\.r492/);
});
