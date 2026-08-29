'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const runtimeScripts = [
  'pdc-email-vehicle-location-service.js',
  'vehicle-location-lifecycle.js',
  'vehicle-modal-identity.js',
  'vehicle-locations-refresh.js',
];

function loadClassicScriptsIntoOneBrowserGlobal() {
  const context = { console, setTimeout, clearTimeout, Promise };
  context.window = context;
  context.globalThis = context;
  vm.createContext(context);
  for (const file of runtimeScripts) {
    const source = fs.readFileSync(path.join(root, file), 'utf8');
    vm.runInContext(source, context, { filename: file });
  }
  return context;
}

class FakeButton {
  constructor() {
    this.disabled = false;
    this.textContent = 'Refresh';
    this.attributes = new Map();
    this.isConnected = true;
  }

  closest(selector) {
    return selector === '[data-vehicle-locations-refresh]' ? this : null;
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  removeAttribute(name) {
    this.attributes.delete(name);
  }

  getAttribute(name) {
    return this.attributes.get(name) || null;
  }
}

class FakeRoot {
  constructor() {
    this.listeners = [];
  }

  addEventListener(name, listener) {
    this.listeners.push({ name, listener });
  }

  click(button) {
    const event = {
      target: button,
      preventDefault() { this.defaultPrevented = true; },
      stopPropagation() { this.propagationStopped = true; },
    };
    this.listeners.filter(item => item.name === 'click').forEach(item => item.listener(event));
  }
}

async function testActualDelegatedClick() {
  const context = loadClassicScriptsIntoOneBrowserGlobal();
  assert.strictEqual(typeof context.PDC_VEHICLE_LOCATIONS_REFRESH?.createVehicleLocationsRefreshCoordinator, 'function');
  const uiSource = fs.readFileSync(path.join(root, 'vehicle-locations-refresh-ui.js'), 'utf8');
  vm.runInContext(uiSource, context, { filename: 'vehicle-locations-refresh-ui.js' });
  assert.strictEqual(typeof context.PDC_VEHICLE_LOCATIONS_REFRESH_UI?.createRefreshClickDelegation, 'function');

  const rootElement = new FakeRoot();
  const button = new FakeButton();
  let resolveRefresh;
  let refreshCalls = 0;
  const results = [];
  const refreshPromise = new Promise(resolve => { resolveRefresh = resolve; });
  const delegation = context.PDC_VEHICLE_LOCATIONS_REFRESH_UI.createRefreshClickDelegation({
    root: rootElement,
    refresh: () => { refreshCalls += 1; return refreshCalls === 1 ? refreshPromise : Promise.resolve({ ok: true }); },
    onResult: result => results.push(result),
  });

  assert.strictEqual(delegation.bind(), true);
  assert.strictEqual(delegation.bind(), false);
  rootElement.click(button);
  rootElement.click(button);
  assert.strictEqual(refreshCalls, 1);
  assert.strictEqual(button.disabled, true);
  assert.strictEqual(button.textContent, 'Refreshing…');
  assert.strictEqual(button.getAttribute('aria-busy'), 'true');

  button.isConnected = false;
  const replacementButton = new FakeButton();
  rootElement.click(replacementButton);
  assert.strictEqual(refreshCalls, 1);

  resolveRefresh({ ok: false, error: 'refresh_unavailable' });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepStrictEqual(results, [{ ok: false, error: 'refresh_unavailable' }]);
  assert.strictEqual(button.disabled, false);
  assert.strictEqual(button.textContent, 'Refresh');
  assert.strictEqual(button.getAttribute('aria-busy'), null);

  const successButton = new FakeButton();
  rootElement.click(successButton);
  assert.strictEqual(refreshCalls, 2);
  await new Promise(resolve => setImmediate(resolve));
  assert.strictEqual(results[1].ok, true);

  const unavailableRoot = new FakeRoot();
  const unavailableButton = new FakeButton();
  const unavailableResults = [];
  const unavailableDelegation = context.PDC_VEHICLE_LOCATIONS_REFRESH_UI.createRefreshClickDelegation({
    root: unavailableRoot,
    onResult: result => unavailableResults.push(result),
  });
  assert.strictEqual(unavailableDelegation.bind(), true);
  unavailableRoot.click(unavailableButton);
  await new Promise(resolve => setImmediate(resolve));
  assert.strictEqual(unavailableResults[0].error, 'refresh_unavailable');
}

function testSourceContracts() {
  const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
  const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
  const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
  assert(app.includes('createRefreshClickDelegation'));
  assert(app.includes('data-vehicle-locations-refresh'));
  assert(app.includes('refresh_unavailable'));
  assert(app.includes('Refresh failed (${app.vehicleLocationsRefreshError || \'refresh_failed\'})'));
  assert(app.includes('handleVehicleLocationsRefreshClickResult'));
  assert(app.includes('aria-busy'));
  assert(!/location\.reload\s*\(/.test(app));
  const scripts = [...index.matchAll(/<script[^>]+src="([^"]+)"/gi)].map(match => match[1]);
  const uiIndex = scripts.findIndex(src => src.includes('vehicle-locations-refresh-ui.js'));
  const appIndex = scripts.findIndex(src => /(^|\/)app\.js(?:\?|$)/.test(src));
  assert(uiIndex >= 0);
  assert(uiIndex < appIndex);
  assert(index.includes('vehicle-locations-refresh-ui.js?v=2026.08.30.770-slimline-bar'));
  assert(css.includes('.vehicle-locations-refresh'));
  assert(css.includes('padding: 5px 10px'));
  assert(css.includes('grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr)'));
  const refreshButtonCss = css.match(/\.vehicle-locations-refresh-button \{([^}]*)\}/s)?.[1] || '';
  assert(refreshButtonCss.includes('grid-column: 2;'));
  assert(refreshButtonCss.includes('grid-row: 1;'));
  assert(css.includes('@media (max-width: 720px)'));
  assert(css.includes('grid-template-columns: 1fr'));
  assert(css.includes('.vehicle-locations-refresh-button { width: fit-content; grid-row: auto; }'));
  assert(css.includes('min-height: 42px'));
}

(async () => {
  await testActualDelegatedClick();
  testSourceContracts();
  console.log('Vehicle Locations deployed-module DOM click delegation regression passed.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
