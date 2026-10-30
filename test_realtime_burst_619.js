'use strict';
// r619 (F234): import bursts refetch the board at most every 20 s; quiet edits still refresh in 250 ms.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const src = fs.readFileSync('app.js', 'utf8');
const start = src.indexOf('const PDC_BURST_QUIET_MS');
const end = src.indexOf('function createPdcSupabaseRealtimeSubscription(');
const ctx = {};
vm.runInNewContext(src.slice(start, end) + ';this.gate=pdcBurstGate;', ctx);

test('quiet: one event refreshes after 250 ms; burst: spaced 20 s apart, latest payload wins', () => {
  let now = 0; const timers = []; const runs = [];
  const gated = ctx.gate(p => runs.push([now, p]), () => now, (cb, ms) => { timers.push([now + ms, cb]); return timers.length; });
  const tick = to => { timers.sort((a, b) => a[0] - b[0]); while (timers.length && timers[0][0] <= to) { const [at, cb] = timers.shift(); now = at; cb(); } now = to; };
  gated('a'); tick(1000);
  assert.deepEqual(runs, [[250, 'a']]);
  for (let i = 0; i < 10; i += 1) { gated('b' + i); tick(now + 1000); }
  assert.ok(runs.length <= 3, `burst collapsed to ${runs.length} refreshes`);
  tick(now + 30000);
  assert.equal(runs.at(-1)[1], 'b9', 'last event is not lost');
  for (let i = 1; i < runs.length; i += 1) assert.ok(runs[i][0] - runs[i - 1][0] >= 250);
});

test('wired into workshop, navision and vehicle board refreshes; cache bust', () => {
  assert.match(src, /\.on\('postgres_changes', changeSpec, \(typeof pdcBurstGate === 'function' \? pdcBurstGate : f => f\)\(/);
  assert.match(src, /table: 'navision_backend_revision' \}, \(typeof pdcBurstGate === 'function' \? pdcBurstGate : f => f\)\(/);
  const svc = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
  assert.match(svc, /recent\.length > 3 \? Math\.max\(250, 20000 - \(now - lastRun\)\) : 250/);
  const html = fs.readFileSync('index.html', 'utf8');
<<<<<<< HEAD
  assert.match(html, /pdc-email-vehicle-location-service\.js\?[^"]*&amp;r619=2026\.10\.28\.r619(&amp;r642=2026\.10\.28\.r642)?(&amp;r676=2026\.10\.28\.r676)?(&amp;r748=2026\.10\.30\.r748)?(&amp;r7\d\d=2026\.10\.30\.r7\d\d)*"/);
  assert.match(html, /app\.js\?[^"]*&amp;r619=2026\.10\.28\.r619(&amp;r642=2026\.10\.28\.r642)?(&amp;r676=2026\.10\.28\.r676)?(&amp;r679=2026\.10\.29\.r679)?(&amp;r681=2026\.10\.29\.r681)?(&amp;r687=2026\.10\.29\.r687)?(&amp;r683=2026\.10\.29\.r683)?(&amp;r692=2026\.10\.29\.r692)?(&amp;r693=2026\.10\.29\.r693)?(&amp;r698=2026\.10\.29\.r698)?(&amp;r707=2026\.10\.29\.r707)?(&amp;r710=2026\.10\.29\.r710)?(&amp;r720=2026\.10\.29\.r720)?(&amp;r722=2026\.10\.29\.r722)?(&amp;r748=2026\.10\.30\.r748)?(&amp;r7\d\d=2026\.10\.30\.r7\d\d)*"/);
=======
  assert.match(html, /pdc-email-vehicle-location-service\.js\?[^"]*&amp;r619=2026\.10\.28\.r619(&amp;r642=2026\.10\.28\.r642)?(&amp;r676=2026\.10\.28\.r676)?(&amp;r748=2026\.10\.30\.r748)?(&amp;r753=2026\.10\.30\.r753)?"/);
  assert.match(html, /app\.js\?[^"]*&amp;r619=2026\.10\.28\.r619(&amp;r642=2026\.10\.28\.r642)?(&amp;r676=2026\.10\.28\.r676)?(&amp;r679=2026\.10\.29\.r679)?(&amp;r681=2026\.10\.29\.r681)?(&amp;r687=2026\.10\.29\.r687)?(&amp;r683=2026\.10\.29\.r683)?(&amp;r692=2026\.10\.29\.r692)?(&amp;r693=2026\.10\.29\.r693)?(&amp;r698=2026\.10\.29\.r698)?(&amp;r707=2026\.10\.29\.r707)?(&amp;r710=2026\.10\.29\.r710)?(&amp;r720=2026\.10\.29\.r720)?(&amp;r722=2026\.10\.29\.r722)?(&amp;r748=2026\.10\.30\.r748)?(&amp;r753=2026\.10\.30\.r753)?"/);
>>>>>>> origin/main
});
