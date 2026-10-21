'use strict';
// r409 (F25): the remaining app.js alert() calls are the r407 toast (pdcNotify).
// Errors stay until dismissed; success/notice messages are info toasts that clear
// themselves. Real yes/no confirm() and the typed prompt() steps before
// destructive actions are unchanged, and the one message that must be read
// before the mail app opens stays a blocking alert.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
// Strip line comments that are not inside strings well enough for counting calls:
// only whole-line and trailing `// ...` after code, never inside template text we test.
const code = app.split('\n').map(line => line.replace(/^\s*\/\/.*$/, '')).join('\n');

function fnBody(source, name) {
  const re = new RegExp(`^(?:async )?function ${name}\\(`, 'm');
  const m = re.exec(source); assert.ok(m, name);
  const end = source.indexOf('\n}\n', m.index);
  return source.slice(m.index, end + 2);
}
const calls = (src, re) => (src.match(re) || []).length;

const INFO_MESSAGES = [
  /^\s*else pdcNotify\(message, 'info'\);$/m, // QZ print sent (no summary panel)
  /pdcNotify\(`Signed in as \$\{[^\n]*\}\)\.`, 'info'\);/,
  /pdcNotify\(`PDC operator set to [^\n]*'info'\);/,
  /pdcNotify\(desired \? 'RFT’d recorded\.[^\n]*'info'\);/,
  /pdcNotify\('Transport booking saved\.[^\n]*'info'\);/,
  /pdcNotify\('The original response was lost, but authoritative history confirms that the decision was recorded\.', 'info'\);/,
  /pdcNotify\(`\$\{email\} is already \$\{userManagementRoleLabel\(newRole\)\}\. Nothing changed\.`, 'info'\);/, // r419 no-op role change
  /pdcNotify\(linkMessage, 'info'\);/, // r432 Link salesperson record result
];

test('F25: app.js has exactly one alert() left, the PO-attachment notice before the mail app opens', () => {
  assert.strictEqual(calls(code, /(?<![\w.])alert\(|window\.alert\(/g), 1);
  const body = fnBody(app, 'draftNewVehicleBuildEmail');
  const at = body.indexOf("window.alert('Your email draft will open now.");
  assert.ok(at > 0, 'kept in draftNewVehicleBuildEmail');
  assert.ok(body.indexOf('window.location.href = `mailto:', at) > at, 'and it still comes before the mailto navigation');
});

