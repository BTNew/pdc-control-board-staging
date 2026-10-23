/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r495 (F108): Karratha Toyota (Sales) is the Broome Sales page for Navision dealer 14450. Broome stays unchanged.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const branch = require('./sales/sales-branch.js');
const read = file => fs.readFileSync(file, 'utf8');
const MIGRATION = 'supabase/migrations/20261023120000_r495_karratha_sales_branch.sql';
const ROLLBACK = 'supabase/rollbacks/20261023120000_r495_karratha_sales_branch.down.sql';
// Broome's existing recipients are read from email-actions.js (test_broome_sales_dashboard_tools.js pins their values), so this file holds no addresses.
const BROOME_TO = Object.fromEntries([...read('sales/email-actions.js').match(/const broomeRecipients=\{([^}]*)\}/)[1].matchAll(/(\w+):'([^']*)'/g)].map(m => [m[1], m[2]]));

function withBranch(key, fn) {
  const before = globalThis.BROOME_SALES_BRANCH;
  globalThis.BROOME_SALES_BRANCH = { current: () => branch.BRANCHES[key] };
  try { return fn(); } finally { if (before === undefined) delete globalThis.BROOME_SALES_BRANCH; else globalThis.BROOME_SALES_BRANCH = before; }
}

test('branch list: Broome 37047 is the default, Karratha is 14450 and only ?branch=karratha selects it', () => {
  assert.deepEqual(Object.keys(branch.BRANCHES), ['broome', 'karratha']);
  assert.equal(branch.BRANCHES.broome.dealerCode, '37047'); assert.equal(branch.BRANCHES.broome.isDefault, true);
  assert.equal(branch.BRANCHES.karratha.dealerCode, '14450'); assert.equal(branch.BRANCHES.karratha.label, 'Karratha Toyota');
  assert.equal(branch.fromSearch('?branch=karratha'), branch.BRANCHES.karratha);
  assert.equal(branch.fromSearch('?branch=KARRATHA'), branch.BRANCHES.karratha);
  for (const search of ['', '?branch=', '?branch=perth', '?branch=karratha%27--', '?x=karratha', null]) assert.equal(branch.fromSearch(search), branch.BRANCHES.broome, String(search));
});

test('only a non-Broome branch sends the X-PDC-Sales-Branch header', () => {
  assert.equal(branch.requestHeaders(branch.BRANCHES.broome), null);
  assert.deepEqual(branch.requestHeaders(branch.BRANCHES.karratha), { 'x-pdc-sales-branch': 'karratha' });
  assert.equal(branch.requestHeaders({ key: 'karratha', isDefault: false }), null, 'only the frozen branch object');
  assert.equal(branch.requestHeaders(null), null);
});

test('roster: Broome keeps its fixed four; Karratha uses the server mapping, else codes on its own feed', () => {
  assert.deepEqual([...branch.roster(branch.BRANCHES.broome, { branch_roster: ['QZ'] }, [{ salesperson_code: 'QY' }])], ['BG', 'AW', 'PM', 'CW']);
  assert.deepEqual([...branch.roster(branch.BRANCHES.karratha, { branch_roster: [' qk', 'QL', 'QK', ''] }, [])], ['QK', 'QL']);
  assert.deepEqual([...branch.roster(branch.BRANCHES.karratha, {}, [{ salesperson_code: 'QL' }, { salesperson_code: ' qk ' }, { salesperson_code: '' }, {}])], ['QK', 'QL']);
});

test('Website drop-down: PMG and Sales pages list Karratha Toyota (Sales) once; frozen switcher and Dept 135 untouched', () => {
  const option = '<option value="karratha-sales">Karratha Toyota (Sales)</option>';
  for (const file of ['index.html', 'sales/index.html']) {
    const html = read(file);
    assert.equal(html.split(option).length - 1, 1, file);
    assert.ok(html.indexOf('<option value="broome">Broome Toyota (Sales)</option>') < html.indexOf(option), file);
    const sw = html.indexOf('site-switcher.js?v=2026.10.13.135-paused"'), extra = html.indexOf('site-switcher-branches.js?r495=2026.10.23.r495"');
    assert.ok(sw > 0 && extra > sw, file);
  }
  assert.ok(!read('karratha/index.html').includes('karratha-sales'));
  assert.ok(!read('karratha/index.html').includes('site-switcher-branches.js'));
  assert.equal(read('site-switcher.js'), read('karratha/site-switcher.js'));
  const s = read('sales/index.html');
  assert.ok(s.indexOf('src="sales-branch.js?r495=2026.10.23.r495"') < s.indexOf('src="../site-switcher.js'));
  assert.ok(s.indexOf('src="sales-branch.js') < s.indexOf('src="../pdc-auth.js'));
});

