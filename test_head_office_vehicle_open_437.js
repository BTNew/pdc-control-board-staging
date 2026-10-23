/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r437 (F48): the vehicle card refused to open for Navision vehicles whose Dealer column is a
// Toyota head office account code (001234 / 002345), showing "The exact vehicle identity is
// unavailable..." on every click. The open guard only accepted dealer codes 14450 / 37047.
// These vehicles now bind to the board's own dealer read scope (the Workshop detail rule from
// #351); every other unknown code, local row, conflict or missing UUID stays blocked.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const slice = (from, to) => { const a = source.indexOf(from); const b = source.indexOf(to, a); assert.ok(a >= 0 && b > a, `slice ${from}`); return source.slice(a, b); };
const dealerHelpers = slice('const PDC_HEAD_OFFICE_ACCOUNT_CODES', 'function vehicleModalCanOpenWithoutDealer(');
const applyHelper = slice('function vehicleModalApplyDealerIdentity(', 'function exactAuthoritativeVehicleSnapshotRow(');
const gate = slice('function openVehicleModal(', "  app.vehicleDetailPage = 'details';") + '\n  return true;\n}';
const MESSAGE = 'The exact vehicle identity is unavailable. Refresh the list and try again. No vehicle was changed.';
const UUID = '22222222-2222-4222-8222-222222222222';

function harness(vehicle, boardDealer = '14450') {
  const toasts = [];
  const context = {
    app: {}, window: { PDC_SUPABASE_CONFIG: boardDealer == null ? undefined : { dealerCode: boardDealer } },
    selectedVehicle: () => vehicle, vehicleLocationActionAllowed: () => true, $: () => ({}), rememberModalReturnFocus() {},
    vehicleKey: v => v.stock, vehicleWorkshopDetailCanonicalId: v => v.__emailVehicleId || '', vehicleModalIdentityStock: v => v.stock || '',
    cleanNavisionText: v => String(v || '').trim(), vehicleModalCanOpenWithoutDealer: () => false, pdcNotify: m => toasts.push(m),
  };
  vm.createContext(context);
  vm.runInContext(`${dealerHelpers}\n${applyHelper}\n${gate}\nthis.__api = { openVehicleModal, vehicleModalDealerIdentity, vehicleModalApplyDealerIdentity };`, context);
  return { context, toasts, api: context.__api };
}
const row = patch => ({ stock: '70000002', __emailVehicleId: UUID, __emailVehicleServerAuthoritative: true, ...patch });
const opens = (vehicle, boardDealer) => { const h = harness(vehicle, boardDealer); const ok = h.api.openVehicleModal(vehicle.stock); return { ok, toasts: h.toasts, identity: h.context.app.vehicleModalIdentity }; };

test('head office account vehicles (001234, 002345) open under the board dealer scope with no toast', () => {
  for (const code of ['001234', '002345']) {
    const r = opens(row({ __sharedNavisionDealerCode: code }));
    assert.equal(r.ok, true, code);
    assert.deepEqual(r.toasts, []);
    assert.equal(r.identity.dealerCode, '14450');
    assert.equal(r.identity.canonicalId, UUID);
  }
  assert.equal(opens(row({ __sharedNavisionDealerCode: '001234' }), '37047').identity.dealerCode, '37047', 'Broome board scope');
});

test('dealer vehicles 14450 / 37047 are unchanged', () => {
  assert.equal(opens(row({ __sharedNavisionDealerCode: '14450' })).identity.dealerCode, '14450');
  assert.equal(opens(row({ dealer_code: '37047' })).identity.dealerCode, '37047');
});

test('everything else stays blocked with the same message', () => {
  const blocked = [
    ['unknown code', row({ __sharedNavisionDealerCode: 'unrecognised' })],
    ['no dealer, Navision', row({})],
    ['local (not server-authoritative) head office row', row({ __sharedNavisionDealerCode: '001234', __emailVehicleServerAuthoritative: false })],
    ['identity conflict', row({ __sharedNavisionDealerCode: '001234', __emailVehicleIdentityConflict: true })],
    ['no canonical UUID', row({ __sharedNavisionDealerCode: '001234', __emailVehicleId: 'shared-navision-x' })],
    ['no stock', row({ __sharedNavisionDealerCode: '001234', stock: '' })],
  ];
  for (const [name, vehicle] of blocked) {
    const r = opens(vehicle);
    assert.equal(r.ok, false, name);
    assert.deepEqual(r.toasts, [MESSAGE], name);
    assert.equal(r.identity, null, name);
  }
  for (const board of [null, '', '001234', '99999']) {
    const r = opens(row({ __sharedNavisionDealerCode: '001234' }), board);
    assert.equal(r.ok, false, `board scope ${board}`);
  }
});

test('binding keeps the head office code and never relabels or cross-binds', () => {
  const { api } = harness(row({}));
  const bound = { canonicalId: UUID, stockBaseline: '70000002', dealerCode: '14450' };
  assert.equal(api.vehicleModalApplyDealerIdentity(row({ __sharedNavisionDealerCode: '001234' }), bound).__sharedNavisionDealerCode, '001234');
  assert.equal(api.vehicleModalApplyDealerIdentity(row({}), bound).__sharedNavisionDealerCode, '14450', 'server row with no dealer still takes the bound scope');
  assert.equal(api.vehicleModalApplyDealerIdentity(row({ __sharedNavisionDealerCode: '37047' }), bound), null, 'other dealer still refused');
  assert.equal(api.vehicleModalApplyDealerIdentity(row({ __sharedNavisionDealerCode: '001234' }), { ...bound, dealerCode: '001234' }), null, 'head office is never a bound dealer');
  assert.equal(api.vehicleModalApplyDealerIdentity(row({ __sharedNavisionDealerCode: '001234' }), { ...bound, dealerCode: '37047' }), null, 'only the board scope accepts head office rows');
});

test('workshop detail and the card agree on head office scope; cache bust present', () => {
  assert.match(source, /function vehicleWorkshopDetailRequestDealerCode[\s\S]{0,900}config\.dealerCode === '14450' \? '14450' : ''/);
  assert.equal(source.split(MESSAGE).length - 1, 1, 'message still raised in one place');
  const index = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  // r510 (F123): allow later cache params after r437. r510 appended &r510=… on the same app.js tag.
  assert.match(index, /app\.js\?[^"]*&amp;r437=2026\.10\.21\.01(?:&amp;[^"]*)?"/);
});
