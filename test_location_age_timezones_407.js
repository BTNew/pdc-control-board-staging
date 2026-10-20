'use strict';
// r407 (F19): vehicle location age counts Perth calendar days whatever the device's
// timezone. Before r407 daysSinceTimestamp / daysSinceDateValue / daysTo used the
// device's local midnight (setHours(0,0,0,0)), so on a PC not set to Perth the PMB
// and Yard Hold ages were a day out (e.g. 44 instead of 45 days in Los Angeles).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');
const { execFileSync } = require('child_process');

const source = fs.readFileSync('app.js', 'utf8');
const ZONES = ['UTC', 'Australia/Perth', 'Australia/Sydney', 'America/Los_Angeles', 'Pacific/Kiritimati', 'Pacific/Pago_Pago'];

function extract(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  return source.slice(start, source.indexOf('\nfunction ', start + 1));
}

test('test_vehicle_location_age.js passes in every timezone', () => {
  for (const TZ of ZONES) {
    const out = execFileSync(process.execPath, ['test_vehicle_location_age.js'], { env: { ...process.env, TZ }, encoding: 'utf8' });
    assert.match(out, /Vehicle location age and colour sources: PASS/, TZ);
  }
});

test('day counts never use the device clock day', () => {
  for (const name of ['daysSinceTimestamp', 'daysSinceDateValue', 'daysTo']) {
    const body = extract(name);
    assert.doesNotMatch(body, /setHours|getHours|getDate\(\)\s*[-+]|toLocaleDateString\(\)/, name);
    assert.match(body, /\+ 8 \* 3600000\) \/ 86400000/, `${name} uses the Perth day number`);
  }
});

test('Perth midnight edges: same answers in every timezone', () => {
  const script = `
    const fs = require('fs'); const vm = require('vm');
    const source = fs.readFileSync('app.js', 'utf8');
    const out = {};
    for (const now of ['2026-09-15T00:00:30+08:00', '2026-09-15T23:59:30+08:00', '2026-04-05T02:30:00+08:00', '2026-10-04T01:30:00+08:00']) {
      const ctx = { Date: class extends Date { constructor(...a) { super(...(a.length ? a : [now])); } } };
      vm.createContext(ctx);
      for (const name of ['scotEtaOnly', 'parseDateAU', 'parseIsoTimestamp', 'daysSinceTimestamp', 'daysSinceDateValue', 'daysTo']) {
        const s = source.indexOf('function ' + name + '('); vm.runInContext(source.slice(s, source.indexOf('\\nfunction ', s + 1)), ctx);
      }
      out[now] = [ctx.daysSinceTimestamp('2026-09-14T23:59:00+08:00'), ctx.daysSinceTimestamp('2026-09-15T00:01:00+08:00'),
        ctx.daysSinceDateValue('14/09/2026'), ctx.daysSinceDateValue('15/09/2026'), ctx.daysTo('16/09/2026'), ctx.daysTo('01/10/2026'),
        ctx.daysSinceDateValue('bad'), ctx.daysTo('')];
    }
    process.stdout.write(JSON.stringify(out));`;
  const results = ZONES.map(TZ => execFileSync(process.execPath, ['-e', script], { env: { ...process.env, TZ }, encoding: 'utf8' }));
  for (const r of results) assert.strictEqual(r, results[1], 'same as Perth');
  const perth = JSON.parse(results[1]);
  assert.deepStrictEqual(perth['2026-09-15T00:00:30+08:00'], [1, 0, 1, 0, 1, 16, null, null]);
  assert.deepStrictEqual(perth['2026-09-15T23:59:30+08:00'], [1, 0, 1, 0, 1, 16, null, null]);
});
