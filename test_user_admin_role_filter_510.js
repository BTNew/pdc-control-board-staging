/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r510 (F123): User Administration Role dropdown. Display only. Filters the rows already
// shown (status tab + Show disabled). Options are the distinct roles in the loaded list.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

function runtime() {
  const froms = [];
  const rpcs = [];
  const nodes = {
    'user-management-role-filter': { innerHTML: '<option value="all">All roles</option>' },
    'user-management-content': host(),
  };
  let changeHandler = null;
  const c = {
    window: {
      PDC_AUTH_CONTEXT: { role: 'administrator' },
      confirm: () => true,
      prompt: () => null,
      PDC_SUPABASE: {
        rpc: async (name, params) => { rpcs.push([name, params]); return {}; },
        from: table => { froms.push(table); throw new Error('no load in this test'); },
      },
    },
    document: { getElementById: id => nodes[id] || null },
    escapeHtml: value => String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'),
    cleanNavisionText: String,
    pdcNotify: () => {},
    backupStatusSharedModeReady: () => true,
    $$: () => [],
    $: selector => {
      if (selector === '#user-management-content') return nodes['user-management-content'];
      if (selector === '#user-management-role-filter') return nodes['user-management-role-filter'];
      return null;
    },
    on: (target, eventName, handler) => { if (target && eventName === 'change') changeHandler = handler; },
  };
  vm.createContext(c);
  vm.runInContext(source.slice(source.indexOf('const USER_MANAGEMENT_STATE ='), source.indexOf('function cancelWorkshopPlannerRender()')), c);
  const start = source.indexOf("on($('#user-management-role-filter'), 'change'");
  const end = source.indexOf('});', start) + 3;
  vm.runInContext(source.slice(start, end), c);
  return { c, nodes, changeHandler, froms, rpcs };
}

const ROWS = [
  { email: 'admin@example.invalid', full_name: 'Ada Admin', account_status: 'approved', role: 'administrator', active: true },
  { email: 'ctrl@example.invalid', full_name: 'Cara Controller', account_status: 'approved', role: 'operator', active: true },
  { email: 'sales@example.invalid', full_name: 'Sam Sales', account_status: 'approved', role: 'salesperson', active: true },
  { email: 'fit@example.invalid', full_name: 'Finn Fitter', account_status: 'approved', role: 'fitter', active: true },
  { email: 'pend@example.invalid', full_name: 'Pat Pending', account_status: 'pending', active: false },
  { email: 'old-fit@example.invalid', full_name: 'Old Fitter', account_status: 'disabled', role: 'fitter', active: false },
  { email: 'old-view@example.invalid', full_name: 'Old Viewer', account_status: 'disabled', role: 'viewer', active: false },
  { email: 'odd@example.invalid', full_name: 'Odd Role', account_status: 'approved', role: 'auditor', active: true },
];

function host() {
  const element = { innerHTML: '', _listener: null, replaceChildren() { element.innerHTML = ''; } };
  element.querySelector = selector => (
    selector === '[data-um-toggle-disabled]' && element.innerHTML.includes('data-um-toggle-disabled')
      ? { addEventListener: (_type, fn) => { element._listener = fn; } }
      : null
  );
  element.clickDisabled = () => element._listener && element._listener();
  return element;
}

function options(markup) {
  return [...String(markup).matchAll(/<option value="([^"]*)"( selected)?>([^<]*)<\/option>/g)]
    .map(match => ({ value: match[1], selected: !!match[2], label: match[3] }));
}

function loadRows(c, rows = ROWS, tab = 'all', showDisabled = false, roleFilter = 'all') {
  vm.runInContext(
    'USER_MANAGEMENT_STATE.rows=ROWS_IN; USER_MANAGEMENT_STATE.tab=TAB_IN; USER_MANAGEMENT_STATE.showDisabled=SHOW_IN; USER_MANAGEMENT_STATE.roleFilter=ROLE_IN;',
    Object.assign(c, { ROWS_IN: rows, TAB_IN: tab, SHOW_IN: showDisabled, ROLE_IN: roleFilter }),
  );
}

test('dropdown lists All roles plus distinct loaded roles, in change-role order, title case', () => {
  const { c } = runtime();
  const listed = options(c.userManagementRoleFilterOptionsHtml(ROWS, 'all'));
  assert.deepEqual(listed.map(option => option.value), ['all', 'viewer', 'operator', 'administrator', 'fitter', 'salesperson', 'auditor']);
  assert.deepEqual(listed.map(option => option.label), ['All roles', 'Viewer', 'Controller', 'Administrator', 'Fitter', 'Salesperson', 'Auditor']);
  assert.deepEqual(listed.filter(option => option.selected).map(option => option.value), ['all']);
  assert.equal(c.userManagementRoleFilterLabel('operator'), 'Controller');
});

test('a blank role does not become an option; an unknown stored role is shown as itself', () => {
  const { c } = runtime();
  const listed = [...c.userManagementDistinctRoles([{ role: '' }, { role: '  ' }, { role: null }, { role: 'fitter' }, { role: 'fitter' }])];
  assert.deepEqual(listed, ['fitter']);
  const selected = options(c.userManagementRoleFilterOptionsHtml([{ role: 'auditor' }], 'auditor'));
  assert.equal(selected.find(option => option.selected).label, 'Auditor');
});

