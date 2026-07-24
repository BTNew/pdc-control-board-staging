'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let code = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
code += String.raw`
(function runAiFileIntakePhase1Checks() {
  function check(condition, message) { if (!condition) throw new Error(message); }

  const poText = [
    'PURCHASE ORDER',
    'PO11204260 15/07/2026 CRAIGW Vehicle / Sublet 139 13037843 1',
    'To Deliver To NEW TOYOTA RETAIL SALES',
    'Toyota Hilux SR5 4x4 GUN126R 001',
    'Colour: 040 Glacier White',
    'Trim: FA20 Black',
    'Stock #: 13037843',
    'VIN: MR0BA3CDX01234567',
    '!ARB01 Bull Bar 1 100.00 100.00',
    '!ARB02 Dual Battery System 1 200.00 200.00',
  ].join('\n');
  const poAnalysis = analyzeAiAssistantText(poText, { name: 'CRAIGW_PO11204260_PurchaseOrder.pdf', type: 'application/pdf' });
  check(poAnalysis.ok === false, 'Purchase orders must be rejected from vehicle-work intake');

  const pdText = [
    'PRE DELIVERY CHECK FORM',
    '(CW) Craig Watson Deal: 47836',
    'CUSTOMER SALES DETAILS',
    'Broome Test Customer Fleet',
    'Stock # 12345678',
    'Make & Model HiLux DCC SR Unit Colour Glacier White Trim Colour Black',
    'Window tint and steel tray body with dual battery',
  ].join('\n');
  const pdAnalysis = analyzeAiAssistantText(pdText, { name: 'PDCheckform.pdf', type: 'application/pdf' });
  check(pdAnalysis.ok === true, 'PD Document analysis should produce a safe draft');
  check(pdAnalysis.review.type === 'vehicle-import', 'PD Document analysis should create a vehicle-import review');
  check(pdAnalysis.review.jobLines.length >= 3, 'PD Document analysis should create review lines from detected tasks');
  check(pdAnalysis.review.jobLines.every(line => line.estimatedHours === null), 'PD Document task drafts must require staff-entered hours');

  const partsText = [
    'Stock: 13047064',
    'Parts stoppage',
    'ETA: 22/07/2026',
    'Awaiting back order from supplier',
  ].join('\n');
  const partsAnalysis = analyzeAiAssistantText(partsText, { name: 'parts-note.txt', type: 'text/plain' });
  check(partsAnalysis.ok === true, 'Parts text analysis should produce a safe draft');
  check(partsAnalysis.review.type === 'parts-update', 'Parts text analysis should create a Parts review');
  check(partsAnalysis.review.action === 'stoppage', 'Parts text analysis should detect stoppage intent');
  check(partsAnalysis.review.eta === '22/07/2026', 'Parts text analysis should retain the ETA text');

  saveAiFileAssistantReviews([pdAnalysis.review]);
  window.PDC_EMAIL_BOARD_DATA = { reviews: [{ id: 'seed-review', stock: 'SEED-1', type: 'parts-update', action: 'note', receivedAt: '2026-07-01T00:00:00.000Z' }] };
  const merged = emailReviewItems();
  check(merged.some(item => item.id === 'seed-review'), 'Email review list must keep seeded review data');
  check(merged.some(item => item.id === pdAnalysis.review.id), 'Email review list must include every saved AI file draft');

  console.log('AI file intake phase 1 checks passed');
})();
`;

const storage = new Map();
const context = {
  console,
  window: {
    VEHICLE_TRACKING_DATA: { vehicles: [], toyotaMatches: {}, report: {} },
    PDC_EMAIL_BOARD_DATA: { reviews: [] },
    location: { search: '', pathname: '' },
    ARB_LABOUR_CATALOG: { entries: {}, ambiguous: {}, labourRate: 160, sourceCode: 'TEST' },
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
    addEventListener: () => {},
    body: { classList: { add(){}, remove(){}, toggle(){} }, appendChild(){}, dataset: {} },
    createElement: () => ({ setAttribute(){}, appendChild(){}, addEventListener(){}, remove(){}, click(){}, style:{}, classList:{ add(){}, remove(){}, toggle(){} } }),
  },
  navigator: {},
  FileReader: function(){},
  Blob: function(){},
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

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
assert.ok(source.includes('function analyzeAiAssistantUploads') || source.includes('function analyzeAiFileAssistantUploads'), 'AI file assistant analysis entrypoint is missing');
assert.ok(source.includes('AI_FILE_ASSISTANT_REVIEWS_KEY'), 'AI file assistant storage key is missing');
assert.ok(source.includes('Phase 1 file analysis'), 'Phase 1 analysis guidance text is missing');
