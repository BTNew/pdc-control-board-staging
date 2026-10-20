'use strict';
// r407 (F20, audit #5): planner messages are a non-blocking, accessible toast, not
// window.alert(). alert() froze the whole page (and any in-flight render or drag) until
// it was dismissed, was not announced politely, and stacked when several failed at once.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');
const code = s => s.replace(/\/\/[^\n]*/g, '');

function fnBody(source, name) {
  const re = new RegExp(`^(?:async )?function ${name}\\(`, 'm');
  const m = re.exec(source); assert.ok(m, name);
  const end = source.indexOf('\n}\n', m.index);
  return source.slice(m.index, end + 2);
}

function fakeDom() {
  const byId = {};
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
  return { body, document: { body, createElement: make, getElementById: id => (byId[id] && byId[id].parent ? byId[id] : null) } };
}

test('workshop-planner.js has no alert() left and keeps its eight real yes/no confirms', () => {
  assert.doesNotMatch(code(planner), /\balert\s*\(/);
  assert.strictEqual((code(planner).match(/window\.confirm\(/g) || []).length, 8);
  assert.ok((planner.match(/workshopNotify\(/g) || []).length >= 87);
});

test('workshopNotify is an accessible, non-blocking toast', () => {
  const { body, document } = fakeDom();
  const timers = [];
  const ctx = { document, console, setTimeout: (f, ms) => timers.push([f, ms]) };
  vm.createContext(ctx);
  vm.runInContext(fnBody(planner, 'workshopNotify'), ctx);
  ctx.workshopNotify('Bay 3 <b>already</b> has a booking.');
  ctx.workshopNotify('Date moved to the next workday.', 'info');
  const region = body.children[0];
  assert.strictEqual(region.id, 'workshop-toast-region');
  const [err, info] = region.children;
  assert.deepStrictEqual([err.attrs.role, err.attrs['aria-live'], err.attrs['aria-atomic']], ['alert', 'assertive', 'true']);
  assert.deepStrictEqual([info.attrs.role, info.attrs['aria-live']], ['status', 'polite']);
  assert.strictEqual(err.children[0].textContent, 'Bay 3 <b>already</b> has a booking.', 'text, never HTML');
  assert.strictEqual(err.children[1].attrs['aria-label'], 'Dismiss message');
  assert.strictEqual(timers.length, 1, 'only info clears itself; errors stay until dismissed');
  assert.strictEqual(timers[0][1], 8000);
  err.children[1].listeners.click();
  assert.strictEqual(region.children.length, 1);
  for (let i = 0; i < 6; i++) ctx.workshopNotify(`Error ${i}`);
  assert.strictEqual(region.children.length, 4, 'at most four on screen');
  ctx.workshopNotify('   ');
  assert.strictEqual(region.children.length, 4, 'blank messages ignored');
  assert.doesNotMatch(fnBody(planner, 'workshopNotify'), /innerHTML|alert\(/);
});

test('without a DOM it never throws', () => {
  const warned = [];
  const ctx = { console: { warn: m => warned.push(m) } };
  vm.createContext(ctx);
  vm.runInContext(fnBody(planner, 'workshopNotify'), ctx);
  ctx.workshopNotify('No bay.');
  assert.deepStrictEqual(warned, ['No bay.']);
});

test('app.js drag, schedule and QC action error paths use the toast', () => {
  assert.match(app, /^function pdcNotify\(message, tone = 'error'\)/m);
  for (const name of ['movePmbVehicleToStage', 'assignPmbVehicleToBay', 'moveVehicleToNextPmbStageFromBay',
    'updatePmbBayScheduleStart', 'updatePmbBayHours', 'savePmbBayDetailForm',
    'completeVehicleQualityControl', 'markVehicleReadyForQualityControl', 'qcPageSignoff']) {
    const body = fnBody(app, name);
    assert.doesNotMatch(body, /window\.alert\(/, name);
    assert.match(body, /pdcNotify\(/, name);
  }
  const p = fnBody(app, 'pdcNotify');
  assert.match(p, /'workshop-toast-region'/);
  assert.match(p, /role', kind === 'info' \? 'status' : 'alert'/);
  assert.doesNotMatch(p, /innerHTML/);
});

test('toast styles ship with the planner stylesheet', () => {
  for (const sel of ['.workshop-toast-region', '.workshop-toast.is-error', '.workshop-toast.is-info', '.workshop-toast-close:focus-visible']) assert.ok(css.includes(sel), sel);
  assert.match(css, /white-space: pre-line/);
});

test('browsers fetch the r407 planner, stylesheet and app.js (cache tokens)', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /workshop-planner\.css\?[^"]*&amp;r407=2026\.10\.21\.01"/);
  assert.match(html, /app\.js\?[^"]*r406=2026\.10\.21\.01&amp;r407=2026\.10\.21\.01/);
  assert.strictEqual((app.match(/workshop-planner\.js\?[^`]*&r407=2026\.10\.21\.01&/g) || []).length, 2);
});
