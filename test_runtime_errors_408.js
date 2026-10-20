'use strict';
// r408 second-pass sweep (F22-F24): things that were still erroring on staging
// or in the browser after r407.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const auth = fs.readFileSync('pdc-auth.js', 'utf8');
const code = s => s.replace(/\/\/[^\n]*/g, '');

function fnBody(source, name) {
  const re = new RegExp(`^(?:async )?function ${name}\\(`, 'm');
  const m = re.exec(source); assert.ok(m, name);
  const end = source.indexOf('\n}\n', m.index);
  return source.slice(m.index, end + 2);
}
function constLine(source, name) {
  const m = new RegExp(`^(?:const|let) ${name} = [^\\n]*$`, 'm').exec(source); assert.ok(m, name);
  return m[0];
}

// --- F22 -------------------------------------------------------------------
test('F22: record_pdc_login is not sent for Fitters bay accounts', () => {
  const at = auth.indexOf("state.client.rpc('record_pdc_login'");
  assert.ok(at > 0);
  assert.strictEqual(auth.split("rpc('record_pdc_login'").length, 2, 'exactly one call site');
  const guard = auth.lastIndexOf('if (', at);
  assert.match(auth.slice(guard, at), /^if \(String\(role\?\.role \|\| ''\)\.trim\(\)\.toLowerCase\(\) !== 'fitter'\) \{\s*$/);
  // The guarded call runs only after the application unlocked.
  assert.ok(auth.lastIndexOf('if (!await unlockApplication(session, role, authGeneration, roleLookupGeneration)) return;', at) > 0);
  // Other approved roles still record their sign-in.
  for (const [r, sends] of [['fitter', false], ['Fitter ', false], ['administrator', true], ['operator', true], ['viewer', true], ['salesperson', true]]) {
    const role = { role: r };
    assert.strictEqual(String(role?.role || '').trim().toLowerCase() !== 'fitter', sends, r);
  }
});

// --- F23 -------------------------------------------------------------------
function runtimeContext() {
  const toasts = []; const banners = []; const logged = [];
  const target = { insertAdjacentHTML: (_where, html) => banners.push(html) };
  const ctx = {
    console: { error: (...a) => logged.push(a) },
    document: { querySelector: () => target },
    escapeHtml: s => String(s),
    pdcNotify: (m, tone = 'error') => toasts.push([m, tone]),
    Date, Map, Set, String,
  };
  vm.createContext(ctx);
  vm.runInContext([
    constLine(app, 'pdcStartupBannerMessages'), constLine(app, 'pdcRuntimeErrorLastShown'),
    constLine(app, 'PDC_RUNTIME_ERROR_REPEAT_MS'), 'var pdcStartupComplete = false;',
    fnBody(app, 'showStartupError'), fnBody(app, 'pdcIsAbortError'), fnBody(app, 'reportPdcRuntimeError'),
    'this.setComplete = v => { pdcStartupComplete = v; };',
  ].join('\n'), ctx);
  return { ctx, toasts, banners, logged };
}

test('F23: global error handlers go through reportPdcRuntimeError, and init marks start-up complete', () => {
  const tail = code(app.slice(app.lastIndexOf("if (document.readyState === 'loading') {")));
  assert.match(tail, /on\(window, 'error', event => \{\s*if \(event\?\.error\) reportPdcRuntimeError\(event\.error\);\s*\}\);/);
  assert.match(tail, /on\(window, 'unhandledrejection', event => \{\s*reportPdcRuntimeError\(event\?\.reason \|\| new Error\('Unhandled promise rejection'\)\);\s*\}\);/);
  assert.strictEqual((tail.match(/finally \{ pdcStartupComplete = true; \}/g) || []).length, 2);
  assert.doesNotMatch(tail.slice(tail.indexOf("on(window, 'error'")), /showStartupError/);
});

test('F23: before start-up completes an error still shows the banner, once per message', () => {
  const { ctx, toasts, banners } = runtimeContext();
  ctx.reportPdcRuntimeError(new Error('init exploded'));
  ctx.reportPdcRuntimeError(new Error('init exploded'));
  ctx.reportPdcRuntimeError(new Error('second problem'));
  assert.strictEqual(banners.length, 2, 'no stacking of identical banners');
  assert.match(banners[0], /Website error/);
  assert.strictEqual(toasts.length, 0);
});

test('F23: after start-up an error is one dismissable toast per message per 30 s, never a banner', () => {
  const { ctx, toasts, banners, logged } = runtimeContext();
  ctx.setComplete(true);
  ctx.reportPdcRuntimeError(new Error('Failed to fetch'), 1000);
  ctx.reportPdcRuntimeError(new Error('Failed to fetch'), 5000);
  ctx.reportPdcRuntimeError(new Error('Other'), 6000);
  ctx.reportPdcRuntimeError(new Error('Failed to fetch'), 31001);
  ctx.reportPdcRuntimeError('plain string reason', 32000);
  assert.strictEqual(banners.length, 0);
  assert.deepStrictEqual(toasts.map(t => t[0]), [
    'Something went wrong: Failed to fetch. If this keeps happening, refresh the page.',
    'Something went wrong: Other. If this keeps happening, refresh the page.',
    'Something went wrong: Failed to fetch. If this keeps happening, refresh the page.',
    'Something went wrong: plain string reason. If this keeps happening, refresh the page.',
  ]);
  assert.ok(toasts.every(t => t[1] === 'error'));
  assert.strictEqual(logged.length, 5, 'every error is still logged to the console');
});

test('F23: aborted requests are not reported', () => {
  const { ctx, toasts, banners } = runtimeContext();
  ctx.setComplete(true);
  ctx.reportPdcRuntimeError({ name: 'AbortError', message: 'The user aborted a request.' });
  ctx.reportPdcRuntimeError({ name: 'DOMException', code: 20, message: 'aborted' });
  assert.strictEqual(toasts.length + banners.length, 0);
});

// --- F24 -------------------------------------------------------------------
const ADMIN_CHAINS = [
  ['removeMechanic', 'service.setTechnicianActive(', 'remove mechanic'],
  ['addSubletProvider', 'service.addSubletProvider(entered, email)', 'add provider'],
  ['removeSubletProvider', 'service.setSubletProviderActive(', 'remove provider'],
  ['saveSalesperson', 'request.then(result =>', 'save salesperson'],
  ['removeSalesperson', 'service.setSalespersonActive(', 'remove salesperson'],
  ['addSubletProviderFromVehicle', 'service.addSubletProvider(entered)', 'add provider'],
];

test('F24: every admin list add/remove chain ends in .catch(pdcAdminListRequestFailed(...))', () => {
  const src = code(app);
  for (const [label, start, action] of ADMIN_CHAINS) {
    const i = src.indexOf(start); assert.ok(i > 0, label);
    const j = src.indexOf('\n  })', i); assert.ok(j > i, label);
    const after = src.slice(j + 5, j + 5 + 80);
    assert.ok(after.startsWith(`.catch(pdcAdminListRequestFailed('${action}'));`), `${label}: ${after}`);
  }
  // No other `service.<x>(...).then(` in app.js is left without a catch.
  const re = /service\.\w+\([^;]*?\)\.then\(/g; let m; const bare = [];
  while ((m = re.exec(src))) {
    const close = /\n\s*\}\)/g; close.lastIndex = m.index; const c = close.exec(src);
    if (!c || !src.slice(c.index + c[0].length, c.index + c[0].length + 8).startsWith('.catch(')) bare.push(src.slice(m.index, m.index + 60));
  }
  assert.deepStrictEqual(bare, []);
});

