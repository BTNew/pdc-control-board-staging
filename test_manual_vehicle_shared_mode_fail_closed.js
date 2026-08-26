const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');

function extractFunction(name, prefix = 'function') {
  const start = source.indexOf(`${prefix} ${name}(`);
  assert.notStrictEqual(start, -1, `${name} must exist`);
  const open = source.indexOf('{', start);
  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const effects = [];
const message = { textContent: '' };
const modal = { hidden: true };
const context = vm.createContext({
  vehicleLifecycleSharedModeActive: () => true,
  window: {
    PDC_AUTH_CONTEXT: { role: 'operator' },
    alert: text => effects.push(`alert:${text}`),
  },
  $: selector => selector === '#customer-modal' ? modal : selector === '#new-customer-message' ? message : null,
  FormData: function FormData(form) { return { entries: () => Object.entries(form.fields) }; },
  Object,
  Date,
});

vm.runInContext(`${extractFunction('openCustomerModal')}; globalThis.openCustomerModal = openCustomerModal;`, context);
vm.runInContext(`${extractFunction('addCustomerFromForm', 'async function')}; globalThis.addCustomerFromForm = addCustomerFromForm;`, context);

assert.strictEqual(context.openCustomerModal(), false, 'non-admin shared users must not open the browser-local creator');
assert.strictEqual(modal.hidden, true, 'rejected open must leave the modal closed');
assert.strictEqual(effects.filter(value => value.startsWith('alert:')).length, 1, 'rejected open must explain the fail-closed result');

(async () => {
  const result = await context.addCustomerFromForm({
    preventDefault: () => effects.push('prevent-default'),
    currentTarget: { fields: { stock: 'REAL-123', client: 'Unsafe local row', vehicle: 'Test' } },
  });
  assert.strictEqual(result, false, 'ordinary shared-mode submission must fail closed');
  assert.match(message.textContent, /unavailable in shared mode/i);
  assert.ok(!source.slice(source.indexOf('async function addCustomerFromForm'), source.indexOf('\nfunction normalizePurchaseOrderText')).match(/vehicleLifecycleSharedModeActive\(\)[\s\S]*saveAddedVehicles\(added\)[\s\S]*vehicleLifecycleSharedModeActive\(\)/), 'shared guard must precede the browser-local save path');
  assert.strictEqual(effects.includes('save'), false, 'rejected submission must not write browser authority');
  console.log('PASS: ordinary manual vehicle creation fails closed before browser-local state in shared mode');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});