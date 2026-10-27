/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r473 (F86, Craig 22 Oct 2026): Vehicle Locations slide-out panel top. Synthetic data only.
//  1. No station-icon strip and no PMB status / PMB stream / Book all stations box at the top of the open panel.
//  2. An "Open Vehicle" button under the stock / key / JC line opens the vehicle card; the stock number is plain text.
//  3. When the vehicle card closes, the open panel and the table are drawn again (nothing the card drew stays on top).
//  4. Nothing else changes: details, Key Edit / History, operations, Edit jobs & hours; parity helper keeps the strip.
// The browser run (1366 px, read-only staging snapshot, customer names blanked) is in the release log, outside Git.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const slideout = require('./pdc-vehicle-slideout.js');
const SRC = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
const CODE = SRC.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
const CSS = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8');

test('1. the open panel hides its summary row (station strip, PMB status / stream, Book all stations); the parity copy keeps it', () => {
  assert.match(CODE, /const summary = card\.querySelector\(':scope > summary'\);\s*if \(summary\) \{ summary\.replaceChildren\(\); summary\.hidden = true; summary\.classList\.add\('vso-summary-removed'\); \}/);
  assert.match(CSS, /#vso-shell \.vso-panel \.vso-card > summary\.vso-summary-removed \{ display: none !important; \}/);
  // parityStrip draws the untouched card off-screen, so PDC_VEHICLE_LOCATIONS_TABLE.parity() still compares every strip.
  const parity = /function parityStrip\([\s\S]*?\n {2}\}/.exec(CODE)[0];
  assert.doesNotMatch(parity, /summary|replaceChildren|vso-summary-removed/);
  assert.match(parity, /\.vso-card \.pdc-station-strip/);
});

test('2. Open Vehicle button under the header line opens the card; no clickable stock number is left in the panel', () => {
  assert.match(CODE, /<div class="vso-open-row"><\/div><\/div>/, 'the button row sits inside the stock / key / JC block');
  assert.doesNotMatch(CODE, /vso-open-slot|cloneNode/, 'the old top-right stock link copy is gone');
  assert.match(CODE, /button\.textContent = 'More details';/);
  assert.match(CODE, /button\.addEventListener\('click', event => \{ event\.stopPropagation\(\); root\.openVehicleCardFromVisibleBoard\(openStock, button\); \}\);/,
    'same call the stock number made');
  assert.match(CODE, /panel\.querySelectorAll\('\.vso-body \[data-open-stock\]'\)\.forEach\(stockButton => \{[\s\S]*?stockButton\.replaceWith\(plain\);/);
  assert.match(CSS, /#vso-shell \.vso-open-vehicle \{[^}]*background: #1d4ed8; color: #fff;/);
  assert.match(CSS, /#vso-shell \.vso-open-vehicle:focus-visible/);
});

test('3. the vehicle card closing redraws the table and the open panel (watched on #vehicle-modal hidden)', () => {
  const observers = [];
  let renders = 0; const refreshed = [];
  const modal = { hidden: true };
  const ctx = {
    console, CSS: { escape: String },
    MutationObserver: class { constructor(cb) { this.cb = cb; observers.push(this); } observe(target, opts) { this.target = target; this.opts = opts; } },
    document: { getElementById: id => (id === 'vehicle-modal' ? modal : null), querySelector: () => null, querySelectorAll: () => [], head: { appendChild() {} }, body: { classList: { add() {}, remove() {} }, appendChild() {} }, createElement: () => ({ dataset: {} }) },
    vehicleLocationsScreenRows: () => [], vehicleKey: v => v.key,
  };
  ctx.window = ctx;
  ctx.PDC_VEHICLE_LOCATIONS_TABLE = { state: { view: 'table' }, setDrawerOpener: o => { ctx.opener = o; return true; }, render: () => { renders += 1; }, drawerClosed() {}, TILE: {} };
  vm.createContext(ctx);
  vm.runInContext(SRC, ctx);
  assert.equal(observers.length, 1);
  assert.equal(observers[0].target, modal);
  assert.deepEqual([...observers[0].opts.attributeFilter], ['hidden']);
  modal.hidden = false; observers[0].cb();
  assert.equal(renders, 0, 'opening the card redraws nothing');
  modal.hidden = true; observers[0].cb();
  assert.equal(renders, 1, 'closing the card redraws the table once');
  ctx.PDC_VEHICLE_LOCATIONS_TABLE.state.view = 'dropdown';
  modal.hidden = false; observers[0].cb(); modal.hidden = true; observers[0].cb();
  assert.equal(renders, 1, 'Drop-down view: nothing redrawn by this module');
  assert.equal(typeof ctx.PDC_VEHICLE_SLIDEOUT.refresh, 'function');
  void refreshed;
});

test('3b. a control another script adds to an operation line sits on its own row, never over the description', () => {
  for (const sel of ['li > select', 'li > label', 'li > div[data-review-control]']) {
    assert.ok(CSS.includes(`#vso-shell .authenticated-email-operations .authenticated-operation-station ${sel}`), sel);
  }
  assert.match(CSS, /li > div\[data-review-control\] \{ grid-column: 1 \/ -1; position: static !important; \}/);
});

test('4. everything else stays: board handlers, Key No. (Edit / History) in the details, operations, Edit jobs & hours; display only', () => {
  assert.match(CODE, /VLT\.bindBoardHandlers\(panel\);/);
  assert.match(CODE, /incomingVehicleDetailRow\(vehicle, bucket, \{ workshopPlans, workshopProjectionAvailable, subletNavigation: true \}\)/);
  assert.match(CODE, /watchOperations\(panel\);/);
  assert.doesNotMatch(CODE, /\bfetch\s*\(|\.rpc\s*\(|localStorage|sessionStorage|deleteIncomingVehicleFromMain\(/);
  assert.match(CODE, /root\.moveWorkshopDroppedPlan/, 'r565 calls the planner move on a bay drop');
  assert.deepEqual(Object.keys(slideout).sort(), ['VERSION', 'chipMovePlan', 'slimWorkPage'].sort()); // r565 (F179)
  assert.equal(slideout.VERSION, '2026.10.27.r578'); // r578 (F192): green complete tick. r565 chip layout stays
});

test('loader and docs: r473 cache-bust tags, FAULT_LOG F86, panel doc; no real stock numbers here', () => {
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /slideout\.src = 'pdc-vehicle-slideout\.js\?vehicle-slideout=2026\.10\.27\.r578';/ /* r578 (F192) */);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*&amp;r473=2026\.10\.22\.r473&amp;/);
  assert.match(SRC, /pdc-vehicle-slideout\.css\?vehicle-slideout=\$\{VERSION\}/);
  const row = fs.readFileSync('docs/FAULT_LOG.md', 'utf8').split('\n').find(line => line.startsWith('| F86 |'));
  assert.ok(row && /Open Vehicle/.test(row) && /Unassigned/.test(row));
  assert.match(fs.readFileSync('docs/vehicle-slideout-panel.md', 'utf8'), /r473 \(F86\)[\s\S]*Open Vehicle/);
  assert.doesNotMatch(fs.readFileSync(__filename, 'utf8'), /\b1[23]\d{6}\b|\bJ13[89]\d{6}\b/);
  for (const locked of ['styles.css', 'app.js']) assert.doesNotMatch(fs.readFileSync(locked, 'utf8'), /r473|vso-open-vehicle/);
});
