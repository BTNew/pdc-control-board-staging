'use strict';
// r502 (F115, Craig 23 Oct): Manage sublets Save toast hid unmapped create codes; ^ display; promote; pit/weigh wording.
// Fictional data only; booking service mocked.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vs = require('./pdc-vehicle-sublets.js');

const U = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const KEY = 'vehicle-key-1';
const jobLines = [
  { line_identity: `source:${U(1)}`, operation_no: '96', description: 'Seat covers front and rear', work_category: 'SUBLET', category_version: 1, department: '139' },
  { line_identity: `source:${U(2)}`, operation_no: '64', description: 'Key WEIGH / Licensing', work_category: 'BUS_4X4_QA', category_version: 2, department: '138',
    po_details: [{ po_number: 'GP1', description: 'PIT AND WEIGH^LICENCE' }] },
  { line_identity: `source:${U(3)}`, operation_no: '12', description: 'Reflective stripes', work_category: 'ACCESSORIES', category_version: 0, department: '139',
    po_details: [{ po_number: 'GP2', description: 'STRIPE FRONT^REAR' }] },
];
const pendingRow = { __subletVehicleKey: KEY, __subletOperationKey: `op:${U(1)}`, __subletOperationIdentity: `SOURCE:${U(1).toUpperCase()}`, pmbSubletNotes: 'JC 96 · Seat covers' };
const providers = [{ id: 'p-mmt', name: 'MMT', email: 'mmt@example.invalid', active: true }];

test('VERSION and cache bust r502', () => {
  assert.equal(vs.VERSION, '2026.10.23.r502');
  const index = fs.readFileSync('index.html', 'utf8');
  assert.match(index, /pdc-vehicle-sublets\.js\?[^"']*r502=2026\.10\.23\.r502/);
  assert.match(index, /pdc-vehicle-sublets\.css\?[^"']*r502=2026\.10\.23\.r502/);
  assert.match(index, /pdc-email-vehicle-location-service\.js\?[^"']*r502=2026\.10\.23\.r502/);
});

test('cleanDescription: Revolution ^ becomes ·', () => {
  assert.equal(vs.cleanDescription('FRONT^REAR^^SIDE '), 'FRONT · REAR · SIDE');
  assert.equal(vs.cleanDescription(''), '');
  const list = vs.poList({ po_numbers: ['GP1'], po_details: [{ po_number: 'GP1', description: 'A^B' }] });
  assert.equal(list[0].description, 'A · B');
});

test('isAlwaysSubletWording: pit / weigh / bridge phrases', () => {
  assert.equal(vs.isAlwaysSubletWording('Pit inspection'), true);
  assert.equal(vs.isAlwaysSubletWording('PIT AND WEIGH'), true);
  assert.equal(vs.isAlwaysSubletWording('pit and way'), true);
  assert.equal(vs.isAlwaysSubletWording('Weighbridge cert'), true);
  assert.equal(vs.isAlwaysSubletWording('WAY BRIDGE'), true);
  assert.equal(vs.isAlwaysSubletWording('Seat covers'), false);
});

test('normalizeOperationIdentity lowercases source:/manual: uuid', () => {
  assert.equal(vs.normalizeOperationIdentity(`SOURCE:${U(1).toUpperCase()}`), `source:${U(1)}`);
  assert.equal(vs.normalizeOperationIdentity(U(2)), `source:${U(2)}`);
  assert.equal(vs.normalizeOperationIdentity(`manual:${U(3)}`), `manual:${U(3)}`);
});

test('failText maps auth/unavailable and always shows unmapped codes', () => {
  assert.equal(vs.failText({ code: 'not_authenticated' }), 'Sign in again, then retry.');
  assert.equal(vs.failText({ code: 'session_changed' }), 'Your sign-in changed while saving. Sign in again, then retry.');
  assert.equal(vs.failText({ code: 'sublet_create_unavailable' }), 'Not saved: connection issue. Check the network, refresh, then try again.');
  assert.equal(vs.failText({ code: 'vehicle_not_found' }), 'That vehicle is not on the board. Refresh, then try again.');
  assert.equal(vs.failText({ code: '42501' }), 'Not saved (42501). Refresh and try again.');
  assert.equal(vs.failText({ code: 'PGRST301' }), 'Not saved (PGRST301). Refresh and try again.');
  // Never hide a code behind the old generic-only toast when a code is present.
  assert.notEqual(vs.failText({ code: 'mystery' }), 'Not saved. Refresh and try again.');
  assert.match(vs.failText({ code: 'mystery' }), /mystery/);
});

test('planSave normalises identity and truncates notes', () => {
  const model = vs.buildModel({ jobLines, poLines: [], bookings: [pendingRow] });
  const line = model.whole.find(r => r.operationNo === '96');
  const plan = vs.planSave(line, { providerId: 'p-mmt', out: '2026-10-24', back: '2026-10-24' });
  assert.equal(plan.kind, 'create');
  assert.equal(plan.identity, `source:${U(1)}`);
  assert.ok(plan.notes.length <= 2000);
});

test('screenHtml: promote on item rows; ^ cleaned; pit wording first in others', () => {
  const model = vs.buildModel({
    jobLines,
    poLines: [
      { line_identity: `source:${U(2)}`, po_numbers: ['GP1'], po_details: [{ po_number: 'GP1', description: 'PIT AND WEIGH^LICENCE' }] },
      { line_identity: `source:${U(3)}`, po_numbers: ['GP2'], po_details: [{ po_number: 'GP2', description: 'STRIPE FRONT^REAR' }] },
    ],
    bookings: [pendingRow],
  });
  assert.ok(model.items.some(r => r.operationNo === '12' || r.operationNo === '64'));
  // Pit/weigh wording sorts first among others.
  assert.ok(model.others.length >= 1);
  assert.equal(vs.isAlwaysSubletWording(model.others[0].description) || model.others[0].pos.some(p => vs.isAlwaysSubletWording(p.description)), true);
  const html = vs.screenHtml(model, {
    vehicleId: U(9),
    title: 'T0099',
    perms: { canTick: false, canMove: true, canEmail: true, choices: [{ value: 'ACCESSORIES', label: 'Accessories' }], canBook: true, providers, drafts: {}, messages: {}, busy: '' },
    loading: false,
  });
  assert.match(html, /data-pvs-whole=/);
  assert.match(html, /Whole line sublet/);
  assert.doesNotMatch(html, /\^/);
  assert.match(html, /pvs-clip/);
  assert.match(html, /FRONT · REAR|PIT AND WEIGH · LICENCE/);
});

test('performSave surfaces failText for create failures', async () => {
  const model = vs.buildModel({ jobLines, poLines: [], bookings: [pendingRow] });
  const line = model.whole.find(r => r.operationNo === '96');
  const plan = vs.planSave(line, { providerId: 'p-mmt', out: '2026-10-24', back: '2026-10-24' });
  const r = await vs.performSave(plan, {
    service: { createSubletBooking: async () => ({ ok: false, code: 'not_authenticated' }) },
    vehicle: { id: U(9), version: 1 },
    providerEmail: 'mmt@example.invalid',
  });
  assert.equal(r.ok, false);
  assert.equal(r.code, 'not_authenticated');
  assert.equal(r.message, 'Sign in again, then retry.');
});
