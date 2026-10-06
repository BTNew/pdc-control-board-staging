'use strict';
// Local runtime only, using fictional accounts, orders and intercepted requests.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http'),assert=require('node:assert/strict');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const runtime=path.resolve(process.argv[2]),output=path.resolve(process.argv[3]);
if(!fs.existsSync(path.join(runtime,'sales/index.html')))throw new Error('Provide built local runtime');
fs.mkdirSync(output,{recursive:true});
const baseFixture=fs.readFileSync(path.join(__dirname,'sales-completed-browser.js'),'utf8').match(/const fixtureScript=`([\s\S]*?)`;/)[1];
function fixture(role){
 let script=baseFixture;
 if(role==='bryce')script=script.replace("role:'administrator',display_name:'QA fixture',can_edit_finance:true","role:'salesperson',display_name:'Bryce fixture',salesperson_code:'BG',can_view_all_salespeople:true,can_edit_finance:false").replace("role:'administrator'","role:'salesperson'").replace('fixture@example.invalid · administrator','fixture@example.invalid · salesperson');
 script=script.replace('const f=window.__salesFixture;f.calls.push(name);','const f=window.__salesFixture;f.calls.push(name);ctx.can_view_all_salespeople=f.teamView!==false;');
 script=script.replace('JSON.parse(JSON.stringify(f.active))',"JSON.parse(JSON.stringify(ctx.role==='administrator'?f.active:f.active.filter(r=>r.salesperson_code===ctx.salesperson_code)))");
 script=script.replace("if(name==='get_broome_sales_snapshot')", "if(name==='get_broome_sales_board_snapshot')return{data:{context:ctx,items:JSON.parse(JSON.stringify(f.active.filter(r=>ctx.can_view_all_salespeople||r.salesperson_code===ctx.salesperson_code))),navision_updated_at:'2026-10-06T04:24:46Z',checked_at:'2026-10-06T04:30:00Z'}};\n  if(name==='get_broome_sales_snapshot')");
 script=script.replace("window.PDC_SUPABASE={rpc:","window.__salesFixture.notes.push({tracking_id:two.tracking_id,notes:'Other salesperson saved team note',custom_information:'Read-only shared instructions',version:1,updated_at:'2026-10-06T03:00:00Z'});\n window.PDC_SUPABASE={rpc:");
 return script;
}
const mime={'.html':'text/html','.js':'text/javascript','.css':'text/css','.png':'image/png','.svg':'image/svg+xml'};
const server=http.createServer((req,res)=>{
 const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'');
 const file=path.resolve(runtime,relative.endsWith('/')?relative+'index.html':relative);
 if(!file.startsWith(runtime+path.sep)){res.writeHead(403);return res.end();}
 fs.readFile(file,(error,data)=>{res.writeHead(error?404:200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});res.end(error?'Missing':data);});
});
(async()=>{
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const browser=await chromium.launch({channel:'msedge',headless:true}),results=[];
 try{
  for(const role of ['bryce','andy'])for(const [name,width,height] of [['desktop',1920,1080],['laptop',1366,768],['ipad',1024,768],['mobile',390,844]]){
   const context=await browser.newContext({viewport:{width,height}}),page=await context.newPage(),errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.route('**/*',route=>{
    const url=new URL(route.request().url());if(url.hostname!=='127.0.0.1')return route.abort();
    if(/\/pdc-auth\.js$/.test(url.pathname))return route.fulfill({contentType:'text/javascript',body:fixture(role)});
    if(/pdc-auth-registration\.js$|pdc-supabase-config\.staging\.js$/.test(url.pathname))return route.fulfill({contentType:'text/javascript',body:''});
    return route.continue();
   });
   await page.goto('http://127.0.0.1:'+server.address().port+'/sales/');
   const area=page.locator(width<=650?'#sales-mobile-vehicles':'#vehicle-table'),picker=page.locator('#salesperson-filter');
   await picker.waitFor({state:'visible'});await area.locator('[data-open="22222222-2222-4222-8222-222222222222"]').first().waitFor();
   assert.equal(await picker.inputValue(),role==='bryce'?'BG':'');
   await picker.selectOption('AW');await area.locator('[data-open="33333333-3333-4333-8333-333333333333"]').first().waitFor();
   assert.equal(await area.locator('[data-open="22222222-2222-4222-8222-222222222222"]').count(),0);
   const otherTicks=area.locator('[data-ordering-id="33333333-3333-4333-8333-333333333333"]');
   assert.equal(await otherTicks.first().isDisabled(),role==='bryce');
   await area.locator('[data-notes-toggle="33333333-3333-4333-8333-333333333333"]').first().click();
   const notes=area.locator('[data-notes-form="33333333-3333-4333-8333-333333333333"]');
   await notes.locator('textarea[name="notes"]').waitFor();
   await page.waitForFunction(()=>document.querySelector('[data-notes-form="33333333-3333-4333-8333-333333333333"] textarea')?.value==='Other salesperson saved team note');
   assert.equal(await notes.locator('button[type="submit"]').isDisabled(),role==='bryce');
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
   await page.screenshot({path:path.join(output,role+'-'+name+'-other-salesperson.png'),fullPage:true});
   await picker.selectOption('');assert.equal(await area.locator('[data-open="22222222-2222-4222-8222-222222222222"]').count()>0,true);
   await page.screenshot({path:path.join(output,role+'-'+name+'-all-salespeople.png'),fullPage:true});
   await picker.selectOption('BG');assert.equal(await area.locator('[data-ordering-id="22222222-2222-4222-8222-222222222222"]').first().isDisabled(),false);
   if(role==='bryce'){
    await picker.selectOption('AW');await area.locator('[data-open="33333333-3333-4333-8333-333333333333"]').first().click();
    await page.locator('#sales-detail').waitFor({state:'visible'});assert.match(await page.locator('#sales-detail-content').innerText(),/view only/);
    await page.evaluate(()=>window.__salesFixture.teamView=false);
    // Modal closes only after the new authorized snapshot excludes its order.
    await page.evaluate(()=>document.getElementById('sales-refresh').click());
    await picker.waitFor({state:'hidden'});await page.locator('#sales-detail').waitFor({state:'hidden'});
    assert.equal(await area.locator('[data-open="33333333-3333-4333-8333-333333333333"]').count(),0);
   }
   assert.deepEqual(errors,[]);results.push({role,viewport:name,selector:true,shared_rows:true,notes:role==='bryce'?'view_only':'editable',revocation:role==='bryce'?'passed':'existing_admin',errors});await context.close();
  }
  fs.writeFileSync(path.join(output,'results.json'),JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e.stack);process.exitCode=1;server.close();});
