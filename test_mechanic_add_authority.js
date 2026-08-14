'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const slice = source.slice(
  source.indexOf('function workshopReferenceAdministratorCanMutate('),
  source.indexOf('async function removeMechanicFromAdminList('),
);
assert(slice.includes('async function addMechanicFromAdminInput()'), 'outer add handler is present');

async function scenario({ role, result, rejects = false }) {
  const input = { value: '  New Mechanic  ', disabled: false, title: '' };
  const calls = { add: [], list: 0, admin: 0, kpis: 0, alerts: [] };
  const service = {
    addTechnician: async name => {
      calls.add.push(name);
      if (rejects) throw new Error('network');
      return result;
    },
    listTechnicians: async force => { assert.strictEqual(force, true); calls.list += 1; },
  };
  const context = {
    window: { PDC_AUTH_CONTEXT: { role }, __workshopReferenceDataService: service, alert: message => calls.alerts.push(message) },
    cleanNavisionText: value => String(value || '').trim(),
    $: selector => selector === '#mechanic-name-input' ? input : null,
    initWorkshopReferenceDataServiceIfAvailable: () => service,
    captureWorkshopReferenceMutation: captured => ({ service: captured }),
    workshopReferenceMutationCurrent: () => true,
    finishWorkshopReferenceMutation: () => {},
    workshopReferenceMutationMessage: (_result, fallback) => fallback,
    renderAdminLists: () => { calls.admin += 1; },
    renderKpis: () => { calls.kpis += 1; },
  };
  vm.runInNewContext(`${slice}\nthis.handler=addMechanicFromAdminInput;`, context);
  const returned = await context.handler();
  return { returned, input, calls };
}

(async () => {
  const denied = await scenario({ role: 'operator', result: { ok: true } });
  assert.strictEqual(denied.returned, false);
  assert.deepStrictEqual(denied.calls.add, [], 'operator denial occurs in the visible outer handler before network dispatch');
  assert.deepStrictEqual(denied.calls.alerts, [], 'operator denial is silent and opens no dialog');

  const success = await scenario({ role: 'administrator', result: { ok: true } });
  assert.strictEqual(success.returned, true);
  assert.deepStrictEqual(success.calls.add, ['New Mechanic']);
  assert.strictEqual(success.calls.list, 1, 'success waits for a final authoritative roster read');
  assert.strictEqual(success.input.value, '', 'input clears only after confirmed success');
  assert.deepStrictEqual([success.calls.admin, success.calls.kpis], [1, 1]);

  const duplicate = await scenario({ role: 'administrator', result: { ok: false, error: 'duplicate_name' } });
  assert.strictEqual(duplicate.returned, false);
  assert.strictEqual(duplicate.calls.list, 0);
  assert.strictEqual(duplicate.input.value, '  New Mechanic  ', 'rejection preserves entered text');
  assert.match(duplicate.calls.alerts[0], /already on the mechanic list/);

  const rejected = await scenario({ role: 'administrator', rejects: true });
  assert.strictEqual(rejected.returned, false);
  assert.strictEqual(rejected.calls.list, 0);
  assert.match(rejected.calls.alerts[0], /Could not add mechanic/);

  console.log('Mechanic add outer-handler authority and rejection behavior passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
