'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const crypto=require('node:crypto');
const parser=require('./sales/navision-orders.js');
const {createImporter}=require('./broome-navision-import.js');
const source=fs.readFileSync(require.resolve('./app.js'),'utf8');
function slice(name){const start=source.indexOf(name);assert.ok(start>=0,name);const end=source.slice(start+1).search(/\n(?:async )?function /);return source.slice(start,start+end+1);}
const header='Order\tBatch\tCOSI\tDealer\tSalesperson\tCustomer Surname\tModel Description\tProduction Month\tETA At Kewdale Yard';
const text=header+'\n'+Array.from({length:260},(_,i)=>['TEST-ORDER-'+i,i<98?'':'TEST-STOCK-'+i,'Yes','037047','BG 19751217','Example customer','Example vehicle','202611','15/11/2026'].join('\t')).join('\n');
function receipt(applied=false){return {accepted:260,without_stock:98,skipped_unsold:0,visibility_updates:0,changed:applied?260:0,applied};}
function host(callback){const calls=[];const h={PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd'},PDC_AUTH_CONTEXT:{userId:'example-admin',email:'admin@example.invalid',role:'administrator'},BROOME_NAVISION_ORDERS:parser,PDC_SUPABASE:{rpc:async(name,args)=>{calls.push({name,args});return callback?callback(name,args):{data:receipt(args.p_apply),error:null};}}};return {h,calls,api:createImporter(h)};}
function runtime(dealer='37047',callback){
 const r=host(callback),status={innerHTML:''},stats=new Map(),parseCalls=[];
 const elements={'#navision-paste':{value:text},'#navision-dealer-code':{value:dealer},'#navision-status-list':status,'#navision-scan-card':{querySelector:s=>{if(!stats.has(s))stats.set(s,{textContent:''});return stats.get(s);}}};
 const context={window:r.h,app:{pendingSharedNavisionImport:null},$:s=>elements[s],sha256Hex:s=>crypto.createHash('sha256').update(s).digest('hex'),prepareNavisionText:s=>s,escapeHtml:s=>String(s).replaceAll('<','&lt;'),updateNavisionImportButton(){},navisionWaitForBusyPaint:async()=>{},setNavisionPreviewBusy(v){context.app.navisionPreviewInFlight=v;},navisionImportOptionsFromDom:()=>({}),parseNavisionInput:(sourceText,options)=>{parseCalls.push({sourceText,options});throw new Error('PMB batch-required parser called');},importNavisionVehiclesLocal(){throw new Error('Local importer called');}};
 r.h.BROOME_NAVISION_IMPORT=r.api;
 r.h.alert=msg=>{throw new Error('Unexpected alert: '+msg);};
 vm.createContext(context);
 for(const name of ['function navisionSharedImportRoleAllowed(','function navisionSharedApplyAuthorityIdentity(','function navisionSharedPendingStillCurrent(','function navisionSharedPreviewRequestStillCurrent(','function sharedNavisionPreviewErrorMessage(','function reportSharedNavisionPreviewError(','function renderBroomeNavisionOrders(','async function previewBroomeNavisionOrders(','async function applyBroomeNavisionOrders(','async function importNavisionVehicles(','function updateNavisionControlStats('])vm.runInContext(slice(name),context);
 return {...r,context,elements,status,stats,parseCalls};
}
test('Broome root preview accepts all 260 sold orders, including 98 blank batches',async()=>{
 const r=runtime();await r.context.importNavisionVehicles();const p=r.context.app.pendingSharedNavisionImport;
 assert.equal(p.route,'broome_sales_orders');assert.equal(p.rows.length,260);assert.equal(p.rows.filter(x=>!x.batch).length,98);
 assert.equal(p.rows[0].consultant,'BG');assert.equal(p.rows[0].dealer_code,'37047');assert.equal(p.rows[0].navisionKewdaleEta,'2026-11-15');
 assert.equal(r.calls.length,1);assert.equal(r.calls[0].name,'import_broome_sales_orders');assert.equal(r.calls[0].args.p_apply,false);
 assert.match(r.status.innerHTML,/98/);assert.match(r.status.innerHTML,/PDC vehicles, Parts, locations and workshop bookings are unchanged/);
 r.context.updateNavisionControlStats();assert.equal(r.stats.get('.navision-detected strong').textContent,'260 rows');assert.equal(r.stats.get('.navision-updated strong').textContent,'98 sold orders without stock accepted');
 await r.context.applyBroomeNavisionOrders(p,r.context.navisionSharedApplyAuthorityIdentity());assert.equal(r.calls[1].args.p_apply,true);assert.equal(r.calls[1].args.p_rows,p.rows);assert.equal(r.context.app.pendingSharedNavisionImport,null);
 assert.match(r.status.innerHTML,/import complete/);
});
test('Other dealer profiles retain the stock-required PMB parser',async()=>{
 for(const dealer of ['14450','001234','002345','combined']){
  const r=runtime(dealer),alerts=[];r.h.alert=message=>alerts.push(message);
  await r.context.importNavisionVehicles();
  assert.equal(r.parseCalls.length,1);assert.equal(r.parseCalls[0].sourceText,text);assert.equal(r.parseCalls[0].options.uploadProfile,null);
  assert.equal(r.calls.length,0);assert.equal(r.context.app.pendingSharedNavisionImport,null);assert.equal(r.context.app.navisionPreviewInFlight,false);
  assert.match(alerts[0],/file could not be checked/);assert.doesNotMatch(alerts[0],/PMB batch-required parser called/);
 }
});
test('Broome upload is denied to salespeople, importers, anonymous users and production',async()=>{
 for(const role of ['salesperson','importer','viewer','']){const r=host();r.h.PDC_AUTH_CONTEXT.role=role;await assert.rejects(r.api.preview(text),/Administrator access/);assert.equal(r.calls.length,0);}
 const r=host();r.h.PDC_SUPABASE_CONFIG.projectRef='vjdtsswhroyguxyfjdkt';await assert.rejects(r.api.preview(text),/Administrator access/);assert.equal(r.calls.length,0);
 const q=host();q.h.PDC_AUTH_CONTEXT.userId='';assert.equal(q.api.allowed(),false);
});
test('Preview never becomes applicable after input, dealer or account changes',async()=>{
 for(const change of [r=>{r.elements['#navision-paste'].value+='\nchanged';},r=>{r.elements['#navision-dealer-code'].value='14450';},r=>{r.h.PDC_AUTH_CONTEXT.userId='other-admin';}]){let finish;const r=runtime('37047',()=>new Promise(resolve=>{finish=resolve;}));const pending=r.context.importNavisionVehicles();await new Promise(resolve=>setImmediate(resolve));change(r);finish({data:receipt(),error:null});await pending;assert.equal(r.context.app.pendingSharedNavisionImport,null);}
});
test('Apply rejects modified reviewed rows and switched accounts before making a request',async()=>{
 const r=host();const p=await r.api.preview(text);p.rows[0].order='CHANGED';await assert.rejects(r.api.apply(p),/reviewed order rows changed/);assert.equal(r.calls.length,1);
 const q=host();const a=await q.api.preview(text);q.h.PDC_AUTH_CONTEXT.userId='other-admin';await assert.rejects(q.api.apply(a),/access changed/);assert.equal(q.calls.length,1);
});
test('Root apply refuses changed source and dealer scope',async()=>{
 for(const change of [r=>{r.elements['#navision-paste'].value+=' changed';},r=>{r.elements['#navision-dealer-code'].value='14450';}]){const r=runtime();await r.context.importNavisionVehicles();const p=r.context.app.pendingSharedNavisionImport;change(r);await r.context.applyBroomeNavisionOrders(p,r.context.navisionSharedApplyAuthorityIdentity());assert.equal(r.calls.length,1);}
});
test('Uncertain apply retains its preview and does not claim nothing was imported',async()=>{
 const r=runtime('37047',(_name,args)=>args.p_apply?Promise.reject(new Error('Network response lost')):{data:receipt(),error:null});await r.context.importNavisionVehicles();const p=r.context.app.pendingSharedNavisionImport;await r.context.applyBroomeNavisionOrders(p,r.context.navisionSharedApplyAuthorityIdentity());assert.equal(r.context.app.pendingSharedNavisionImport,p);assert.match(r.status.innerHTML,/could not be confirmed/);assert.doesNotMatch(r.status.innerHTML,/Nothing was imported|No orders were imported/);
});
test('Broome duplicate preview clicks issue one read-only request',async()=>{
 let finish;const r=runtime('37047',()=>new Promise(resolve=>{finish=resolve;}));const first=r.context.importNavisionVehicles();await new Promise(resolve=>setImmediate(resolve));await r.context.importNavisionVehicles();assert.equal(r.calls.length,1);finish({data:receipt(),error:null});await first;assert.equal(r.context.app.navisionPreviewInFlight,false);
});
test('Malformed or wrong-mode receipts cannot enable apply or show completion',async()=>{
 for(const data of [{},{...receipt(),accepted:-1},{...receipt(),without_stock:'98'},{...receipt(),applied:true}]){const r=host(()=>({data,error:null}));await assert.rejects(r.api.preview(text),/result could not be checked/);}
});
test('Root loads the stockless parser and bridge before the application',()=>{
 const html=fs.readFileSync(require.resolve('./index.html'),'utf8');assert.ok(html.indexOf('sales/navision-orders.js')<html.indexOf('broome-navision-import.js'));assert.ok(html.indexOf('broome-navision-import.js')<html.indexOf('<script src="app.js'));
 assert.match(slice('async function applySharedNavisionImportPending('),/pending\?\.route === 'broome_sales_orders'/);
});

test('Uploaded text and Excel use the same Broome stockless route and count',async()=>{
 for(const excel of [false,true]){const r=runtime();Object.assign(r.context,{console,isXlsxFile:()=>excel,readTextFile:async()=>text,readXlsxVehicleSpreadsheet:async()=>({text,sheetName:'Orders',rows:parser.cells(text),headerRowIndex:0})});vm.runInContext(slice('async function handleNavisionFileSelect('),r.context);await r.context.handleNavisionFileSelect({target:{files:[{name:excel?'example.xlsx':'example.tsv'}]}});assert.match(r.status.innerHTML,/260 Broome source rows detected/);assert.doesNotMatch(r.status.innerHTML,/PMB batch-required/);await r.context.importNavisionVehicles();assert.equal(r.context.app.pendingSharedNavisionImport.rows.length,260);}
});
test('Duplicate apply clicks submit the reviewed Broome orders once',async()=>{
 let finish;const r=runtime('37047',(_name,args)=>args.p_apply?new Promise(resolve=>{finish=resolve;}):{data:receipt(),error:null});r.context.setNavisionSharedApplyBusy=v=>{r.context.app.navisionSharedApplyInFlight=v;};vm.runInContext(slice('async function applySharedNavisionImport('),r.context);vm.runInContext(slice('async function applySharedNavisionImportPending('),r.context);await r.context.importNavisionVehicles();const first=r.context.applySharedNavisionImport();await new Promise(resolve=>setImmediate(resolve));await r.context.applySharedNavisionImport();assert.equal(r.calls.length,2);finish({data:receipt(true),error:null});await first;assert.equal(r.context.app.navisionSharedApplyInFlight,false);
});
