/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r472 (F85): a key tag save from the vehicle card keeps the authenticated snapshot rows raw, so the card stays bound to
// its exact UUID + Stock and never re-reads the whole board behind "Refreshing exact vehicle identity…".
// Synthetic data only (no stock number, vehicle id, customer or job card in Git).
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const key = require('./pdc-key-number.js');
const service = require('./pdc-email-vehicle-location-service.js');
const identity = require('./vehicle-modal-identity.js');
const V = '11111111-2222-4333-8444-555555555555';
const BOARD_ID = 'TUNE/SYN:S-SYN-1'; // the board key a Tune / PMG vehicle carries (permanent_vehicle_id)
const STOCK = 'S-SYN-1';
const rawRow = () => ({ id: V, permanent_vehicle_id: BOARD_ID, stock_number: STOCK, version: 20, key_number: null, current_location: 'PMB', customer_name: 'Synthetic' });
const APP = fs.readFileSync('app.js', 'utf8');
const fn = name => { const start = APP.indexOf(`\nfunction ${name}(`); assert.ok(start > 0, `${name} in app.js`); const end = APP.indexOf('\n}\n', start); return APP.slice(start, end + 3); };
const NAMES = ['authoritativeSalespersonCode', 'authoritativeReceiptData', 'applyAuthoritativeVehicleReceipt', 'authoritativeVehicleReadbackStatus',
  'authoritativeVehicleReceiptExpectation', 'authoritativeVehicleRawOverlay', 'applyAuthoritativeVehicleReceiptToState', 'applyAuthoritativeVehicleReadbackRow'];
const receipt = { ok: true, code: 'vehicle_detail_updated', data: { vehicle_id: V, vehicle_version_after: 21, receipt_id: 'r-1', request_sha256: 'a'.repeat(64) } };

function page({ withR472 = true, reconcileImpl } = {}) {
  const notes = []; let renders = 0;
  const ctx = { console, setTimeout, setInterval: () => 0, crypto: { randomUUID: () => 'u' }, PDC_EMAIL_VEHICLE_LOCATION_SERVICE: service,
    document: { head: { appendChild() {} }, createElement: () => ({}), addEventListener() {}, querySelectorAll: () => [], querySelector: sel => (sel === '#vehicle-modal' ? { hidden: false } : null), visibilityState: 'visible' },
    fetch: async () => ({ ok: true, text: async () => '{"ok":false}' }) };
  ctx.window = ctx;
  ctx.window.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' };
  ctx.window.__pdcCachedAccessToken = 'jwt';
  ctx.pdcNotify = message => notes.push(message);
  ctx.renderDetail = () => { renders += 1; };
  vm.createContext(ctx);
  vm.runInContext(`var app = { data: [], emailVehicleLocationRows: [], emailVehicleReceiptOverlays: new Map() };
    ${NAMES.map(fn).join('\n')}
    function applyPendingSharedWorkStateOverlays(rows) { return rows; }
    var reconcileAuthoritativeVehicleReceipt = ${reconcileImpl || 'async () => ({ status: "matching", vehicle: {} })'};`, ctx);
  ctx.app = vm.runInContext('app', ctx);
  ctx.app.emailVehicleLocationRows = [rawRow(), { ...rawRow(), id: '99999999-2222-4333-8444-555555555555', permanent_vehicle_id: 'TUNE/SYN:OTHER', stock_number: 'S-SYN-2' }];
  const card = { ...service.mapServerVehicle(rawRow()), __emailVehicleServerAuthoritative: true };
  ctx.app.data = [card];
  if (withR472) vm.runInContext(fs.readFileSync('pdc-key-number.js', 'utf8'), ctx);
  return { ctx, card, notes, renders: () => renders };
}
const bound = rows => {
  const exact = identity.resolveExactAuthoritativeVehicleRow(rows, { canonicalId: V, stockBaseline: STOCK });
  return { code: exact.code, mappedId: exact.ok ? service.mapServerVehicle(exact.row).__emailVehicleId : '' };
};

test('the card vehicle carries the board key as id (why the old merge broke the raw row)', () => {
  const card = service.mapServerVehicle(rawRow());
  assert.equal(card.id, BOARD_ID);
  assert.equal(card.__emailVehicleId, V);
});

test('before r472: the receipt merge overwrote the raw row id, so the card lost its exact UUID row (fault reproduced)', () => {
  const { ctx, card } = page({ withR472: false });
  vm.runInContext('applyAuthoritativeVehicleReceiptToState', ctx)(card, receipt, '', { key_number: '12347' });
  const row = ctx.app.emailVehicleLocationRows.find(r => r.stock_number === STOCK);
  assert.equal(row.id, BOARD_ID);
  assert.notEqual(bound(ctx.app.emailVehicleLocationRows).mappedId, V);
});

