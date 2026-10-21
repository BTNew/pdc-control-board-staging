// r419 (F34): User Admin role lists offer every server role, preselect the real role (never a silent "viewer"),
// and every role change is confirmed first. The server guard (no self-demotion, last-admin count of admins who can
// sign in) is in supabase/migrations/*_r419_admin_role_guard.sql.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
function runtime({confirm=true}={}) {
 const notes=[];const confirms=[];const rpcs=[];
 const nodes={};
 const c={window:{PDC_AUTH_CONTEXT:{role:'administrator'},confirm:m=>{confirms.push(m);return confirm;},prompt:()=>null,PDC_SUPABASE:{rpc:async(n,p)=>{rpcs.push([n,p]);return {};}}},
  document:{getElementById:id=>nodes[id]},escapeHtml:s=>String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;'),cleanNavisionText:String,
  pdcNotify:(m)=>notes.push(m),backupStatusSharedModeReady:()=>true};
 vm.createContext(c);
 vm.runInContext(source.slice(source.indexOf('const USER_MANAGEMENT_STATE ='),source.indexOf('function cancelWorkshopPlannerRender()')),c);
 return {c,notes,confirms,rpcs};
}
const options=html=>[...html.matchAll(/<option value="([^"]*)"( selected)?>([^<]*)<\/option>/g)].map(m=>({value:m[1],selected:!!m[2],label:m[3]}));
test('approved row offers all six roles and preselects the real role, including fitter and salesperson',()=>{
 const {c}=runtime();
 for(const role of ['viewer','operator','importer','administrator','fitter','salesperson']){
  const opts=options(c.userManagementRowActionsHtml({email:'u@example.invalid',account_status:'approved',role}));
  assert.deepEqual(opts.map(o=>o.value),['viewer','operator','importer','administrator','fitter','salesperson']);
  assert.deepEqual(opts.filter(o=>o.selected).map(o=>o.value),[role]);
 }
});
test('Fitters row no longer shows viewer as its role',()=>{
 const {c}=runtime();
 const opts=options(c.userManagementRowActionsHtml({email:'f@example.invalid',account_status:'approved',role:'fitter'}));
 assert.equal(opts.find(o=>o.selected).value,'fitter');
 assert.equal(opts.find(o=>o.value==='viewer').selected,false);
});
test('an unknown role is shown as itself and selected, never replaced by the first option',()=>{
 const {c}=runtime();
 const opts=options(c.userManagementRowActionsHtml({email:'x@example.invalid',account_status:'approved',role:'auditor'}));
 assert.deepEqual(opts.filter(o=>o.selected).map(o=>o.value),['auditor']);
});
test('pending approval list includes fitter and salesperson; controller label kept',()=>{
 const {c}=runtime();
 const opts=options(c.userManagementRowActionsHtml({email:'p@example.invalid',account_status:'pending'}));
 assert.deepEqual(opts.map(o=>o.value),['viewer','operator','importer','administrator','fitter','salesperson']);
 assert.equal(opts.find(o=>o.value==='operator').label,'controller');
 assert.equal(c.userManagementRoleLabel('operator'),'controller');
 assert.match(c.userManagementRowHtml({email:'p@example.invalid',account_status:'approved',role:'operator',active:true}),/admin-role-cell">controller</);
});
test('role change asks for confirmation, warns on administrator changes and skips no-op changes',()=>{
 const {c,confirms,notes}=runtime();
 assert.equal(c.userManagementConfirmRoleChange('a@example.invalid','administrator','operator'),true);
 assert.match(confirms[0],/from administrator to controller/);assert.match(confirms[0],/lose administrator access/);
 assert.equal(c.userManagementConfirmRoleChange('a@example.invalid','operator','administrator'),true);
 assert.match(confirms[1],/full administrator access/);
 assert.equal(c.userManagementConfirmRoleChange('a@example.invalid','fitter','fitter'),false);
 assert.equal(confirms.length,2);assert.match(notes[0],/already fitter/);
 assert.equal(c.userManagementConfirmRoleChange('a@example.invalid','fitter',''),false);
});
test('declining the confirm sends nothing to the server',async()=>{
 const {c,rpcs}=runtime({confirm:false});
 const buttons=[];const select={value:'viewer',dataset:{umCurrentRole:'fitter'}};
 c.$=s=>s.startsWith('[data-um-role-for')?select:null;
 c.$$=s=>s==='[data-um-change-role]'?[{dataset:{umChangeRole:'f@example.invalid'},addEventListener:(e,fn)=>buttons.push(fn)}]:[];
 c.wireUserManagementActions();
 await buttons[0]();
 assert.equal(rpcs.length,0);
});
test('confirmed change calls admin_change_role with the chosen role',async()=>{
 const {c,rpcs}=runtime({confirm:true});
 const buttons=[];const select={value:'operator',dataset:{umCurrentRole:'administrator'}};
 c.$=s=>s.startsWith('[data-um-role-for')?select:null;
 c.$$=s=>s==='[data-um-change-role]'?[{dataset:{umChangeRole:'a@example.invalid'},addEventListener:(e,fn)=>buttons.push(fn)}]:[];
 c.renderUserManagementScreen=async()=>{};
 c.wireUserManagementActions();
 await buttons[0]();
 assert.deepEqual(JSON.parse(JSON.stringify(rpcs)),[['admin_change_role',{p_target_email:'a@example.invalid',p_role:'operator'}]]);
});
test('server migration refuses self-demotion and counts only admins who can sign in',()=>{
 const dir='supabase/migrations';const f=fs.readdirSync(dir).find(n=>/_r419_admin_role_guard\.sql$/.test(n));
 assert.ok(f,'r419 migration present');const sql=fs.readFileSync(`${dir}/${f}`,'utf8');
 assert.match(sql,/You cannot remove your own administrator role/);
 assert.match(sql,/pdc_effective_admin_count_419\(v_target\.id\)/);
 assert.match(sql,/u\.banned_until IS NULL OR u\.banned_until <= now\(\)/);
 assert.match(sql,/coalesce\(u\.last_sign_in_at, r\.last_sign_in_at\) IS NOT NULL/);
 assert.match(sql,/REVOKE ALL ON FUNCTION public\.pdc_effective_admin_count_419\(uuid\) FROM PUBLIC, anon, authenticated/);
});
