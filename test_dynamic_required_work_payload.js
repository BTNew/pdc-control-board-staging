'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('app.js', 'utf8');

function extractFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  const open = (() => {
    let parens = 0;
    for (let i = source.indexOf('(', start); i < source.length; i += 1) {
      if (source[i] === '(') parens += 1;
      else if (source[i] === ')' && --parens === 0) return source.indexOf('{', i);
    }
    return -1;
  })();
  let depth = 0;
  for (let i = open; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const defs = [
  { key: 'tint', requireKey: 'pdcRequiresTint', completeKey: 'pdcCompleteTint' },
  { key: 'hoist', requireKey: 'pdcRequiresHoist', completeKey: 'pdcCompleteHoist' },
  { key: 'fitting', requireKey: 'pdcRequiresFitting', completeKey: 'pdcCompleteFitting' },
  { key: 'parts', requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts' },
];
const context = { PDC_JOB_DEFS: defs, pdcJobTriState: () => 'none' };
vm.runInNewContext([
  extractFunction('pdcWorkStateFromForm'),
  extractFunction('pdcWorkStateMapFromForm'),
  extractFunction('pdcWorkStateUpdatesFromMap'),
].join('\n'), context);

const buttons = new Map([
  ['tint', { dataset: { state: 'required' } }],
  ['hoist', { dataset: { state: 'required' } }],
  ['fitting', { dataset: { state: 'complete' } }],
  ['parts', { dataset: { state: 'none' } }],
]);
const form = {
  querySelector(selector) {
    const match = selector.match(/data-pdc-work-state="([^"]+)"/);
    return buttons.get(match?.[1]) || null;
  },
  elements: { namedItem: () => ({ value: '0' }) },
};
const map = context.pdcWorkStateMapFromForm(form, {}, false);
assert.strictEqual(JSON.stringify(map), JSON.stringify({ tint: 'required', hoist: 'required', fitting: 'complete', parts: 'none' }), 'visual tri-state buttons must drive the submitted work map');
const updates = context.pdcWorkStateUpdatesFromMap(map);
assert.strictEqual(updates.requirementUpdates.pdcRequiresHoist, true);
assert.strictEqual(updates.requirementUpdates.pdcRequiresFitting, true);
assert.strictEqual(updates.completionUpdates.pdcCompleteFitting, true);
assert.strictEqual(updates.requirementUpdates.pdcRequiresParts, false);
assert.ok(source.includes('const workStateMap = pdcWorkStateMapFromForm(form, v, isCompletedVehicle);'), 'vehicle Save uses the visual tri-state map');
console.log('Dynamic required-work payload contract passed.');
