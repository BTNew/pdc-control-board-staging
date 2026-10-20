'use strict';
// r403: a `return` inside `finally` silently throws away any error raised in
// the try/catch above it (eslint no-unsafe-finally). The vehicle card identity
// check (app.js) and three New Vehicles saves (pdc-new-vehicles.js) did this.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const FILES = ['app.js', 'pdc-new-vehicles.js', 'workshop-planner.js', 'pdc-auth.js', 'workshop-data-service.js', 'canonical-entry.js'];

// Returns the body of every finally block, with nested function bodies removed.
function finallyBodies(src) {
  const out = [];
  const re = /\bfinally\s*\{/g;
  let m;
  while ((m = re.exec(src))) {
    let i = m.index + m[0].length, depth = 1;
    const start = i;
    for (; i < src.length && depth; i += 1) {
      if (src[i] === '{') depth += 1;
      else if (src[i] === '}') depth -= 1;
    }
    out.push({ at: src.slice(0, m.index).split('\n').length, body: src.slice(start, i - 1) });
  }
  return out;
}
function stripNestedFunctions(body) {
  let text = body.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|\s)\/\/[^\n]*/g, '$1'), changed = true;
  while (changed) {
    changed = false;
    text = text.replace(/(?:function\b[^{]*|=>\s*)\{[^{}]*\}/g, () => { changed = true; return ''; });
  }
  return text;
}

test('no return statement inside a finally block in the board scripts', () => {
  const offenders = [];
  for (const file of FILES) {
    for (const { at, body } of finallyBodies(fs.readFileSync(file, 'utf8'))) {
      if (/\breturn\b/.test(stripNestedFunctions(body))) offenders.push(`${file}:${at}`);
    }
  }
  assert.deepEqual(offenders, []);
});

test('the scanner catches the old pattern', () => {
  const old = 'try { a(); } finally {if(s===g){saving=false;if(applyPendingDepartment())return;render();}}';
  assert.equal(finallyBodies(old).some(({ body }) => /\breturn\b/.test(stripNestedFunctions(body))), true);
  const ok = 'try { a(); } finally { list.forEach(x => { return x; }); }';
  assert.equal(finallyBodies(ok).some(({ body }) => /\breturn\b/.test(stripNestedFunctions(body))), false);
});

test('an error in the vehicle card identity check is logged, and the card still resets', async () => {
  const app = fs.readFileSync('app.js', 'utf8');
  const at = app.indexOf("console.error('Vehicle card identity check failed.', error);");
  assert.ok(at > 0);
  const block = app.slice(at - 200, at + 400);
  assert.match(block, /\} catch \(error\) \{/);
  assert.match(block, /finally \{\s*if \(app\.vehicleModalIdentity === identityAtOpen && !ready\) \{/);
  // Behaviour: same shape run in isolation.
  const ctx = { logged: [], reset: 0 };
  vm.createContext(ctx);
  await vm.runInContext(`(async () => { let ready = false; const same = true;
    try { throw new Error('lookup failed'); }
    catch (error) { logged.push(error.message); }
    finally { if (same && !ready) { reset += 1; } } })()`, ctx);
  assert.deepEqual([...ctx.logged], ['lookup failed']);
  assert.equal(ctx.reset, 1);
});

test('New Vehicles saves render unless the department switch takes over', () => {
  const src = fs.readFileSync('pdc-new-vehicles.js', 'utf8');
  assert.equal(src.includes('if(applyPendingDepartment())return;'), false);
  assert.equal((src.match(/if\(!applyPendingDepartment\(\)\)\s*\{/g) || []).length, 3);
});