test('r472 receipt: the exact UUID raw row keeps its raw fields and takes only the receipt values', () => {
  const { ctx, card } = page();
  const out = vm.runInContext('applyAuthoritativeVehicleReceiptToState', ctx)(card, receipt, '', { key_number: '12347' });
  assert.ok(out && out.patched.keyNumber === '12347');
  const rows = ctx.app.emailVehicleLocationRows;
  const row = rows.find(r => r.stock_number === STOCK);
  assert.equal(row.id, V);
  assert.equal(row.permanent_vehicle_id, BOARD_ID);
  assert.equal(row.key_number, '12347');
  assert.equal(row.version, 21);
  assert.equal(row.keyNumber, undefined, 'no card (camelCase) fields mixed into the raw row');
  assert.deepEqual(bound(rows), { code: 'exact_match', mappedId: V });
  assert.equal(JSON.stringify(rows[1]), JSON.stringify({ ...rawRow(), id: '99999999-2222-4333-8444-555555555555', permanent_vehicle_id: 'TUNE/SYN:OTHER', stock_number: "S-SYN-2" }), "other vehicles untouched");
  assert.equal(ctx.app.data[0].keyNumber, '12347', 'the board row still shows the new key straight away');
  assert.ok(ctx.app.emailVehicleReceiptOverlays.has(V), 'the pending overlay is still kept until the read-back matches');
});

test('r472 read-back: the exact UUID row becomes the server row; identity still exact', () => {
  const { ctx } = page();
  const server = { ...rawRow(), version: 21, key_number: '12347' };
  const mapped = vm.runInContext('applyAuthoritativeVehicleReadbackRow', ctx)(server);
  assert.equal(mapped.__emailVehicleId, V);
  const row = ctx.app.emailVehicleLocationRows.find(r => r.stock_number === STOCK);
  assert.equal(JSON.stringify(row), JSON.stringify(server));
  assert.deepEqual(bound(ctx.app.emailVehicleLocationRows), { code: 'exact_match', mappedId: V });
});

test('r472 identity safety unchanged: a wrong-Stock or duplicate UUID row still refuses to bind', () => {
  const rows = key.rawRowsAfterReceipt([rawRow(), { ...rawRow(), stock_number: 'S-OTHER' }], V, { id: V, version: 21, key_number: '1' });
  assert.equal(identity.resolveExactAuthoritativeVehicleRow(rows, { canonicalId: V, stockBaseline: STOCK }).code, 'conflicting_stock');
  assert.equal(key.rawRowsAfterReceipt([rawRow()], 'not-a-uuid', {}), null);
  assert.equal(key.rawRowsAfterReadback([rawRow()], { id: BOARD_ID }), null);
});

test('r472 key-only save: the read-back runs behind the card (pending at once); other saves still wait for it', async () => {
  let calls = 0;
  const { ctx, card, notes } = page({ reconcileImpl: 'async () => { globalThis.__calls = (globalThis.__calls || 0) + 1; return { status: "matching", vehicle: {} }; }' });
  const reconcile = vm.runInContext('reconcileAuthoritativeVehicleReceipt', ctx);
  const fast = await reconcile(receipt, card, '', { key_number: '12347' });
  assert.equal(fast.status, 'pending');
  assert.equal(fast.vehicle, card);
  await new Promise(r => setImmediate(r));
  calls = vm.runInContext('globalThis.__calls', ctx);
  assert.equal(calls, 1, 'the read-back still runs');
  const slow = await reconcile(receipt, card, 'SP', { key_number: '12347' });
  assert.equal(slow.status, 'matching', 'a salesperson change still waits for its read-back');
  assert.equal((await reconcile(receipt, card, '', { key_number: '1', client_name: 'x' })).status, 'matching');
  assert.equal(notes.length, 0);
  assert.equal(key.keyOnlySave('', { key_number: '1' }), true);
  assert.equal(key.keyOnlySave('', { job_card_number: '1' }), false);
  assert.equal(key.keyOnlySave(' ', {}), false);
});

test('r472 key-only save: a contradicting read-back still tells the person and redraws the card', async () => {
  const { ctx, card, notes, renders } = page({ reconcileImpl: 'async () => ({ status: "contradictory", vehicle: {} })' });
  const out = await vm.runInContext('reconcileAuthoritativeVehicleReceipt', ctx)(receipt, card, '', { key_number: '12347' });
  assert.equal(out.status, 'pending');
  for (let i = 0; i < 4; i += 1) await new Promise(r => setImmediate(r));
  assert.equal(notes.length, 1);
  assert.match(notes[0], /did not read back as saved/);
  assert.equal(renders(), 1);
});

test('the wrapped app.js functions still exist with these names (locked file, read only)', () => {
  for (const name of [...NAMES, 'reconcileAuthoritativeVehicleReceipt', 'saveAuthoritativeVehicleChanges']) assert.match(APP, new RegExp(`\\n(async )?function ${name}\\(`));
  assert.match(fn('applyAuthoritativeVehicleReceiptToState'), /app\.emailVehicleLocationRows = /);
  assert.match(APP, /const readback = await reconcileAuthoritativeVehicleReceipt\(result, applied\.patched, '', detailChanges\);/);
});

test('loader: pdc-key-number.js cache-busted r472; index.html cache-busts canonical-entry.js', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /keyNumber\.src = 'pdc-key-number\.js\?key-number=2026\.10\.22\.r460&r472=2026\.10\.22\.r472&r490=2026\.10\.23\.r490&r575=2026\.10\.27\.r575(&r616=2026\.10\.28\.r616)?';/); // r490 (F103) and r575 (F189) append their own tags
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*&amp;r472=2026\.10\.22\.r472&amp;/);
  assert.equal(key.R472, '2026.10.22.r472');
});
