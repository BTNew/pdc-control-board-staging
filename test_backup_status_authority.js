'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8').replace(/\r\n/g, '\n');

function extract(startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start, `extractable block: ${startMarker}`);
  return source.slice(start, end);
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

function queryFor(promise) {
  return {
    select() { return this; },
    eq() { return this; },
    order() { return this; },
    limit() { return promise; },
  };
}

(async () => {
  const block = extract('function backupStatusSharedModeReady()', '// ---------------------------------------------------------------------');
  let role = 'administrator';
  let principal = 'admin-a';
  let authorityGeneration = 1;
  let currentClient;
  let runsResult;
  let restoreResult;

  function makeClient(label) {
    return {
      label,
      from(table) {
        if (table === 'backup_runs') return queryFor(runsResult);
        if (table === 'restore_test_runs') return queryFor(restoreResult);
        throw new Error(`unexpected table ${table}`);
      },
    };
  }

  const panel = { hidden: true };
  const host = {
    innerHTML: '',
    replaceChildren() { this.innerHTML = ''; },
  };
  const context = vm.createContext({
    window: {
      PDC_SUPABASE_CONFIG: { projectRef: 'staging-project' },
      PDC_AUTH_CONTEXT: { userId: principal, role },
    },
    PRODUCTION_SUPABASE_PROJECT_REF: 'production-project',
    workshopSharedModeEnabled: () => true,
    $: selector => selector === '#backup-status-panel' ? panel : (selector === '#backup-status-content' ? host : null),
    escapeHtml: value => String(value),
    captureUserManagementAuthority() {
      if (role !== 'administrator' || !currentClient || !principal) return null;
      return { client: currentClient, identity: `${principal}\nadministrator`, authorityGeneration };
    },
    userManagementAuthorityCurrent(authority) {
      return Boolean(
        authority
        && role === 'administrator'
        && authority.client === currentClient
        && authority.identity === `${principal}\nadministrator`
        && authority.authorityGeneration === authorityGeneration
      );
    },
  });
  vm.runInContext(block, context);

  assert.match(source, /function resetBackupStatusAuthorityState\(\)[\s\S]*?BACKUP_STATUS_REQUEST_GENERATION \+= 1;[\s\S]*?panel\.hidden = true;[\s\S]*?host\.replaceChildren\(\)/, 'backup status authority reset helper must revoke generation and clear rendered DOM');
  assert.match(source, /window\.addEventListener\?\.\('pdc-auth-ready',[\s\S]*?resetBackupStatusAuthorityState\(\)/, 'auth-ready must synchronously revoke rendered backup status');
  assert.match(source, /window\.addEventListener\?\.\('pdc-auth-token-changed',[\s\S]*?resetBackupStatusAuthorityState\(\)/, 'token changes must synchronously revoke rendered backup status');
  assert.match(source, /window\.addEventListener\?\.\('pdc-auth-locked',[\s\S]*?resetBackupStatusAuthorityState\(\)/, 'lockout must synchronously revoke rendered backup status');

  // Demotion while the first query is pending must suppress both success and
  // any later administrator-only detail publication.
  currentClient = makeClient('A');
  context.window.PDC_SUPABASE = currentClient;
  runsResult = deferred();
  restoreResult = Promise.resolve({ data: [], error: null });
  const afterFirstAwait = vm.runInContext('renderBackupStatusPanel()', context);
  role = 'viewer';
  context.window.PDC_AUTH_CONTEXT = { userId: principal, role };
  runsResult.resolve({
    data: [{ status: 'failed', started_at: '2026-08-14T00:00:00Z', error_message: 'private failure A' }],
    error: null,
  });
  assert.strictEqual(await afterFirstAwait, false, 'demotion after first await must supersede backup rendering');
  assert.strictEqual(panel.hidden, true, 'demotion after first await must hide the administrator panel');
  assert.ok(!host.innerHTML.includes('private failure A'), 'demotion after first await must suppress private failure details');

  // Demotion while the second query is pending must also suppress publication.
  role = 'administrator';
  context.window.PDC_AUTH_CONTEXT = { userId: principal, role };
  runsResult = Promise.resolve({ data: [{ status: 'success', started_at: '2026-08-14T00:00:00Z' }], error: null });
  restoreResult = deferred();
  const afterSecondAwait = vm.runInContext('renderBackupStatusPanel()', context);
  await Promise.resolve();
  role = 'viewer';
  context.window.PDC_AUTH_CONTEXT = { userId: principal, role };
  restoreResult.resolve({ data: [{ status: 'failed', started_at: '2026-08-14T01:00:00Z', row_count_matches: false }], error: null });
  assert.strictEqual(await afterSecondAwait, false, 'demotion after second await must supersede backup rendering');
  assert.strictEqual(panel.hidden, true, 'demotion after second await must hide the administrator panel');
  assert.ok(!host.innerHTML.includes('FAILED'), 'demotion after second await must suppress restore-test detail');

  // A stale backend error must not leak after authority revocation.
  role = 'administrator';
  context.window.PDC_AUTH_CONTEXT = { userId: principal, role };
  runsResult = deferred();
  restoreResult = Promise.resolve({ data: [], error: null });
  const staleError = vm.runInContext('renderBackupStatusPanel()', context);
  role = 'viewer';
  context.window.PDC_AUTH_CONTEXT = { userId: principal, role };
  runsResult.resolve({ data: null, error: new Error('private backup backend detail') });
  assert.strictEqual(await staleError, false, 'stale backup error must be discarded');
  assert.ok(!host.innerHTML.includes('private backup backend detail'), 'stale backup errors must not publish after demotion');

  // Principal/client B may complete a replacement request while A is still
  // pending. A's late result must not hide or overwrite B's current panel.
  role = 'administrator';
  principal = 'admin-a';
  context.window.PDC_AUTH_CONTEXT = { userId: principal, role };
  const clientA = makeClient('A2');
  currentClient = clientA;
  context.window.PDC_SUPABASE = currentClient;
  runsResult = deferred();
  const oldRuns = runsResult;
  restoreResult = Promise.resolve({ data: [], error: null });
  const requestA = vm.runInContext('renderBackupStatusPanel()', context);

  principal = 'admin-b';
  authorityGeneration += 1;
  context.window.PDC_AUTH_CONTEXT = { userId: principal, role };
  currentClient = makeClient('B');
  context.window.PDC_SUPABASE = currentClient;
  runsResult = Promise.resolve({ data: [{ status: 'success', started_at: '2026-08-14T02:00:00Z', file_size_bytes: 2048 }], error: null });
  restoreResult = Promise.resolve({ data: [{ status: 'success', started_at: '2026-08-14T03:00:00Z', row_count_matches: true }], error: null });
  assert.strictEqual(await vm.runInContext('renderBackupStatusPanel()', context), true, 'replacement principal B may publish current backup state');
  const replacementHtml = host.innerHTML;
  assert.ok(replacementHtml.includes('2.0 KB'), 'replacement principal B result rendered');

  oldRuns.resolve({ data: [{ status: 'failed', started_at: '2026-08-14T04:00:00Z', error_message: 'old principal private detail' }], error: null });
  assert.strictEqual(await requestA, false, 'old principal A completion must be stale');
  assert.strictEqual(panel.hidden, false, 'old A completion must not hide B panel');
  assert.strictEqual(host.innerHTML, replacementHtml, 'old A completion must not overwrite B DOM');

  console.log('Backup Status post-await authority and replacement isolation checks passed');
})().catch(error => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
