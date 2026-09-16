const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
function runtime(role='administrator') {
 const nodes=Object.fromEntries(['nav-user-management','user-management','user-management-content'].map(id=>[id,{hidden:false,innerHTML:'old users',replaceChildren(){this.innerHTML='';}}]));
 const state={reads:0,rpcs:0,removed:0};
 const c={window:{PDC_AUTH_CONTEXT:{role},PDC_SUPABASE:{removeChannel(){state.removed++;},rpc:async()=>{state.rpcs++;return {};}}},document:{getElementById:id=>nodes[id]},$:s=>nodes[s.slice(1)],backupStatusSharedModeReady:()=>c.window.PDC_AUTH_CONTEXT?.role==='administrator',escapeHtml:String,cleanNavisionText:String};
 vm.createContext(c);
 vm.runInContext(source.slice(source.indexOf('const USER_MANAGEMENT_STATE ='),source.indexOf('function wireUserManagementActions()')),c);
 c.subscribeUserManagementRealtime=()=>{};
 c.loadUserManagementRows=async()=>{state.reads++;return [];};
 return {c,nodes,state};
}
for(const role of ['operator','fitter','viewer','importer',undefined]) test(`${role||'signed out'} cannot see, load or change user management`,async()=>{
 const {c,nodes,state}=runtime(role); if(role===undefined)c.window.PDC_AUTH_CONTEXT=null;
 assert.equal(c.syncUserManagementAccess(),false);
 assert.equal(nodes['nav-user-management'].hidden,true);
 assert.equal(nodes['user-management'].hidden,true);
 await c.renderUserManagementScreen();
 assert.equal(await c.userManagementCallRpc('admin_disable_user',{}),false);
 assert.equal(state.reads,0);assert.equal(state.rpcs,0);
 assert.equal(nodes['user-management-content'].innerHTML,'');
});
test('administrator can see and load User Management',async()=>{
 const {c,nodes,state}=runtime();
 await c.renderUserManagementScreen();
 assert.equal(nodes['nav-user-management'].hidden,false);
 assert.equal(nodes['user-management'].hidden,false);
 assert.equal(state.reads,1);
 assert.match(nodes['user-management-content'].innerHTML,/No all accounts/);
});
test('downgrade clears users and subscription and ignores a late response',async()=>{
 const {c,nodes,state}=runtime();let finish;
 c.loadUserManagementRows=()=>new Promise(resolve=>{finish=resolve;});
 const pending=c.renderUserManagementScreen();
 vm.runInContext("USER_MANAGEMENT_STATE.rows=[{email:'private@example.invalid'}];USER_MANAGEMENT_STATE.realtimeChannel={};",c);
 c.window.PDC_AUTH_CONTEXT.role='operator';c.syncUserManagementAccess();
 finish([{email:'private@example.invalid'}]);await pending;
 assert.equal(nodes['user-management-content'].innerHTML,'');
 assert.equal(vm.runInContext('USER_MANAGEMENT_STATE.rows.length',c),0);
 assert.equal(state.removed,1);
});
test('direct User Management routes are blocked before any navigation effects',()=>{
 const start=source.indexOf('function showView(view, options)');
 const end=source.indexOf("  if (requestedView === 'pipeline')",start);
 for(const role of ['operator','viewer','importer','fitter','administrator',undefined]) {
  const {c}=runtime(role);if(role===undefined)c.window.PDC_AUTH_CONTEXT=null;
  vm.runInContext(source.slice(start,end)+'return requestedView;}',c);
  assert.equal(c.showView('user-management'),role==='administrator'?'user-management':role==='fitter'?'fitters':'dashboard');
 }
});
test('User Management starts hidden and cannot be exposed by sidebar display styles',()=>{
 const html=fs.readFileSync('index.html','utf8'),css=fs.readFileSync('styles.css','utf8');
 assert.match(html,/<button[^>]+id="nav-user-management"[^>]+hidden/);
 assert.match(html,/<section id="user-management"[^>]+hidden/);
 assert.match(css,/#nav-user-management\[hidden\], #user-management\[hidden\] \{ display: none !important; \}/);
});
