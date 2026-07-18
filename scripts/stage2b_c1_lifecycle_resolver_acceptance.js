'use strict';

const fs = require('fs');
const { chromium } = require('playwright-core');

const URL = process.env.PDC_STAGING_URL || 'https://btnew.github.io/pdc-control-board-staging/';
const PROD_REF = 'vjdtsswhroyguxyfjdkt';
const EXPECTED_REF = 'cdsmnqxtyyoeoznmbidd';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = process.env.PDC_C1_ACCEPTANCE_OUTPUT || '_staging_test_tools/c1_acceptance_result.json';
const fixture = {
  id: required('C1_ACCEPT_ID'),
  stock: required('C1_ACCEPT_STOCK'),
  token: required('C1_ACCEPT_TOKEN'),
};

function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}

function account(prefix) {
  return { email: required(`${prefix}_EMAIL`), password: required(`${prefix}_PASSWORD`) };
}

async function login(page, credentials) {
  await page.goto(`${URL}?c1=${Date.now()}`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.locator('#pdc-login-email').fill(credentials.email);
  await page.locator('#pdc-login-password').fill(credentials.password);
  await page.locator('#pdc-password-form button[type=submit]').click();
  await page.waitForFunction(() => {
    const shell = document.getElementById('app-shell');
    return shell && !shell.hasAttribute('inert') && shell.getAttribute('aria-hidden') !== 'true';
  }, null, { timeout: 30000 });
  await page.waitForFunction(() => (
    window.PDC_AUTH_CONTEXT?.role
    && window.__vehicleLifecycleIdentityResolver
    && typeof window.__vehicleLifecycleIdentityResolver.resolve === 'function'
  ), null, { timeout: 30000 });
  await page.waitForFunction(() => {
    const channels = window.PDC_SUPABASE?.getChannels?.() || [];
    return channels.some(channel => channel.topic === 'realtime:pdc-reference-vehicle_lifecycle_resolver_revision' && channel.state === 'joined');
  }, null, { timeout: 30000 });
}

async function storageSnapshot(page) {
  return page.evaluate(() => Object.keys(localStorage)
    .filter(key => key.startsWith('vehicleTrackingCore'))
    .sort()
    .map(key => [key, localStorage.getItem(key)]));
}

async function resolve(page, stock) {
  return page.evaluate(async value => {
    return window.__vehicleLifecycleIdentityResolver.resolve({ p_stock_number: value }, { reason: 'c1-browser-acceptance' });
  }, stock);
}

function assertResolvedProjection(result, expectedId) {
  if (result?.outcome !== 'resolved' || result.vehicleId !== expectedId) {
    throw new Error(`resolver did not resolve expected fixture: ${JSON.stringify(result)}`);
  }
  const expected = ['isArchived', 'lifecycleState', 'matchedBy', 'outcome', 'qcCompletedAt', 'resolverRevision', 'vehicleId', 'version'];
  const actual = Object.keys(result).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`resolver projection was not narrow: ${JSON.stringify(actual)}`);
  }
}

