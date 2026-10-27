/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
// r560 (F174): clicking a stock number opens the Vehicle Locations side panel, not the centred vehicle card.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const app = fs.readFileSync('app.js', 'utf8');

const grab = (source, name) => {
  const asyncNeedle = `async function ${name}(`;
  const plainNeedle = `function ${name}(`;
  const i = source.includes(asyncNeedle) ? source.indexOf(asyncNeedle) : source.indexOf(plainNeedle);
  assert.ok(i >= 0, name);
  let depth = 0;
  const j = source.indexOf('{', source.indexOf(')', i));
  for (let k = j; k < source.length; k++) {
    if (source[k] === '{') depth++;
    else if (source[k] === '}') { depth--; if (!depth) return source.slice(i, k + 1); }
  }
  throw new Error(name);
};

function runStockClick(key, rows, { slideout = true } = {}) {
  const calls = { panel: [], modal: [] };
  const ctx = {
    window: slideout ? { PDC_VEHICLE_SLIDEOUT: { open: (id, bucket) => calls.panel.push({ id, bucket }) } } : {},
    app: { selectedStock: '' },
    vehicleLocationsScreenRows: () => rows,
    vehicleKey: row => String(row.stock || row.stock_number || ''),
    incomingBucketForVehicle: () => 'pmb',
    selectedVehicle: stock => rows.find(row => String(row.stock) === String(stock)) || null,
    vehicleLocationActionAllowed: () => true,
    openVehicleModal: stock => { calls.modal.push(stock); return true; },
    sharedNavisionVisibilityConfigured: () => false,
    sharedNavisionLocationAuthorityReady: () => true,
    pdcNotify: () => {},
  };
  vm.createContext(ctx);
  const body = [
    grab(app, 'vehicleLocationsVehicleForSidePanel'),
    grab(app, 'tryOpenVehicleSidePanel'),
    grab(app, 'ensureVehicleOpenableFromBoard'),
    grab(app, 'openVehicleFromStockClick'),
    grab(app, 'openVehicleCardFromVisibleBoard'),
    `return openVehicleFromStockClick('${key}');`,
  ].join('\n');
  return vm.runInContext(`(async () => { ${body} })()`, ctx).then(ok => ({ ok, calls }));
}

test('openVehicleFromStockClick opens the side panel for a board vehicle', async () => {
  const { ok, calls } = await runStockClick('13056870', [{ stock: '13056870', stock_number: '13056870' }]);
  assert.equal(ok, true);
  assert.deepEqual(calls.panel, [{ id: '13056870', bucket: 'pmb' }]);
  assert.deepEqual(calls.modal, []);
});

test('openVehicleCardFromVisibleBoard still opens the vehicle card modal', async () => {
  const calls = { modal: [] };
  const ctx = {
    app: {},
    selectedVehicle: () => ({ stock: '13056870' }),
    vehicleLocationActionAllowed: () => true,
    openVehicleModal: stock => { calls.modal.push(stock); return true; },
    sharedNavisionVisibilityConfigured: () => false,
    pdcNotify: () => {},
  };
  vm.createContext(ctx);
  const ok = await vm.runInContext(`(async () => {
    ${grab(app, 'ensureVehicleOpenableFromBoard')}
    ${grab(app, 'openVehicleCardFromVisibleBoard')}
    return openVehicleCardFromVisibleBoard('13056870');
  })()`, ctx);
  assert.equal(ok, true);
  assert.deepEqual(calls.modal, ['13056870']);
});

test('dashboard and table stock bindings call openVehicleFromStockClick, not openVehicleModal', () => {
  assert.match(app, /void openVehicleFromStockClick\(button\.dataset\.openStock, button\)/);
  assert.doesNotMatch(app.slice(app.indexOf('function renderIncomingDashboardBoardContent'), app.indexOf('function renderIncomingDashboardBoardContent') + 8000), /openVehicleModal\(button\.dataset\.openStock\)/);
  const table = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(table, /openVehicleFromStockClick\(button\.dataset\.openStock, button\)/);
});

test('fault #542 / r560 is in the website regression run and is not an open gap', () => {
  const workflow = fs.readFileSync('.github/workflows/pages-runtime.yml', 'utf8');
  assert.match(workflow, /node --test test_\*\.js/);
  const pending = fs.readFileSync('docs/FAULT_LOG_PENDING.md', 'utf8');
  const open = pending.slice(pending.indexOf('## Open'), pending.indexOf('## Cleared'));
  const cleared = pending.slice(pending.indexOf('## Cleared'));
  assert.equal(open.includes('#542'), false);
  assert.equal(open.includes('r560'), false);
  assert.equal(open.includes('F174'), false);
  assert.match(cleared, /#542 \/ r560 \/ F174/);
  assert.match(cleared, /test_stock_opens_side_panel_560\.js/);
  for (const file of ['app.js', 'pdc-vehicle-locations-table.js']) {
    const text = fs.readFileSync(file, 'utf8');
    let at = 0;
    while ((at = text.indexOf('dataset.openStock', at)) !== -1) {
      const near = text.slice(Math.max(0, at - 220), at + 40);
      assert.equal(near.includes('openVehicleModal('), false, `${file} at ${at}`);
      at += 1;
    }
  }
});

test('the slide-out keeps a More details link to the vehicle card', () => {
  const slide = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  assert.match(slide, /button\.textContent = 'More details'/);
  assert.match(slide, /openVehicleCardFromVisibleBoard\(openStock, button\)/);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /vehicle-slideout=2026\.10\.28\.r588/); // r588 (F202) tick grid; r565 (F179) chip layout stays
  assert.match(entry, /r560 \(F174\): More details/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /r560=2026\.10\.27\.r560/);
});
