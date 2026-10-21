// r430: User Admin's All list hides Disabled accounts by default, with a "Show disabled (N)" toggle.
// Display only: no account row is changed, no server call is made by the toggle.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
function runtime(){
 const rpcs=[];const froms=[];
 const c={window:{PDC_AUTH_CONTEXT:{role:'administrator'},confirm:()=>true,prompt:()=>null,
   PDC_SUPABASE:{rpc:async(n,p)=>{rpcs.push([n,p]);return {};},from:t=>{froms.push(t);throw new Error('no load in this test');}}},
  document:{getElementById:()=>null},escapeHtml:s=>String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/"/g,'&quot;'),cleanNavisionText:String,
  pdcNotify:()=>{},backupStatusSharedModeReady:()=>true,$$:()=>[]};
 vm.createContext(c);
 vm.runInContext(source.slice(source.indexOf('const USER_MANAGEMENT_STATE ='),source.indexOf('function cancelWorkshopPlannerRender()')),c);
 return {c,rpcs,froms};
}
const ROWS=[
 {email:'a@example.invalid',account_status:'approved',role:'operator',active:true},
 {email:'d1@example.invalid',account_status:'disabled',role:'viewer',active:false},
 {email:'p@example.invalid',account_status:'pending',active:false},
 {email:'r@example.invalid',account_status:'rejected',active:false},
 {email:'d2@example.invalid',account_status:'disabled',role:'fitter',active:false},
 {email:'legacy@example.invalid',active:false},
];
function host(){
 const h={innerHTML:'',_l:null};
 h.querySelector=sel=>(sel==='[data-um-toggle-disabled]'&&h.innerHTML.includes('data-um-toggle-disabled'))?{addEventListener:(t,f)=>{h._l=f;}}:null;
 h.click=()=>h._l&&h._l();
 return h;
}
test('All hides disabled accounts by default and counts them',()=>{
 const {c}=runtime();
 const v=c.userManagementVisibleRows(ROWS,'all',false);
 assert.deepEqual(v.rows.map(r=>r.email),['a@example.invalid','p@example.invalid','r@example.invalid']);
 assert.equal(v.disabledCount,3);assert.equal(v.hiddenDisabled,3);
});
test('Show disabled reveals every row in the original order',()=>{
 const {c}=runtime();
 const v=c.userManagementVisibleRows(ROWS,'all',true);
 assert.deepEqual(v.rows.map(r=>r.email),ROWS.map(r=>r.email));
 assert.equal(v.hiddenDisabled,0);
});
test('Pending, Approved, Rejected and Disabled tabs are unchanged',()=>{
 const {c}=runtime();
 for(const tab of ['pending','approved','rejected','disabled']){
  for(const show of [false,true]){
   assert.deepEqual(c.userManagementVisibleRows(ROWS,tab,show).rows.map(r=>r.email),ROWS.filter(r=>r.account_status===tab).map(r=>r.email));
  }
 }
});
test('toggle label shows the count and flips; no toggle when nothing is disabled',()=>{
 const {c}=runtime();
 assert.match(c.userManagementDisabledToggleHtml({disabledCount:3},false),/>Show disabled \(3\)</);
 assert.match(c.userManagementDisabledToggleHtml({disabledCount:3},true),/>Hide disabled \(3\)</);
 assert.match(c.userManagementDisabledToggleHtml({disabledCount:3},true),/aria-pressed="true"/);
 assert.equal(c.userManagementDisabledToggleHtml({disabledCount:0},false),'');
});
test('rendered All list: disabled rows hidden, toggle reveals them without any server call or row change',()=>{
 const {c,rpcs,froms}=runtime();
 const before=JSON.stringify(ROWS);
 vm.runInContext('USER_MANAGEMENT_STATE.rows=ROWS_IN; USER_MANAGEMENT_STATE.tab="all"; USER_MANAGEMENT_STATE.showDisabled=false;',Object.assign(c,{ROWS_IN:ROWS}));
 const h=host();
 c.renderUserManagementList(h);
 assert.match(h.innerHTML,/Show disabled \(3\)/);
 assert.doesNotMatch(h.innerHTML,/d1@example\.invalid|d2@example\.invalid|legacy@example\.invalid/);
 assert.match(h.innerHTML,/a@example\.invalid/);assert.match(h.innerHTML,/r@example\.invalid/);assert.match(h.innerHTML,/p@example\.invalid/);
 h.click();
 assert.match(h.innerHTML,/Hide disabled \(3\)/);
 assert.match(h.innerHTML,/d1@example\.invalid/);assert.match(h.innerHTML,/d2@example\.invalid/);
 assert.match(h.innerHTML,/data-um-restore="d1@example\.invalid"/);
 h.click();
 assert.doesNotMatch(h.innerHTML,/d1@example\.invalid/);
 assert.deepEqual(rpcs,[]);assert.deepEqual(froms,[]);
 assert.equal(JSON.stringify(ROWS),before);
});
test('All with only disabled accounts still offers the toggle',()=>{
 const {c}=runtime();
 vm.runInContext('USER_MANAGEMENT_STATE.rows=ONLY; USER_MANAGEMENT_STATE.tab="all"; USER_MANAGEMENT_STATE.showDisabled=false;',Object.assign(c,{ONLY:[ROWS[1]]}));
 const h=host();c.renderUserManagementList(h);
 assert.match(h.innerHTML,/Show disabled \(1\)/);assert.match(h.innerHTML,/No other accounts/);
});
test('app.js cache bust carries r430',()=>{
 assert.match(fs.readFileSync('index.html','utf8'),/app\.js\?[^"]*&amp;r430=2026\.10\.21\.01(?:&amp;[^"]*)?"/);
});
