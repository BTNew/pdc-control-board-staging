'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\nif \(document\.readyState === 'loading'\)[\s\S]*$/, '');
const removalBlock = code.slice(code.indexOf('function removeMissingFromLastNavisionImport()'), code.indexOf('function handlePdfSelect'));
if (removalBlock.includes('saveJson(') || removalBlock.includes('removeVehiclesFromTracker(')) {
  throw new Error('Post-import removal button must not bypass exact quota preflight');
}
code += String.raw`
(function navisionStorageSafetyChecks() {
  function assert(condition, message) {
    if (!condition) throw new Error(message);
  }
  function storageSnapshot() { return new Map(storage); }
  function assertSnapshotExact(before, message) {
    assert(storage.size === before.size && [...before].every(([key, value]) => localStorage.getItem(key) === value), message);
  }

  assert(sha256Hex('abc') === 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'SHA-256 must match the standard abc vector');
  assert(navisionPayloadFingerprint('same', { fullRefresh: true }) === navisionPayloadFingerprint('same', { fullRefresh: false }), 'Rejected identity must be based only on exact source bytes');
  assert(navisionPayloadFingerprint('same') !== navisionPayloadFingerprint('different'), 'Different source bytes must have different fingerprints');

  const rows = [{ id: 'NAV-1', stock: '10000001', source: 'Navision', sourceRow: 'row one' }];
  const manyWarnings = Array.from({ length: 200 }, (_, index) => 'warning-' + index + '-' + 'w'.repeat(400));
  const full = {
    parsed: { vehicles: rows, warnings: manyWarnings },
    added: rows,
    updated: [{ key: 'K1', payload: { id: 'CHANGED-1', notes: 'x'.repeat(8000) } }],
    unchanged: [], stockNumberUpdates: [], restored: [], missingFromUpload: [], removedMissing: [],
    skipped: manyWarnings,
    sourceFingerprint: navisionPayloadFingerprint('source'),
    importedAt: '2026-07-20T00:00:00.000Z',
    appliedAt: '2026-07-20T00:00:01.000Z',
    fullRefresh: true, confirmed: true,
  };
  const summary = boundedNavisionImportSummary(full);
  const summaryText = JSON.stringify(summary);
  assert(summary.summaryVersion === 2 && summary.counts.rows === 1, 'Bounded summary must retain versioned counts');
  assert(!summaryText.includes('sourceRow') && !('skipped' in summary) && !Array.isArray(summary.parsed.vehicles), 'Bounded summary must not duplicate complete vehicle or warning arrays');
  assert(summary.vehiclePayloadSha256 === sha256Hex(JSON.stringify(rows)), 'Bounded summary must hash the exact vehicle payload');
  assert(summaryText.length <= NAVISION_IMPORT_SUMMARY_MAX_CHARS && summary.warningPreviewTruncated, 'Bounded summary must enforce a hard serialized ceiling');
  const adversarialSummary = boundedNavisionImportSummary({ ...full, sourceFingerprint: 'f'.repeat(20000), importedAt: 'i'.repeat(20000), appliedAt: 'a'.repeat(20000) });
  assert(JSON.stringify(adversarialSummary).length <= NAVISION_IMPORT_SUMMARY_MAX_CHARS && adversarialSummary.sourceFingerprint.length === 64, 'Untrusted summary metadata must remain hard bounded');

  const originalRows = [{ id: 'SAFE-ROW', stock: '10000001', source: 'Navision' }];
  const originalText = JSON.stringify(originalRows);
  localStorage.setItem(ADDED_KEY, originalText);
  const plan = { ...full, parsed: { vehicles: [{ id: 'TOO-LARGE', sourceRow: 'y'.repeat(250000) }], warnings: [] }, skipped: [], sourceFingerprint: 'oversized-fingerprint' };

  // Find the exact boundary for the conservative budget and prove the next UTF-16 code unit fails.
  let low = 0, high = 2200000;
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    localStorage.setItem('near-quota-fixture', 'x'.repeat(mid));
    if (projectNavisionImportPeakStorage(plan).allowed) low = mid;
    else high = mid - 1;
  }
  localStorage.setItem('near-quota-fixture', 'x'.repeat(low));
  const boundary = projectNavisionImportPeakStorage(plan);
  localStorage.setItem('near-quota-fixture', 'x'.repeat(low + 1));
  const overBoundary = projectNavisionImportPeakStorage(plan);
  assert(boundary.allowed && !overBoundary.allowed, 'Exact quota boundary must allow the largest fitting value and reject the smallest overage');
  assert(overBoundary.journalBytes > 0 && overBoundary.summaryBytes > 0 && overBoundary.commit.finalValues.size >= 5, 'Projection must use the exact journal and complete final commit');
  let independentlyComputed = overBoundary.currentBytes - (storage.has(STORAGE_TRANSACTION_JOURNAL_KEY) ? localStorageQuotaBytes(STORAGE_TRANSACTION_JOURNAL_KEY, storage.get(STORAGE_TRANSACTION_JOURNAL_KEY)) : 0) + overBoundary.journalBytes;
  let independentPeak = Math.max(overBoundary.currentBytes, independentlyComputed);
  overBoundary.writeOrder.forEach(write => { independentlyComputed += write.deltaBytes; independentPeak = Math.max(independentPeak, independentlyComputed); });
  assert(independentPeak === overBoundary.projectedPeakBytes, 'Projection must exactly simulate the serialized journal and every final key value in write order');

  const beforeReject = storageSnapshot();
  const writesBefore = localStorage.writeCount;
  const first = applyNavisionImportPlan(plan);
  assert(first === null && app.rejectedNavisionFingerprint === 'oversized-fingerprint', 'Oversized import must be rejected and fingerprinted');
  assert(alerts.at(-1) === NAVISION_IMPORT_TOO_LARGE_MESSAGE, 'Quota rejection must display the exact approved message');
  assert(localStorage.writeCount === writesBefore && localStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY) === null, 'Quota rejection must occur before the first localStorage write or journal');
  assertSnapshotExact(beforeReject, 'Quota rejection must preserve every existing value');

  const originalProjector = projectNavisionImportPeakStorage;
  let retryProjectionCalls = 0;
  projectNavisionImportPeakStorage = (...args) => { retryProjectionCalls += 1; return originalProjector(...args); };
  const retryWrites = localStorage.writeCount;
  const second = applyNavisionImportPlan(plan);
  assert(second === null && retryProjectionCalls === 0 && localStorage.writeCount === retryWrites, 'Identical oversized retry must stop immediately without projection or writes');
  projectNavisionImportPeakStorage = originalProjector;

  // Inject a quota failure after the guard and prove every touched key is restored exactly.
  storage.delete('near-quota-fixture');
  app.rejectedNavisionFingerprint = '';
  app.rejectedNavisionProjection = null;
  const safePlan = { ...full, parsed: { vehicles: [{ id: 'SAFE-NEW', stock: '10000002', source: 'Navision' }], warnings: [] }, skipped: [], sourceFingerprint: 'safe-fingerprint' };
  const beforeFailure = storageSnapshot();
  localStorage.failOnKey = OPERATIONAL_HEALTH_KEY;
  localStorage.failOnce = true;
  const failed = applyNavisionImportPlan(safePlan);
  assert(failed === null, 'Injected post-guard failure must not report success');
  assertSnapshotExact(beforeFailure, 'Injected post-guard failure must restore all touched keys exactly');
  assert(!localStorage.getItem(STORAGE_TRANSACTION_JOURNAL_KEY), 'Successful rollback must remove the recovery journal');

  localStorage.failOnKey = '';

  // A successful commit must write exactly the values from the same projection used by the guard.
  let committedProjection = null;
  projectNavisionImportPeakStorage = (...args) => {
    committedProjection = originalProjector(...args);
    return committedProjection;
  };
  const applied = applyNavisionImportPlan(safePlan);
  const expectedFinal = new Map(committedProjection.commit.finalValues);
  assert(applied && expectedFinal.size >= 5, 'Safe projected import must apply');
  expectedFinal.forEach((value, key) => assert(localStorage.getItem(key) === value, 'Committed value must exactly equal projected value for ' + key));
  projectNavisionImportPeakStorage = originalProjector;

  const exportWrites = localStorage.writeCount;
  localStorage.setItem(ADDED_KEY, originalText);
  const validEvidence = exportLocalNavisionDataset();
  assert(validEvidence.records === 1 && validEvidence.datasetSha256 === sha256Hex(originalText), 'Export evidence must hash exact authority bytes');
  assert(downloadState.lastBlob.parts[0] === originalText, 'Download must contain exact stored authority bytes without an envelope');
  localStorage.setItem(ADDED_KEY, '{malformed');
  const malformedEvidence = exportLocalNavisionDataset();
  assert(malformedEvidence.records === null && downloadState.lastBlob.parts[0] === '{malformed', 'Malformed authority bytes must still be exported exactly');
  localStorage.removeItem(ADDED_KEY);
  const absentEvidence = exportLocalNavisionDataset();
  assert(absentEvidence.exactStoredBytes === false && downloadState.lastBlob.parts[0] === '[]', 'Absent authority must export the exact [] fallback');
  assert(localStorage.writeCount === exportWrites + 3, 'Exports themselves must not mutate localStorage');

  console.log('Navision exact quota projection, rollback, bounded summary, retry blocking and raw export checks passed');
})();
`;