function switcherPage({ role = 'administrator', site = 'pmb', branchKey = null, href }) {
  const listeners = {}, winListeners = {}, visits = [];
  const select = { value: site === 'pmb' ? 'pmb' : 'broome', closest: () => ({}), addEventListener: (t, f) => { listeners[t] = f; } };
  const window = {
    PDC_AUTH_CONTEXT: { role }, PDC_SALES_BRANCH: branchKey ? { key: branchKey } : undefined,
    location: { href, assign: url => visits.push(String(url)) },
    addEventListener: (t, f) => { winListeners[t] = f; },
  };
  const document = { body: { dataset: { pdcSite: site === 'pmb' ? undefined : 'broome' } }, getElementById: () => select };
  vm.runInNewContext(read('site-switcher-branches.js'), { window, document, URL });
  return { select, visits, change: () => listeners.change(), ready: () => winListeners['pdc-auth-ready']() };
}

test('switcher add-on: administrators reach Karratha Sales and back; others go nowhere', () => {
  let p = switcherPage({ href: 'https://example.invalid/board/' });
  p.select.value = 'karratha-sales'; p.change();
  assert.deepEqual(p.visits, ['https://example.invalid/board/sales/?branch=karratha']);
  p = switcherPage({ site: 'sales', href: 'https://example.invalid/board/sales/' });
  p.select.value = 'karratha-sales'; p.change();
  assert.deepEqual(p.visits, ['https://example.invalid/board/sales/?branch=karratha']);
  p = switcherPage({ site: 'sales', branchKey: 'karratha', href: 'https://example.invalid/board/sales/?branch=karratha' });
  assert.equal(p.select.value, 'karratha-sales');
  p.select.value = 'broome'; p.change();
  assert.deepEqual(p.visits, ['https://example.invalid/board/sales/']);
  p = switcherPage({ site: 'sales', branchKey: 'karratha', href: 'https://example.invalid/board/sales/?branch=karratha' });
  p.select.value = 'karratha-sales'; p.change(); assert.deepEqual(p.visits, []);
  for (const role of ['salesperson', 'controller', 'fitter']) {
    p = switcherPage({ role, href: 'https://example.invalid/board/' });
    p.select.value = 'karratha-sales'; p.change(); assert.deepEqual(p.visits, [], role);
  }
});

