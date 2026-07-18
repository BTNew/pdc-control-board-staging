'use strict';

const fs = require('fs');
const { spawnSync } = require('child_process');
const { chromium } = require('playwright-core');

const STAGING_URL = process.env.PDC_STAGING_URL || 'https://btnew.github.io/pdc-control-board-staging/';
const PROD_REF = 'vjdtsswhroyguxyfjdkt';
const STAGING_REF = 'cdsmnqxtyyoeoznmbidd';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const OUT = process.env.PDC_ASSIGNMENT_ACCEPTANCE_OUTPUT || 'review-evidence/final-contained/two-browser-assignment-acceptance.json';
const VEHICLE_ID = '8debaf15-2344-4617-aada-f39728c5c0de';
const VEHICLE_STOCK = 'STK-STAGE-001';
const BOOKING_DATE = '2099-01-05';
const LEAVE_DATE = '2099-01-06';
const PREFIX = `S2A-ASSIGN-${Date.now()}`;
const TECHNICIAN_NAME = `${PREFIX} Technician`;

function required(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) throw new Error(`Missing required environment variable ${name}`);
  return value;
}
function python(script, args = []) {
  const result = spawnSync('python3', [script, ...args], { cwd: process.cwd(), env: process.env, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(`${script} failed: ${result.stderr || result.stdout}`);
  return String(result.stdout || '').trim();
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
  await page.waitForFunction(() => window.__workshopReferenceDataService && window.__workshopDataService?.getLastSnapshot?.(), null, { timeout: 30000 });
  await page.waitForFunction(() => {
    const channels = window.PDC_SUPABASE?.getChannels?.() || [];
    const needed = channels.filter(channel => channel.topic?.startsWith('realtime:pdc-reference-') || channel.topic?.includes('workshop-revision'));
    return needed.length >= 6 && needed.every(channel => channel.state === 'joined');
  }, null, { timeout: 30000 });
}
async function setPlannerDate(page, date) {
  const input = page.locator('[data-workshop-date]');
  await input.fill(date);
  await input.dispatchEvent('change');
}
async function waitForBooking(page, technicianId, present = true) {
  await page.waitForFunction(({ vehicleId, technicianId, present }) => {
    const rows = window.__workshopDataService?.getLastSnapshot?.()?.bookings || [];
    const match = rows.find(row => row.vehicle_id === vehicleId && row.assignment?.technician_id === technicianId);
    return present ? Boolean(match) : !match;
  }, { vehicleId: VEHICLE_ID, technicianId, present }, { timeout: 30000 });
  return page.evaluate(({ vehicleId, technicianId }) => {
    return (window.__workshopDataService.getLastSnapshot().bookings || []).find(row => row.vehicle_id === vehicleId && row.assignment?.technician_id === technicianId) || null;
  }, { vehicleId: VEHICLE_ID, technicianId });
}
async function updateLeave(page, expectedVersion, value) {
  const result = await page.evaluate(async ({ expectedVersion, value }) => {
    return window.__workshopReferenceDataService.updateWorkshopConfiguration('technician_leave', expectedVersion, value);
  }, { expectedVersion, value });
  if (!result?.ok) throw new Error(`technician_leave update failed: ${JSON.stringify(result)}`);
  return result;
}

(async () => {
  if (STAGING_URL.includes(PROD_REF) || !STAGING_URL.includes('pdc-control-board-staging')) throw new Error('Refusing non-staging URL');
  python('_staging_test_tools/reset_workshop_test_fixtures.py');
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const contexts = [await browser.newContext(), await browser.newContext()];
  const pages = [await contexts[0].newPage(), await contexts[1].newPage()];
  const labels = ['Administrator', 'Operator'];
  const errors = { console: [], csp: [], page: [], request: [], http: [], production: [] };
  const hosts = new Set();
  const moveRpcRequests = [];
  pages.forEach((page, index) => {
    page.on('console', msg => {
      if (msg.type() === 'error') {
        const item = { browser: labels[index], text: msg.text() };
        errors.console.push(item);
        if (/content security policy|csp/i.test(item.text)) errors.csp.push(item);
      }
    });
    page.on('pageerror', err => errors.page.push({ browser: labels[index], text: String(err) }));
    page.on('request', req => {
      try { hosts.add(new URL(req.url()).host); } catch (_) {}
      if (req.url().includes(PROD_REF)) errors.production.push({ browser: labels[index], url: req.url() });
      if (req.url().includes('/rpc/move_workshop_booking')) moveRpcRequests.push(req.url());
    });
    page.on('requestfailed', req => errors.request.push({ browser: labels[index], url: req.url(), error: req.failure()?.errorText }));
    page.on('response', response => { if (response.status() >= 400) errors.http.push({ browser: labels[index], status: response.status(), url: response.url() }); });
  });

  let technicianId = null;
  let originalLeave = null;
  let leaveVersion = null;
  let leaveChanged = false;
  let report;
  try {
    await login(pages[0], required('PDC_STAGING_ADMIN_EMAIL'), required('PDC_STAGING_ADMIN_PASSWORD'));
    await login(pages[1], required('PDC_STAGING_CONTROLLER_A_EMAIL'), required('PDC_STAGING_CONTROLLER_A_PASSWORD'));
    await new Promise(resolve => setTimeout(resolve, 3000));

    const added = await pages[0].evaluate(async ({ name, code }) => {
      return window.__workshopReferenceDataService.addTechnician(name, 'technician', code, ['HOIST']);
    }, { name: TECHNICIAN_NAME, code: PREFIX.slice(-24) });
    if (!added?.ok) throw new Error(`Administrator could not create technician: ${JSON.stringify(added)}`);
    technicianId = added.technician.id;
    await pages[1].waitForFunction(({ id, name }) => {
      const cached = window.__workshopReferenceDataService?.getCachedTechnicians?.();
      return cached?.rows?.some(row => row.id === id && row.name === name && row.active === true);
    }, { id: technicianId, name: TECHNICIAN_NAME }, { timeout: 30000 });

    await pages[1].locator('[data-workshop-stage="HOIST"]').click();
    await setPlannerDate(pages[1], BOOKING_DATE);
    const search = pages[1].locator('[data-workshop-search]');
    await search.fill(VEHICLE_STOCK);
    await search.press('Enter');
    const schedule = pages[1].locator(`[data-workshop-vehicle-key] [data-workshop-schedule-vehicle]`).first();
    await schedule.waitFor({ state: 'visible', timeout: 15000 });
    await schedule.click();
    const form = pages[1].locator('[data-workshop-schedule-form]');
    await form.locator('[name="date"]').fill(BOOKING_DATE);
    await form.locator('[name="hours"]').fill('1');
    await form.locator('[name="assignee"]').selectOption({ label: TECHNICIAN_NAME });
    const timeOptions = await form.locator('[name="startMinutes"] option').evaluateAll(options => options.map(option => ({ value: option.value, text: option.textContent })));
    const nine = timeOptions.find(option => /9:00/i.test(option.text));
    if (!nine) throw new Error(`09:00 option unavailable: ${JSON.stringify(timeOptions)}`);
    await form.locator('[name="startMinutes"]').selectOption(nine.value);
    await form.locator('button[type="submit"]').click();
    await form.waitFor({ state: 'detached', timeout: 30000 });

    const bookingA = await waitForBooking(pages[0], technicianId);
    const bookingB = await waitForBooking(pages[1], technicianId);
    if (bookingA.booking_id !== bookingB.booking_id || bookingA.assignment.technician_name !== TECHNICIAN_NAME || bookingB.assignment.technician_name !== TECHNICIAN_NAME) {
      throw new Error(`Realtime assignment mismatch: ${JSON.stringify({ bookingA, bookingB })}`);
    }

    const leaveRow = await pages[0].evaluate(() => window.__workshopReferenceDataService.getCachedWorkshopConfiguration().rows.technician_leave);
    originalLeave = JSON.parse(JSON.stringify(leaveRow.value || []));
    leaveVersion = Number(leaveRow.version);
    const changed = await updateLeave(pages[0], leaveVersion, [...originalLeave, { technician_id: technicianId, date: LEAVE_DATE }]);
    leaveVersion = Number(changed.setting.version);
    leaveChanged = true;
    await pages[1].waitForFunction(({ id, date, version }) => {
      const row = window.__workshopReferenceDataService?.getCachedWorkshopConfiguration?.()?.rows?.technician_leave;
      return Number(row?.version) >= version && row.value.some(item => item.technician_id === id && item.date === date);
    }, { id: technicianId, date: LEAVE_DATE, version: leaveVersion }, { timeout: 30000 });

    await setPlannerDate(pages[1], BOOKING_DATE);
    await pages[1].locator(`[data-workshop-select-plan="${bookingB.booking_id}"]`).click();
    const detail = pages[1].locator('[data-workshop-detail-form]');
    await detail.locator('[name="startAt"]').fill(`${LEAVE_DATE}T09:00`);
    const beforeMoveRequests = moveRpcRequests.length;
    let leaveAlert = '';
    pages[1].once('dialog', async dialog => { leaveAlert = dialog.message(); await dialog.accept(); });
    await detail.locator('button[type="submit"]').click();
    await pages[1].waitForTimeout(1000);
    const afterRejected = await waitForBooking(pages[1], technicianId);
    const moveBlocked = afterRejected.booking_id === bookingB.booking_id
      && afterRejected.scheduled_start_at === bookingB.scheduled_start_at
      && moveRpcRequests.length === beforeMoveRequests
      && /leave/i.test(leaveAlert);
    if (!moveBlocked) throw new Error(`Move onto leave was not blocked before RPC: ${JSON.stringify({ leaveAlert, beforeMoveRequests, moveRequests: moveRpcRequests.length, bookingB, afterRejected })}`);

    const restored = await updateLeave(pages[0], leaveVersion, originalLeave);
    leaveVersion = Number(restored.setting.version);
    leaveChanged = false;
    await pages[1].waitForFunction(({ id, version }) => {
      const row = window.__workshopReferenceDataService?.getCachedWorkshopConfiguration?.()?.rows?.technician_leave;
      return Number(row?.version) >= version && !row.value.some(item => item.technician_id === id);
    }, { id: technicianId, version: leaveVersion }, { timeout: 30000 });

    report = {
      runAt: new Date().toISOString(), url: STAGING_URL,
      deploymentCommit: process.env.PDC_STAGING_DEPLOYMENT_COMMIT || null,
      appVersion: await pages[0].locator('#app-version').textContent(),
      technician: { id: technicianId, name: TECHNICIAN_NAME },
      booking: { id: bookingB.booking_id, vehicleId: VEHICLE_ID, technicianId: bookingB.assignment.technician_id, technicianName: bookingB.assignment.technician_name },
      leaveDate: LEAVE_DATE, moveAlert: leaveAlert,
      checks: {
        administratorCreatedActiveTechnician: true,
        operatorSelectedTechnicianAndScheduled: true,
        bothBrowsersRetainedSameAssignmentThroughRealtime: true,
        moveOntoLeaveBlockedBeforeRpc: moveBlocked,
        noConsoleErrors: errors.console.length === 0,
        noCspErrors: errors.csp.length === 0,
        noPageErrors: errors.page.length === 0,
        noFailedRequests: errors.request.length === 0,
        noHttpErrors: errors.http.length === 0,
        noProductionRequests: errors.production.length === 0,
        stagingSupabaseContacted: hosts.has(`${STAGING_REF}.supabase.co`),
        stagingPageLoaded: hosts.has('btnew.github.io'),
      },
      errors, requestHosts: [...hosts].sort(), passed: true,
    };
    report.passed = Object.values(report.checks).every(Boolean);
    if (!report.passed) process.exitCode = 1;
  } catch (error) {
    report = { runAt: new Date().toISOString(), url: STAGING_URL, failure: String(error?.stack || error), errors, requestHosts: [...hosts].sort(), passed: false };
    process.exitCode = 1;
  } finally {
    if (leaveChanged && originalLeave && Number.isFinite(leaveVersion)) {
      try { await updateLeave(pages[0], leaveVersion, originalLeave); } catch (error) { report.leaveRestoreFailure = String(error); process.exitCode = 1; }
    }
    await browser.close();
    try { report.fixtureReset = python('_staging_test_tools/reset_workshop_test_fixtures.py'); } catch (error) { report.fixtureResetFailure = String(error); process.exitCode = 1; }
    if (technicianId) {
      try { report.technicianCleanup = python('_staging_test_tools/cleanup_stage2a_assignment_acceptance.py', [technicianId, PREFIX]); } catch (error) { report.technicianCleanupFailure = String(error); process.exitCode = 1; }
    }
    report.cleanupZero = !report.fixtureResetFailure && !report.technicianCleanupFailure;
    report.passed = report.passed === true && report.cleanupZero;
    fs.mkdirSync(require('path').dirname(OUT), { recursive: true });
    fs.writeFileSync(OUT, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
  }
})();
