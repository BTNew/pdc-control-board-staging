'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\ninit\(\);\s*$/, '');
code += String.raw`
(function storageTransactionChecks() {
  function assert(condition, message) {
    if (!condition) throw new Error(message);
  }

  localStorage.setItem('tx-a', 'old-a');
  localStorage.setItem('tx-b', 'old-b');
  const success = runStorageTransaction('Successful update', ['tx-a', 'tx-b'], () => {
    localStorage.setItem('tx-a', 'new-a');
    localStorage.setItem('tx-b', 'new-b');
    return 'committed';
  });
  assert(success === 'committed', 'A successful transaction should return its operation result');
  assert(localStorage.getItem('tx-a') === 'new-a' && localStorage.getItem('tx-b') === 'new-b', 'A successful transaction should retain all writes');
  assert(localStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) === null, 'A successful transaction must clear its journal');

  localStorage.setItem('tx-a', 'old-a');
  localStorage.setItem('tx-b', 'old-b');
  localStorage.failNextSetFor('tx-b');
  let rollbackError = null;
  try {
    runStorageTransaction('Forced failure', ['tx-a', 'tx-b'], () => {
      localStorage.setItem('tx-a', 'partial-a');
      localStorage.setItem('tx-b', 'partial-b');
    });
  } catch (error) {
    rollbackError = error;
  }
  assert(rollbackError && /previous tracker data was restored/i.test(rollbackError.message), 'A failed transaction should report that rollback occurred');
  assert(localStorage.getItem('tx-a') === 'old-a' && localStorage.getItem('tx-b') === 'old-b', 'A failed transaction must restore every touched key');
  assert(localStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) === null, 'A rolled-back transaction must clear its journal');

  let operationRan = false;
  localStorage.failNextSetFor(STORAGE_TRANSACTION_JOURNAL_KEY);
  runStorageTransaction('Fallback journal', ['tx-a'], () => {
    operationRan = true;
    localStorage.setItem('tx-a', 'fallback-saved');
  });
  assert(operationRan === true && localStorage.getItem('tx-a') === 'fallback-saved', 'A full localStorage journal should fall back to sessionStorage');
  assert(sessionStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) === null, 'A successful fallback transaction must clear its session journal');

  operationRan = false;
  localStorage.failNextSetFor(STORAGE_TRANSACTION_JOURNAL_KEY);
  sessionStorage.failNextSetFor(STORAGE_TRANSACTION_JOURNAL_KEY);
  let startError = null;
  try {
    runStorageTransaction('Unsafe start', ['tx-a'], () => {
      operationRan = true;
      localStorage.setItem('tx-a', 'must-not-write');
    });
  } catch (error) {
    startError = error;
  }
  assert(startError && /could not start safely/i.test(startError.message), 'Failure of both journal stores should abort before writes begin');
  assert(operationRan === false && localStorage.getItem('tx-a') === 'fallback-saved', 'No operation may run without a recovery snapshot');

  localStorage.setItem('recover-existing', 'damaged');
  localStorage.setItem('recover-new', 'partial');
  localStorage.setItem(STORAGE_TRANSACTION_JOURNAL_KEY, JSON.stringify({
    version: 1,
    label: 'Interrupted test',
    snapshot: {
      'recover-existing': { exists: true, value: 'safe-value' },
      'recover-new': { exists: false, value: null },
    },
  }));
  assert(recoverInterruptedStorageTransaction() === true, 'Startup recovery should detect a valid interrupted transaction');
  assert(localStorage.getItem('recover-existing') === 'safe-value', 'Startup recovery should restore existing values');
  assert(localStorage.getItem('recover-new') === null, 'Startup recovery should remove keys created by the interrupted operation');
  assert(localStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) === null, 'Startup recovery should clear its completed journal');

  localStorage.setItem('recover-session', 'damaged');
  sessionStorage.setItem(STORAGE_TRANSACTION_JOURNAL_KEY, JSON.stringify({
    version: 1,
    label: 'Interrupted session fallback test',
    snapshot: {
      'recover-session': { exists: true, value: 'safe-session-value' },
    },
  }));
  assert(recoverInterruptedStorageTransaction() === true, 'Startup recovery should detect a sessionStorage fallback journal');
  assert(localStorage.getItem('recover-session') === 'safe-session-value', 'Session fallback recovery should restore saved values');
  assert(sessionStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) === null, 'Session fallback recovery should clear its completed journal');

  localStorage.setItem(STORAGE_TRANSACTION_JOURNAL_KEY, '{not-json');
  assert(recoverInterruptedStorageTransaction() === false, 'An invalid journal should be rejected safely');
  assert(localStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) === null, 'An invalid journal should be removed');

  app.data = [{ id: 'safe-row', stock: 'SAFE-1', internalStatus: 'Original' }];
  localStorage.setItem(EDITS_KEY, JSON.stringify({ 'safe-row': { internalStatus: 'Original' } }));
  localStorage.failNextSetFor(EDITS_KEY);
  const editResult = saveVehicleEdits('safe-row', { internalStatus: 'Must roll back' });
  assert(editResult === false, 'A vehicle edit should report failure when browser storage rejects the write');
  assert(app.data[0].internalStatus === 'Original', 'A failed vehicle edit must restore its in-memory field value');
  assert(JSON.parse(localStorage.getItem(EDITS_KEY))['safe-row'].internalStatus === 'Original', 'A failed vehicle edit must retain its previous saved value');

  app.data = [
    { id: 'email-a', stock: 'EMAIL-A', order: 'SHARED-EMAIL-ORDER', pdcRequiresParts: false },
    { id: 'email-b', stock: 'EMAIL-B', order: 'SHARED-EMAIL-ORDER', pdcRequiresParts: false },
  ];
  assert(vehicleForEmailReview({ stock: 'SHARED-EMAIL-ORDER' }) === null, 'Email review lookup must fail closed when an alias matches more than one vehicle');
  assert(vehicleForEmailReview({ stock: 'EMAIL-A' }) === app.data[0], 'Email review lookup should return a uniquely matched vehicle');

  localStorage.setItem(OPERATOR_NAME_KEY, 'QA Operator');
  localStorage.setItem(EDITS_KEY, JSON.stringify({}));
  localStorage.setItem(AUDIT_LOG_KEY, JSON.stringify([]));
  localStorage.setItem(EMAIL_REVIEW_DECISIONS_KEY, JSON.stringify({}));
  window.PDC_EMAIL_BOARD_DATA = { reviews: [{ id: 'parts-apply-review', stock: 'EMAIL-A', type: 'parts-update', action: 'note', notes: 'Atomic apply test' }] };
  localStorage.failNextSetFor(EMAIL_REVIEW_DECISIONS_KEY);
  const applyResult = applyEmailReview('parts-apply-review');
  assert(applyResult === false, 'A failed Parts-email Apply should report failure');
  assert(Object.keys(JSON.parse(localStorage.getItem(EDITS_KEY))).length === 0, 'Failed Parts-email Apply must roll back vehicle edits');
  assert(JSON.parse(localStorage.getItem(AUDIT_LOG_KEY)).length === 0, 'Failed Parts-email Apply must roll back audit writes');
  assert(Object.keys(JSON.parse(localStorage.getItem(EMAIL_REVIEW_DECISIONS_KEY))).length === 0, 'Failed Parts-email Apply must leave no decision');

  window.PDC_EMAIL_BOARD_DATA = { reviews: [{ id: 'parts-reject-review', stock: 'EMAIL-A', type: 'parts-update', action: 'note' }] };
  localStorage.failNextSetFor(AUDIT_LOG_KEY);
  const rejectResult = rejectEmailReview('parts-reject-review');
  assert(rejectResult === false, 'A failed Parts-email Reject should report failure');
  assert(Object.keys(JSON.parse(localStorage.getItem(EMAIL_REVIEW_DECISIONS_KEY))).length === 0, 'Failed Parts-email Reject must roll back its decision');
  assert(JSON.parse(localStorage.getItem(AUDIT_LOG_KEY)).length === 0, 'Failed Parts-email Reject must leave no audit');

  app.data = [{ id: 'render-row', stock: 'RENDER-1', internalStatus: 'Original' }];
  localStorage.setItem(EDITS_KEY, JSON.stringify({}));
  let renderCalls = 0;
  const originalRenderAll = renderAll;
  renderAll = () => { renderCalls += 1; };
  assert(saveVehicleEdits('render-row', { internalStatus: 'Updated' }, { render: false }) === true, 'No-render vehicle edit should still save successfully');
  assert(renderCalls === 0, 'saveVehicleEdits({ render: false }) must not trigger a broad render');
  renderAll = originalRenderAll;

  console.log('Storage transaction, email-review atomicity and recovery checks passed');
})();
`;