const storage = new Map();
const session = new Map();
const alerts = [];
const downloadState = { clicks: 0, lastBlob: null };
function createStorage(map) {
  return {
    writeCount: 0,
    failOnKey: '',
    failOnce: false,
    getItem(key) { return map.has(key) ? map.get(key) : null; },
    setItem(key, value) {
      this.writeCount += 1;
      if (this.failOnce && key === this.failOnKey) { this.failOnce = false; throw new Error('Injected quota failure'); }
      map.set(key, String(value));
    },
    removeItem(key) { this.writeCount += 1; map.delete(key); },
    key(index) { return Array.from(map.keys())[index] ?? null; },
    get length() { return map.size; },
  };
}
const localStorage = createStorage(storage);
const sessionStorage = createStorage(session);
const context = {
  console, storage, alerts, downloadState,
  window: {
    VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} },
    location: { search: '', pathname: '/index.html', href: 'http://127.0.0.1:8124/index.html', origin: 'http://127.0.0.1:8124' },
    alert: message => alerts.push(String(message)), confirm: () => true, prompt: () => 'QA',
    setTimeout, requestAnimationFrame: callback => callback(),
  },
  localStorage, sessionStorage,
  document: {
    readyState: 'complete', querySelector: () => null, querySelectorAll: () => [], addEventListener: () => {},
    body: { classList: { add() {}, remove() {}, toggle() {} }, appendChild() {}, dataset: {} },
    createElement: () => ({ href: '', download: '', style: {}, classList: { add() {}, remove() {}, toggle() {} }, setAttribute() {}, appendChild() {}, addEventListener() {}, remove() {}, click() { downloadState.clicks += 1; } }),
  },
  navigator: {}, FileReader: function FileReader() {},
  Blob: function Blob(parts, options) { this.parts = parts; this.options = options; downloadState.lastBlob = this; },
  URL: { createObjectURL: () => 'blob:test', revokeObjectURL: () => {} }, URLSearchParams, Intl, Date, Map, Set, JSON, String, Number, Boolean, Array, Object, RegExp, Math, Error, Promise, setTimeout, clearTimeout,
};
context.window.navigator = context.navigator;
context.globalThis = context;
vm.createContext(context);
vm.runInContext(code, context, { filename: 'app.js' });