test('pdc-auth sends the branch header only on the Sales page and only that one header', () => {
  const auth = read('pdc-auth.js');
  assert.match(auth, /function salesBranchRequestHeaders\(value\) \{\n    if \(document\.body\?\.dataset\?\.pdcSite !== 'broome'/);
  assert.match(auth, /keys\.length === 1 && keys\[0\] === 'x-pdc-sales-branch' && \/\^\[a-z\]\{3,20\}\$\/\.test\(branch\)/);
  assert.match(auth, /\.\.\.\(salesBranchHeaders \? \{ global: \{ headers: salesBranchHeaders \} \} : \{\}\),/);
  const fn = new Function('document', auth.match(/function salesBranchRequestHeaders[\s\S]*?\n  \}\n/)[0] + 'return salesBranchRequestHeaders;');
  const sales = fn({ body: { dataset: { pdcSite: 'broome' } } }), pmg = fn({ body: { dataset: {} } });
  assert.deepEqual(sales({ 'x-pdc-sales-branch': 'karratha' }), { 'x-pdc-sales-branch': 'karratha' });
  assert.equal(pmg({ 'x-pdc-sales-branch': 'karratha' }), null);
  assert.equal(sales({ 'x-pdc-sales-branch': 'karratha', authorization: 'x' }), null);
  assert.equal(sales({ 'x-pdc-sales-branch': 'Karratha;drop' }), null);
  assert.equal(sales(undefined), null);
});

test('sales.js refuses a page whose branch the server has not switched on, and salespeople adopt their own branch', () => {
  const src = read('sales/sales.js');
  assert.match(src, /Sales is not switched on yet/);
  assert.match(src, /adopt\(/);
  assert.match(src, /dealer_code/);
  for (const file of ['email-actions.js', 'customer-emails.js']) assert.match(read('sales/index.html'), new RegExp(file.replace('.', '\\.') + '\\?[^"]*r495=2026\\.10\\.23\\.r495'));
  assert.doesNotMatch(read('sales/index.html'), /finance-pipeline\.js\?[^"]*r495=/);
  assert.match(read('sales/index.html'), /src="sales\.js\?[^"]*r499b=2026\.10\.23\.r499b[^"]*&amp;r495=2026\.10\.23\.r495&amp;no-yard-flag=2026\.10\.22\.r486"/);
  assert.match(read('sales/sales.js'), /financeSkipped/);
  assert.match(read('sales/sales.js'), /hidesHeadOffice/);
  assert.match(read('sales/sales.js'), /pmbStationsHtml\(row\)/);
});

test('emails: Broome wording and recipients unchanged; Karratha names Karratha with blank recipients', () => {
  delete require.cache[require.resolve('./sales/email-actions.js')];
  const email = require('./sales/email-actions.js');
  const r = { stock: 'TESTK001', order: '0099001', client: 'EXAMPLE', vehicle: 'Example Hilux', kewdale_eta: '2026-11-03' };
  assert.equal(email.template('released', r).to, BROOME_TO.released);
  assert.match(email.template('released', r).body, /^Hi Amy,/);
  assert.match(email.template('released', r).subject, /released to Broome/);
  assert.equal(email.template('tint', r).to, BROOME_TO.tint);
  assert.ok(BROOME_TO.released.includes('@') && BROOME_TO.tint.includes('@'));
  assert.deepEqual(email.typesFor().map(t => t[1]), ['Vehicle Released to Broome', 'Request Update', 'New Vehicle Build', 'Tint PO Email']);
  withBranch('karratha', () => {
    for (const kind of ['released', 'update', 'build', 'tint']) assert.equal(email.template(kind, r).to, '', kind);
    assert.match(email.template('released', r).subject, /released to Karratha/);
    assert.match(email.template('released', r).body, /^Hi,\n/);
    assert.doesNotMatch(email.template('released', r).body, /Broome|Amy/);
    assert.match(email.template('tint', r).body, /^Hi,\n/);
    assert.doesNotMatch(email.template('tint', r).body, /Broome|Jono/);
    assert.equal(email.typesFor()[0][1], 'Vehicle Released to Karratha');
  });
  withBranch('broome', () => assert.equal(email.template('released', r).to, BROOME_TO.released));
});

test('customer emails sign off with the page branch; Broome text unchanged', () => {
  delete require.cache[require.resolve('./sales/customer-emails.js')];
  const customer = require('./sales/customer-emails.js');
  const broome = customer.template('perth_eta').body;
  assert.match(broome, /\{\{salesperson_name\}\}\nBroome Toyota\n/);
  withBranch('karratha', () => {
    const body = customer.template('perth_eta').body;
    assert.match(body, /\{\{salesperson_name\}\}\nKarratha Toyota\n/);
    assert.equal(body.replace('Karratha Toyota', 'Broome Toyota'), broome);
  });
});

test('Karratha finance is skipped; Broome finance groups stay Broome / Port Hedland', () => {
  assert.equal(branch.BRANCHES.karratha.financeSkipped, true);
  assert.equal(branch.BRANCHES.karratha.financeGroups, undefined);
  assert.equal(branch.BRANCHES.karratha.fleetUnderFeedSalesperson, true);
  assert.equal(branch.BRANCHES.karratha.separateFromBroomeInitials, true);
  assert.deepEqual([...branch.BRANCHES.broome.financeGroups], ['Broome', 'Port Hedland']);
  assert.equal(branch.hidesHeadOffice(branch.BRANCHES.karratha, '001234'), true);
  assert.equal(branch.hidesHeadOffice(branch.BRANCHES.karratha, '002345'), true);
  assert.equal(branch.hidesHeadOffice(branch.BRANCHES.karratha, '1234'), true);
  assert.equal(branch.hidesHeadOffice(branch.BRANCHES.karratha, '14450'), false);
  assert.equal(branch.hidesHeadOffice(branch.BRANCHES.broome, '001234'), false);
  delete require.cache[require.resolve('./sales/finance-pipeline.js')];
  const finance = require('./sales/finance-pipeline.js');
  assert.deepEqual([...finance.choices.group_name], ['Broome', 'Port Hedland']);
  withBranch('karratha', () => assert.deepEqual([...finance.choices.group_name], ['Broome', 'Port Hedland']));
  assert.equal(finance.financeGroup('Karratha'), '');
  assert.equal(finance.financeGroup('Broome'), 'broome');
  assert.equal(finance.financeGroup('Port Hedland'), 'pilbara');
  assert.doesNotMatch(read('sales/finance-pipeline.js'), /Karratha/);
});

test('migration and rollback: LF only, guarded, unapplied shape, no deletes and Broome kept as default', () => {
  const sql = read(MIGRATION), down = read(ROLLBACK);
  for (const [name, text] of [['migration', sql], ['rollback', down]]) {
    assert.ok(!text.includes('\r'), name);
    assert.doesNotMatch(text, /vjdtsswhroyguxyfjdkt/, name);
  }
  assert.doesNotMatch(sql, /\bDELETE\s+FROM\b/i);
  assert.doesNotMatch(sql, /c495cf01-1990-4112-a000-000000000001/, 'CF is the existing Broome row, not a new id');
  assert.match(sql, /UPDATE public\.salespeople SET email='clint\.franklin@karrathatoyota\.com\.au'/);
  assert.match(sql, /UPDATE public\.salespeople SET email='scott@karrathatoyota\.com\.au'/);
  assert.match(sql, /clint\.franklin@pmgwa\.com\.au/);
  assert.match(sql, /scott\.lovett@pmgwa\.com\.au/);
  assert.match(sql, /skipped RK Rebecca Kingma/);
  assert.match(down, /SET email='clint\.franklin@pmgwa\.com\.au'/);
  assert.match(down, /SET email='scott\.lovett@pmgwa\.com\.au'/);
  assert.doesNotMatch(down, /c495cf01-1990-4112-a000-000000000001/, 'undo does not delete the existing CF row');
  // Pins, the regression check, the Karratha mapping on the existing CF/SL rows, and unused RK/JS/DB placeholders.
  const deletes = down.match(/DELETE FROM [a-z0-9_.]+ WHERE [^;]*/g) || [];
  assert.equal(deletes.length, 5);
  assert.ok(deletes.some(d => d.startsWith("DELETE FROM pdc_ops.expected_function_md5 WHERE release='r495' AND signature IN (")));
  assert.ok(deletes.some(d => d.startsWith("DELETE FROM pdc_ops.regression_checks WHERE check_name='sales_branch_495'")));
  assert.ok(deletes.some(d => d.startsWith("DELETE FROM pdc_sales_private.salesperson_branches WHERE dealer_code='14450' AND salesperson_id IN (SELECT id FROM public.salespeople")));
  assert.ok(deletes.some(d => d.startsWith("DELETE FROM public.salespeople WHERE id IN ('c4950003-0000-4000-a000-000000000003'")));
  assert.match(sql, /Clint Franklin/);
  assert.match(sql, /Scott Lovett/);
  assert.match(sql, /19901126/);
  assert.match(sql, /19660914/);
  assert.match(sql, /'Later'/);
  assert.match(sql, /Rebecca Kingma/);
  assert.doesNotMatch(sql, /CREATE TABLE pdc_sales_private\.finance_application_branches/);
  assert.doesNotMatch(down, /DROP TABLE pdc_sales_private\.finance_application_branches/);
  assert.match(sql, /release='r495'\)<>12/);
  assert.match(down, /release='r495'\)<>12/);
  assert.match(sql, /r495: already applied/);
  assert.match(sql, /cdsmnqxtyyoeoznmbidd|staging/i);
  assert.match(sql, /\('37047','broome','Broome Toyota'/);
  assert.match(sql, /\('14450','karratha','Karratha Toyota'/);
  assert.match(sql, /'sales_branch_495','F108'/);
  assert.match(sql, /NOT IN \('salesperson','operator'\)/);
  assert.match(sql, /IF r\.role::text='administrator' THEN/);
  assert.match(down, /active=false WHERE dealer_code='14450'/);
  assert.ok(!sql.includes('karratha_135'), 'no Department 135 objects');
});

test('Pages runtime ships the new files', () => {
  const pages = read('scripts/build_pages_runtime.js');
  for (const file of ['site-switcher-branches.js', 'sales/sales-branch.js', 'sales/assets/karratha-toyota-logo.svg']) assert.ok(pages.includes(`'${file}'`), file);
  assert.equal(read('sales/assets/karratha-toyota-logo.svg'), read('karratha/assets/karratha-toyota-logo.svg'));
});
