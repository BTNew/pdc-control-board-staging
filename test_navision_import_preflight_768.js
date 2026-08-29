'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf('function navisionClientPreflight');
const end = app.indexOf('\nasync function loadSharedNavisionCurrentRows', start);
assert(start >= 0 && end > start, 'client preflight helpers must remain present');
const source = app.slice(start, end);
const context = {
  normalizeBatch(value) { return String(value || '').trim().replace(/[^A-Za-z0-9]/g, '').toUpperCase(); },
  normalizeVin(value) { const normalized = String(value || '').trim().replace(/[^A-Za-z0-9]/g, '').toUpperCase(); return normalized || ''; },
  cleanNavisionText(value) { return String(value || '').trim(); },
  Map, Array, String, Number, Date, Math, Object, RegExp,
};
vm.createContext(context);
vm.runInContext(source, context, { filename: 'app.js' });
const preflight = context.navisionClientPreflight;
assert.strictEqual(typeof preflight, 'function');

const exact = { id: 'navision-13080534', stock: '13080534', batch: '13080534', toyotaStatus: 'Planned for Production' };
const duplicate = { id: 'navision-13080534-second-source', stock: '13080534', batch: '13080534', toyotaStatus: 'Planned for Production' };
const duplicateResult = preflight([exact, duplicate], '14450');
assert.strictEqual(duplicateResult.blocking, true, 'duplicate Stock candidates must block');
assert.strictEqual(JSON.stringify(duplicateResult.issues.map(issue => issue.reason)), JSON.stringify(['duplicate_stock_number', 'duplicate_stock_number']));
assert(duplicateResult.issues.every(issue => issue.stock_number === '13080534' && issue.field === 'stock'), 'duplicate Stock issue must name Stock and the exact value');

const invalidResult = preflight([
  { id: 'invalid-status', stock: '13080535', status_code: 'NOT-A-STATUS' },
  { id: 'invalid-date', stock: '13080536', pdcEtaDate: '31/02/2026' },
  { id: 'invalid-location', stock: '13080537', pdcLocation: 'WAREHOUSE-9' },
], '14450');
assert.strictEqual(JSON.stringify(invalidResult.issues.map(issue => issue.reason)), JSON.stringify(['invalid_status_code', 'invalid_date', 'invalid_location_code']));
assert(invalidResult.issues.every(issue => issue.classification === 'invalid' && issue.stock_number), 'invalid rows must remain classified with Stock context');

const wrongDealer = preflight([{ id: 'wrong-dealer', stock: '13080538', dealerCode: '37047' }], '14450');
assert.strictEqual(wrongDealer.issues[0].reason, 'wrong_dealer_scope');
assert.strictEqual(wrongDealer.issues[0].field, 'dealer_code');

const valid = preflight([
  { id: 'valid-a', stock: '13080539', toyotaStatus: 'Planned for Production', pdcLocation: 'PMB', pdcEtaDate: '2026-08-30' },
  { id: 'valid-b', stock: '13080540', toyotaStatus: 'In Transit to WA' },
], '14450');
assert.strictEqual(valid.issue_count, 0, 'valid sibling rows must remain eligible');
assert.strictEqual(valid.atomic_apply, true, 'client preflight must preserve atomic apply semantics');

assert(app.includes('No localStorage fallback was attempted') || app.includes('no browser-local fallback was attempted'), 'shared failure messaging must retain fail-closed fallback wording');
const applyStart = app.indexOf('async function applySharedNavisionImportPending');
const applyEnd = app.indexOf('\nfunction selectedPendingNavisionUpdateKeys', applyStart);
const applyBlock = app.slice(applyStart, applyEnd);
assert(!applyBlock.includes('localStorage.setItem') && !applyBlock.includes('saveJson('), 'shared apply must not write browser-local authority');
console.log('Navision 768 client preflight regression: exact Stock, invalid fields, dealer scope, valid siblings, atomicity and no-localStorage checks passed');
