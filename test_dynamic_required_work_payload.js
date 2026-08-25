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
assert.ok(source.includes('async function refreshSharedVehicleWorkState(vehicle = {})'), 'shared vehicle cards have canonical UUID work-state readback');
assert.ok(source.includes('/rest/v1/vehicle_work_items?select=work_key,required,completed'), 'readback fetches authoritative required-work rows');
assert.ok(source.includes('/rest/v1/vehicle_parts_updates?select=parts_required,parts_ordered,parts_received'), 'readback fetches authoritative Parts rows');
assert.ok(!source.includes('vehicle_parts_updates?select=parts_required,parts_ordered,parts_received,worst_eta,previous_worst_eta'), 'readback does not request a non-existent Parts column');
assert.ok(source.includes('async function authenticatedPartsTarget(key = \'\', selected = null)'), 'Parts actions have canonical shared target fallback');
assert.strictEqual((source.match(/const sharedTarget = await authenticatedPartsTarget\(key, vehicle\);/g) || []).length, 5, 'Ordered, Complete, ETA, STOPPAGE and recovery all resolve canonical shared targets');
assert.ok(source.includes('await refreshSharedVehicleWorkState(sharedVehicle);'), 'Parts actions read back the canonical UUID state');
console.log('Dynamic required-work payload and canonical readback contract passed.');