test('F25: 210 former alert() calls are toasts; exactly eight are info (six + r419 + r432), the rest errors', () => {
  const notify = calls(code, /(?<!function )\bpdcNotify\(/g);
  assert.strictEqual(notify, 238, '25 from r407/r408 + 210 converted + 1 r419 no-op role change notice + 2 r432 Link salesperson record (failure, result)');
  assert.strictEqual(calls(code, /pdcNotify\([^\n]*'info'\);/g), 8);
  for (const re of INFO_MESSAGES) assert.match(app, re);
  // No error message became info by accident: every 'info' toast is in the list above.
  const infoLines = app.split('\n').filter(l => /pdcNotify\(.*'info'\);/.test(l));
  assert.strictEqual(infoLines.length, INFO_MESSAGES.length);
  for (const l of infoLines) assert.ok(INFO_MESSAGES.some(re => re.test(l)), l);
  // Failures / refusals stay errors (spot-check by category).
  for (const text of [
    "pdcNotify(`Action failed: ${error.message || error}`);",                       // user management RPC
    "pdcNotify('Stock Number confirmation did not match exactly. No vehicle was changed.');", // destructive refusal
    "pdcNotify(`Cannot transfer to RFT yet.",                                        // RFT gate (multi-line)
    "pdcNotify('Enter a valid provider email address.');",                          // validation
    "pdcNotify(`Could not print to Zebra via QZ Tray.",                              // device failure
    "pdcNotify('The server outcome is not yet known.",                               // outcome unknown
  ]) assert.ok(app.includes(text), text);
});

test('F25: yes/no confirm() and typed prompt() steps are all kept (43 and 29)', () => {
  // r419 adds two: confirm Approve and confirm Change role in User Admin. r432 adds one: confirm Link salesperson record.
  assert.strictEqual(calls(code, /(?<![\w.])confirm\(|window\.confirm\(/g), 43);
  assert.strictEqual(calls(code, /(?<![\w.])prompt\(|window\.prompt\(/g), 29);
  // Destructive admin actions still ask, and ask before calling the server.
  for (const [fn, rpc] of [['removeVehicle', 'window.__vehicleLifecycleActions'], ['completeVehicleDelete', 'window.__vehicleLifecycleActions.adminCompleteVehicleDelete'], ['runDeletedVehicleAdminAction', 'window.__vehicleLifecycleActions']]) {
    const body = fnBody(app, fn);
    const firstAsk = Math.min(...['window.confirm(', 'window.prompt('].map(s => body.indexOf(s)).filter(i => i >= 0));
    assert.ok(Number.isFinite(firstAsk), `${fn} asks`);
    const call = body.indexOf(rpc, body.indexOf('await', firstAsk));
    assert.ok(call > firstAsk, `${fn}: ask before ${rpc}`);
  }
});

function fakeDom() {
  const byId = {}; const timers = [];
  const make = tag => {
    const el = { tagName: tag, attrs: {}, children: [], listeners: {}, parent: null, textContent: '', className: '', id: '' };
    el.setAttribute = (k, v) => { el.attrs[k] = String(v); };
    el.addEventListener = (k, f) => { el.listeners[k] = f; };
    el.appendChild = c => { c.parent = el; el.children.push(c); if (c.id) byId[c.id] = c; return c; };
    el.append = (...cs) => cs.forEach(el.appendChild);
    el.remove = () => { if (el.parent) el.parent.children = el.parent.children.filter(x => x !== el); el.parent = null; };
    Object.defineProperty(el, 'firstElementChild', { get: () => el.children[0] });
    return el;
  };
  const body = make('body');
  const ctx = { document: { body, createElement: make, getElementById: id => (byId[id] && byId[id].parent ? byId[id] : null) }, console, setTimeout: (f, ms) => timers.push([f, ms]), String };
  vm.createContext(ctx);
  vm.runInContext(fnBody(app, 'pdcNotify'), ctx);
  return { ctx, body, timers };
}

test('F25: errors stay until dismissed, info clears after 8 s, multi-line text is kept as text', () => {
  const { ctx, body, timers } = fakeDom();
  ctx.pdcNotify('Cannot transfer to RFT yet.\n\n• 123 - <b>QC</b>');
  ctx.pdcNotify('Transport booking saved.', 'info');
  const [err, info] = body.children[0].children;
  assert.strictEqual(err.attrs.role, 'alert');
  assert.strictEqual(info.attrs.role, 'status');
  assert.strictEqual(err.children[0].textContent, 'Cannot transfer to RFT yet.\n\n• 123 - <b>QC</b>');
  assert.deepStrictEqual(timers.map(t => t[1]), [8000]);
  timers[0][0]();
  assert.deepStrictEqual(body.children[0].children, [err], 'info cleared, error still shown');
  err.children[1].listeners.click();
  assert.strictEqual(body.children[0].children.length, 0, 'error goes only when dismissed');
  const css = fs.readFileSync('workshop-planner.css', 'utf8');
  assert.match(css, /\.workshop-toast-message \{[^}]*white-space: pre-line/);
});

test('F25: past four toasts the oldest info goes before any error', () => {
  const { ctx, body } = fakeDom();
  ctx.pdcNotify('E1'); ctx.pdcNotify('I1', 'info'); ctx.pdcNotify('E2'); ctx.pdcNotify('E3'); ctx.pdcNotify('E4');
  const texts = () => body.children[0].children.map(t => t.children[0].textContent);
  assert.deepStrictEqual(texts(), ['E1', 'E2', 'E3', 'E4']);
  ctx.pdcNotify('E5');
  assert.deepStrictEqual(texts(), ['E2', 'E3', 'E4', 'E5'], 'only errors left: oldest error goes');
  ctx.pdcNotify('I2', 'info');
  assert.deepStrictEqual(texts(), ['E3', 'E4', 'E5', 'I2'], 'the newest toast is always shown');
});

test('F25: a converted refusal reaches the toast (confirmRftGateOverride)', () => {
  const seen = [];
  const ctx = {
    pdcNotify: (m, tone) => seen.push([m, tone]),
    window: { alert: () => { throw new Error('alert() must not be used'); } },
    vehiclesWithRftGateIssues: v => v.map(vehicle => ({ vehicle, issues: ['QC not signed'] })),
    displayStockNumber: v => v.stock,
  };
  vm.createContext(ctx);
  vm.runInContext(fnBody(app, 'confirmRftGateOverride'), ctx);
  const r = ctx.confirmRftGateOverride([{ stock: '123' }]);
  assert.strictEqual(r.allowed, false);
  assert.strictEqual(seen.length, 1);
  assert.strictEqual(seen[0][1], undefined, 'error tone (default)');
  assert.match(seen[0][0], /^Cannot transfer to RFT yet\.\n\n/);
  assert.match(seen[0][0], /• 123 - QC not signed/);
});

test('r409 cache token: app.js is re-fetched', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  // Later releases may append their own token (r414: qc-photo-readback).
  assert.match(html, /src="app\.js\?[^"]*&amp;r408=2026\.10\.21\.01&amp;r409=2026\.10\.21\.01(&amp;[^"]*)?"/);
});
