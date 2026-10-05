'use strict';
// Run against a built local runtime only. All data/auth/RPC responses are fictional.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const runtime=path.resolve(process.argv[2]),output=path.resolve(process.argv[3]);
if(!fs.existsSync(path.join(runtime,'sales/index.html')))throw new Error('Provide a built local runtime');
fs.mkdirSync(output,{recursive:true});
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{
 const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'');
 const file=path.resolve(runtime,relative.endsWith('/')?relative+'index.html':relative);
 if(!file.startsWith(runtime+path.sep)){res.writeHead(403);return res.end();}
 fs.readFile(file,(error,data)=>{res.writeHead(error?404:200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});res.end(error?'Missing':data);});
});
const fixtureScript=`
 window.PDC_AUTH_CONTEXT={userId:'11111111-1111-4111-8111-111111111111',role:'administrator'};
 const ctx={role:'administrator',display_name:'QA fixture',can_edit_finance:true,dealer_code:'37047'};
 const one={tracking_id:'22222222-2222-4222-8222-222222222222',stock:'QA-101',order:'250000001',transport_number:'001234',autocare_dispatch_version:0,client:'Fictional North Coast Customer',vehicle:'HiLux 4x4 Dual Cab',salesperson_code:'BG',cosi:true,source_current:true,toyota_status:'Despatched - From TWA',navision_notes:'Tray and build request',ordering_version:0};
 const two={...one,tracking_id:'33333333-3333-4333-8333-333333333333',stock:'',order:'250000002',salesperson_code:'AW',client:'Fictional Long Customer Name for Layout Verification',vehicle:'LandCruiser 300 Series 3.3L Diesel Wagon GX Automatic',navision_notes:''};
 const gone={...one,tracking_id:'44444444-4444-4444-8444-444444444444',stock:'QA-OLD',order:'250000003',client:'Fictional Removed Order',source_current:false,completion_reason:'absent_from_navision',completed_at:'2026-10-05T04:24:46Z',last_seen_at:'2026-10-01T01:00:00Z',notes:'Saved staff instruction retained after omission',custom_information:'Keep delivery paperwork in the vehicle folder'};
 window.__salesFixture={active:[one,two],completed:[gone],notes:[{tracking_id:one.tracking_id,notes:'Confirmed manual note',custom_information:'',version:1,updated_at:'2026-10-05T04:00:00Z'}],calls:[],financeDelay:0,financeError:false,
  financeEntries:Array.from({length:80},(_,i)=>({id:'qa-finance-'+i,customer:'Fictional Finance Customer '+(i+1),new_used:i%2?'Used':'New',financier:'TFS',group_name:'Broome',approval:'Yes',settlement:'No',notes:'Fictional application',salesperson_code:'BG',version:1,created_at:'2026-10-05T04:00:00Z'}))};
 window.PDC_SUPABASE={rpc:async(name,args)=>{
  const f=window.__salesFixture;f.calls.push(name);
  if(name==='get_broome_sales_snapshot')return{data:{context:ctx,items:JSON.parse(JSON.stringify(f.active)),navision_updated_at:'2026-10-05T04:24:46Z',checked_at:'2026-10-05T04:30:00Z'}};
  if(name==='get_broome_completed_sales_vehicles')return{data:{context:ctx,items:JSON.parse(JSON.stringify(f.completed)),navision_updated_at:'2026-10-05T04:24:46Z'}};
  if(name==='get_broome_sales_vehicle_notes')return{data:f.notes};
  if(name==='save_broome_sales_vehicle_notes'){
   const record={tracking_id:args.p_tracking_id,notes:args.p_notes,custom_information:args.p_custom_information,version:args.p_expected_version+1,updated_at:'2026-10-05T04:30:00Z'};
   f.notes=f.notes.filter(n=>n.tracking_id!==record.tracking_id);f.notes.push(record);return{data:record};
  }
  if(name==='get_broome_sales_workspace')return{data:{context:ctx,contacts:[],activities:[],tasks:[],delivery:[],finance:[],views:[],timeline:[],alerts:[],history:[]}};
  if(name==='get_broome_sales_builds')return{data:{context:ctx,items:[]}};
  if(name==='get_broome_finance_pipeline')return{data:{context:ctx,entries:JSON.parse(JSON.stringify(f.financeEntries)),vehicle_options:[],salespeople:[]}};
  if(name==='save_broome_finance_application'){
   await new Promise(r=>setTimeout(r,f.financeDelay));
   if(f.financeError){f.financeError=false;return{error:{message:'Fictional connection failure'}};}
   const record=f.financeEntries.find(r=>r.id===args.p_id);if(record.version!==args.p_expected_version)return{error:{message:'Changed elsewhere',code:'40001'}};
   Object.assign(record,args.p_data,{version:record.version+1});return{data:{record:JSON.parse(JSON.stringify(record))}};
  }
  if(name==='set_broome_sales_autocare_dispatch'){
   const items=args.p_entries.map(p=>{const record=f.active.find(r=>r.tracking_id===p.tracking_id);Object.assign(record,{autocare_dispatched:args.p_dispatched,autocare_dispatch_version:record.autocare_dispatch_version+1,autocare_dispatched_at:'2026-10-05T04:30:00Z'});return{tracking_id:record.tracking_id,autocare_dispatched:record.autocare_dispatched,autocare_dispatch_version:record.autocare_dispatch_version,autocare_dispatched_at:record.autocare_dispatched_at};});return{data:{items}};
  }
  if(name==='get_broome_customer_emails')return{data:{context:ctx,drafts:[]}};
  throw new Error('Unexpected fixture RPC '+name);
 }};
 document.body.dataset.authState='ready';document.body.classList.remove('auth-pending');
 document.getElementById('pdc-auth-gate').hidden=true;
 const account=document.getElementById('pdc-auth-user');account.hidden=false;account.textContent='fixture@example.invalid · administrator';
 document.getElementById('pdc-auth-signout').hidden=false;
 const shell=document.getElementById('app-shell');shell.removeAttribute('inert');shell.removeAttribute('aria-hidden');
 window.dispatchEvent(new Event('pdc-auth-ready'));
`;
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const url='http://127.0.0.1:'+server.address().port+'/sales/';
 const browser=await chromium.launch({channel:'msedge',headless:true});const results=[];
 try{
  for(const [name,width,height] of [['desktop',1920,1080],['laptop',1366,768],['ipad',1024,768],['mobile',390,844]]){
   const context=await browser.newContext({viewport:{width,height}}),page=await context.newPage(),errors=[];
   page.on('pageerror',error=>errors.push(error.message));
   await page.route('**/*',route=>{
    const requestUrl=new URL(route.request().url());
    if(requestUrl.hostname!=='127.0.0.1')return route.abort();
    if(/\/pdc-auth\.js$/.test(requestUrl.pathname))return route.fulfill({contentType:'text/javascript',body:fixtureScript});
    if(/pdc-auth-registration\.js$|pdc-supabase-config\.staging\.js$/.test(requestUrl.pathname))return route.fulfill({contentType:'text/javascript',body:''});
    return route.continue();
   });
   await page.goto(url);await page.locator(width<=650?'.mobile-navision-notes.has-staff-note':'.notes-cell.has-staff-note').first().waitFor();
   const orange=await page.locator(width<=650?'.mobile-navision-notes.has-staff-note':'.notes-cell.has-staff-note').first().evaluate(el=>getComputedStyle(el).backgroundColor);
   assert.equal(orange,'rgb(255, 240, 220)');
   const activeArea=page.locator(width<=650?'#sales-mobile-vehicles':'#vehicle-table');
   assert.equal(await activeArea.locator('.has-staff-note').count(),1,'only saved manual note gets orange');
   const controls=await page.locator('.topbar-actions select,.topbar-actions>button,.tracker-panel>.panel-header .panel-actions>button').evaluateAll(elements=>elements.filter(el=>el.getClientRects().length).map(el=>({id:el.id,height:el.getBoundingClientRect().height,font:getComputedStyle(el).fontSize})));
   for(const control of controls){assert.equal(control.height,width<=650?44:40,'matching control height: '+control.id);assert.equal(control.font,'13px','matching control font: '+control.id);}
   const selectors=await page.locator('#salesperson-filter-label,.topbar-actions .site-switcher').evaluateAll(elements=>elements.map(el=>({display:getComputedStyle(el).display,label:el.querySelector('span').getBoundingClientRect().y,select:el.querySelector('select').getBoundingClientRect().y})));
   for(const selector of selectors){assert.equal(selector.display,'grid');assert.ok(selector.select>selector.label,'both dropdown labels sit above their controls');}
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,'dashboard controls fit without page overflow');
   await page.screenshot({path:path.join(output,name+'-dashboard.png'),fullPage:true});
   const row=activeArea.locator('[data-note-row="33333333-3333-4333-8333-333333333333"]');
   await row.locator('[data-notes-toggle]').first().click();
   await activeArea.locator('[data-notes-form="33333333-3333-4333-8333-333333333333"] [name="notes"]').fill('New staff note');
   assert.equal(await activeArea.locator('.has-staff-note').count(),1,'unsaved draft does not imply a saved note');
   await activeArea.locator('[data-notes-form="33333333-3333-4333-8333-333333333333"] button[type="submit"]').click();
   await page.waitForFunction(()=>document.querySelectorAll(window.innerWidth<=650?'#sales-mobile-vehicles .has-staff-note':'#vehicle-table .has-staff-note').length===2);
   await activeArea.locator('[data-notes-form="33333333-3333-4333-8333-333333333333"] [name="notes"]').fill('');
   await activeArea.locator('[data-notes-form="33333333-3333-4333-8333-333333333333"] button[type="submit"]').click();
   await page.waitForFunction(()=>document.querySelectorAll(window.innerWidth<=650?'#sales-mobile-vehicles .has-staff-note':'#vehicle-table .has-staff-note').length===1);
   await page.locator('#search').fill('001234');await page.waitForFunction(()=>document.getElementById('sales-summary').textContent.includes('2 vehicles shown'));
   if(width<=650){for(const id of ['22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333'])await activeArea.locator('[data-select="'+id+'"]').check();}
   else await page.locator('#sales-select-visible').check();
   await page.locator('#sales-dispatch-selected').click();await page.waitForFunction(()=>document.getElementById('sales-dispatch-status').textContent.includes('2 vehicles marked'));
   assert.equal(await page.locator('#status-tabs [data-category="autocare"] strong').innerText(),'2');
   await page.screenshot({path:path.join(output,name+'-autocare.png'),fullPage:true});
   await page.evaluate(()=>window.__salesFixture.active[0].toyota_status='Delivered - At Dealer');await page.locator('#sales-refresh').click();
   await page.waitForFunction(()=>document.querySelector('#status-tabs [data-category="dealer"] strong').textContent==='1');
   assert.equal(await page.locator('#status-tabs [data-category="autocare"] strong').innerText(),'1');
   await page.locator('#sales-clear-filters').click();
   await page.locator('[data-sales-view="history"]').click();await page.locator('.completed-table').waitFor();
   assert.match(await page.locator('#completed-results').innerText(),/QA-OLD/);
   await page.locator('.completed-notes summary').click();assert.match(await page.locator('#completed-results').innerText(),/Saved staff instruction retained/);
   assert.equal(await page.locator('.completed-notes').evaluate(el=>{const end=el.querySelector('div:last-child').getBoundingClientRect().bottom;return end<=el.closest('td').getBoundingClientRect().bottom+1;}),true,'expanded saved information is not clipped');
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true,'no page overflow');
   await page.screenshot({path:path.join(output,name+'-completed.png'),fullPage:true});
   await page.locator('#completed-search').fill('250000003');assert.match(await page.locator('#completed-results').innerText(),/QA-OLD/);
   await page.locator('#completed-search').fill('NO-MATCH');assert.match(await page.locator('#completed-results').innerText(),/No completed vehicles/);
   await page.locator('#completed-search').fill('');
   // Reappearance, followed by another omission: exercise the same refresh/navigation used after real uploads.
   await page.evaluate(()=>{const f=window.__salesFixture;f.active.push({...f.completed[0],source_current:true});f.completed=[];});
   await page.locator('#sales-refresh').click();await page.waitForFunction(()=>document.getElementById('completed-results').textContent.includes('No completed vehicles'));
   await page.locator('[data-sales-view="dashboard"]').click();assert.match(await activeArea.innerText(),/QA-OLD/);
   await page.evaluate(()=>{const f=window.__salesFixture;const old=f.active.pop();f.completed=[{...old,source_current:false}];});
   await page.locator('#sales-refresh').click();await page.waitForFunction(()=>!document.getElementById('vehicle-table').textContent.includes('QA-OLD'));
   await page.locator('[data-sales-view="history"]').click();await page.locator('.completed-table').waitFor();assert.match(await page.locator('#completed-results').innerText(),/QA-OLD/);
   await page.locator('[data-sales-view="finance"]').click();await page.locator('.finance-pipeline-table').waitFor();
   await page.evaluate(()=>window.scrollTo(0,900));
   const header=page.locator(width>800?'.finance-pipeline-table thead':'.finance-pipeline-heading');
   const headerBox=await header.boundingBox();assert.ok(headerBox&&Math.abs(headerBox.y)<=2,'Finance header follows document scrolling: '+JSON.stringify(headerBox));
   if(width>800){
    assert.equal(await page.locator('.finance-pipeline-table thead select').count(),15);
    await page.locator('.finance-pipeline-table thead [data-finance-filter="new_used"]').selectOption('value:New');
    assert.equal(await page.locator('.finance-pipeline-table tbody tr').count(),40,'sticky filter remains functional');
    assert.ok(Math.abs((await header.boundingBox()).y)<=2,'Finance headings stay pinned after filtering');
   }
   await page.screenshot({path:path.join(output,name+'-finance-sticky-header.png')});
   await page.locator('[data-finance-id="qa-finance-0"][data-finance-key="notes"]').fill('Automatic note');
   await page.waitForFunction(()=>window.__salesFixture.financeEntries[0].notes==='Automatic note');
   assert.equal(await page.locator('[data-finance-status="qa-finance-0"]').innerText(),'Saved');
   await page.evaluate(()=>window.__salesFixture.financeDelay=800);
   const note=page.locator('[data-finance-id="qa-finance-0"][data-finance-key="notes"]');await note.fill('Slow first edit');
   await page.waitForFunction(()=>document.querySelector('[data-finance-status="qa-finance-0"]').textContent==='Saving…');await note.fill('Latest edit kept');
   await page.waitForFunction(()=>window.__salesFixture.financeEntries[0].notes==='Latest edit kept');assert.equal(await note.inputValue(),'Latest edit kept');
   await page.evaluate(()=>{window.__salesFixture.financeDelay=0;window.__salesFixture.financeError=true;});await note.fill('Retained after error');
   await page.waitForFunction(()=>document.querySelector('[data-finance-status="qa-finance-0"]').textContent.includes('connection failure'));assert.equal(await note.inputValue(),'Retained after error');
   await page.locator('[data-finance-save="qa-finance-0"]').click();await page.waitForFunction(()=>window.__salesFixture.financeEntries[0].notes==='Retained after error');
   const date=page.locator('[data-finance-id="qa-finance-0"][data-finance-key="settlement_date"]');await date.fill('2024-02-29');await date.press('Tab');
   await page.waitForFunction(()=>window.__salesFixture.financeEntries[0].settlement_date==='2024-02-29');assert.equal(await page.evaluate(()=>window.__salesFixture.financeEntries[0].settlement),'Yes');
   assert.deepEqual(errors,[]);results.push({viewport:name,passed:true,manual_note_colour:orange,errors});await context.close();
  }
  fs.writeFileSync(path.join(output,'verification.json'),JSON.stringify(results,null,2)+'\n');console.log(JSON.stringify(results));
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);server.close();process.exitCode=1;});
