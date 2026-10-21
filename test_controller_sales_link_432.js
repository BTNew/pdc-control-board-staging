// r432 (F43): a controller whose account is linked to a salesperson record can also use the Sales site as that salesperson,
// keeping the controller role. Server: supabase/migrations/*_r432_controller_sales_link.sql (Sales check, admin link RPC, link status).
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const app=fs.readFileSync('app.js','utf8');
const auth=fs.readFileSync('pdc-auth.js','utf8');
const mig=fs.readFileSync('supabase/migrations/20261021044811_r432_controller_sales_link.sql','utf8');
const down=fs.readFileSync('supabase/rollbacks/20261021044811_r432_controller_sales_link.down.sql','utf8');
function userAdmin(confirmAnswer=true,rpcResult={data:{ok:true,already_linked:false,salesperson_code:'ZZ',salesperson_name:'Synthetic Person'},error:null}){
 const confirms=[];const notes=[];const calls=[];
 const c={window:{PDC_AUTH_CONTEXT:{role:'administrator'},confirm:m=>{confirms.push(m);return confirmAnswer;},prompt:()=>null,
   PDC_SUPABASE:{rpc:async(name,args)=>{calls.push([name,args]);return rpcResult;}}},
  document:{getElementById:()=>null},escapeHtml:String,cleanNavisionText:String,pdcNotify:(m,k)=>notes.push([m,k]),backupStatusSharedModeReady:()=>true,
  $:()=>null,$$:()=>[]};
 vm.createContext(c);
 vm.runInContext(app.slice(app.indexOf('const USER_MANAGEMENT_STATE ='),app.indexOf('function cancelWorkshopPlannerRender()')),c);
 c.renderUserManagementScreen=async()=>{};
 return {c,confirms,notes,calls};
}
test('User Admin offers "Link salesperson record" on approved controller rows only',()=>{
 const {c}=userAdmin();
 const row=role=>({email:'x@example.invalid',role,account_status:'approved',active:true});
 assert.match(c.userManagementRowActionsHtml(row('operator')),/data-um-link-sales="x@example\.invalid"[^>]*>Link salesperson record</);
 for(const role of ['viewer','importer','administrator','fitter','salesperson'])
  assert.doesNotMatch(c.userManagementRowActionsHtml(row(role)),/data-um-link-sales/);
 assert.doesNotMatch(c.userManagementRowActionsHtml({email:'x@example.invalid',role:'operator',account_status:'disabled'}),/data-um-link-sales/);
});
test('linking asks first, calls the admin RPC with the email and reports the record',async()=>{
 const {c,confirms,notes,calls}=userAdmin();
 assert.equal(await c.userManagementLinkSalesRecord('x@example.invalid'),true);
 assert.match(confirms[0],/salesperson record with the same email/);
 assert.match(confirms[0],/stay a controller \(no extra admin access\)/);
 assert.equal(JSON.stringify(calls),JSON.stringify([['admin_link_controller_salesperson_432',{p_target_email:'x@example.invalid'}]]));
 assert.match(notes[0][0],/linked to Synthetic Person \(ZZ\) and can now use the Sales site/);
});
test('declined confirm sends nothing; a refusal is shown; already linked says nothing changed',async()=>{
 let t=userAdmin(false);
 assert.equal(await t.c.userManagementLinkSalesRecord('x@example.invalid'),false);
 assert.equal(t.calls.length,0);
 t=userAdmin(true,{data:null,error:{message:'No active salesperson record has the email x@example.invalid.'}});
 assert.equal(await t.c.userManagementLinkSalesRecord('x@example.invalid'),false);
 assert.match(t.notes[0][0],/Action failed: No active salesperson record/);
 t=userAdmin(true,{data:{ok:true,already_linked:true,salesperson_code:'ZZ',salesperson_name:'Synthetic Person'},error:null});
 await t.c.userManagementLinkSalesRecord('x@example.invalid');
 assert.match(t.notes[0][0],/already linked to Synthetic Person \(ZZ\)\. Nothing changed\./);
});
function route(role,salesLinked,site){
 const src=auth.slice(auth.indexOf('  function routeApprovedSite('),auth.indexOf('  function authPrincipalKey('));
 const replaced=[];
 const c={document:{body:{dataset:{pdcSite:site}}},window:{location:{href:'https://example.invalid/sales/',replace:u=>replaced.push(u)}},URL,lockOwnRoleAuthority:()=>{}};
 vm.createContext(c);vm.runInContext(src+';this.r=routeApprovedSite;',c);
 return {moved:c.r(role,salesLinked),replaced};
}
test('sign-in keeps a linked controller on the Sales site and sends an unlinked one back to the board',()=>{
 assert.equal(route('operator',true,'broome').moved,false);
 assert.equal(route('operator',false,'broome').moved,true);
 assert.equal(route('operator',undefined,'broome').moved,true);
 assert.equal(route('viewer',true,'broome').moved,true);
 assert.equal(route('importer',true,'broome').moved,true);
 assert.equal(route('salesperson',false,'broome').moved,false);
 assert.equal(route('administrator',false,'broome').moved,false);
 assert.equal(route('operator',true,undefined).moved,false);
 assert.equal(route('salesperson',false,undefined).moved,true);
 assert.match(auth,/state\.client\.rpc\('pdc_my_sales_link_432'\)/);
 assert.match(auth,/if \(role !== 'operator' \|\| !state\.client/);
 assert.match(auth,/role: role\.role,\n        salesLinked: false,/);
});
test('Sales check accepts linked controllers as a salesperson, never as administrator',()=>{
 assert.match(mig,/CREATE OR REPLACE FUNCTION pdc_sales_private\.context\(\)/);
 assert.match(mig,/IF coalesce\(r\.role::text,''\) NOT IN \('salesperson','operator'\) OR r\.auth_user_id IS DISTINCT FROM auth\.uid\(\) THEN/);
 assert.match(mig,/IF sp\.id IS NULL AND r\.role::text='operator' THEN RAISE EXCEPTION 'Salesperson access required'/);
 assert.match(mig,/IF r\.role::text='administrator' THEN\n  RETURN jsonb_build_object\('role','administrator'/);
 assert.match(mig,/RETURN jsonb_build_object\('role','salesperson','display_name',sp\.name,'salesperson_code',sp\.code,/);
 assert.match(mig,/'can_view_all_salespeople',scope\.can_view_all_salespeople,'account_role',r\.role::text\);/);
});
test('admin link RPC: administrators only, controllers only, same-email active record, no re-point, audited, closed to anon',()=>{
 assert.match(mig,/PERFORM public\.require_pdc_role\('administrator'\);/);
 assert.match(mig,/IF v_target\.role::text<>'operator' THEN/);
 assert.match(mig,/s\.active AND s\.email IS NOT NULL AND lower\(btrim\(s\.email\)\)=lower\(btrim\(v_target\.email\)\)/);
 assert.match(mig,/No active salesperson record has the email %/);
 assert.match(mig,/More than one active salesperson record has the email %/);
 assert.match(mig,/'already_linked',true/);
 assert.match(mig,/'operation','assign_broome_sales_access','via','admin_link_controller_salesperson','release','r432'/);
 assert.match(mig,/WHERE account_scopes\.user_role_id=excluded\.user_role_id;/);
 assert.doesNotMatch(mig,/can_view_all_salespeople\s*=/);
 assert.doesNotMatch(mig,/UPDATE public\.pdc_user_roles/);
 assert.match(mig,/REVOKE ALL ON FUNCTION public\.admin_link_controller_salesperson_432\(text\) FROM PUBLIC, anon, authenticated, service_role;/);
 assert.match(mig,/REVOKE ALL ON FUNCTION public\.pdc_my_sales_link_432\(\) FROM PUBLIC, anon, service_role;/);
});
test('release guards, pins, regression check and undo are in place',()=>{
 for(const s of [mig,down]){
  assert.match(s,/NOT BETWEEN 2 AND 45/);
  assert.match(s,/project_ref='cdsmnqxtyyoeoznmbidd'/);
  assert.doesNotMatch(s,/vjdtsswhroyguxyfjdkt/);
  assert.match(s,/84af7607bfd0ce9907c89bae8644d5b6/);
  assert.doesNotMatch(s,/CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/);
 }
 assert.match(mig,/'controller_sales_link','F43'/);
 assert.match(mig,/INSERT INTO pdc_ops\.expected_function_md5\(signature,prosrc_md5,release,note\) VALUES/);
 assert.match(down,/b0238d177dcdd68ec945a1964f4efac6/);
 assert.match(down,/DROP FUNCTION public\.admin_link_controller_salesperson_432\(text\);/);
 assert.match(down,/DROP FUNCTION public\.pdc_my_sales_link_432\(\);/);
 assert.match(down,/DELETE FROM pdc_ops\.regression_checks WHERE check_name='controller_sales_link' AND added_in='r432';/);
});
test('no staff emails or account ids in the release files',()=>{
 for(const s of [mig,down,fs.readFileSync(__filename,'utf8')]){
  assert.doesNotMatch(s,/@(broometoyota|pmgwa)\.com\.au/);
  assert.doesNotMatch(s,/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/);
 }
});
test('cache busts carry r432 (site-switcher.js is shared byte for byte with the frozen Department 135 copy, so it is unchanged)',()=>{
 assert.doesNotMatch(fs.readFileSync('index.html','utf8'),/site-switcher\.js\?[^"]*r432/);
 const index=fs.readFileSync('index.html','utf8'),sales=fs.readFileSync('sales/index.html','utf8');
 assert.match(index,/app\.js\?[^"]*&amp;r432=2026\.10\.21\.01(?:&amp;[^"]*)?"/);
 assert.match(index,/pdc-auth\.js\?[^"]*&amp;r432=2026\.10\.21\.01"/);
 assert.match(sales,/\.\.\/pdc-auth\.js\?[^"]*&amp;r432=2026\.10\.21\.01"/);
});
