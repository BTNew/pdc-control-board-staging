'use strict';
const { chromium } = require('playwright-core');
const URL = process.env.PDC_DELETE_UI_URL || 'https://btnew.github.io/pdc-control-board-staging/';
const CHROME = process.env.PDC_CHROME_EXECUTABLE || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const users = {
  admin: { email: process.env.PDC_STAGING_ADMIN2_EMAIL, password: process.env.PDC_STAGING_ADMIN2_PASSWORD, role: 'administrator' },
  viewer: { email: process.env.PDC_STAGING_CONTROLLER_B_EMAIL, password: process.env.PDC_STAGING_CONTROLLER_B_PASSWORD, role: 'operator' },
};
async function login(page, who) {
  await page.goto(URL + '?accept=' + Date.now(), { waitUntil: 'networkidle', timeout: 60000 });
  await page.waitForFunction(() => document.body.dataset.authState === 'signed-out' || !document.getElementById('pdc-password-form')?.hidden, null, { timeout: 60000 });
  await page.locator('#pdc-login-email').fill(who.email); await page.locator('#pdc-login-password').fill(who.password); await page.locator('#pdc-password-login').click();
  try {
    await page.waitForFunction(role => window.PDC_AUTH_CONTEXT?.role === role && document.body.dataset.authState === 'approved', who.role, { timeout: 60000 });
  } catch (error) {
    const state=await page.evaluate(()=>({authState:document.body.dataset.authState,role:window.PDC_AUTH_CONTEXT?.role||null,title:document.getElementById('pdc-auth-title')?.textContent,message:document.getElementById('pdc-auth-message')?.textContent}));
    throw new Error(`real ${who.role} login failed: ${JSON.stringify(state)}; ${error.message}`);
  }
}
async function waitStock(page, stock, present) {
  await page.waitForFunction(({stock,present}) => {
    const rows = window.app?.emailVehicleLocationRows || [];
    return rows.some(r => String(r.stock_number || r.stock || '').trim() === stock) === present;
  }, {stock,present}, {timeout:60000});
}
(async()=>{
  for(const u of Object.values(users)) if(!u.email||!u.password) throw new Error('missing staging credential');
  const browser=await chromium.launch({executablePath:CHROME,headless:true});
  const admin=await browser.newPage({viewport:{width:1440,height:1000}}), viewer=await browser.newPage({viewport:{width:1280,height:800}}); const errors=[]; for(const p of [admin,viewer])p.on('pageerror',e=>errors.push(e.message));
  await Promise.all([login(admin,users.admin),login(viewer,users.viewer)]);
  const project=await admin.evaluate(()=>window.PDC_SUPABASE_CONFIG?.projectRef); if(project!=='cdsmnqxtyyoeoznmbidd')throw new Error('wrong project '+project);
  const stock=process.env.PDC_ACCEPT_STOCK, vehicleId=process.env.PDC_ACCEPT_VEHICLE_ID, version=Number(process.env.PDC_ACCEPT_VEHICLE_VERSION);
  if(!stock||!vehicleId||!Number.isInteger(version))throw new Error('missing disposable fixture identity');
  await Promise.all([waitStock(admin,stock,true),waitStock(viewer,stock,true)]);
  const controls=await admin.evaluate(stock=>{vehicleLocationBoardRows();const v=selectedVehicle(stock)||app.emailVehicleLocationRows.find(r=>String(r.stock_number)===stock);const opened=v?openVehicleModal(vehicleKey(v)):false;return {vehicleFound:!!v,opened,admin:vehicleLifecycleAdministratorActive(),shared:vehicleLifecycleSharedModeActive(),authorityReady:sharedNavisionLocationAuthorityReady(),deleteVisible:!!document.querySelector('[data-remove-vehicle]'),resetVisible:!!document.querySelector('[data-reset-test-vehicle]')}} ,stock);
  const viewerDenied=await viewer.evaluate(()=>{syncAdminNavigationVisibility();showView('deleted');return {admin:vehicleLifecycleAdministratorActive(),route:app.currentView,navHidden:document.querySelector('.nav-item[data-view="deleted"]')?.hidden}});
  if(!controls.deleteVisible||!controls.resetVisible||viewerDenied.admin||viewerDenied.route==='deleted'||viewerDenied.navHidden!==true)throw new Error('control authority failed '+JSON.stringify({controls,viewerDenied}));
  const archive=await admin.evaluate(async x=>window.__vehicleLifecycleActions.adminArchiveVehicle({vehicleId:x.vehicleId,expectedVersion:x.version,stockConfirmation:x.stock,reason:'Deployed two-user Realtime archive acceptance',resetTest:false}),{vehicleId,version,stock});
  if(!archive.ok)throw new Error('archive failed '+JSON.stringify(archive)); const tombstone=archive.data.tombstone_id;
  await Promise.all([waitStock(admin,stock,false),waitStock(viewer,stock,false)]);
  const restore=await admin.evaluate(async x=>window.__vehicleLifecycleActions.adminRestoreVehicle({tombstoneId:x.tombstone,stockConfirmation:x.stock,reason:'Deployed two-user Realtime restore acceptance'}),{tombstone,stock});
  if(!restore.ok)throw new Error('restore failed '+JSON.stringify(restore));
  await Promise.all([waitStock(admin,stock,true),waitStock(viewer,stock,true)]);
  const cleanup=await admin.evaluate(async x=>window.__vehicleLifecycleActions.adminArchiveVehicle({vehicleId:x.vehicleId,expectedVersion:x.version,stockConfirmation:x.stock,reason:'Remove deployed Realtime acceptance fixture',resetTest:false}),{vehicleId,version:restore.data.vehicle_version,stock});
  if(!cleanup.ok)throw new Error('cleanup failed '+JSON.stringify(cleanup));
  if(errors.length)throw new Error(errors.join('; '));
  console.log(JSON.stringify({schema:'pdc.delete-vehicle-deployed-realtime/v1',url:URL,projectRef:project,stock,controls,viewerDenied,archiveWithoutRefresh:true,restoreWithoutRefresh:true,twoAuthenticatedUsers:true,pageErrors:errors,productionAccessed:false,passed:true},null,2));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
