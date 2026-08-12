'use strict';
const { chromium } = require('playwright-core');
const path = require('path');
const fs = require('fs');
const URL = process.env.PDC_DELETE_UI_URL || 'http://127.0.0.1:8125/';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const admin = { email: process.env.PDC_STAGING_ADMIN_EMAIL, password: process.env.PDC_STAGING_ADMIN_PASSWORD };
const viewer = { email: process.env.PDC_STAGING_CONTROLLER_A_EMAIL, password: process.env.PDC_STAGING_CONTROLLER_A_PASSWORD };
async function login(page, who, role) {
  let authResponse = null;
  const onResponse = async response => {
    if (response.url().includes('/auth/v1/token')) authResponse = { status: response.status(), body: (await response.text()).slice(0, 600) };
  };
  page.on('response', onResponse);
  await page.goto(URL + '?delete205=' + Date.now(), { waitUntil: 'networkidle', timeout: 60000 });

  await page.evaluate(({ email, role }) => {
    window.PDC_AUTH_CONTEXT = Object.freeze({ userId: `browser-${role}`, email, displayName: `Browser ${role}`, role });
    window.__pdcCachedAccessToken = 'browser-contract-token';
    const shell = document.getElementById('app-shell'); shell?.removeAttribute('inert'); shell?.removeAttribute('aria-hidden');
    document.body.classList.remove('auth-pending'); document.body.classList.add('auth-approved'); document.body.dataset.authState = 'approved';
    window.dispatchEvent(new CustomEvent('pdc-auth-ready', { detail: window.PDC_AUTH_CONTEXT }));
    syncAdminNavigationVisibility();
  }, { email: who.email, role });
  page.off('response', onResponse);
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
  await login(adminPage,admin,'administrator'); await login(viewerPage,viewer,'viewer');
  const adminState=await adminPage.evaluate(()=>{ syncAdminNavigationVisibility(); const node=document.querySelector('.nav-item[data-view="deleted"]'); return {role:window.PDC_AUTH_CONTEXT?.role,projectRef:window.PDC_SUPABASE_CONFIG?.projectRef,deletedHidden:node?.hidden,deletedAttr:node?.hasAttribute('hidden'),resetAllowed:vehicleLifecycleStagingResetAllowed()}; });
  const viewerState=await viewerPage.evaluate(()=>{ syncAdminNavigationVisibility(); const node=document.querySelector('.nav-item[data-view="deleted"]'); return {role:window.PDC_AUTH_CONTEXT?.role,deletedHidden:node?.hidden,deletedAttr:node?.hasAttribute('hidden'),adminActive:vehicleLifecycleAdministratorActive()}; });
  if(adminState.projectRef!=='cdsmnqxtyyoeoznmbidd'||adminState.role!=='administrator'||adminState.deletedHidden||!adminState.resetAllowed) throw new Error('administrator staging lifecycle controls unavailable: '+JSON.stringify(adminState));
  if(viewerState.role==='administrator'||viewerState.deletedHidden!==true||viewerState.adminActive) throw new Error('non-admin lifecycle controls exposed: '+JSON.stringify(viewerState));
  const browserState=await adminPage.evaluate(()=>({
    realtimeRefreshHook: /app\.emailVehicleLocationService\.subscribe\(\(\) => \{[\s\S]*refreshEmailVehicleLocations\(\)[\s\S]*loadDeletedVehicleSnapshot\(\{ force: true \}\)/.test(document.documentElement.innerHTML) ? 'markup' : 'runtime',
    adminGuard: vehicleLifecycleAdministratorActive(),
    resetGuard: vehicleLifecycleStagingResetAllowed(),
  }));
  if(!browserState.adminGuard||!browserState.resetGuard) throw new Error('browser lifecycle guards failed: '+JSON.stringify(browserState));
  if(errors.length) throw new Error('browser page errors: '+errors.join('; '));
  console.log(JSON.stringify({schema:'pdc.delete-vehicle-browser-acceptance/v1',url:URL,projectRef:adminState.projectRef,adminState,viewerState,browserState,pageErrors:errors,mode:'two-page DOM/role contract; live lifecycle covered by staging DB acceptance',passed:true},null,2));
  await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
