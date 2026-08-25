const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');

function extractFunction(name) {
  const start = source.indexOf(`function ${name}(`);
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

const sideEffects = [];
const upload = { disabled: false, value: 'selected.json' };
const strong = { textContent: 'Restore CRM backup' };
const detail = { textContent: 'Select a backup JSON.' };
const dropZone = {
  classList: { add: value => sideEffects.push(`class:${value}`) },
  querySelector: selector => selector === 'strong' ? strong : detail,
};
const context = vm.createContext({
  vehicleLifecycleSharedModeActive: () => true,
  renderBackupStatus: payload => sideEffects.push(`status:${payload.type}:${payload.message}`),
  $: selector => selector === '#backup-upload' ? upload : selector === '.backup-drop-zone' ? dropZone : null,
  FileReader: function FileReader() { sideEffects.push('file-reader'); },
  localStorage: {
    setItem: () => sideEffects.push('set'),
    removeItem: () => sideEffects.push('remove'),
  },
  window: { confirm: () => { sideEffects.push('confirm'); return true; } },
});

for (const name of ['configureCrmBackupAuthorityUi', 'handleCrmBackupFileSelect', 'restoreCrmBackup']) {
  vm.runInContext(`${extractFunction(name)}; globalThis.${name} = ${name};`, context);
}

context.configureCrmBackupAuthorityUi();
assert.strictEqual(upload.disabled, true, 'shared mode must disable browser-local restore upload');
assert.strictEqual(strong.textContent, 'Restore unavailable in shared mode');
assert.match(detail.textContent, /authoritative/i);

const event = { target: { files: [{ name: 'unsafe.json' }], value: 'unsafe.json' } };
assert.strictEqual(context.handleCrmBackupFileSelect(event), false, 'file selection must fail closed');
assert.strictEqual(event.target.value, '', 'rejected selection must be cleared');
assert.strictEqual(context.restoreCrmBackup(JSON.stringify({ vehicles: [{ stock: 'FAKE-RESTORE' }] }), 'unsafe.json'), false, 'direct restore call must fail closed');
assert.ok(sideEffects.filter(item => item.startsWith('status:error:')).length >= 2, 'fail-closed attempts must show an actionable error');
assert.ok(!sideEffects.includes('file-reader'), 'guard must run before file parsing');
assert.ok(!sideEffects.includes('confirm'), 'guard must run before confirmation');
assert.ok(!sideEffects.includes('set') && !sideEffects.includes('remove'), 'guard must run before browser authority writes');

console.log('PASS: shared lifecycle mode disables and rejects CRM browser-local restore before parsing, confirmation, or storage');
