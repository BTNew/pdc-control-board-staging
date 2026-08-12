'use strict';
const { chromium } = require('playwright-core');
const path = require('path');
const fs = require('fs');
const URL = process.env.PDC_DELETE_UI_URL || 'http://127.0.0.1:8125/';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const admin = { email: process.env.PDC_STAGING_ADMIN_EMAIL, password: process.env.PDC_STAGING_ADMIN_PASSWORD };
const viewer = { email: process.env.PDC_STAGING_CONTROLLER_A_EMAIL, password: process.env.PDC_STAGING_CONTROLLER_A_PASSWORD, role: 'operator' };
async function login(page, who, expectedRole) {
  let authResponse = null;
  const onResponse = response => {
    if (response.url().includes('/auth/v1/token')) authResponse = { status: response.status() };
  };
  page.on('response', onResponse);
  await page.goto(URL + '?delete205=' + Date.now(), { waitUntil: 'networkidle', timeout: 60000 });

  await page.waitForFunction(() => document.body.dataset.authState === 'signed-out' || !document.getElementById('pdc-password-form')?.hidden, null, { timeout: 60000 });
  await page.locator('#pdc-login-email').fill(who.email);
  await page.locator('#pdc-login-password').fill(who.password);
  await page.locator('#pdc-password-login').click();
  try {
    await page.waitForFunction(role => window.PDC_AUTH_CONTEXT?.role === role && document.body.dataset.authState === 'approved', expectedRole, { timeout: 60000 });
  } catch (error) {
    const state = await page.evaluate(() => ({ authState: document.body.dataset.authState, role: window.PDC_AUTH_CONTEXT?.role || null, title: document.getElementById('pdc-auth-title')?.textContent, message: document.getElementById('pdc-auth-message')?.textContent, formHidden: document.getElementById('pdc-password-form')?.hidden }));
    throw new Error(`real ${expectedRole} authentication did not reach approved state: ${JSON.stringify(state)}; token=${JSON.stringify(authResponse)}; ${error.message}`);
  }
  page.off('response', onResponse);
  if (!authResponse || authResponse.status >= 400) throw new Error(`real ${expectedRole} authentication failed: ${JSON.stringify(authResponse)}`);
}
(async()=>{
  if (!admin.email || !admin.password || !viewer.email || !viewer.password) throw new Error('staging browser credentials missing');
  const browser = await chromium.launch({ executablePath: CHROME, headless: true });
  const adminPage = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  const viewerPage = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const stagingConfig = fs.readFileSync(path.join(__dirname, '..', 'pdc-supabase-config.staging.js'), 'utf8')
    .replace(/publishableKey:\s*'[^']+'/i, `publishableKey: '${process.env.PDC_STAGING_ANON_KEY}'`);
  for (const page of [adminPage, viewerPage]) {
    await page.route('**/pdc-supabase-config.js', route => route.fulfill({ status: 200, contentType: 'application/javascript', body: stagingConfig }));
    await page.route('https://cdsmnqxtyyoeoznmbidd.supabase.co/**', async route => {
      const original = route.request();
      const response = await fetch(original.url(), {
        method: original.method(), headers: original.headers(),
        body: ['GET', 'HEAD'].includes(original.method()) ? undefined : original.postDataBuffer(),
      });
      await route.fulfill({ status: response.status, headers: Object.fromEntries(response.headers), body: Buffer.from(await response.arrayBuffer()) });
    });
  }
  const errors=[]; for(const p of [adminPage,viewerPage]) p.on('pageerror',e=>errors.push(e.message));
  await login(adminPage,admin,'administrator'); await login(viewerPage,viewer,viewer.role);
  const adminState=await adminPage.evaluate(()=>{ syncAdminNavigationVisibility(); const node=document.querySelector('.nav-item[data-view="deleted"]'); return {role:window.PDC_AUTH_CONTEXT?.role,projectRef:window.PDC_SUPABASE_CONFIG?.projectRef,deletedHidden:node?.hidden,deletedAttr:node?.hasAttribute('hidden'),resetAllowed:vehicleLifecycleStagingResetAllowed()}; });
  const viewerState=await viewerPage.evaluate(()=>{ syncAdminNavigationVisibility(); showView('deleted'); const node=document.querySelector('.nav-item[data-view="deleted"]'); return {role:window.PDC_AUTH_CONTEXT?.role,deletedHidden:node?.hidden,deletedAttr:node?.hasAttribute('hidden'),adminActive:vehicleLifecycleAdministratorActive(),directRoute:app.currentView}; });
  const officialStagingUrl = URL === 'https://btnew.github.io/pdc-control-board-staging/' || URL === 'https://btnew.github.io/pdc-control-board-staging/index.html';
  if(adminState.projectRef!=='cdsmnqxtyyoeoznmbidd'||adminState.role!=='administrator'||adminState.deletedHidden||adminState.resetAllowed!==officialStagingUrl) throw new Error('administrator staging lifecycle controls unavailable or origin guard incorrect: '+JSON.stringify({adminState,officialStagingUrl}));
  if(viewerState.role==='administrator'||viewerState.deletedHidden!==true||viewerState.adminActive||viewerState.directRoute==='deleted') throw new Error('non-admin lifecycle controls exposed: '+JSON.stringify(viewerState));
  const browserState=await adminPage.evaluate(()=>({
    realtimeRefreshHook: /app\.emailVehicleLocationService\.subscribe\(\(\) => \{[\s\S]*refreshEmailVehicleLocations\(\)[\s\S]*loadDeletedVehicleSnapshot\(\{ force: true \}\)/.test(document.documentElement.innerHTML) ? 'markup' : 'runtime',
    adminGuard: vehicleLifecycleAdministratorActive(),
    resetGuard: vehicleLifecycleStagingResetAllowed(),
  }));
  if(!browserState.adminGuard||browserState.resetGuard!==officialStagingUrl) throw new Error('browser lifecycle guards failed: '+JSON.stringify({browserState,officialStagingUrl}));
  if(errors.length) throw new Error('browser page errors: '+errors.join('; '));
  console.log(JSON.stringify({schema:'pdc.delete-vehicle-browser-acceptance/v2',url:URL,projectRef:adminState.projectRef,adminState,viewerState,browserState,pageErrors:errors,mode:'two-page real authentication and role/direct-route contract; live lifecycle covered by staging DB acceptance',passed:true},null,2));
  await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
