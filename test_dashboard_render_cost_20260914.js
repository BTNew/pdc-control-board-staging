'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');

test('a direct dashboard redraw reads each saved note once and partitions locations once', () => {
  const f = createFixture();
  f.context.renderIncomingDashboardBoard();
  assert.equal(f.stats.reads, 102);
  assert.ok([...f.stats.keys.values()].every(count => count === 1));
  assert.equal(f.stats.classifications, 3 * f.rows.length); // screen eligibility, active filters, bucket grouping
  assert.match(f.host.innerHTML, /13070000/);
  assert.match(f.host.innerHTML, /13070101/);
  assert.match(f.host.innerHTML, /incoming-pmb/);
  assert.match(f.host.innerHTML, /incoming-yardhold/);
  assert.match(f.host.innerHTML, /incoming-transit/);
  assert.equal(f.evaluate('activeRenderJsonCache'), null);
});

test('later renders see fresh saved notes and writes invalidate the current synchronous render', () => {
  const f = createFixture({ vehicleCount: 3 });
  let loaded;
  f.context.renderIncomingDashboardBoardContent = () => {
    loaded = f.context.getNotes('13070000');
    assert.strictEqual(f.context.getNotes('13070000'), loaded);
  };
  f.context.renderIncomingDashboardBoard();
  assert.deepEqual(Array.from(loaded), []);
  f.storage.set('vehicleTrackingCoreNotes:13070000', JSON.stringify(['Saved after first render']));
  f.context.renderIncomingDashboardBoard();
  assert.deepEqual(Array.from(loaded), ['Saved after first render']);
  f.context.renderIncomingDashboardBoardContent = () => {
    f.context.getNotes('13070000');
    f.context.setNotes('13070000', ['Saved inside current render']);
    assert.deepEqual(Array.from(f.context.getNotes('13070000')), ['Saved inside current render']);
  };
  f.context.renderIncomingDashboardBoard();
  assert.equal(f.evaluate('activeRenderJsonCache'), null);
});

test('a failed or nested dashboard render releases its cache and preserves its parent render', () => {
  const f = createFixture({ vehicleCount: 0 });
  f.context.renderIncomingDashboardBoardContent = () => { f.context.getNotes('test'); throw Error('fixture render failure'); };
  assert.throws(() => f.context.renderIncomingDashboardBoard(), /fixture render failure/);
  assert.equal(f.evaluate('activeRenderJsonCache'), null);
  f.evaluate("activeRenderJsonCache = new Map([['outer', 'retained']])");
  const outer = f.evaluate('activeRenderJsonCache');
  assert.throws(() => f.context.renderIncomingDashboardBoard(), /fixture render failure/);
  assert.strictEqual(f.evaluate('activeRenderJsonCache'), outer);
  assert.equal(outer.get('outer'), 'retained');
});

test('startup helpers leave unrelated routes untouched and install controls for later navigation', () => {
  for (const route of ['qc', 'workshop', 'newvehicles', 'sublet', 'parts', 'workflow']) {
    const f = createFixture({ vehicleCount: 3 });
    f.context.app.currentView = route;
    f.context.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd' };
    f.context.renderAll = () => { throw Error('unrelated route redrawn'); };
    f.loadHelper('pdc-book-all-stations.js');
    f.loadHelper('pdc-rft-actions.js');
    assert.equal(f.stats.renders, 0, route);
    assert.equal(f.host.innerHTML, '', route);
    assert.equal(typeof f.context.PDC_BOOK_ALL_STATIONS.actionHtml, 'function');
    assert.equal(f.context.PDC_RFT_ACTIONS_VERSION, '2026.09.10.04');
    f.context.app.currentView = 'dashboard';
    f.context.renderIncomingDashboardBoard();
    assert.match(f.host.innerHTML, /13070000/);
  }
});

test('helper startup still refreshes the dashboard and RFT pages that display its controls', () => {
  for (const route of ['dashboard', 'rft', 'collected']) {
    const f = createFixture({ vehicleCount: 0 });
    f.context.app.currentView = route;
    f.context.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd' };
    let activeRenders = 0;
    f.context.renderAll = () => { activeRenders++; };
    f.loadHelper('pdc-book-all-stations.js');
    f.loadHelper('pdc-rft-actions.js');
    assert.equal(f.stats.renders, route === 'dashboard' ? 1 : 0, route);
    assert.equal(activeRenders, 1, route);
  }
});
