'use strict';

const assert = require('assert');
const { buildNavisionVinParts, navisionSourceIdentity } = require('./navision-vin');

const planned = buildNavisionVinParts(' MR0 ', '', '');
assert.deepStrictEqual(planned, {
  wmi: 'MR0',
  vdsNumber: '',
  frame: '',
  vin: '',
}, 'a WMI-only planned vehicle must preserve components without creating an effective VIN');

const complete = buildNavisionVinParts('JTM', '5CAAVX', '0D014977');
assert.deepStrictEqual(complete, {
  wmi: 'JTM',
  vdsNumber: '5CAAVX',
  frame: '0D014977',
  vin: 'JTM5CAAVX0D014977',
}, 'three complete source components must produce the normalized 17-character VIN');

const forbidden = buildNavisionVinParts('JTM', '5CAIVX', '0D014977');
assert.strictEqual(forbidden.vin, '', 'VIN letters I, O and Q must remain invalid');

const beforeAllocation = navisionSourceIdentity('13092228', planned.vin, 2);
const afterAllocation = navisionSourceIdentity('13092228', complete.vin, 2);
assert.strictEqual(beforeAllocation, 'navision-13092228');
assert.strictEqual(afterAllocation, beforeAllocation, 'later VIN allocation must retain the stable Stock identity');

console.log('Navision VIN normalization and stable Stock identity: PASS');