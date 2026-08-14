'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

function functionSource(name) {
  const start = source.indexOf(`async function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  const nextAsync = source.indexOf('\nasync function ', start + 1);
  const nextPlain = source.indexOf('\nfunction ', start + 1);
  const candidates = [nextAsync, nextPlain].filter(index => index > start);
  return source.slice(start, candidates.length ? Math.min(...candidates) : source.length);
}

const mutationFamilies = [
  ['addMechanicFromAdminInput', ''],
  ['removeMechanicFromAdminList', "'Alice'"],
  ['addSubletProviderFromAdminInput', ''],
  ['removeSubletProviderFromAdminList', "'Provider A'"],
  ['addSalespersonFromAdminInput', ''],
  ['removeSalespersonFromAdminList', "'CW'"],
  ['addMechanicFromPrompt', ''],
  ['addSubletProviderFromPrompt', ''],
];

(async () => {
  for (const [name, args] of mutationFamilies) {
    const fn = functionSource(name);
    const gateIndex = fn.indexOf('workshopReferenceAdministratorCanMutate()');
    const initIndex = fn.indexOf('initWorkshopReferenceDataServiceIfAvailable');
    const captureIndex = fn.indexOf('captureWorkshopReferenceMutation(');
    const promptIndex = fn.indexOf('window.prompt(');
    const confirmIndex = fn.indexOf('window.confirm(');
    assert.ok(gateIndex >= 0, `${name} has an explicit local administrator gate`);
    assert.ok(initIndex < 0 || gateIndex < initIndex, `${name} rejects before service initialization`);
    assert.ok(captureIndex < 0 || gateIndex < captureIndex, `${name} rejects before owner capture`);
    assert.ok(promptIndex < 0 || gateIndex < promptIndex, `${name} rejects before prompt`);
    assert.ok(confirmIndex < 0 || gateIndex < confirmIndex, `${name} rejects before confirm`);
    assert.match(fn, /captureWorkshopReferenceMutation\([\s\S]*?\{ requireAdministrator: true \}\)/, `${name} captures a privileged owner`);

    const calls = { alerts: 0, prompts: 0, confirms: 0, serviceInitializations: 0, rpcs: 0 };
    const context = {
      window: {
        alert() { calls.alerts += 1; },
        prompt() { calls.prompts += 1; return 'should-not-open'; },
        confirm() { calls.confirms += 1; return true; },
      },
      workshopReferenceAdministratorCanMutate: () => false,
      initWorkshopReferenceDataServiceIfAvailable: () => {
        calls.serviceInitializations += 1;
        return new Proxy({}, { get: () => async () => { calls.rpcs += 1; return { ok: true }; } });
      },
      cleanNavisionText: value => String(value || '').trim(),
      $: () => ({ value: 'valid value' }),
      loadMechanicRecords: () => [{ id: 'tech-1', version: 1, name: 'Alice' }],
      loadSubletProviderRecords: () => [{ id: 'provider-1', version: 1, name: 'Provider A' }],
      loadSalespersonRecords: () => [{ id: 'sales-1', version: 1, code: 'CW', name: 'Craig' }],
      normalizeSalespersonRecord: value => value,
      captureWorkshopReferenceMutation: () => { throw new Error('operator reached owner capture'); },
      workshopReferenceMutationCurrent: () => true,
      finishWorkshopReferenceMutation: () => {},
      renderAdminLists: () => {},
      renderKpis: () => {},
      renderDetail: () => {},
    };
    vm.createContext(context);
    vm.runInContext(fn, context, { filename: `${name}.js` });
    const result = await vm.runInContext(`${name}(${args})`, context);
    assert.strictEqual(result, false, `${name} rejects operator locally`);
    assert.deepStrictEqual(calls, { alerts: 1, prompts: 0, confirms: 0, serviceInitializations: 0, rpcs: 0 }, `${name} sends no service/dialog/RPC activity for operator`);
  }

  const renderStart = source.indexOf('function renderAdminLists()');
  const renderEnd = source.indexOf('\nfunction renderHostingSecurityWarning(', renderStart) > renderStart
    ? source.indexOf('\nfunction renderHostingSecurityWarning(', renderStart)
    : source.indexOf('\n// Admin-visible backup status widget', renderStart);
  const renderSource = source.slice(renderStart, renderEnd);
  for (const id of [
    'mechanic-name-input', 'add-mechanic-list-button',
    'sublet-provider-name-input', 'add-sublet-provider-button',
    'salesperson-initials-input', 'salesperson-name-input', 'salesperson-email-input', 'add-salesperson-button'
  ]) {
    assert.ok(renderSource.includes(id), `renderAdminLists owns ${id} administrator-only disabled state`);
  }
  assert.match(renderSource, /data-remove-provider[\s\S]*?canMutate/, 'provider removal controls receive administrator mutability');
  assert.match(renderSource, /data-remove-salesperson[\s\S]*?disabled/, 'salesperson removal controls are disabled for non-administrators');

  console.log('PASS workshop reference local administrator gates across active and dormant UI surfaces');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