(async () => {
  if (!URL.includes('pdc-control-board-staging') || URL.includes(PROD_REF)) throw new Error('staging URL guard failed');
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const adminContext = await browser.newContext();
  const controllerContext = await browser.newContext();
  const adminPage = await adminContext.newPage();
  const controllerPage = await controllerContext.newPage();
  const productionRequests = [];
  const directVehicleReads = [];
  const resolverRequests = { admin: 0, controller: 0 };
  for (const [name, page] of [['admin', adminPage], ['controller', controllerPage]]) {
    page.on('request', request => {
      const url = request.url();
      if (url.includes(PROD_REF)) productionRequests.push(url);
      if (url.includes('/rest/v1/vehicles?')) directVehicleReads.push(url);
      if (url.includes('/rest/v1/rpc/resolve_vehicle_lifecycle_identity')) resolverRequests[name] += 1;
    });
  }

  try {
    await Promise.all([
      login(adminPage, account('PDC_STAGING_ADMIN')),
      login(controllerPage, account('PDC_STAGING_CONTROLLER_A')),
    ]);

    const refs = await Promise.all([
      adminPage.evaluate(() => window.PDC_SUPABASE_CONFIG?.projectRef),
      controllerPage.evaluate(() => window.PDC_SUPABASE_CONFIG?.projectRef),
    ]);
    if (refs.some(ref => ref !== EXPECTED_REF)) throw new Error(`wrong Supabase ref: ${JSON.stringify(refs)}`);

    const roles = await Promise.all([
      adminPage.evaluate(() => window.PDC_AUTH_CONTEXT?.role),
      controllerPage.evaluate(() => window.PDC_AUTH_CONTEXT?.role),
    ]);
    if (roles[0] !== 'administrator' || !['operator', 'controller'].includes(roles[1])) {
      throw new Error(`unexpected acceptance roles: ${JSON.stringify(roles)}`);
    }

    const rollbackFlags = await Promise.all([
      adminPage.evaluate(() => window.PDC_SUPABASE_CONFIG?.vehicleLifecycle?.resolverRollbackDirectRead),
      controllerPage.evaluate(() => window.PDC_SUPABASE_CONFIG?.vehicleLifecycle?.resolverRollbackDirectRead),
    ]);
    if (rollbackFlags.some(Boolean)) throw new Error('rollback direct-read flag is enabled');

    const beforeStorage = await Promise.all([storageSnapshot(adminPage), storageSnapshot(controllerPage)]);
    const before = await Promise.all([resolve(adminPage, fixture.stock), resolve(controllerPage, fixture.stock)]);
    before.forEach(result => assertResolvedProjection(result, fixture.id));
    if (before[0].version !== before[1].version) throw new Error('sessions did not start on the same version');

    const editResult = await adminPage.evaluate(async args => {
      const token = await getPdcSupabaseAccessToken();
      const client = createWorkshopSupabaseClient(window.PDC_SUPABASE_CONFIG);
      return client.rpc(token, 'edit_vehicle_master', {
        p_vehicle_id: args.id,
        p_expected_version: args.version,
        p_changes: { key_number: `C1-RT-${args.token}-V2` },
        p_reason: 'Stage 2B C1 two-session Realtime acceptance',
        p_idempotency_key: `C1-RT-${args.token}`,
      });
    }, { id: fixture.id, version: before[0].version, token: fixture.token });
    if (!editResult?.ok || editResult?.body?.ok !== true) {
      throw new Error(`administrator synthetic edit failed: ${JSON.stringify(editResult)}`);
    }

    await Promise.all([adminPage, controllerPage].map(page => page.waitForFunction(({ stock, version }) => {
      const latest = window.__vehicleLifecycleIdentityResolver?.getLatest?.({ p_stock_number: stock });
      return latest?.outcome === 'resolved' && Number(latest.version) > Number(version);
    }, { stock: fixture.stock, version: before[0].version }, { timeout: 30000 })));

    const refreshed = await Promise.all([
      adminPage.evaluate(stock => window.__vehicleLifecycleIdentityResolver.getLatest({ p_stock_number: stock }), fixture.stock),
      controllerPage.evaluate(stock => window.__vehicleLifecycleIdentityResolver.getLatest({ p_stock_number: stock }), fixture.stock),
    ]);
    refreshed.forEach(result => assertResolvedProjection(result, fixture.id));
    if (refreshed.some(result => result.version !== before[0].version + 1)) {
      throw new Error(`stale/torn version refresh: ${JSON.stringify(refreshed)}`);
    }

    const afterStorage = await Promise.all([storageSnapshot(adminPage), storageSnapshot(controllerPage)]);
    if (JSON.stringify(beforeStorage) !== JSON.stringify(afterStorage)) throw new Error('browser-local authority stores changed');
    if (productionRequests.length) throw new Error('production request observed');
    if (directVehicleReads.length) throw new Error('direct vehicles read observed while rollback flag was false');
    if (resolverRequests.admin < 2 || resolverRequests.controller < 2) {
      throw new Error(`resolver did not refresh in both sessions: ${JSON.stringify(resolverRequests)}`);
    }
    const rollbackDiagnostics = await Promise.all([
      adminPage.evaluate(() => (window.__vehicleLifecycleResolverDiagnostics || []).filter(item => item.mode === 'staging_direct_read')),
      controllerPage.evaluate(() => (window.__vehicleLifecycleResolverDiagnostics || []).filter(item => item.mode === 'staging_direct_read')),
    ]);
    if (rollbackDiagnostics.some(items => items.length)) throw new Error('rollback path diagnostic observed unexpectedly');

    const result = {
      ok: true,
      projectRef: EXPECTED_REF,
      roles,
      vehicleId: fixture.id,
      initialVersion: before[0].version,
      refreshedVersion: refreshed[0].version,
      resolverRevision: refreshed[0].resolverRevision,
      resolverRequests,
      directVehicleReads: 0,
      productionRequests: 0,
      rollbackFlag: false,
      browserLocalStoresUnchanged: true,
      sessions: 2,
    };
    fs.writeFileSync(OUT, JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result));
  } finally {
    await adminContext.close();
    await controllerContext.close();
    await browser.close();
  }
})().catch(error => {
  console.error(error?.stack || String(error));
  process.exitCode = 1;
});
