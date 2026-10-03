'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, 'pd-department-navigation.js'), 'utf8');
function page(role, site) {
  const handlers = {}, elements = [], visits = [];
  const website = { insertAdjacentElement(position, element) { assert.equal(position, 'afterend'); elements.push(element); } };
  function element(tag) { return { tag, dataset: {}, children: [], events: {}, append(...children) { this.children.push(...children); }, setAttribute(name, value) { this[name] = value; }, addEventListener(name, handler) { this.events[name] = handler; } }; }
  const window = { PDC_AUTH_CONTEXT: role ? {role} : null, location: {href: 'https://btnew.github.io/pdc-control-board-staging/#/dashboard', assign(url) { visits.push(String(url)); }}, addEventListener(name, handler) { handlers[name] = handler; } };
  const document = {body: {dataset: {pdcSite: site}}, querySelector() { return website; }, createElement: element};
  vm.runInNewContext(source, {window, document, URL});
  return {window, elements, visits, handlers, select: elements[0]?.children[1]};
}
test('PMB administrator has a navigation-only department selector', () => {
  const p = page('administrator');
  assert.equal(p.elements[0].hidden, false);
  assert.equal(p.select.disabled, false);
  assert.deepEqual(p.select.children.map(x => x.value), ['pmb', 'karratha']);
  p.select.value = 'karratha'; p.select.events.change();
  assert.deepEqual(p.visits, ['https://btnew.github.io/pdc-control-board-staging/karratha/']);
});
test('other PMB roles and a locked session cannot navigate through the control', () => {
  for (const role of [null, 'controller', 'salesperson', 'viewer']) {
    const p = page(role); assert.equal(p.elements[0].hidden, true); assert.equal(p.select.disabled, true);
    p.select.value = 'karratha'; p.select.events.change(); assert.equal(p.visits.length, 0);
  }
  const p = page('administrator'); p.window.PDC_AUTH_CONTEXT = null; p.handlers['pdc-auth-locked']();
  assert.equal(p.elements[0].hidden, true); assert.equal(p.select.value, 'pmb');
});
test('Sales keeps its existing navigation and PMB operational code is not imported', () => {
  assert.equal(page('administrator', 'broome').elements.length, 0);
  assert.doesNotMatch(source, /\.rpc\(|\.from\(|localStorage|sessionStorage|fetch\(|workshop|pdc_user_roles|vehicles/);
  const html = fs.readFileSync(require('node:path').join(__dirname, 'index.html'), 'utf8');
  assert.equal((html.match(/src="pd-department-navigation\.js\?v=2026\.10\.03\.01"/g) || []).length, 1);
});
