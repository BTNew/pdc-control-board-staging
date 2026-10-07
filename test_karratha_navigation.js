'use strict';
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, 'site-switcher.js'), 'utf8');
const root = 'https://btnew.github.io/pdc-control-board-staging/';
const routes = { pmb: '', karratha: 'karratha/', broome: 'sales/' };
function page(role, site) {
  const handlers = {}, events = {}, visits = [], label = {};
  const select = { closest: () => label, addEventListener: (name, fn) => events[name] = fn };
  const window = { PDC_AUTH_CONTEXT: role ? {role} : null, location: {href: root + routes[site] + '#/dashboard', assign: url => visits.push(String(url))}, addEventListener: (name, fn) => handlers[name] = fn };
  const document = { body: {dataset: {pdcSite: site === 'broome' ? 'broome' : 'pmb'}}, getElementById: () => select };
  vm.runInNewContext(source, {window, document, URL});
  return {window, handlers, events, visits, label, select};
}
test('administrator can switch between all three sites from every site', () => {
  for (const current of Object.keys(routes)) for (const destination of Object.keys(routes)) {
    const p = page('administrator', current);
    assert.equal(p.label.hidden, false); assert.equal(p.select.disabled, false);
    assert.equal(p.select.value, current);
    p.select.value = destination; p.events.change();
    assert.deepEqual(p.visits, destination === current ? [] : [root + routes[destination]]);
  }
});
test('existing role and session guard protects navigation on all sites', () => {
  for (const site of Object.keys(routes)) {
    for (const role of [null, 'controller', 'salesperson', 'viewer']) {
      const p = page(role, site); assert.equal(p.label.hidden, true); assert.equal(p.select.disabled, true);
      p.select.value = 'broome'; p.events.change(); assert.equal(p.visits.length, 0);
    }
    const p = page('administrator', site); p.window.PDC_AUTH_CONTEXT = null; p.handlers['pdc-auth-locked']();
    assert.equal(p.label.hidden, true); assert.equal(p.select.value, site);
  }
});
test('one Website control sits under each sidebar logo before navigation', () => {
  for (const file of ['index.html', 'karratha/index.html', 'sales/index.html']) {
    const html = fs.readFileSync(path.join(__dirname, file), 'utf8');
    const sidebar = html.slice(html.indexOf('<aside'), html.indexOf('</aside>'));
    assert.equal(html.split('id="pdc-site-switcher"').length - 1, 1, file);
    assert.ok(sidebar.indexOf('data-site-switcher') > sidebar.indexOf('<img'), file);
    assert.ok(sidebar.indexOf('data-site-switcher') < sidebar.indexOf('<nav'), file);
    for (const label of ['PMG (Dept 138/139)', 'Karratha Toyota (135)', 'Broome Toyota (Sales)']) assert.ok(sidebar.includes(label));
    assert.ok(!html.includes('src="pd-department-navigation'));
  }
});
test('navigation performs no board writes and Karratha freshness coordinator remains', () => {
  for (const call of ['.rpc(', '.from(', 'localStorage', 'sessionStorage', 'fetch(']) assert.ok(!source.includes(call));
  assert.equal(source, fs.readFileSync(path.join(__dirname, 'karratha/site-switcher.js'), 'utf8'));
  const own = fs.readFileSync(path.join(__dirname, 'karratha/pd135-navigation.js'), 'utf8');
  assert.ok(!own.includes('PD Departments'));
  assert.ok(own.includes('createNavisionBackendService')); assert.ok(own.includes('visibleSnapshot'));
});
