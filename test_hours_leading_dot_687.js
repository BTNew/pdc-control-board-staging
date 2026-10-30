/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r687 (F297, Craig 29 Oct 2026): ".2" saves as 0.2 in Edit hours and jobs.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const src = fs.readFileSync('app.js', 'utf8');
const rowsBody = src.slice(src.indexOf('function vehicleWorkshopHoursBatchRowsFromPage'), src.indexOf('function vehicleWorkshopHoursBatchValueValid'));
const rowsFromPage = new Function(`${rowsBody}; return vehicleWorkshopHoursBatchRowsFromPage;`)();
const normalize = value => rowsFromPage({ querySelectorAll: () => [{ value, dataset: {} }] })[0].raw;
const validBody = src.slice(src.indexOf('function vehicleWorkshopHoursBatchValueValid'), src.indexOf('function vehicleWorkshopHoursBatchDirty'));
const valid = new Function(`${validBody}; return vehicleWorkshopHoursBatchValueValid;`)();
const row = raw => ({ operationLineId: 'x', lineKey: 'source:00000000-0000-0000-0000-000000000000', expectedLineVersion: 1, raw, estimatedHours: raw === '' ? null : Number(raw) });

test('r687: leading and trailing dots', () => {
  assert.equal(normalize('.2'), '0.2');
  assert.equal(normalize(' .25 '), '0.25');
  assert.equal(normalize('2.'), '2');
  assert.equal(normalize('1.5'), '1.5');
  assert.equal(normalize(''), '');
  assert.equal(normalize('.'), '.');
});

test('r687: normalised values pass the save check; bad ones still fail', () => {
  ['.2', '.25', '2.', '1.5', '0'].forEach(v => assert.equal(valid(row(normalize(v))), true, v));
  ['.', '.255', 'abc', '1000'].forEach(v => assert.equal(valid(row(normalize(v))), false, v));
  assert.match(fs.readFileSync('index.html', 'utf8'), /app\.js\?[^"]*&amp;r687=2026\.10\.29\.r687(&amp;r683=2026\.10\.29\.r683)?(&amp;r692=2026\.10\.29\.r692)?(&amp;r693=2026\.10\.29\.r693)?(&amp;r698=2026\.10\.29\.r698)?(&amp;r707=2026\.10\.29\.r707)?(&amp;r710=2026\.10\.29\.r710)?(&amp;r720=2026\.10\.29\.r720)?(&amp;r722=2026\.10\.29\.r722)?(&amp;r744=2026\.10\.30\.r744)?"/);
});