const storage = new Map();
const failures = new Map();
function createStorage(storage, failures) {
  return {
  getItem(key) {
    return storage.has(key) ? storage.get(key) : null;
  },
  setItem(key, value) {
    const remaining = failures.get(key) || 0;
    if (remaining > 0) {
      if (remaining === 1) failures.delete(key);
      else failures.set(key, remaining - 1);
      throw new Error(`Simulated storage failure for ${key}`);
    }
    storage.set(key, String(value));
  },
  removeItem(key) {
    storage.delete(key);
  },
  clear() {
    storage.clear();
  },
  key(index) {
    return Array.from(storage.keys())[index] || null;
  },
  failNextSetFor(key) {
    failures.set(key, (failures.get(key) || 0) + 1);
  },
  get length() {
    return storage.size;
  },
  };
}
const localStorage = createStorage(storage, failures);
const sessionStorage = createStorage(new Map(), new Map());

const context = {
  console,
  window: {
    VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} },
    location: { search: '', pathname: '/index.html', href: 'about:blank' },
    alert: () => {},
    confirm: () => true,
    prompt: () => 'QA',
    setTimeout,
    requestAnimationFrame: callback => callback(),
  },
  localStorage,
  sessionStorage,
  document: {
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener: () => {},
    body: { classList: { add() {}, remove() {}, toggle() {} }, appendChild() {}, dataset: {} },
    createElement: () => ({ setAttribute() {}, appendChild() {}, addEventListener() {}, remove() {}, click() {}, style: {}, classList: { add() {}, remove() {}, toggle() {} } }),
  },
  navigator: {},
  FileReader: function FileReader() {},
  Blob: function Blob() {},
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} },
  URLSearchParams,
  Intl,
  Date,
  Map,
  Set,
  JSON,
  String,
  Number,
  Boolean,
  Array,
  Object,
  RegExp,
  Math,
  Error,
  Promise,
  setTimeout,
  clearTimeout,
};
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });
