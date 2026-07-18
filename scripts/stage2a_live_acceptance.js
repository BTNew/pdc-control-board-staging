'use strict';

const fs = require('fs');
const { chromium } = require('playwright-core');

const STAGING_URL = process.env.PDC_STAGING_URL || 'https://btnew.github.io/pdc-control-board-staging/';
const PROD_REF = 'vjdtsswhroyguxyfjdkt';
const EXPECTED_STAGING_REF = 'cdsmnqxtyyoeoznmbidd';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = process.env.PDC_ACCEPTANCE_OUTPUT || 'two-browser-realtime-acceptance.json';
const SYNTHETIC_CLOSURE_DATE = '2099-01-05'; // Monday, synthetic and fully restored.

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
    return ['connected_read_only', 'connected_editable'].includes(cached?.state)
      && cached?.rows?.day_start_time && cached?.rows?.closures;
  }, null, { timeout: 30000 });
  await page.waitForFunction(() => {
    const channels = window.PDC_SUPABASE?.getChannels?.() || [];
    const reference = channels.filter(channel => channel.topic?.startsWith('realtime:pdc-reference-'));
    return reference.length === 5 && reference.every(channel => channel.state === 'joined');
  }, null, { timeout: 30000 });
}

async function cacheSnapshot(page) {
  return page.evaluate(() => {
    const cached = window.__workshopReferenceDataService.getCachedWorkshopConfiguration();
    return {
      state: cached.state,
      role: window.PDC_AUTH_CONTEXT?.role || null,
      dayStart: cached.rows.day_start_time,
      closures: cached.rows.closures,
      currentView: typeof app !== 'undefined' ? app.currentView : null,
      versionText: document.getElementById('app-version')?.textContent || null,
    };
  });
}

async function updateSetting(page, key, version, value) {
  const result = await page.evaluate(async args => {
    return window.__workshopReferenceDataService.updateWorkshopConfiguration(args.key, args.version, args.value);
  }, { key, version, value });
  if (!result?.ok) throw new Error(`Administrator ${key} update failed: ${JSON.stringify(result)}`);
  return result;
}

async function waitForSetting(page, key, predicateArgs, predicateSource) {
  await page.waitForFunction(({ key: settingKey, predicateArgs: args, predicateSource: source }) => {
    const row = window.__workshopReferenceDataService?.getCachedWorkshopConfiguration?.()?.rows?.[settingKey];
    if (!row) return false;
    // Predicate source is defined locally by this trusted harness, not external input.
    return Function('row', 'args', `return (${source})(row, args);`)(row, args);
  }, { key, predicateArgs, predicateSource }, { timeout: 30000 });
}

async function renderSyntheticWeek(page) {
  return page.evaluate(dateKey => {
    workshopSyncConfigFromSharedSettings();
    const state = workshopPlannerState();
    state.mode = 'weekly';
    state.weekStart = dateKey;
    renderWorkshopPlanner();
    const closure = document.querySelector(`.workshop-week-day.is-closure [data-workshop-week-date="${dateKey}"]`);
    return {
      configuredDayStartMinutes: WORKSHOP_PLANNER_CONFIG.dayStartMinutes,
      firstAxisLabel: document.querySelector('.workshop-time-axis span')?.textContent?.trim() || null,
      closureRendered: Boolean(closure),
      closureHeader: closure?.closest('.workshop-week-day')?.querySelector('header')?.textContent?.trim() || null,
      closureDroppable: Boolean(document.querySelector(`.workshop-week-day.is-closure [data-workshop-week-drop-date="${dateKey}"]`)),
    };
  }, SYNTHETIC_CLOSURE_DATE);
}

