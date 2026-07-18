'use strict';

const fs = require('fs');
const { chromium } = require('playwright-core');

const STAGING_URL = process.env.PDC_STAGING_URL || 'https://btnew.github.io/pdc-control-board-staging/';
const PROD_REF = 'vjdtsswhroyguxyfjdkt';
const EXPECTED_STAGING_REF = 'cdsmnqxtyyoeoznmbidd';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = process.env.PDC_ACCEPTANCE_OUTPUT || 'two-browser-realtime-acceptance.json';

function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Missing required environment variable ${name}; see _staging_test_tools/.env.example`);
  return value;
}

if (STAGING_URL.includes(PROD_REF) || !STAGING_URL.includes('btnew.github.io/pdc-control-board-staging')) {
  throw new Error('Refusing to run Stage 2A acceptance against a non-staging website');
}

async function login(page, email, password) {
  await page.goto(STAGING_URL, { waitUntil: 'networkidle', timeout: 60000 });
  await page.locator('#pdc-login-email').fill(email);
  await page.locator('#pdc-login-password').fill(password);
  await page.locator('#pdc-password-form button[type=submit]').click();
  await page.waitForFunction(() => {
    const shell = document.getElementById('app-shell');
    return shell && !shell.hasAttribute('inert') && shell.getAttribute('aria-hidden') !== 'true';
  }, null, { timeout: 30000 });
  await page.locator('[data-view="workshop"]').click();
  await page.waitForFunction(() => window.__workshopReferenceDataService && window.PDC_AUTH_CONTEXT?.role, null, { timeout: 30000 });
  await page.waitForFunction(() => {
    const cached = window.__workshopReferenceDataService?.getCachedWorkshopConfiguration?.();
    return ['connected_read_only', 'connected_editable'].includes(cached?.state) && cached?.rows?.default_booking_duration_minutes;
  }, null, { timeout: 30000 });
  await page.waitForFunction(() => {
    const channels = window.PDC_SUPABASE?.getChannels?.() || [];
    return channels.filter(channel => channel.topic?.startsWith('realtime:pdc-reference-')).length === 5
      && channels.filter(channel => channel.topic?.startsWith('realtime:pdc-reference-')).every(channel => channel.state === 'joined');
  }, null, { timeout: 30000 });
}

async function cachedConfig(page) {
  return page.evaluate(() => {
    const cached = window.__workshopReferenceDataService.getCachedWorkshopConfiguration();
    return {
      state: cached.state,
      role: window.PDC_AUTH_CONTEXT?.role || null,
      defaultDuration: cached.rows.default_booking_duration_minutes,
      currentView: typeof app !== 'undefined' ? app.currentView : null,
      versionText: document.getElementById('app-version')?.textContent || null,
      workshopBanner: document.querySelector('.workshop-connection-banner')?.textContent?.trim() || null,
    };
  });
}

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const contexts = [await browser.newContext(), await browser.newContext()];
  const pages = [await contexts[0].newPage(), await contexts[1].newPage()];
  const labels = ['Browser A (administrator)', 'Browser B (controller)'];
  const consoleErrors = [];
  const pageErrors = [];
  const failedRequests = [];
  const httpErrors = [];
  const requestHosts = new Set();
  const productionRequests = [];

  pages.forEach((page, index) => {
    page.on('console', msg => {
      if (msg.type() === 'error') consoleErrors.push({ browser: labels[index], text: msg.text() });
    });
    page.on('pageerror', err => pageErrors.push({ browser: labels[index], text: String(err) }));
    page.on('request', req => {
      try { requestHosts.add(new URL(req.url()).host); } catch (_) {}
      if (req.url().includes(PROD_REF)) productionRequests.push({ browser: labels[index], url: req.url() });
    });
    page.on('requestfailed', req => failedRequests.push({ browser: labels[index], url: req.url(), failure: req.failure()?.errorText || null }));
    page.on('response', response => {
      if (response.status() >= 400) httpErrors.push({ browser: labels[index], status: response.status(), url: response.url() });
    });
  });

  const adminEmail = required('PDC_STAGING_ADMIN_EMAIL');
  const adminPassword = required('PDC_STAGING_ADMIN_PASSWORD');
  const controllerEmail = required('PDC_STAGING_CONTROLLER_A_EMAIL');
  const controllerPassword = required('PDC_STAGING_CONTROLLER_A_PASSWORD');

  let original;
  let alternate;
  let changed;
  let browserBObservedChange = false;
  let browserBObservedRestore = false;
  let restored;
  let failure = null;

  try {
    await login(pages[0], adminEmail, adminPassword);
    await login(pages[1], controllerEmail, controllerPassword);
    // Supabase reports a channel as joined just before the server-side
    // postgres_changes binding is consistently ready to receive the first
    // event. Give both independent sockets a short settle window so the
    // acceptance mutation cannot race that hand-off.
    await new Promise(resolve => setTimeout(resolve, 3000));

    const beforeA = await cachedConfig(pages[0]);
    const beforeB = await cachedConfig(pages[1]);
    original = Number(beforeA.defaultDuration.value);
    alternate = original === 195 ? 210 : 195;
    const originalVersion = Number(beforeA.defaultDuration.version);
    if (beforeB.defaultDuration.value !== beforeA.defaultDuration.value) throw new Error('Browsers did not start from the same configuration value');

    changed = await pages[0].evaluate(async ({ value, version }) => {
      return window.__workshopReferenceDataService.updateWorkshopConfiguration('default_booking_duration_minutes', version, value);
    }, { value: alternate, version: originalVersion });
    if (!changed?.ok) throw new Error(`Administrator update failed: ${JSON.stringify(changed)}`);
    const changedVersion = Number(changed.setting.version);

    await pages[1].waitForFunction(({ value, minVersion }) => {
      const row = window.__workshopReferenceDataService?.getCachedWorkshopConfiguration?.()?.rows?.default_booking_duration_minutes;
      return Number(row?.value) === value && Number(row?.version) >= minVersion;
    }, { value: alternate, minVersion: changedVersion }, { timeout: 30000 });
    browserBObservedChange = true;

    restored = await pages[0].evaluate(async ({ value, version }) => {
      return window.__workshopReferenceDataService.updateWorkshopConfiguration('default_booking_duration_minutes', version, value);
    }, { value: original, version: changedVersion });
    if (!restored?.ok) throw new Error(`Administrator restore failed: ${JSON.stringify(restored)}`);
    const restoredVersion = Number(restored.setting.version);

    await pages[1].waitForFunction(({ value, minVersion }) => {
      const row = window.__workshopReferenceDataService?.getCachedWorkshopConfiguration?.()?.rows?.default_booking_duration_minutes;
      return Number(row?.value) === value && Number(row?.version) >= minVersion;
    }, { value: original, minVersion: restoredVersion }, { timeout: 30000 });
    browserBObservedRestore = true;

    const afterA = await cachedConfig(pages[0]);
    const afterB = await cachedConfig(pages[1]);
    const checks = {
      bothAuthenticated: beforeA.role === 'administrator' && beforeB.role === 'operator',
      bothOpenedWorkshop: beforeA.currentView === 'workshop' && beforeB.currentView === 'workshop',
      bothReferenceServicesReady: ['connected_read_only', 'connected_editable'].includes(beforeA.state) && ['connected_read_only', 'connected_editable'].includes(beforeB.state),
      administratorMutationSucceeded: changed?.ok === true,
      browserBRealtimeObservedChange: browserBObservedChange,
      restoreSucceeded: restored?.ok === true,
      browserBRealtimeObservedRestore: browserBObservedRestore,
      finalValuesMatchOriginal: Number(afterA.defaultDuration.value) === original && Number(afterB.defaultDuration.value) === original,
      noConsoleErrors: consoleErrors.length === 0,
      noPageErrors: pageErrors.length === 0,
      noFailedRequests: failedRequests.length === 0,
      noHttpErrors: httpErrors.length === 0,
      noProductionRequests: productionRequests.length === 0,
      stagingSupabaseContacted: [...requestHosts].includes('cdsmnqxtyyoeoznmbidd.supabase.co'),
      stagingPageLoaded: [...requestHosts].includes('btnew.github.io'),
    };
    const passed = Object.values(checks).every(Boolean);
    const report = {
      runAt: new Date().toISOString(),
      url: STAGING_URL,
      deploymentCommit: 'ee9d7419f3f1926ca9634dd4f49d314756ab4e7e',
      browsers: [
        { label: labels[0], account: 'administrator test account', role: beforeA.role, context: 'independent browser context' },
        { label: labels[1], account: 'controller A test account', role: beforeB.role, context: 'independent browser context' },
      ],
      mutation: {
        setting: 'default_booking_duration_minutes',
        originalValue: original,
        temporaryValue: alternate,
        changedVersion: changed?.setting?.version || null,
        restoredVersion: restored?.setting?.version || null,
        restoredToOriginal: checks.finalValuesMatchOriginal,
      },
      checks,
      consoleErrors,
      pageErrors,
      failedRequests,
      httpErrors,
      productionRequests,
      requestHosts: [...requestHosts].sort(),
      passed,
    };
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
    if (!passed) process.exitCode = 1;
  } catch (err) {
    failure = String(err?.stack || err);
    let emergencyRestore = null;
    if (changed?.setting?.version && Number.isFinite(Number(original))) {
      try {
        emergencyRestore = await pages[0].evaluate(async ({ value, version }) => {
          return window.__workshopReferenceDataService.updateWorkshopConfiguration('default_booking_duration_minutes', version, value);
        }, { value: original, version: Number(changed.setting.version) });
      } catch (restoreError) {
        emergencyRestore = { ok: false, error: String(restoreError) };
      }
    }
    const browserSnapshots = [];
    for (let index = 0; index < pages.length; index += 1) {
      try {
        browserSnapshots.push({ browser: labels[index], cache: await cachedConfig(pages[index]), channels: await pages[index].evaluate(() => window.PDC_SUPABASE?.getChannels?.().map(channel => ({ topic: channel.topic, state: channel.state })) || []) });
      } catch (snapshotError) {
        browserSnapshots.push({ browser: labels[index], error: String(snapshotError) });
      }
    }
    const report = { runAt: new Date().toISOString(), url: STAGING_URL, failure, emergencyRestore, browserSnapshots, consoleErrors, pageErrors, failedRequests, httpErrors, productionRequests, requestHosts: [...requestHosts].sort(), passed: false };
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
    console.error(failure);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
