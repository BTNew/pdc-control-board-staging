'use strict';
// r744 (F348): "Import running, part N of M" rides on every board answer; the banner shows and hides from it, no timer.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const api = require('./pdc-email-vehicle-location-service');
const reply = (body, status = 200) => ({ ok: status >= 200 && status < 300, status, json: async () => body });
const v = id => ({ id, operation_lines: [] });
const full = (token, extra = {}) => ({ ok: true, code: 'board', snapshot_token: token, data: { revision: 1, vehicles: [v('a')] }, ...extra });

test('service: import_progress reaches the caller on full, delta and not_modified answers; never on a failure', async () => {
  const seen = []; const responses = [
    reply(full('h:1', { import_progress: { running: true, mode: 'apply', status: 'running', part: 3, n_parts: 40 } })),
    reply({ ok: true, code: 'board', delta: true, snapshot_token: 'h:2', base_token: 'h:1', data: { revision: 2 }, vehicle_ids: ['a'], changed: [], import_progress: { running: true, part: 4, n_parts: 40 } }),
    reply({ ok: true, code: 'not_modified', not_modified: true, snapshot_token: 'h:2', import_progress: { running: false } }),
    reply({ ok: false, code: 'unauthorized', import_progress: { running: true } }, 401),
  ];
  const service = api.createPdcEmailVehicleLocationService({ config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, getAccessToken: () => 'A',
    onImportProgress: p => seen.push(p), fetchImpl: async () => responses.shift() });
  for (let i = 0; i < 4; i += 1) await service.snapshot();
  assert.deepEqual(seen.map(p => [p.running, p.part]), [[true, 3], [true, 4], [false, undefined]]);
});

test('service: a throwing banner never breaks the board read', async () => {
  const service = api.createPdcEmailVehicleLocationService({ config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, getAccessToken: () => 'A',
    onImportProgress: () => { throw new Error('boom'); }, fetchImpl: async () => reply(full('h:1', { import_progress: { running: true } })) });
  const result = await service.snapshot();
  assert.equal(result.ok, true); assert.equal(result.data.vehicles.length, 1);
});

test('website: banner text, hidden when not running, wired into the service, markup and css tagged r744', () => {
  const js = fs.readFileSync('app.js', 'utf8');
  const start = js.indexOf('function renderImportProgressBanner('); const end = js.indexOf('function initEmailVehicleLocationsIfAvailable(');
  assert.ok(start > 0 && end > start);
  const host = { hidden: true, innerHTML: '' };
  const ctx = { document: { getElementById: id => (id === 'pdc-import-banner' ? host : null) }, escapeHtml: s => String(s) };
  vm.runInNewContext(js.slice(start, end) + ';this.f=renderImportProgressBanner;', ctx);
  ctx.f({ running: true, mode: 'apply', status: 'running', part: 7, n_parts: 40 });
  assert.equal(host.hidden, false); assert.match(host.innerHTML, /Import running · part 7 of 40/);
  ctx.f({ running: true, mode: 'apply', status: 'queued', part: 0, n_parts: 40 });
  assert.match(host.innerHTML, /waiting to start/);
  ctx.f({ running: true, mode: 'preview', status: 'running', part: 0, n_parts: 40 });
  assert.match(host.innerHTML, /Import preview running · part 1 of 40/);
  ctx.f({ running: false });
  assert.equal(host.hidden, true); assert.equal(host.innerHTML, '');
  ctx.f(null); assert.equal(host.hidden, true);
  assert.match(js, /onImportProgress: renderImportProgressBanner,/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /<div class="pdc-import-banner" id="pdc-import-banner" role="status" aria-live="polite" hidden><\/div>/);
  assert.match(html, /pdc-email-vehicle-location-service\.js\?[^"]*&amp;r744=2026\.10\.30\.r744"/);
  assert.match(html, /app\.js\?[^"]*&amp;r744=2026\.10\.30\.r744"/);
  assert.match(html, /pdc-revolution-upload\.css\?[^"]*&amp;r744=2026\.10\.30\.r744"/);
  assert.match(fs.readFileSync('pdc-revolution-upload.css', 'utf8'), /\.pdc-import-banner\[hidden\] \{ display: none; \}/);
});

test('migration: progress function staff-invisible, three anchored replaces on the reader, check 461, rollback present', () => {
  const up = fs.readFileSync('supabase/migrations/20261030093000_r744_import_progress_on_the_board.sql', 'utf8');
  assert.match(up, /REVOKE ALL ON FUNCTION public\.pdc_import_progress_744\(\) FROM PUBLIC, anon, authenticated;/);
  assert.match(up, /md5\(v_old\) <> '5347811a3b138b67126da2fb023578bf'/, 'replaces only the body it was written against');
  assert.match(up, /replace\(replace\(replace\(v_old, a1, b1\), a2, b2\), a3, b3\)/);
  assert.match(up, /'import_progress_on_the_board_744', 'F348', 'r744', true, 461,/);
  assert.match(up, /WHERE j\.status IN \('queued', 'running'\) ORDER BY j\.created_at DESC LIMIT 1/);
  assert.doesNotMatch(up, /expected_function_md5 \(/, 'the reader is not pinned');
  assert.ok(fs.existsSync('supabase/rollbacks/20261030093000_r744_import_progress_on_the_board.down.sql'));
});