(async () => {
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const contexts = [await browser.newContext(), await browser.newContext()];
  const pages = [await contexts[0].newPage(), await contexts[1].newPage()];
  const labels = ['Browser A (administrator)', 'Browser B (controller)'];
  const consoleErrors = [];
  const cspErrors = [];
  const pageErrors = [];
  const failedRequests = [];
  const httpErrors = [];
  const requestHosts = new Set();
  const productionRequests = [];

  pages.forEach((page, index) => {
    page.on('console', msg => {
      if (msg.type() === 'error') {
        const item = { browser: labels[index], text: msg.text() };
        consoleErrors.push(item);
        if (/content security policy|csp/i.test(item.text)) cspErrors.push(item);
      }
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

  let originalStart;
  let originalClosures;
  let startVersion;
  let closureVersion;
  let startChanged = false;
  let closureChanged = false;
  let report;

  try {
    await login(pages[0], adminEmail, adminPassword);
    await login(pages[1], controllerEmail, controllerPassword);
    await new Promise(resolve => setTimeout(resolve, 3000));

    const beforeA = await cacheSnapshot(pages[0]);
    const beforeB = await cacheSnapshot(pages[1]);
    if (beforeB.dayStart.value !== beforeA.dayStart.value) throw new Error('Browsers did not start from the same day_start_time');

    originalStart = String(beforeA.dayStart.value);
    originalClosures = JSON.parse(JSON.stringify(beforeA.closures.value || []));
    startVersion = Number(beforeA.dayStart.version);
    closureVersion = Number(beforeA.closures.version);
    if (originalClosures.some(item => String(item?.date || item) === SYNTHETIC_CLOSURE_DATE)) {
      throw new Error(`Synthetic closure date ${SYNTHETIC_CLOSURE_DATE} already exists; refusing to overwrite it`);
    }

    // Force an actual transition to 07:30 even if staging already begins there.
    if (originalStart === '07:30') {
      const intermediate = await updateSetting(pages[0], 'day_start_time', startVersion, '08:00');
      startVersion = Number(intermediate.setting.version);
      startChanged = true;
      await waitForSetting(pages[1], 'day_start_time', { value: '08:00', version: startVersion }, '(row,args) => row.value === args.value && Number(row.version) >= args.version');
    }
    const startResult = await updateSetting(pages[0], 'day_start_time', startVersion, '07:30');
    startVersion = Number(startResult.setting.version);
    startChanged = true;
    await waitForSetting(pages[1], 'day_start_time', { value: '07:30', version: startVersion }, '(row,args) => row.value === args.value && Number(row.version) >= args.version');
    const afterStartB = await renderSyntheticWeek(pages[1]);
    if (afterStartB.configuredDayStartMinutes !== 450 || afterStartB.firstAxisLabel !== '07:30') {
      throw new Error(`Browser B did not render/use 07:30: ${JSON.stringify(afterStartB)}`);
    }

    const syntheticClosures = [...originalClosures, { date: SYNTHETIC_CLOSURE_DATE, label: 'Stage 2A synthetic acceptance closure' }];
    const closureResult = await updateSetting(pages[0], 'closures', closureVersion, syntheticClosures);
    closureVersion = Number(closureResult.setting.version);
    closureChanged = true;
    await waitForSetting(pages[1], 'closures', { date: SYNTHETIC_CLOSURE_DATE, version: closureVersion }, '(row,args) => Array.isArray(row.value) && row.value.some(item => String(item?.date || item) === args.date) && Number(row.version) >= args.version');
    const afterClosureB = await renderSyntheticWeek(pages[1]);
    if (!afterClosureB.closureRendered || afterClosureB.closureDroppable) {
      throw new Error(`Browser B did not render a closed/non-droppable planner date: ${JSON.stringify(afterClosureB)}`);
    }

    // Restore both settings in reverse order and prove Browser B observes it.
    const closureRestore = await updateSetting(pages[0], 'closures', closureVersion, originalClosures);
    closureVersion = Number(closureRestore.setting.version);
    closureChanged = false;
    await waitForSetting(pages[1], 'closures', { date: SYNTHETIC_CLOSURE_DATE, version: closureVersion }, '(row,args) => Array.isArray(row.value) && !row.value.some(item => String(item?.date || item) === args.date) && Number(row.version) >= args.version');

    const startRestore = await updateSetting(pages[0], 'day_start_time', startVersion, originalStart);
    startVersion = Number(startRestore.setting.version);
    startChanged = false;
    await waitForSetting(pages[1], 'day_start_time', { value: originalStart, version: startVersion }, '(row,args) => row.value === args.value && Number(row.version) >= args.version');
    const restoredB = await renderSyntheticWeek(pages[1]);

    const checks = {
      bothAuthenticated: beforeA.role === 'administrator' && beforeB.role === 'operator',
      bothOpenedWorkshop: beforeA.currentView === 'workshop' && beforeB.currentView === 'workshop',
      browserBRendered0730: afterStartB.configuredDayStartMinutes === 450 && afterStartB.firstAxisLabel === '07:30',
      browserBBlockedSyntheticClosure: afterClosureB.closureRendered && !afterClosureB.closureDroppable,
      closureRestored: !restoredB.closureRendered,
      startTimeRestored: (await cacheSnapshot(pages[1])).dayStart.value === originalStart,
      noConsoleErrors: consoleErrors.length === 0,
      noCspErrors: cspErrors.length === 0,
      noPageErrors: pageErrors.length === 0,
      noFailedRequests: failedRequests.length === 0,
      noHttpErrors: httpErrors.length === 0,
      noProductionRequests: productionRequests.length === 0,
      stagingSupabaseContacted: [...requestHosts].includes(`${EXPECTED_STAGING_REF}.supabase.co`),
      stagingPageLoaded: [...requestHosts].includes('btnew.github.io'),
    };
    report = {
      runAt: new Date().toISOString(),
      url: STAGING_URL,
      deploymentCommit: process.env.PDC_STAGING_DEPLOYMENT_COMMIT || null,
      appVersion: beforeA.versionText,
      syntheticClosureDate: SYNTHETIC_CLOSURE_DATE,
      plannerOutcomes: { afterStartB, afterClosureB, restoredB },
      restored: { dayStartTime: originalStart, closures: originalClosures },
      checks,
      consoleErrors, cspErrors, pageErrors, failedRequests, httpErrors,
      productionRequests,
      requestHosts: [...requestHosts].sort(),
      passed: Object.values(checks).every(Boolean),
    };
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
    if (!report.passed) process.exitCode = 1;
  } catch (err) {
    const emergencyRestores = [];
    if (closureChanged && Number.isFinite(closureVersion) && originalClosures) {
      try { emergencyRestores.push(await updateSetting(pages[0], 'closures', closureVersion, originalClosures)); } catch (restoreError) { emergencyRestores.push({ ok: false, setting: 'closures', error: String(restoreError) }); }
    }
    if (startChanged && Number.isFinite(startVersion) && originalStart) {
      try { emergencyRestores.push(await updateSetting(pages[0], 'day_start_time', startVersion, originalStart)); } catch (restoreError) { emergencyRestores.push({ ok: false, setting: 'day_start_time', error: String(restoreError) }); }
    }
    report = {
      runAt: new Date().toISOString(), url: STAGING_URL,
      failure: String(err?.stack || err), emergencyRestores,
      consoleErrors, cspErrors, pageErrors, failedRequests, httpErrors,
      productionRequests, requestHosts: [...requestHosts].sort(), passed: false,
    };
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
    console.error(report.failure);
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