test('F24: a rejected admin request shows a specific, non-blocking error', () => {
  const toasts = []; const logged = [];
  const ctx = { pdcNotify: (m, t) => toasts.push([m, t]), console: { error: (...a) => logged.push(a) }, String };
  vm.createContext(ctx);
  vm.runInContext(fnBody(app, 'pdcAdminListRequestFailed'), ctx);
  ctx.pdcAdminListRequestFailed('remove mechanic')(new TypeError('Failed to fetch'));
  ctx.pdcAdminListRequestFailed('add provider')(undefined);
  assert.deepStrictEqual(toasts, [
    ['Could not remove mechanic (Failed to fetch). Check your connection and try again.', undefined],
    ['Could not add provider. Check your connection and try again.', undefined],
  ]);
  assert.strictEqual(logged.length, 2);
});

test('F24: the reference-data service really can reject on a network failure (why the catch is needed)', async () => {
  const src = fs.readFileSync('workshop-reference-data-service.js', 'utf8');
  const rpc = src.slice(src.indexOf('async function rpc(accessToken, name, params, options = {}) {'));
  const head = rpc.slice(0, rpc.indexOf('\n  }\n') + 4);
  assert.match(head, /const res = await fetchFn\(/);
  assert.doesNotMatch(head.slice(0, head.indexOf('let body')), /try \{/, 'fetch failure is not caught in rpc()');
});

test('r408 cache tokens: app.js and pdc-auth.js are re-fetched', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  const sales = fs.readFileSync('sales/index.html', 'utf8');
  assert.match(html, /src="app\.js\?[^"]*&amp;r407=2026\.10\.21\.01&amp;r408=2026\.10\.21\.01(?:&amp;[^"]*)?"/);
  assert.match(html, /src="pdc-auth\.js\?[^"]*&amp;r403=2026\.10\.21\.01&amp;r408=2026\.10\.21\.01"/);
  assert.match(sales, /src="\.\.\/pdc-auth\.js\?[^"]*&amp;r403=2026\.10\.21\.01&amp;r408=2026\.10\.21\.01"/);
});
