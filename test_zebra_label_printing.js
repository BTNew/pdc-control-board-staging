'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const indexSource = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const qzSource = fs.readFileSync(path.join(root, 'vendor', 'qz', 'qz-tray.js'), 'utf8');

assert.match(qzSource, /@version 2\.2\.6/, 'The bundled QZ Tray connector should be version 2.2.6');
assert.ok(indexSource.indexOf('vendor/qz/qz-tray.js?v=2.2.6') < indexSource.indexOf('app.js?v='), 'QZ Tray must load before app.js');
assert.ok((indexSource.match(/data-print-selected-zpl/g) || []).length >= 2, 'Vehicle Locations and tracker selections should expose Print Labels while Control Board remains a read-only work overview');
assert.ok(indexSource.includes('id="zpl-print"'), 'The hidden/admin ZPL troubleshooting screen should keep a QZ print button');
assert.ok(appSource.includes('data-label-vehicle='), 'Vehicle rows and the vehicle detail card should expose a Label action');
assert.ok(appSource.includes("on($('#autocare-zpl-all'), 'click', () => printZplFromAutocareResults('all'))"), 'The top Autocare label action should print directly through QZ Tray');
assert.ok(appSource.includes('Print one Zebra label for each vehicle now?'), 'A successful Autocare scan should offer the approved single label immediately');
assert.ok(appSource.includes('const arrival = autocarePmbArrivalUpdates(match.vehicle, updatedAt)') && appSource.includes('...arrival.updates'), 'AutoCare matches should apply the PMB-arrival updates');
assert.ok(appSource.includes('migrateLegacyAutocareArrivalsToPmb();'), 'Previously scanned AutoCare vehicles should be migrated on startup');
assert.ok(appSource.includes('button.hidden = count === 0'), 'Print Labels should stay hidden until one or more rows are selected');
assert.ok(appSource.includes('copies: 1') && appSource.includes('scaleContent: false') && appSource.includes("'^PQ1'"), 'QZ should send one raw job containing the approved single-copy ZPL');

const storage = new Map();
const context = {
  console,
  window: {
    VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} },
    alert() {},
    confirm: () => true,
    addEventListener() {},
    requestAnimationFrame: callback => callback(),
    setTimeout,
  },
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: key => storage.delete(key),
    clear: () => storage.clear(),
    key: index => Array.from(storage.keys())[index] || null,
    get length() { return storage.size; },
  },
  document: {
    readyState: 'loading',
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener() {},
    body: { classList: { add() {}, remove() {}, toggle() {} }, appendChild() {} },
    createElement: () => ({
      dataset: {}, style: {}, classList: { add() {}, remove() {}, toggle() {} },
      setAttribute() {}, appendChild() {}, addEventListener() {}, remove() {}, click() {},
      querySelector: () => null, querySelectorAll: () => [],
    }),
  },
  navigator: {},
  FileReader: function FileReader() {},
  Blob: function Blob() {},
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL() {} },
  Intl, Date, Map, Set, JSON, String, Number, Boolean, Array, Object, RegExp, Math, Error, Promise,
  setTimeout, clearTimeout,
};
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(appSource, context, { filename: 'app.js' });

const header = ['Batch', 'Customer Surname', 'Dealer Customer Name', 'Model Description', 'Suffix Description', 'Trim Description', 'Colour Description', 'WMI', 'VDS Number', 'Frame'].join('\t');
const row = ['12^654~321', '', 'Broome   Toyota', 'Hilux DCC', 'SR5 48V', 'Black Fabric', 'Glacier White', 'MR0', 'BA3FS2', '01361094'].join('\t');
const parsed = context.parseZplInput(`${header}\n${row}`);
assert.strictEqual(parsed.vehicles.length, 1, 'One pasted vehicle should create one ZPL block');
assert.strictEqual(parsed.warnings.length, 0, 'A complete 17-character VIN should not warn');
assert.deepStrictEqual(JSON.parse(JSON.stringify(parsed.vehicles[0])), {
  batch: '12654321',
  customer: 'Broome Toyota',
  model: 'Hilux DCC',
  specLine: 'SR5 48V Black Fabric Glacier White',
  vin: 'MR0BA3FS201361094',
  row: 2,
});

const zpl = context.vehicleToZplBlock(parsed.vehicles[0]);
for (const command of [
  '^PW540', '^LL360', '^LH0,0', '^CI28',
  '^FO18,12^A0N,62,62^FB504,1,0,L,0^FD12654321^FS',
  '^FO18,82^A0N,28,28^FB504,1,0,L,0^FDSTOCK —^FS',
  '^FO18,116^A0N,25,25^FB504,1,0,L,0^FDJOB CARD —^FS',
  '^FO18,150^A0N,27,27^FB504,2,2,L,0^FDBroome Toyota^FS',
  '^FO18,210^A0N,25,25^FB504,2,2,L,0^FDHilux DCC^FS',
  '^FO18,276^A0N,23,23^FB504,1,0,L,0^FDSALES —^FS',
  '^FO18,308^A0N,22,22^FB504,1,0,L,0^FDPDC^FS',
  '^PQ1',
]) {
  assert.ok(zpl.includes(command), `ZPL is missing ${command}`);
}
assert.ok(!zpl.includes('~'), 'Cleaned fields must not contain ~');
assert.strictEqual(context.cleanZplField('  Broome^\n~Toyota\t '), 'Broome Toyota', 'ZPL field cleaning should strip control characters and collapse whitespace');