test('All roles keeps the status list, including the hidden-disabled rule', () => {
  const { c } = runtime();
  assert.deepEqual(c.userManagementApplyRoleFilter(c.userManagementVisibleRows(ROWS, 'all', false).rows, 'all').map(row => row.email), [
    'admin@example.invalid', 'ctrl@example.invalid', 'sales@example.invalid', 'fit@example.invalid', 'pend@example.invalid', 'odd@example.invalid',
  ]);
  assert.deepEqual(c.userManagementApplyRoleFilter(c.userManagementVisibleRows(ROWS, 'approved', false).rows, 'operator').map(row => row.email), ['ctrl@example.invalid']);
});

test('rendered All list: Controller shows only controllers and does not reload', () => {
  const { c, nodes, changeHandler, froms, rpcs } = runtime();
  loadRows(c);
  c.renderUserManagementList(nodes['user-management-content']);
  assert.match(nodes['user-management-role-filter'].innerHTML, /<option value="all" selected>All roles<\/option>/);
  assert.match(nodes['user-management-content'].innerHTML, /ctrl@example\.invalid/);
  assert.match(nodes['user-management-content'].innerHTML, /admin@example\.invalid/);
  assert.match(nodes['user-management-content'].innerHTML, /Show disabled \(2\)/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /old-fit@example\.invalid/);
  changeHandler({ target: { value: 'operator' } });
  assert.equal(vm.runInContext('USER_MANAGEMENT_STATE.roleFilter', c), 'operator');
  assert.match(nodes['user-management-content'].innerHTML, /ctrl@example\.invalid/);
  assert.match(nodes['user-management-content'].innerHTML, /Link salesperson record/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /admin@example\.invalid|sales@example\.invalid|fit@example\.invalid|pend@example\.invalid|odd@example\.invalid|old-fit@example\.invalid/);
  assert.match(nodes['user-management-role-filter'].innerHTML, /<option value="operator" selected>Controller<\/option>/);
  assert.deepEqual(froms, []);
  assert.deepEqual(rpcs, []);
});

test('a role that exists only on hidden disabled accounts stays listed and says so', () => {
  const { c, nodes, changeHandler } = runtime();
  loadRows(c);
  c.renderUserManagementList(nodes['user-management-content']);
  assert.match(nodes['user-management-role-filter'].innerHTML, /<option value="viewer">Viewer<\/option>/);
  changeHandler({ target: { value: 'viewer' } });
  assert.match(nodes['user-management-content'].innerHTML, /No viewer accounts/);
  assert.match(nodes['user-management-content'].innerHTML, /1 disabled Viewer account stays hidden until Show disabled is on/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /old-view@example\.invalid/);
  nodes['user-management-content'].clickDisabled();
  assert.match(nodes['user-management-content'].innerHTML, /old-view@example\.invalid/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /old-fit@example\.invalid|ctrl@example\.invalid/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /stay hidden/);
});

test('Fitter on All hides the disabled fitter until Show disabled; Disabled tab lists that fitter only', () => {
  const { c, nodes } = runtime();
  loadRows(c, ROWS, 'all', false, 'fitter');
  c.renderUserManagementList(nodes['user-management-content']);
  assert.match(nodes['user-management-content'].innerHTML, /fit@example\.invalid/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /old-fit@example\.invalid/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /stay hidden/);
  nodes['user-management-content'].clickDisabled();
  assert.match(nodes['user-management-content'].innerHTML, /fit@example\.invalid/);
  assert.match(nodes['user-management-content'].innerHTML, /old-fit@example\.invalid/);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /ctrl@example\.invalid|admin@example\.invalid/);
  loadRows(c, ROWS, 'disabled', false, 'fitter');
  c.renderUserManagementList(nodes['user-management-content']);
  const disabledEmails = [...new Set([...nodes['user-management-content'].innerHTML.matchAll(/[a-z0-9.-]+@example\.invalid/g)].map(match => match[0]))];
  assert.deepEqual(disabledEmails, ['old-fit@example.invalid']);
  assert.doesNotMatch(nodes['user-management-content'].innerHTML, /stay hidden/);
});

test('signing out clears the role filter', () => {
  const { c, nodes } = runtime();
  loadRows(c, ROWS, 'all', false, 'operator');
  nodes['user-management-role-filter'].innerHTML = '<option value="operator" selected>Controller</option>';
  c.window.PDC_AUTH_CONTEXT.role = 'operator';
  c.syncUserManagementAccess();
  assert.equal(vm.runInContext('USER_MANAGEMENT_STATE.roleFilter', c), 'all');
  assert.equal(vm.runInContext('USER_MANAGEMENT_STATE.rows.length', c), 0);
  assert.match(nodes['user-management-role-filter'].innerHTML, /<option value="all" selected>All roles<\/option>/);
});

test('the control sits on the User Administration tab row and app.js is cache-busted; Karratha is untouched', () => {
  assert.match(html, /id="user-management-tabs"[\s\S]*id="user-management-role-filter"[\s\S]*All roles[\s\S]*id="user-management-content"/);
  assert.match(html, /aria-label="Filter by role"/);
  assert.match(html, /app\.js\?[^"]*&amp;r510=2026\.10\.23\.r510(?:&amp;[^"]*)?"/);
  assert.equal(fs.readFileSync('karratha/index.html', 'utf8').includes('user-management-role-filter'), false);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('userManagementRoleFilter'), false);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F123 \| 23 Oct 12:30 \|/m);
  assert.match(fs.readFileSync('release_log/r510/NOTES', 'utf8'), /revert this PR/i);
  assert.match(source, /renderUserManagementList\(host\); \/\/ display only: no reload, no server call/);
});
