'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

let code = fs.readFileSync('app.js', 'utf8');
code += String.raw`
(function runPdcJobLineHourTests() {
  function check(condition, message) { if (!condition) throw new Error(message); }

  const direct = arbEstimateForJobLine('SS177HF', 'Safari snorkel', 2);
  check(direct.estimatedHours === 7, 'Unambiguous ARB hours must multiply by quantity');
  check(direct.estimateStatus === 'provisional', 'Catalogue estimates must start provisional');
  check(/page 100/.test(direct.estimateSource), 'Catalogue estimate must retain source page provenance');

  const ambiguous = arbEstimateForJobLine('LX110', 'LINX vehicle interface', 1);
  check(ambiguous.estimatedHours === null, 'Vehicle-dependent ARB times must not be guessed');
  check(ambiguous.estimateStatus === 'review-required', 'Ambiguous ARB times must require review');
  const multipleCodes = arbEstimateForJobLine('SS177HF', 'Includes SS178HF as a second product', 1);
  check(multipleCodes.estimatedHours === null, 'Multiple catalogue products on one line must not reuse one fitting charge');

  const vehicle = {
    id: 'vehicle-1', stock: '13037843', client: 'Test Customer',
    pdcJobLines: [{
      id: 'jobline-email-1', code: 'SS177HF', description: 'Safari snorkel', quantity: 1,
      estimatedHours: 3.5, estimateStatus: 'provisional', estimateSource: 'DRT20260201.1 · SS177HF · page 100'
    }]
  };
  app.data = [vehicle];
  app.selectedStock = '13037843';
  const html = renderPdcJobLinesSection(vehicle);
  check(/is-provisional/.test(html) && /Confirm hours/.test(html), 'Unconfirmed hours must render orange/provisional with a confirmation action');
  check(/3.5/.test(html) && /SS177HF/.test(html), 'Vehicle card must show the estimate beside its job line');

  localStorage.setItem(OPERATOR_NAME_KEY, 'CW');
  localStorage.setItem(OPERATOR_ROLE_KEY, 'Manager');
  check(confirmPdcJobLineHours('13037843', 'jobline-email-1', '4.25') === true, 'Adjusted hours should confirm');
  check(vehicle.pdcJobLineReviews['jobline-email-1'].confirmedHours === 4.25, 'Confirmed adjusted hours must be retained on the vehicle');
  const edits = JSON.parse(localStorage.getItem(EDITS_KEY));
  check(edits['13037843'].pdcJobLineReviews['jobline-email-1'].confirmed === true, 'Confirmation must persist in vehicle edits');
  const audits = JSON.parse(localStorage.getItem(AUDIT_LOG_KEY));
  check(audits[0].action === 'Provisional job-line hours confirmed' && audits[0].details.hours === 4.25, 'Confirmation must be audited with hours');

  const completedVehicle = {
    id: 'vehicle-completed', stock: '13037845', pdcLocation: 'RFT', rftCollectedAt: '2026-07-14T10:00:00.000Z',
    pdcJobLines: [{ id: 'jobline-completed', description: 'Locked completed work', quantity: 1, estimatedHours: 2, estimateStatus: 'provisional' }]
  };
  app.data = [completedVehicle];
  check(/disabled/.test(renderPdcJobLinesSection(completedVehicle)), 'Completed vehicle job-line controls must render locked');
  check(confirmPdcJobLineHours('13037845', 'jobline-completed', '3') === false, 'Completed vehicle hours must fail closed in the handler');
  check(!completedVehicle.pdcJobLineReviews, 'Completed vehicle lock must prevent mutations');

  const rollbackVehicle = {
    id: 'vehicle-2', stock: '13037844', client: 'Rollback Test',
    pdcJobLines: [{ id: 'jobline-email-2', code: '', description: 'Tint', quantity: 1, estimatedHours: null, estimateStatus: 'review-required' }]
  };
  app.data = [rollbackVehicle];
  app.selectedStock = '13037844';
  STORAGE.failAuditOnce = true;
  check(confirmPdcJobLineHours('13037844', 'jobline-email-2', '1.5') === false, 'Storage failure must reject confirmation');
  check(!rollbackVehicle.pdcJobLineReviews, 'Storage failure must restore in-memory confirmation state');
  const rollbackEdits = JSON.parse(localStorage.getItem(EDITS_KEY));
  check(!rollbackEdits['13037844'], 'Storage failure must not leave a partial vehicle edit');

  console.log('PDC job-line estimate and confirmation checks passed');
})();
`;

const storage = new Map();
const storageControl = { failAuditOnce: false };
const context = {
  console,
  STORAGE: storageControl,
  window: {
    VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} },
    ARB_LABOUR_CATALOG: {
      sourceCode: 'DRT20260201.1', labourRate: 160, labourRateSourcePage: 6,
      entries: {
        SS177HF: { hours: 3.5, page: 100, fittingCharge: 560, method: 'catalog-fitting-charge-at-160' },
        SS178HF: { hours: 3.5, page: 101, method: 'catalog-fitting-charge-at-160' },
      },
      ambiguous: { LX110: [{ hours: 3 }, { hours: 4 }] },
    },
    location: { search: '', pathname: '' },
  },
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => {
      if (storageControl.failAuditOnce && key === 'vehicleTrackingCoreNavisionOnlyAuditLog:v1') {
        storageControl.failAuditOnce = false;
        throw new Error('simulated audit storage failure');
      }
      storage.set(key, String(value));
    },
    removeItem: key => storage.delete(key),
    clear: () => storage.clear(),
    key: index => Array.from(storage.keys())[index] || null,
    get length() { return storage.size; },
  },
  document: {
    readyState: 'loading',
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){}, dataset: {} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{ add(){}, remove(){}, toggle(){} } }),
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
