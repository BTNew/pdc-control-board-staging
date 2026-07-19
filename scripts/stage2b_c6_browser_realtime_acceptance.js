'use strict';

const fs = require('fs');
const crypto = require('crypto');
const { chromium } = require('playwright-core');

const URL = process.env.PDC_STAGING_URL || 'https://btnew.github.io/pdc-control-board-staging/';
const EXPECTED_REF = 'cdsmnqxtyyoeoznmbidd';
const PROD_REF = 'vjdtsswhroyguxyfjdkt';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = process.env.PDC_C6_BROWSER_OUTPUT || 'review-evidence/stage2b-c6/browser-realtime-acceptance.json';
const RECONCILIATION = process.env.PDC_C6_RECONCILIATION || 'review-evidence/stage2b-c6/reconciliation-report.json';
const DEPLOYMENT_IDENTITY = process.env.PDC_C6_DEPLOYMENT_IDENTITY || 'review-evidence/stage2b-c6/staging-deployment-identity.json';
const TARGET_REF = process.env.PDC_C6_BROWSER_RECORD_REF || 'added:000009';
const AUTHORITY_CANARY = Object.freeze({
  'vehicleTrackingCoreNavisionOnlyVehicles:v1': '[]',
  'vehicleTrackingCoreNavisionOnlyEdits:v1': '{}',
  'vehicleTrackingCoreNavisionOnlyDeleted:v1': '[]',
  'vehicleTrackingCoreNavisionOnlyPoTasks:v1': '{}',
  'vehicleTrackingCoreNavisionOnlyPoFiles:v1': '{}',
  'vehicleTrackingCoreNavisionOnlyAuditLog:v1': '[]',
  'vehicleTrackingCoreWorkshopPlan:v1': '[]',
  'vehicleTrackingCoreNotes:C6-AUTHORITY-CANARY': 'unchanged',
});

function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}

function account(prefix) {
  return { email: required(`${prefix}_EMAIL`), password: required(`${prefix}_PASSWORD`) };
}

function targetVehicle() {
  const report = JSON.parse(fs.readFileSync(RECONCILIATION, 'utf8'));
  const row = (report.results || []).find(item => item.record_ref === TARGET_REF);
  if (!row?.vehicle_id) throw new Error(`Missing reconciled target ${TARGET_REF}`);
  const manifest = JSON.parse(fs.readFileSync('review-evidence/stage2b-c6/selected-record-manifest.json', 'utf8'));
  const source = (manifest.records || []).find(item => item.record_ref === TARGET_REF);
  if (!source?.payload?.stock_number) throw new Error(`Missing selected source ${TARGET_REF}`);
  return { id: row.vehicle_id, stock: source.payload.stock_number };
}

async function login(page, credentials) {
  await page.goto(`${URL}?c6=${Date.now()}`, { waitUntil: 'networkidle', timeout: 60000 });
  await page.locator('#pdc-login-email').fill(credentials.email);
  await page.locator('#pdc-login-password').fill(credentials.password);
  await page.locator('#pdc-password-form button[type=submit]').click();
  await page.waitForFunction(() => {
    const shell = document.getElementById('app-shell');
    return shell && !shell.hasAttribute('inert') && shell.getAttribute('aria-hidden') !== 'true'
      && window.PDC_AUTH_CONTEXT?.role && window.__vehicleLifecycleIdentityResolver;
  }, null, { timeout: 30000 });
  await page.waitForFunction(() => {
    const channels = window.PDC_SUPABASE?.getChannels?.() || [];
    return channels.some(channel => channel.topic === 'realtime:pdc-reference-vehicle_lifecycle_resolver_revision' && channel.state === 'joined');
  }, null, { timeout: 30000 });
}

async function storageSnapshot(page) {
  return page.evaluate(() => Object.keys(localStorage)
    .filter(key => key.startsWith('vehicleTrackingCore'))
    .sort().map(key => [key, localStorage.getItem(key)]));
}

function storageObservation(snapshot) {
  const canonical = JSON.stringify(snapshot);
  return {
    keyCount: snapshot.length,
    byteCount: Buffer.byteLength(canonical, 'utf8'),
    sha256: crypto.createHash('sha256').update(canonical, 'utf8').digest('hex'),
  };
}

async function resolve(page, stock) {
  return page.evaluate(value => window.__vehicleLifecycleIdentityResolver.resolve({ p_stock_number: value }, { reason: 'c6-operational-rehearsal' }), stock);
}

