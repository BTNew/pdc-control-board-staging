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
  let startError = null;
  try {
    runStorageTransaction('Unsafe start', ['tx-a'], () => {
      operationRan = true;
      localStorage.setItem('tx-a', 'must-not-write');
    });
  } catch (error) {
    startError = error;
  }
  assert(startError && /could not start safely/i.test(startError.message), 'A journal failure should abort before writes begin');
  assert(operationRan === false && localStorage.getItem('tx-a') === 'old-a', 'No operation may run without a recovery snapshot');

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

  console.log('Storage transaction and recovery checks passed');
})();
`;

const storage = new Map();
const failures = new Map();
const localStorage = {
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