const shortVin = context.parseZplInput(`${header}\n${['12345678', 'Smith', '', 'Hilux', '', '', '', 'MR0', 'BA3FS2', '01'].join('\t')}`);
assert.ok(shortVin.warnings.some(warning => warning.includes('VIN is 11 characters')), 'An incomplete VIN should warn with its actual length');
const missingParts = context.parseZplInput(`${header}\n${['12345678', 'Smith', '', 'Hilux', '', '', '', 'MR0', '', ''].join('\t')}`);
assert.ok(missingParts.warnings.some(warning => warning.includes('missing VDS Number and Frame')), 'Missing VIN components should be named before printing');
const autocareRow = context.autocareItemToZplRow({
  batch: 'AC123', vin: 'MR0BA3FS201361094', modelDescription: 'Hilux', versionDescription: 'SR5 48V', colour: 'Glacier White',
}, '').split('\t');
assert.strictEqual(autocareRow[1], '', 'A blank Autocare customer should fall through to (Dealer Order) during parsing');
assert.strictEqual(autocareRow[3], 'Hilux', 'Autocare Model should map to the model line');
assert.strictEqual(autocareRow[4], 'SR5 48V', 'Autocare Version should map to the spec line');
assert.strictEqual(autocareRow[6], '', 'Autocare-only labels should use Version as the complete spec line');

const arrivedAt = '2026-07-13T08:30:00.000Z';
const backendArrival = context.autocarePmbArrivalUpdates({
  stock: '12345678', batch: '12345678', toyotaStatus: 'In Transit to WA', pdcSheetVisible: false,
}, arrivedAt);
assert.strictEqual(backendArrival.updates.pdcSheetVisible, true, 'An AutoCare match should activate a back-end vehicle');
assert.strictEqual(backendArrival.updates.pdcLocation, 'PMB', 'An AutoCare match should arrive at PMB');
assert.strictEqual(backendArrival.updates.pmbStage, '', 'A newly arrived AutoCare vehicle should land in Unallocated');
assert.strictEqual(backendArrival.updates.pdcLocationLocked, true, 'A later Navision import must not move an AutoCare arrival backwards');
assert.strictEqual(backendArrival.updates.pmbEnteredAt, arrivedAt, 'AutoCare scanning should start PMB age at arrival');

const existingPmbArrival = context.autocarePmbArrivalUpdates({
  stock: '22345678', pdcLocation: 'PMB', pmbStage: 'TINT', pmbEnteredAt: '2026-07-12T01:00:00.000Z',
}, arrivedAt);
assert.ok(!Object.prototype.hasOwnProperty.call(existingPmbArrival.updates, 'pmbStage'), 'A repeat notice must not reset an existing PMB work bucket');
assert.strictEqual(existingPmbArrival.updates.pmbEnteredAt, '2026-07-12T01:00:00.000Z', 'A repeat notice must preserve the original PMB arrival time');

const rftArrival = context.autocarePmbArrivalUpdates({ stock: '32345678', pdcLocation: 'RFT' }, arrivedAt);
assert.ok(!Object.prototype.hasOwnProperty.call(rftArrival.updates, 'pdcLocation'), 'A late AutoCare notice must not move RFT backwards to PMB');
assert.match(rftArrival.arrivalNote, /RFT location retained/, 'The protected RFT outcome should be explained');

(async () => {
  context.qz = context.window.qz = {
    websocket: { isActive: () => true, connect: async () => {} },
    printers: { find: async () => ['Office PDF', 'dc-01\\BT-Zebra-EricComp'] },
    configs: { create: () => ({}) },
    print: async () => {},
  };
  assert.strictEqual(await context.findZebraPrinterName(), 'dc-01\\BT-Zebra-EricComp', 'The configured Zebra printer should be preferred');
  context.qz.printers.find = async () => ['ZDesigner ZD421'];
  storage.clear();
  assert.strictEqual(await context.findZebraPrinterName(), 'ZDesigner ZD421', 'The first available Zebra printer should be the fallback');
  context.qz.printers.find = async () => ['Office PDF'];
  storage.clear();
  await assert.rejects(() => context.findZebraPrinterName(), /Zebra printer not found/, 'A non-Zebra-only printer list must not be used silently');
  console.log('Zebra label printing checks passed');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