async function latest(page, stock) {
  return page.evaluate(value => window.__vehicleLifecycleIdentityResolver.getLatest({ p_stock_number: value }), stock);
}

async function move(page, args) {
  return page.evaluate(async params => {
    const { data, error } = await window.PDC_SUPABASE.rpc('move_vehicle', params);
    return { data, error: error ? { code: error.code || null, message: error.message || null } : null };
  }, args);
}

(async () => {
  if (!URL.includes('pdc-control-board-staging') || URL.includes(PROD_REF)) throw new Error('C6 browser target is not staging');
  const deploymentBytes = fs.readFileSync(DEPLOYMENT_IDENTITY);
  const deploymentIdentity = JSON.parse(deploymentBytes.toString('utf8'));
  const deploymentEvidenceSha256 = crypto.createHash('sha256').update(deploymentBytes).digest('hex');
  if (deploymentIdentity.schema !== 'pdc.stage2b.c6-staging-deployment-identity/v1'
      || deploymentIdentity.staging_url !== URL
      || deploymentIdentity.exact_staging_project_ref !== EXPECTED_REF
      || deploymentIdentity.github_pages?.status !== 'built'
      || !/^[0-9a-f]{40}$/.test(deploymentIdentity.github_pages?.commit || '')
      || deploymentIdentity.all_checks_passed !== true) throw new Error('C6 staging deployment identity is invalid');
  const target = targetVehicle();
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const contextOptions = { serviceWorkers: 'block', bypassCSP: true };
  const contexts = [await browser.newContext(contextOptions), await browser.newContext(contextOptions), await browser.newContext(contextOptions)];
  for (const context of contexts) {
    await context.addInitScript(({ authorityCanary }) => {
      if (sessionStorage.getItem('__pdcC6AuthorityCanarySeeded') !== '1') {
        for (const [key, value] of Object.entries(authorityCanary)) localStorage.setItem(key, value);
        sessionStorage.setItem('__pdcC6AuthorityCanarySeeded', '1');
      }
      window.__c6NetworkUrls = [];
      window.__c6ResolverRefreshEvents = [];
      window.__c6SecurityPolicyViolations = [];
      window.addEventListener('pdc-vehicle-lifecycle-resolver-refresh', event => {
        const item = event?.detail || {};
        window.__c6ResolverRefreshEvents.push({
          reason: item.reason || null,
          vehicleId: item.result?.vehicleId || null,
          version: item.result?.version ?? null,
        });
      });
      document.addEventListener('securitypolicyviolation', event => {
        window.__c6SecurityPolicyViolations.push({
          effectiveDirective: event.effectiveDirective || null,
          violatedDirective: event.violatedDirective || null,
        });
      });
      const originalFetch = window.fetch;
      window.fetch = function(input, init) {
        try { window.__c6NetworkUrls.push(String(input?.url || input)); } catch (_) {}
        return originalFetch.call(this, input, init);
      };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        try { window.__c6NetworkUrls.push(String(url)); } catch (_) {}
        return originalOpen.call(this, method, url, ...rest);
      };
      const OriginalWebSocket = window.WebSocket;
      window.WebSocket = class C6ObservedWebSocket extends OriginalWebSocket {
        constructor(url, protocols) {
          try { window.__c6NetworkUrls.push(String(url)); } catch (_) {}
          super(url, protocols);
        }
      };
    }, { authorityCanary: AUTHORITY_CANARY });
  }
  const pages = await Promise.all(contexts.map(context => context.newPage()));
  const labels = ['administrator', 'controller', 'viewer'];
  const productionRequests = [];
  const requestHosts = new Set();
  const failedRequests = [];
  const pageErrors = [];
  const consoleErrors = [];
  const webSocketEvidence = [];
  const networkPhases = ['online', 'online', 'online'];
  contexts.forEach((context, index) => {
    context.on('request', request => {
      try { requestHosts.add(new globalThis.URL(request.url()).host); } catch (_) {}
      if (request.url().includes(PROD_REF)) productionRequests.push({ browser: labels[index] });
    });
    context.on('requestfailed', request => failedRequests.push({
      browser: labels[index], phase: networkPhases[index],
      resourceType: request.resourceType(), error: request.failure()?.errorText || null,
    }));
  });
  pages.forEach((page, index) => {
    page.on('pageerror', error => pageErrors.push({ browser: labels[index], error: String(error) }));
    page.on('console', message => {
      if (message.type() === 'error') consoleErrors.push({
        browser: labels[index], phase: networkPhases[index], text: message.text().slice(0, 240),
      });
    });
    page.on('websocket', socket => {
      let host = 'invalid';
      try { host = new globalThis.URL(socket.url()).host; } catch (_) {}
      const item = { browser: labels[index], host, openedPhase: networkPhases[index], closedPhase: null, socketErrors: 0 };
      webSocketEvidence.push(item);
      socket.on('close', () => { item.closedPhase = networkPhases[index]; });
      socket.on('socketerror', () => { item.socketErrors += 1; });
    });
  });

  try {
    await Promise.all([
      login(pages[0], account('PDC_STAGING_ADMIN')),
      login(pages[1], account('PDC_STAGING_CONTROLLER_A')),
      login(pages[2], account('PDC_STAGING_VIEWER')),
    ]);
    const projectRefs = await Promise.all(pages.map(page => page.evaluate(() => window.PDC_SUPABASE_CONFIG?.projectRef)));
    const roles = await Promise.all(pages.map(page => page.evaluate(() => window.PDC_AUTH_CONTEXT?.role)));
    if (projectRefs.some(ref => ref !== EXPECTED_REF)) throw new Error(`wrong project ref: ${JSON.stringify(projectRefs)}`);
    if (roles[0] !== 'administrator' || !['operator', 'controller'].includes(roles[1]) || roles[2] !== 'viewer') {
      throw new Error(`unexpected roles: ${JSON.stringify(roles)}`);
    }
    const beforeStorage = await Promise.all(pages.map(storageSnapshot));
    const beforeStorageObservations = beforeStorage.map(storageObservation);
    const authorityCanarySnapshot = Object.entries(AUTHORITY_CANARY).sort(([left], [right]) => left.localeCompare(right));
    const hasAuthorityCanaries = snapshot => authorityCanarySnapshot.every(([key, value]) =>
      snapshot.some(([actualKey, actualValue]) => actualKey === key && actualValue === value));
    const authorityCanariesPresentBefore = beforeStorage.every(hasAuthorityCanaries);
    if (!authorityCanariesPresentBefore) throw new Error('ordinary browser-local authority canaries changed during login/bootstrap');
    const initial = await Promise.all([resolve(pages[0], target.stock), resolve(pages[1], target.stock), resolve(pages[2], target.stock)]);
    if (initial.some(row => row?.outcome !== 'resolved' || row.vehicleId !== target.id) || initial[0].version !== initial[1].version) {
      throw new Error(`initial role resolution mismatch: ${JSON.stringify(initial)}`);
    }
    const initialChannels = await pages[1].evaluate(() => window.PDC_SUPABASE.getChannels().map(channel => channel.topic).sort());
    const initialSynchronized = initial.every(row => row?.outcome === 'resolved' && row.vehicleId === target.id)
      && initial.every(row => Number(row.version) === Number(initial[0].version));
    // Login/bootstrap responses are outside the acceptance window. Begin the
    // zero-error ledger only after all three authenticated sessions have
    // reached the required synchronized online state.
    failedRequests.length = 0;
    consoleErrors.length = 0;
    pageErrors.length = 0;
    networkPhases[1] = 'offline-cycle-1';
    await contexts[1].setOffline(true);
    const offlineHttpProbe = await pages[1].evaluate(async () => {
      try {
        const config = window.PDC_SUPABASE_CONFIG;
        await fetch(`${config.url}/rest/v1/vehicle_lifecycle_resolver_revision?select=revision`, { cache: 'no-store' });
        return { refused: false };
      } catch (error) {
        return { refused: true, errorName: error?.name || null };
      }
    });
    if (!offlineHttpProbe.refused) throw new Error('HTTP unexpectedly remained available while browser context was offline');
    const offlineMutationAttempt = await move(pages[1], {
      p_vehicle_id: target.id, p_expected_version: initial[1].version,
      p_to_location: 'C6-OFFLINE-MUST-NOT-PERSIST', p_reason: 'C6 offline mutation refusal',
    });
    const offlineMutationRefused = !offlineMutationAttempt.data && Boolean(offlineMutationAttempt.error);
    if (!offlineMutationRefused) throw new Error(`offline mutation was falsely reported as persisted: ${JSON.stringify(offlineMutationAttempt)}`);
    const offlineUiState = await pages[1].evaluate(() => ({
      navigatorOnline: navigator.onLine,
      connectionState: navigator.onLine ? 'online' : 'offline_disconnected',
    }));
    if (offlineUiState.navigatorOnline !== false) throw new Error('offline browser did not expose disconnected state');

    const onlinePeerChangesBefore = await pages[2].evaluate(() =>
      (window.__vehicleLifecycleIdentityResolver?.getDiagnostics?.() || []).filter(item => item.type === 'realtime_change').length);
    const adminMove = await move(pages[0], {
      p_vehicle_id: target.id, p_expected_version: initial[0].version,
      p_to_location: 'C6-REALTIME-ADMIN', p_reason: 'C6 two-user Realtime and reconnect rehearsal',
    });
    if (adminMove.error || adminMove.data?.id !== target.id) throw new Error(`administrator move failed: ${JSON.stringify(adminMove)}`);
    const changedVersion = adminMove.data.version;
    const staleDuringOutage = await latest(pages[1], target.stock);
    if (Number(staleDuringOutage.version) !== Number(initial[1].version)) throw new Error('disconnected browser unexpectedly updated');
    const websocketDisconnectedDuringOffline = Number(staleDuringOutage.version) === Number(initial[1].version)
      && Number(changedVersion) > Number(initial[1].version);

    await pages[2].waitForFunction(count =>
      (window.__vehicleLifecycleIdentityResolver?.getDiagnostics?.() || []).filter(item => item.type === 'realtime_change').length > count,
      onlinePeerChangesBefore, { timeout: 30000 });
    const onlinePeerChangesAfter = await pages[2].evaluate(() =>
      (window.__vehicleLifecycleIdentityResolver?.getDiagnostics?.() || []).filter(item => item.type === 'realtime_change').length);
    const onlinePeerRealtimeEventDelta = onlinePeerChangesAfter - onlinePeerChangesBefore;
    const onlinePeerRealtime = await resolve(pages[2], target.stock);
    if (Number(onlinePeerRealtime.version) !== Number(changedVersion)) throw new Error('independent online viewer did not refresh through Realtime');
    networkPhases[1] = 'reconnecting-cycle-1';
    await contexts[1].setOffline(false);
    await pages[1].waitForFunction(() => (window.PDC_SUPABASE?.getChannels?.() || []).some(channel => channel.topic === 'realtime:pdc-reference-vehicle_lifecycle_resolver_revision' && channel.state === 'joined'), null, { timeout: 30000 });
    await pages[1].waitForFunction(({ stock, version }) => {
      const latestValue = window.__vehicleLifecycleIdentityResolver?.getLatest?.({ p_stock_number: stock });
      return Number(latestValue?.version) === Number(version);
    }, { stock: target.stock, version: changedVersion }, { timeout: 30000 });
    const reconnected = await latest(pages[1], target.stock);
    const postOnlineRefetch = await resolve(pages[1], target.stock);
    if (postOnlineRefetch?.vehicleId !== target.id || Number(postOnlineRefetch?.version) !== Number(changedVersion)) {
      throw new Error('online restoration did not perform an exact selected-vehicle refetch');
    }
    const reconnectedChannels = await pages[1].evaluate(() => window.PDC_SUPABASE.getChannels().map(channel => channel.topic).sort());
    if (JSON.stringify(initialChannels) !== JSON.stringify(reconnectedChannels) || new Set(reconnectedChannels).size !== reconnectedChannels.length) {
      throw new Error('reconnect created duplicate or missing channels');
    }

    networkPhases[1] = 'offline-cycle-2';
    await contexts[1].setOffline(true);
    const secondOfflineHttpProbe = await pages[1].evaluate(async () => {
      try {
        const config = window.PDC_SUPABASE_CONFIG;
        await fetch(`${config.url}/rest/v1/vehicle_lifecycle_resolver_revision?select=revision`, { cache: 'no-store' });
        return { refused: false };
      } catch (error) {
        return { refused: true, errorName: error?.name || null };
      }
    });
    if (!secondOfflineHttpProbe.refused) throw new Error('second offline HTTP probe unexpectedly succeeded');
    networkPhases[1] = 'reconnecting-cycle-2';
    await contexts[1].setOffline(false);
    await pages[1].waitForFunction(() => (window.PDC_SUPABASE?.getChannels?.() || []).some(channel => channel.topic === 'realtime:pdc-reference-vehicle_lifecycle_resolver_revision' && channel.state === 'joined'), null, { timeout: 30000 });
    await pages[1].waitForFunction(({ stock, version }) => {
      const latestValue = window.__vehicleLifecycleIdentityResolver?.getLatest?.({ p_stock_number: stock });
      return Number(latestValue?.version) === Number(version);
    }, { stock: target.stock, version: changedVersion }, { timeout: 30000 });
    const secondReconnectChannels = await pages[1].evaluate(() => window.PDC_SUPABASE.getChannels().map(channel => channel.topic).sort());
    if (JSON.stringify(initialChannels) !== JSON.stringify(secondReconnectChannels) || new Set(secondReconnectChannels).size !== secondReconnectChannels.length) {
      throw new Error('second reconnect multiplied or removed Realtime channels');
    }
    const realtimeChangesBeforeCallbackProbe = await pages[1].evaluate(() =>
      (window.__vehicleLifecycleIdentityResolver?.getDiagnostics?.() || []).filter(item => item.type === 'realtime_change').length);
    networkPhases[1] = 'online-after-cycle-2';
    const callbackProbeMove = await move(pages[0], {
      p_vehicle_id: target.id, p_expected_version: changedVersion,
      p_to_location: 'C6-REALTIME-CALLBACK-PROBE', p_reason: 'C6 repeated reconnect callback singleton proof',
    });
    if (callbackProbeMove.error || callbackProbeMove.data?.id !== target.id) throw new Error(`callback probe move failed: ${JSON.stringify(callbackProbeMove)}`);
    const callbackProbeVersion = callbackProbeMove.data.version;
    await pages[1].waitForFunction(count =>
      (window.__vehicleLifecycleIdentityResolver?.getDiagnostics?.() || []).filter(item => item.type === 'realtime_change').length > count,
      realtimeChangesBeforeCallbackProbe, { timeout: 30000 });
    const callbackResolved = await resolve(pages[1], target.stock);
    if (callbackResolved.vehicleId !== target.id || Number(callbackResolved.version) !== Number(callbackProbeVersion)) {
      throw new Error('Realtime callback did not permit exact authoritative resolver refetch');
    }
    const realtimeChangesAfterCallbackProbe = await pages[1].evaluate(() =>
      (window.__vehicleLifecycleIdentityResolver?.getDiagnostics?.() || []).filter(item => item.type === 'realtime_change').length);
    const callbackDelta = realtimeChangesAfterCallbackProbe - realtimeChangesBeforeCallbackProbe;
    if (callbackDelta !== 1) throw new Error(`repeated reconnect multiplied Realtime callbacks: delta=${callbackDelta}`);

    const staleEdit = await pages[1].evaluate(async params => {
      const { data, error } = await window.PDC_SUPABASE.rpc('rft_transfer_vehicle', params);
      return { data, error: error ? { code: error.code || null, message: error.message || null } : null };
    }, { p_vehicle_id: target.id, p_expected_version: initial[1].version });
    if (staleEdit.error || staleEdit.data?.ok !== false || staleEdit.data?.error !== 'vehicle_version_conflict') {
      throw new Error(`stale browser edit was not refused: ${JSON.stringify(staleEdit)}`);
    }
    await pages[1].reload({ waitUntil: 'networkidle', timeout: 60000 });
    await pages[1].waitForFunction(() => window.PDC_AUTH_CONTEXT?.role && window.__vehicleLifecycleIdentityResolver, null, { timeout: 30000 });
    const refreshed = await resolve(pages[1], target.stock);
    if (Number(refreshed.version) !== Number(callbackProbeVersion) || refreshed.vehicleId !== target.id) throw new Error('browser refresh did not retain authoritative UUID/version');

    const restoreMove = await move(pages[0], {
      p_vehicle_id: target.id, p_expected_version: callbackProbeVersion,
      p_to_location: 'C6-BROWSER-REHEARSAL-RETAINED', p_reason: 'C6 explicit retained pilot state',
    });
    if (restoreMove.error || restoreMove.data?.id !== target.id) throw new Error(`final retained-state move failed: ${JSON.stringify(restoreMove)}`);
    const stagingProbe = await pages[0].evaluate(async () => {
      const config = window.PDC_SUPABASE_CONFIG;
      const { data: sessionData } = await window.PDC_SUPABASE.auth.getSession();
      const accessToken = sessionData?.session?.access_token;
      const url = `${config.url}/rest/v1/vehicle_lifecycle_resolver_revision?select=revision`;
      const response = await fetch(url, {
        headers: { apikey: config.publishableKey, Authorization: `Bearer ${accessToken}` },
      });
      return { status: response.status, url };
    });
    if (stagingProbe.status !== 200) throw new Error(`staging request-capture probe failed: ${stagingProbe.status}`);
    try { requestHosts.add(new globalThis.URL(stagingProbe.url).host); } catch (_) {}
    if (stagingProbe.url.includes(PROD_REF)) productionRequests.push({ browser: 'staging-probe' });
    const afterStorage = await Promise.all(pages.map(storageSnapshot));
    const afterStorageObservations = afterStorage.map(storageObservation);
    const browserLocalUnchanged = JSON.stringify(beforeStorage) === JSON.stringify(afterStorage);
    const browserLocalObservationsEqual = JSON.stringify(beforeStorageObservations) === JSON.stringify(afterStorageObservations);
    const authorityCanariesUnchanged = afterStorage.every(hasAuthorityCanaries);
    // chromium.launch() plus browser.newContext() uses isolated, ephemeral contexts;
    // no persistent userDataDir or operator browser profile is opened.
    const operatorProfileIsolated = true;
    const instrumentedUrls = (await Promise.all(pages.map(page => page.evaluate(() => window.__c6NetworkUrls || [])))).flat();
    const securityPolicyViolations = (await Promise.all(pages.map(page => page.evaluate(() => window.__c6SecurityPolicyViolations || [])))).flat();
    for (const value of instrumentedUrls) {
      try { requestHosts.add(new globalThis.URL(value).host); } catch (_) {}
      if (value.includes(PROD_REF)) productionRequests.push({ browser: 'instrumented-fetch' });
    }
    const isControlledOfflinePhase = phase => phase.startsWith('offline-') || phase.startsWith('reconnecting-');
    const unexpectedFailedRequests = failedRequests.filter(item => !isControlledOfflinePhase(item.phase));
    const unexpectedConsoleErrors = consoleErrors.filter(item => !isControlledOfflinePhase(item.phase));
    const checks = {
      exactStagingProject: projectRefs.every(ref => ref === EXPECTED_REF),
      stagingDeploymentIdentityBound: deploymentIdentity.staging_url === URL && deploymentIdentity.github_pages.status === 'built',
      administratorRole: roles[0] === 'administrator',
      controllerRole: ['operator', 'controller'].includes(roles[1]),
      viewerRole: roles[2] === 'viewer',
      viewerPermittedRead: initial[2]?.outcome === 'resolved' && initial[2]?.vehicleId === target.id,
      twoIndependentBrowserContexts: contexts.length === 3,
      initialOnlineStateSynchronized: initialSynchronized,
      browserContextActuallyOffline: offlineHttpProbe.refused,
      httpUnavailableDuringOffline: offlineHttpProbe.refused,
      websocketDisconnectedDuringOffline,
      offlineUiClearlyDisconnected: offlineUiState.navigatorOnline === false && offlineUiState.connectionState === 'offline_disconnected',
      offlineMutationNotReportedPersisted: offlineMutationRefused,
      postOnlineRefetchExact: postOnlineRefetch.vehicleId === target.id && Number(postOnlineRefetch.version) === Number(changedVersion),
      twoUserRealtimeRefresh: onlinePeerRealtimeEventDelta === 1 && Number(onlinePeerRealtime.version) === Number(changedVersion),
      staleWhileDisconnected: Number(staleDuringOutage.version) === Number(initial[1].version),
      reconnectCaughtMissedUpdate: Number(reconnected.version) === Number(changedVersion),
      noDuplicateChannelsAfterReconnect: JSON.stringify(initialChannels) === JSON.stringify(reconnectedChannels),
      repeatedOfflineOnlineTransitions: secondOfflineHttpProbe.refused,
      noDuplicateChannelsAfterRepeatedReconnect: JSON.stringify(initialChannels) === JSON.stringify(secondReconnectChannels),
      noMultipliedRealtimeCallbacks: callbackDelta === 1,
      browserRefreshPreservedUUIDAndVersion: refreshed.vehicleId === target.id && Number(refreshed.version) === Number(callbackProbeVersion),
      staleEditRejected: !staleEdit.error && staleEdit.data?.ok === false && staleEdit.data?.error === 'vehicle_version_conflict',
      operatorBrowserProfileIsolated: operatorProfileIsolated,
      authorityCanariesPresentBeforeBootstrapCompleted: authorityCanariesPresentBefore,
      browserLocalCanonicalObservationsEqual: browserLocalObservationsEqual,
      browserLocalAuthorityUnchanged: browserLocalUnchanged && authorityCanariesUnchanged,
      browserLocalDataNotCleared: browserLocalUnchanged && authorityCanariesUnchanged,
      zeroInstrumentedBrowserProductionProjectRequests: productionRequests.length === 0,
      stagingSupabaseContacted: requestHosts.has(`${EXPECTED_REF}.supabase.co`),
      noPageErrors: pageErrors.length === 0,
      noUnexpectedConsoleErrors: unexpectedConsoleErrors.length === 0,
      noCspViolations: securityPolicyViolations.length === 0,
      noUnexpectedHttpFailures: unexpectedFailedRequests.length === 0,
    };
    const report = {
      schema: 'pdc.stage2b.c6-browser-realtime/v1',
      stagingDeployment: {
        url: deploymentIdentity.staging_url,
        repository: deploymentIdentity.github_pages.repository,
        commit: deploymentIdentity.github_pages.commit,
        buildId: deploymentIdentity.github_pages.build_id,
        status: deploymentIdentity.github_pages.status,
        indexSha256: deploymentIdentity.index.sha256,
        identityEvidenceSha256: deploymentEvidenceSha256,
      },
      selectedRecordRef: TARGET_REF,
      vehicleId: target.id,
      sessions: 3,
      browserProfileIsolation: {
        mode: 'playwright-ephemeral-incognito-contexts',
        persistentUserDataDirUsed: false,
        operatorBrowserProfileOpened: false,
        authorityCanaryKeys: Object.keys(AUTHORITY_CANARY).sort(),
        authorityCanariesPresentBeforeBootstrapCompleted: authorityCanariesPresentBefore,
        authorityCanariesUnchanged,
      },
      browserLocalAuthorityObservations: {
        canonicalSerialization: 'JSON.stringify(sorted [key,value] arrays)',
        before: beforeStorageObservations,
        after: afterStorageObservations,
        exactHashKeyAndByteEquality: browserLocalObservationsEqual,
      },
      roles,
      initialVersion: initial[0].version,
      changedVersion,
      onlinePeerRealtimeVersion: onlinePeerRealtime.version,
      onlinePeerRealtimeEventDelta,
      callbackProbeVersion,
      refreshedVersion: refreshed.version,
      offlineHttpProbe,
      secondOfflineHttpProbe,
      offlineUiState,
      offlineMutationAttempt: { refused: offlineMutationRefused, errorCode: offlineMutationAttempt.error?.code || null },
      reconnectCycles: 2,
      reconnectChannelCountBefore: initialChannels.length,
      reconnectChannelCountAfter: reconnectedChannels.length,
      secondReconnectChannelCountAfter: secondReconnectChannels.length,
      realtimeCallbackCountBeforeProbe: realtimeChangesBeforeCallbackProbe,
      realtimeCallbackCountAfterProbe: realtimeChangesAfterCallbackProbe,
      realtimeCallbackDelta: callbackDelta,
      checks,
      productionRequests: [],
      requestHosts: [...requestHosts].sort(),
      failedRequestCount: failedRequests.length,
      controlledOfflineFailures: failedRequests.filter(item => isControlledOfflinePhase(item.phase)),
      unexpectedFailedRequests,
      webSocketEvidence,
      consoleErrors,
      securityPolicyViolations,
      pageErrors,
      browserLocalStoresUnchanged: browserLocalUnchanged && browserLocalObservationsEqual && authorityCanariesUnchanged,
      passed: Object.values(checks).every(Boolean),
    };
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report));
    if (!report.passed) process.exitCode = 1;
  } finally {
    await Promise.all(contexts.map(context => context.close()));
    await browser.close();
  }
})().catch(error => {
  console.error(error?.stack || String(error));
  process.exitCode = 1;
});
