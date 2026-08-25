const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');

function extractFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.notStrictEqual(start, -1, `${name} must exist`);
  const open = source.indexOf(') {', start) + 2;
  assert.ok(open > 1, `${name} opening brace must exist`);
  let depth = 0;
  for (let index = open; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const context = vm.createContext({
  vehicleLifecycleSharedModeActive: () => true,
  // Every legacy dependency is deliberately absent. A guard placed after any
  // lookup, confirmation, audit or local save would therefore throw.
});

for (const name of [
  'renderPmbBayControlSection',
  'savePmbBayDetailForm',
  'completePmbBayWork',
]) {
  vm.runInContext(`${extractFunction(name)}; globalThis.${name} = ${name};`, context);
}

assert.strictEqual(context.renderPmbBayControlSection({}), '', 'shared mode must not render legacy PMB bay mutation controls');
assert.strictEqual(context.savePmbBayDetailForm({}, {}), false, 'shared mode must reject direct legacy PMB bay saves');
assert.strictEqual(context.completePmbBayWork('HERMES-TEST-001', 'FITTING'), false, 'shared mode must reject direct legacy PMB completion');

console.log('PASS: shared lifecycle mode hides and rejects legacy browser-local PMB bay mutations before side effects');