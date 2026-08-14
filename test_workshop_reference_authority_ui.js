'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const helperStart = source.indexOf('let WORKSHOP_REFERENCE_AUTHORITY_GENERATION = 0;');
const helperEnd = source.indexOf('function workshopTechnicianAdminCanMutate(', helperStart);
assert.ok(helperStart >= 0 && helperEnd > helperStart, 'workshop reference authority-owner helper block exists');
const helperSource = source.slice(helperStart, helperEnd);

let token = 'token-a';
const serviceA = {};
const serviceB = {};
const context = {
  serviceA,
  serviceB,
  window: {
    PDC_AUTH_CONTEXT: { userId: 'principal-a', role: 'administrator' },
    __workshopReferenceDataService: serviceA,
  },
  getPdcSupabaseAccessToken: () => token,
};
vm.createContext(context);
vm.runInContext(helperSource, context, { filename: 'workshop-reference-authority.js' });
const evaluate = expression => vm.runInContext(expression, context);

const ownerToken = evaluate("captureWorkshopReferenceMutation(serviceA, 'technician:add', { requireAdministrator: true })");
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(ownerToken), true, 'captured owner starts current');
token = 'token-b';
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(ownerToken), false, 'token replacement invalidates owner');

token = 'token-b';
const ownerPrincipal = evaluate("captureWorkshopReferenceMutation(serviceA, 'technician:add', { requireAdministrator: true })");
context.window.PDC_AUTH_CONTEXT = { userId: 'principal-b', role: 'administrator' };
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(ownerPrincipal), false, 'principal replacement invalidates owner');

context.window.PDC_AUTH_CONTEXT = { userId: 'principal-b', role: 'administrator' };
const ownerRole = evaluate("captureWorkshopReferenceMutation(serviceA, 'technician:add', { requireAdministrator: true })");
context.window.PDC_AUTH_CONTEXT = { userId: 'principal-b', role: 'operator' };
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(ownerRole), false, 'administrator demotion invalidates privileged owner');

context.window.PDC_AUTH_CONTEXT = { userId: 'principal-b', role: 'administrator' };
const ownerService = evaluate("captureWorkshopReferenceMutation(serviceA, 'technician:add', { requireAdministrator: true })");
context.window.__workshopReferenceDataService = serviceB;
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(ownerService), false, 'service replacement invalidates owner');

context.window.__workshopReferenceDataService = serviceA;
const olderOwner = evaluate("captureWorkshopReferenceMutation(serviceA, 'technician:add', { requireAdministrator: true })");
const newerOwner = evaluate("captureWorkshopReferenceMutation(serviceA, 'technician:add', { requireAdministrator: true })");
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(olderOwner), false, 'new same-key operation replaces older owner');
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(newerOwner), true, 'new same-key owner remains current');
evaluate('invalidateWorkshopReferenceAuthority')();
assert.strictEqual(evaluate('workshopReferenceMutationCurrent')(newerOwner), false, 'auth invalidation revokes owner');

function functionSource(name) {
  const start = source.indexOf(`async function ${name}(`);
  assert.ok(start >= 0, `${name} is async and exists`);
  const nextAsync = source.indexOf('\nasync function ', start + 1);
  const nextPlain = source.indexOf('\nfunction ', start + 1);
  const candidates = [nextAsync, nextPlain].filter(index => index > start);
  return source.slice(start, candidates.length ? Math.min(...candidates) : source.length);
}

