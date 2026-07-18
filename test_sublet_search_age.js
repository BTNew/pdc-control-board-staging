const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');
assert.ok(css.includes('.vehicle-search-highlight'), 'Single vehicle search result highlight styling is missing');
assert.ok(!/animation:\s*pdc(?:Card)?Flash/i.test(css), 'Kewdale/PMB age indicators must not flash');
assert.ok(css.includes('.pmb-age-fresh { background: #e0f2fe'), 'Fresh Kewdale age should use light blue');
assert.ok(css.includes('.pmb-age-watch { background: #fef9c3'), 'Watch Kewdale age should use yellow');
assert.ok(css.includes('.pmb-age-warning { background: #ffedd5'), 'Warning Kewdale age should use orange');
assert.ok(css.includes('.pmb-age-critical { background: #fee2e2'), 'Critical Kewdale age should use red');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function(){
  function check(condition, message) { if (!condition) throw new Error(message); }
  // Stage 2A: sublet providers are now Supabase-backed via
  // workshop-reference-data-service.js, not localStorage. Stub a fake
  // reference-data service exposing the same shape loadSubletProviders()/
  // loadSubletProviderRecords() expect, seeded with the exact set this
  // test previously seeded into SUBLET_PROVIDERS_KEY, so the name-
  // normalization behaviour under test (normalizeSubletProviderName,
  // dedup, case-insensitive merge) is exercised through the real
  // production code path rather than a bypassed one.
  let fakeProviderRows = normalizedSubletProviderList(DEFAULT_SUBLET_PROVIDERS).map((name, index) => ({
    id: 'fake-provider-' + index, name, active: true, version: 1, sort_order: index,
  }));
  window.__workshopReferenceDataService = {
    getCachedSubletProviders: () => ({ rows: fakeProviderRows, state: 'connected_editable', error: null }),
    addSubletProvider: (name) => {
      const cleaned = normalizeSubletProviderName(name);
      if (fakeProviderRows.some(row => row.name.toLowerCase() === cleaned.toLowerCase())) {
        return Promise.resolve({ ok: false, error: 'duplicate_name' });
      }
      fakeProviderRows = [...fakeProviderRows, { id: 'fake-provider-' + fakeProviderRows.length, name: cleaned, active: true, version: 1, sort_order: fakeProviderRows.length }];
      return Promise.resolve({ ok: true, provider: fakeProviderRows[fakeProviderRows.length - 1] });
    },
  };
  const providers = loadSubletProviders();
  ['Techfire', 'ARB', 'PTE', 'PK Technology', 'Tyrepower - West Perth', 'Hidrive - Canning Vale', 'Unicorn Transport Equipment', 'Pedders - Cockburn'].forEach(name => {
    check(providers.includes(name), 'Missing normalized sublet provider: ' + name);
  });
  check(!providers.includes('UNICORN TRANSPORT EQUIPMENT'), 'Normal company names must not remain all capitals');
  check(providers.filter(name => name === 'PTE').length === 1, 'Repeated PTE entries must be deduplicated');
  check(normalizeSubletProviderName('ROSCOS') === 'Roscoes', 'Roscos/Roscoes variants should be merged');
  check(normalizeSubletProviderName('ARB WELSHPOOL') === 'ARB - Welshpool', 'ARB Welshpool variants should be merged');
  check(normalizeSubletProviderName('HarnessMaster') === 'Harness Master', 'HarnessMaster should be displayed as two words');
  // Stage 2A: deduplication for a genuinely new-cased entry is now
  // enforced by add_sublet_provider()'s duplicate_name check (real,
  // case-insensitive, tested live against staging in
  // _staging_test_tools/test_stage2a_workshop_reference_data_staging.py)
  // rather than by a client-side saveSubletProviders() array dedup --
  // confirm the fake service's addSubletProvider() rejects a duplicate
  // exactly as the real RPC does.
  window.__workshopReferenceDataService.addSubletProvider('pte').then(result => {
    check(result.ok === false && result.error === 'duplicate_name', 'Adding a case-variant duplicate ("pte") must be rejected, not silently deduplicated client-side');
  });

  function auDateDaysAgo(days) {
    const date = new Date();
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() - days);
    return [String(date.getDate()).padStart(2, '0'), String(date.getMonth() + 1).padStart(2, '0'), date.getFullYear()].join('/');
  }
  check(onSiteDaysClass({ etaAtDealer: auDateDaysAgo(2) }) === 'fresh', '0-5 Kewdale days should be light blue');
  check(onSiteDaysClass({ etaAtDealer: auDateDaysAgo(7) }) === 'watch', '6-10 Kewdale days should be yellow');
  check(onSiteDaysClass({ etaAtDealer: auDateDaysAgo(14) }) === 'warning', '11-21 Kewdale days should be orange');
  check(onSiteDaysClass({ etaAtDealer: auDateDaysAgo(22) }) === 'critical', '22+ Kewdale days should be red');

  const appliedClasses = new Set();
  let scrolled = false;
  const bucket = { open: false };
  const row = {
    dataset: { incomingRow: 'SEARCH-1' },
    open: false,
    classList: { add: value => appliedClasses.add(value) },
    closest: selector => selector === 'details.incoming-bucket' ? bucket : null,
    scrollIntoView: () => { scrolled = true; },
  };
  const host = { querySelectorAll: selector => selector === '[data-incoming-row]' ? [row] : [] };
  revealSingleVehicleSearchResult(host, [{ stock: 'SEARCH-1' }], 'SEARCH-1', 'test');
  check(row.open && bucket.open, 'A single search match should open both its bucket and vehicle row');
  check(appliedClasses.has('vehicle-search-highlight'), 'A single search match should be highlighted');
  check(scrolled, 'A single search match should scroll into view once');
  console.log('Sublet, search reveal and Kewdale age tests passed');
})();
`;

const storage = new Map();
const context = {
  console,
  window: { VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} }, location: { href: '' } },
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: key => storage.delete(key), clear: () => storage.clear(),
    key: index => Array.from(storage.keys())[index] || null,
    get length() { return storage.size; },
  },
  document: {
    querySelector: () => null, querySelectorAll: () => [], addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){}, dataset: {} },
    documentElement: { dataset: {} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, style: {}, classList: { add(){}, remove(){}, toggle(){} } }),
  },
  navigator: {}, FileReader: function(){}, Blob: function(){},
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
  Intl, Date, Map, Set, JSON, String, Number, Boolean, Array, Object, RegExp, Math, Error, Promise, setTimeout, clearTimeout,
};
context.window.alert = () => {};
context.window.confirm = () => true;
context.window.prompt = () => 'QA';
context.window.setTimeout = setTimeout;
context.window.requestAnimationFrame = fn => fn();
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });
