/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r707 (F318): a bay hidden in Bay Manager (Hoist 01) must leave the Workshop Planner.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const planner = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');

function grab(name) {
  const start = planner.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} present`);
  let depth = 0;
  for (let i = planner.indexOf('{', start); i < planner.length; i += 1) {
    if (planner[i] === '{') depth += 1;
    if (planner[i] === '}' && --depth === 0) return planner.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

function sandbox({ status, plans = [] }) {
  const ctx = {
    workshopSelectedBusGroup: () => null,
    workshopStageBayCount: () => 3,
    workshopBayAvailabilityStatus: (stage, bay) => status[`${stage}:${bay}`] || 'active',
    workshopLoadPlans: () => plans,
  };
  vm.createContext(ctx);
  vm.runInContext(`${grab('workshopVisibleBays')}\nthis.visible = workshopVisibleBays;`, ctx);
  return ctx.visible;
}

test('r707: hidden Hoist 01 is not drawn; Hoist 02 and 03 stay', () => {
  const visible = sandbox({ status: { 'HOIST:1': 'inactive' } });
  assert.deepEqual([...visible('HOIST')], [2, 3]);
});

test('r707: loading or unknown bays stay visible (fail safe)', () => {
  const visible = sandbox({ status: { 'HOIST:1': 'unavailable', 'HOIST:2': 'unknown' } });
  assert.deepEqual([...visible('HOIST')], [1, 2, 3]);
});

test('r707: a hidden bay that still holds open work stays visible', () => {
  const visible = sandbox({ status: { 'HOIST:1': 'inactive' }, plans: [{ stage: 'HOIST', bay: 1, status: 'planned' }] });
  assert.deepEqual([...visible('HOIST')], [1, 2, 3]);
  const done = sandbox({ status: { 'HOIST:1': 'inactive' }, plans: [{ stage: 'HOIST', bay: 1, status: 'completed' }] });
  assert.deepEqual([...done('HOIST')], [2, 3]);
});