const mutationFamilies = [
  ['addMechanicFromAdminInput', 'addTechnician', ''],
  ['removeMechanicFromAdminList', 'setTechnicianActive', 'confirm'],
  ['addSubletProviderFromAdminInput', 'addSubletProvider', ''],
  ['removeSubletProviderFromAdminList', 'setSubletProviderActive', 'confirm'],
  ['addSalespersonFromAdminInput', 'addSalesperson', ''],
  ['removeSalespersonFromAdminList', 'setSalespersonActive', 'confirm'],
  ['addMechanicFromPrompt', 'addTechnician', 'prompt'],
  ['addSubletProviderFromPrompt', 'addSubletProvider', 'prompt'],
];
for (const [name, method, dialogKind] of mutationFamilies) {
  const fn = functionSource(name);
  const captureIndex = fn.indexOf('captureWorkshopReferenceMutation(');
  const dispatchIndex = fn.indexOf(`owner.service.${method}(`);
  assert.ok(captureIndex >= 0, `${name} captures exact authority/service owner`);
  assert.ok(dispatchIndex > captureIndex, `${name} dispatches only through captured service owner`);
  assert.doesNotMatch(fn, /(?<!owner\.)\bservice\.(?:add|edit|set)[A-Z]/, `${name} never dispatches through a replaceable local/global service`);
  assert.ok((fn.match(/workshopReferenceMutationCurrent\(owner\)/g) || []).length >= 2, `${name} revalidates before publication and after awaits`);
  assert.doesNotMatch(fn, /\.then\s*\(/, `${name} uses awaited owner checks rather than unowned promise callbacks`);
  if (dialogKind) {
    const dialogIndex = fn.indexOf(`window.${dialogKind}(`);
    assert.ok(dialogIndex > captureIndex, `${name} captures owner and immutable record before ${dialogKind}`);
    assert.match(fn.slice(dialogIndex, dispatchIndex), /workshopReferenceMutationCurrent\(owner\)/, `${name} revalidates immediately after ${dialogKind}`);
  }
}

const initStart = source.indexOf('function initWorkshopReferenceDataServiceIfAvailable()');
const initEnd = source.indexOf('\nfunction initWorkshopSharedServicesIfEnabled()', initStart);
const initSource = source.slice(initStart, initEnd);
assert.match(initSource, /captureWorkshopReferenceServiceAuthority\(\)/, 'service callback captures authority generation/token/principal');
assert.match(initSource, /workshopReferenceServiceAuthorityCurrent\(service, serviceAuthority\)[\s\S]*?renderAdminLists\(\)/, 'stale service callbacks cannot publish into replacement authority DOM');

assert.ok((source.match(/resetWorkshopReferenceDataAuthorityState\(\)/g) || []).length >= 5, 'read loss, auth-ready, token-change and lock reset exact reference authority');

const removeCalls = { a: 0, b: 0, alerts: 0, renders: 0 };
let removeToken = 'token-a';
const removeServiceA = { setTechnicianActive: async () => { removeCalls.a += 1; return { ok: true }; } };
const removeServiceB = { setTechnicianActive: async () => { removeCalls.b += 1; return { ok: true }; } };
const removeContext = {
  window: {
    PDC_AUTH_CONTEXT: { userId: 'principal-a', role: 'administrator' },
    __workshopReferenceDataService: removeServiceA,
    confirm() {
      removeToken = 'token-b';
      this.PDC_AUTH_CONTEXT = { userId: 'principal-b', role: 'administrator' };
      this.__workshopReferenceDataService = removeServiceB;
      return true;
    },
    alert() { removeCalls.alerts += 1; },
  },
  getPdcSupabaseAccessToken: () => removeToken,
  cleanNavisionText: value => String(value || '').trim(),
  workshopTechnicianAdminCanMutate: () => true,
  initWorkshopReferenceDataServiceIfAvailable: () => removeContext.window.__workshopReferenceDataService,
  loadMechanicRecords: () => [{ id: 'tech-1', version: 7, name: 'Alice' }],
  renderAdminLists: () => { removeCalls.renders += 1; },
  renderKpis: () => { removeCalls.renders += 1; },
};
vm.createContext(removeContext);
vm.runInContext(`${helperSource}\n${functionSource('removeMechanicFromAdminList')}`, removeContext, { filename: 'workshop-reference-remove-dialog.js' });

const addCalls = { add: 0, list: 0, alerts: 0, renders: 0 };
let addToken = 'token-a';
const addInput = { value: 'Alice' };
let addContext;
const addServiceA = {
  async addTechnician() {
    addCalls.add += 1;
    addToken = 'token-b';
    addContext.window.PDC_AUTH_CONTEXT = { userId: 'principal-b', role: 'administrator' };
    addContext.window.__workshopReferenceDataService = {};
    return { ok: true };
  },
  async listTechnicians() { addCalls.list += 1; return []; },
};
addContext = {
  window: {
    PDC_AUTH_CONTEXT: { userId: 'principal-a', role: 'administrator' },
    __workshopReferenceDataService: addServiceA,
    alert() { addCalls.alerts += 1; },
  },
  getPdcSupabaseAccessToken: () => addToken,
  cleanNavisionText: value => String(value || '').trim(),
  workshopTechnicianAdminCanMutate: () => true,
  initWorkshopReferenceDataServiceIfAvailable: () => addContext.window.__workshopReferenceDataService,
  workshopReferenceMutationMessage: (_result, fallback) => fallback,
  $: () => addInput,
  renderAdminLists: () => { addCalls.renders += 1; },
  renderKpis: () => { addCalls.renders += 1; },
};
vm.createContext(addContext);
vm.runInContext(`${helperSource}\n${functionSource('addMechanicFromAdminInput')}`, addContext, { filename: 'workshop-reference-add-completion.js' });

(async () => {
  await vm.runInContext("removeMechanicFromAdminList('Alice')", removeContext);
  assert.deepStrictEqual(removeCalls, { a: 0, b: 0, alerts: 0, renders: 0 }, 're-entrant confirm cannot dispatch principal-A intent through principal-B reference service');
  await vm.runInContext('addMechanicFromAdminInput()', addContext);
  assert.deepStrictEqual(addCalls, { add: 1, list: 0, alerts: 0, renders: 0 }, 'stale successful mutation cannot publish, refresh or alert');
  assert.strictEqual(addInput.value, 'Alice', 'stale successful mutation cannot clear current input');
  console.log('PASS workshop reference UI mutation authority ownership');
})().catch(error => { console.error(error); process.exitCode = 1; });
