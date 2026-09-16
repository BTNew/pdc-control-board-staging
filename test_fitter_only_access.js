const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('./app.js','utf8');
test('fitter login routes directly to its section without starting broad data services',()=>{
 const calls=[];
 const handler=source.slice(source.indexOf("window.addEventListener?.('pdc-auth-ready', () => {"),source.indexOf('// Independent-review remediation, finding #5 / critical blocker #5:',source.indexOf("window.addEventListener?.('pdc-auth-ready', () => {")));
 const context={window:{PDC_AUTH_CONTEXT:{role:'fitter'},addEventListener:(_,fn)=>fn()},document:{body:{classList:{toggle:(...v)=>calls.push(v)}}},
 teardownWorkshopPlannerScope:()=>calls.push('planner-stopped'),teardownWorkshopEligibilityOverview:()=>calls.push('overview-stopped'),closeVehicleModal:()=>calls.push('modal-closed'),showView:(...v)=>calls.push(v)};
 vm.runInNewContext(handler,context);
 assert.equal(calls.at(-1)[0],'fitters');
 assert.equal(calls.at(-1)[1].historyMode,'replace');
 assert.equal(calls[0][0],'fitter-only');
});
test('direct and stale browser routes are rewritten before the app performs navigation',()=>{
 const start=source.indexOf('function showView(view, options)');
 const end=source.indexOf('  // Hidden navigation',start);
 const prefix=source.slice(start,end)+'return requestedView; }';
 for(const role of ['fitter','operator','administrator']) {
  const context={window:{PDC_AUTH_CONTEXT:{role}}};vm.createContext(context);vm.runInContext(prefix,context);
  for(const route of ['dashboard','lists','user-management','planner-fitting','parts','qc','fitters'])
   assert.equal(context.showView(route),role==='fitter'?'fitters':route);
 }
});
