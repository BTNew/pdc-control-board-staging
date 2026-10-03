const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const zebra=require('./sales/zebra-labels.js');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const preference='broome-sales-qz-printer-v1';
const example={cosi:'Yes',salesperson_code:'BG',salesperson_name:'Example Salesperson',tracking_id:'example-id',stock:'EXAMPLE123',order:'ORDER123',client:'Fictional Customer',vehicle:'Example Vehicle',vin:'FICTIONALVIN123',trim:'Example trim',colour:'Example colour'};

// All connections, queues and print jobs in this harness are fictional promises.
// Resolving a print request records a job only after the real Sales guard approves it.
function harness({role='administrator',stored={},storageThrows=false}={}){
 const elements=new Map(),events={},calls=[],connections=[],prints=[],jobs=[],storageCalls=[];
 const values=new Map(Object.entries(stored));
 function el(id){
  if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',dataset:{},events:{},attributes:{},
   classList:{toggle(){}},setAttribute(key,value){this.attributes[key]=value;},removeAttribute(key){delete this.attributes[key];},
   addEventListener(name,fn){this.events[name]=fn;},close(){this.closed=true;},showModal(){this.closed=false;},scrollIntoView(){},focus(){}});
  return elements.get(id);
 }
 const nav=['dashboard','pipeline','labels','finance'].map(view=>{const e=el('nav-'+view);e.dataset.salesView=view;return e;});
 const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},
  PDC_AUTH_CONTEXT:{role,userId:'example-account'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},
  localStorage:{getItem(key){storageCalls.push(['get',key]);if(storageThrows)throw Error('Storage unavailable');return values.get(key)||null;},
   setItem(key,value){storageCalls.push(['set',key,value]);if(storageThrows)throw Error('Storage unavailable');values.set(key,value);},
   removeItem(key){storageCalls.push(['remove',key]);if(storageThrows)throw Error('Storage unavailable');values.delete(key);}},
  BROOME_ZEBRA_LABELS:{...zebra,
   checkConnection(guard){return new Promise((resolve,reject)=>connections.push({guard,resolve,reject}));},
   print(rows,guard,printer){return new Promise((resolve,reject)=>prints.push({rows,guard,printer,reject,
    finish(){if(!guard()){reject(Error('Vehicle access changed. Refresh before printing.'));return;}jobs.push({rows,printer});resolve(printer||'Example Zebra');}}));}},
  addEventListener(name,fn){events[name]=fn;},setInterval(){}};
 vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,globalThis:window,module:undefined,Set,Map,Date,console});
 async function snapshot(rows=[{...example}],contextRole=role){calls.at(-1).resolve({data:{context:{role:contextRole,display_name:'Example'},items:rows}});await tick();}
 function select(id=example.tracking_id){el('vehicle-table').events.change({target:{dataset:{select:id},checked:true}});}
 function labels(){el('sales-view-labels').events.click();}
 function connect(){el('sales-connect-printer').events.click();}
 function print(){el('sales-print-labels').events.click();}
 function scope(code){el('salesperson-filter').value=code;el('salesperson-filter').events.change({target:{value:code}});}
 function choose(name){el('sales-label-printer').value=name;el('sales-label-printer').events.change({target:{value:name}});}
 async function refresh(rows,contextRole=role){el('sales-refresh').events.click();await snapshot(rows,contextRole);}
 function signout(){delete window.PDC_AUTH_CONTEXT;events['pdc-auth-locked']();}
 return{window,events,calls,connections,prints,jobs,values,storageCalls,el,snapshot,select,labels,connect,print,scope,choose,refresh,signout};
}
test('Connect / find printers works without selected vehicles and never sends a label job',async()=>{
 const h=harness();await h.snapshot();h.labels();h.connect();
 assert.equal(h.connections.length,1);assert.equal(h.connections[0].guard(),true);
 assert.equal(h.el('sales-connect-printer').disabled,true);assert.equal(h.el('sales-print-labels').disabled,true);
 h.connect();h.print();assert.equal(h.connections.length,1);assert.equal(h.prints.length,0);
 h.connections[0].resolve({connected:true,printers:['Example Zebra','Example <queue>'],printer:'Example Zebra'});await tick();
 assert.equal(h.el('sales-connect-printer').disabled,false);assert.equal(h.el('sales-label-printer').disabled,false);
 assert.equal(h.el('sales-label-printer').value,'Example Zebra');assert.match(h.el('sales-label-printer').innerHTML,/Example &lt;queue&gt;/);
 assert.doesNotMatch(h.el('sales-label-printer').innerHTML,/<queue>/);assert.match(h.el('sales-label-status').textContent,/QZ Tray connected/);
 assert.equal(h.el('sales-print-labels').disabled,true);assert.equal(h.jobs.length,0);assert.equal(h.prints.length,0);
 assert.deepEqual(h.calls.map(call=>call.name),['get_broome_sales_snapshot']);
});
test('only an exact discovered queue is saved and passed as the print API third argument',async()=>{
 const h=harness({stored:{[preference]:'Saved Zebra','pdc-zebra-printer':'Unrelated PDC Queue'}});await h.snapshot();h.select();h.labels();h.connect();
 h.connections[0].resolve({connected:true,printers:['Saved Zebra','Alternate Zebra'],printer:'Alternate Zebra'});await tick();
 assert.equal(h.el('sales-label-printer').value,'Saved Zebra');h.choose('Alternate Zebra');
 assert.equal(h.values.get(preference),'Alternate Zebra');h.print();assert.equal(h.prints.length,1);
 assert.equal(h.prints[0].printer,'Alternate Zebra');assert.equal(h.prints[0].rows[0].vin,example.vin);assert.equal(h.prints[0].guard(),true);
 assert.equal(h.el('sales-connect-printer').disabled,true);h.connect();h.print();assert.equal(h.connections.length,1);assert.equal(h.prints.length,1);
 h.prints[0].finish();await tick();assert.equal(h.jobs.length,1);assert.match(h.el('sales-label-status').textContent,/2 label copies.*Alternate Zebra/);
 h.choose('Alternate');h.print();assert.equal(h.prints.length,1);assert.equal(h.values.has(preference),false);
 assert.match(h.el('sales-label-status').textContent,/Choose the Zebra/);
 assert.ok(h.storageCalls.every(call=>call[1]===preference));assert.equal(h.values.get('pdc-zebra-printer'),'Unrelated PDC Queue');
 assert.deepEqual(h.storageCalls.filter(call=>call[0]==='set'),[['set',preference,'Alternate Zebra']]);
});
test('unavailable saved queues fall back to the current preferred queue and storage failures are harmless',async()=>{
 for(const settings of [{stored:{[preference]:'Retired Zebra'}},{storageThrows:true}]){
  const h=harness(settings);await h.snapshot();h.select();h.labels();h.connect();
  h.connections[0].resolve({connected:true,printers:['Current Zebra'],printer:'Current Zebra'});await tick();
  assert.equal(h.el('sales-label-printer').value,'Current Zebra');h.choose('Current Zebra');h.print();
  assert.equal(h.prints[0].printer,'Current Zebra');h.prints[0].finish();await tick();assert.equal(h.jobs.length,1);
 }
});
test('successful connections without Zebra or installed queues explain how to continue without printing',async()=>{
 for(const printers of [[],['Ordinary office queue']]){
  const h=harness();await h.snapshot();h.select();h.labels();h.connect();
  h.connections[0].resolve({connected:true,printers,printer:''});await tick();
  assert.equal(h.el('sales-connect-printer').disabled,false);assert.equal(h.el('sales-label-printer').disabled,!printers.length);
  assert.match(h.el('sales-label-status').textContent,printers.length?/Choose the Zebra/:/no printer queues/);
  assert.equal(h.prints.length,0);assert.equal(h.jobs.length,0);
  if(printers.length){h.print();assert.equal(h.prints.length,0);assert.match(h.el('sales-label-status').textContent,/Choose the Zebra/);}
 }
});
test('string connection errors retain useful details and allow an explicit retry',async()=>{
 const h=harness();await h.snapshot();h.select();h.labels();h.connect();h.connections[0].reject('Fictional permission denied');await tick();
 assert.match(h.el('sales-label-status').textContent,/Fictional permission denied/);assert.match(h.el('sales-label-status').textContent,/allow this website/i);
 assert.equal(h.el('sales-connect-printer').disabled,false);assert.equal(h.el('sales-print-labels').disabled,false);
 h.connect();assert.equal(h.connections.length,2);h.connections[1].resolve({connected:true,printers:['Example Zebra'],printer:'Example Zebra'});await tick();
 assert.match(h.el('sales-label-status').textContent,/connected/);assert.equal(h.jobs.length,0);
});
test('leaving Labels or changing salesperson cancels a delayed connection response and frees the controls',async()=>{
 for(const change of ['view','scope']){
  const h=harness();await h.snapshot();h.select();h.labels();h.connect();
  if(change==='view')h.el('nav-dashboard').events.click();else h.scope('AW');
  assert.equal(h.connections[0].guard(),false);h.connections[0].resolve({connected:true,printers:['Late private queue'],printer:'Late private queue'});await tick();
  assert.doesNotMatch(h.el('sales-label-printer').innerHTML,/Late private queue/);assert.equal(h.storageCalls.length,0);assert.equal(h.prints.length,0);
  h.labels();assert.equal(h.el('sales-connect-printer').disabled,false);h.connect();assert.equal(h.connections.length,2);
  h.connections[1].resolve({connected:true,printers:[],printer:''});await tick();assert.equal(h.el('sales-connect-printer').disabled,false);
 }
});
test('sign-out and replacement accounts reject late printer lists and cannot undo a new connection',async()=>{
 for(const replacement of [false,true]){
  const h=harness();await h.snapshot();h.select();h.labels();h.connect();const old=h.connections[0];h.signout();
  assert.equal(old.guard(),false);assert.equal(h.el('sales-label-status').textContent,'');assert.equal(h.el('sales-label-printer').disabled,true);
  if(replacement){h.window.PDC_AUTH_CONTEXT={role:'administrator',userId:'replacement-account'};h.events['pdc-auth-ready']();await h.snapshot([{...example,tracking_id:'replacement-id'}]);h.connect();assert.equal(h.connections.length,2);}
  old.resolve({connected:true,printers:['Old account queue'],printer:'Old account queue'});await tick();
  assert.doesNotMatch(h.el('sales-label-printer').innerHTML,/Old account queue/);assert.equal(h.storageCalls.length,0);assert.equal(h.jobs.length,0);
  if(replacement){assert.equal(h.el('sales-connect-printer').disabled,true);h.connections[1].resolve({connected:true,printers:['New queue'],printer:'New queue'});await tick();assert.equal(h.el('sales-label-printer').value,'New queue');}
  else{assert.equal(h.el('sales-label-status').textContent,'');assert.equal(h.el('sales-labels').innerHTML,'');}
 }
});
test('sign-out clears loaded queue memory and selected labels before another account can print',async()=>{
 const h=harness();await h.snapshot();h.select();h.labels();h.connect();
 h.connections[0].resolve({connected:true,printers:['Example Zebra'],printer:'Example Zebra'});await tick();h.choose('Example Zebra');
 h.signout();assert.equal(h.el('sales-label-printer').disabled,true);assert.equal(h.el('sales-label-printer').innerHTML,'<option value="">Connect to load printers</option>');
 assert.equal(h.el('sales-labels').innerHTML,'');assert.equal(h.el('sales-label-status').textContent,'');assert.equal(h.el('sales-print-labels').disabled,true);
 h.window.PDC_AUTH_CONTEXT={role:'administrator',userId:'replacement-account'};h.events['pdc-auth-ready']();await h.snapshot([{...example,tracking_id:'replacement-id'}]);
 h.print();assert.equal(h.prints.length,0);h.select('replacement-id');h.print();assert.equal(h.prints.length,1);
 assert.equal(h.prints[0].printer,'');assert.equal(h.prints[0].rows[0].tracking_id,'replacement-id');assert.equal(h.jobs.length,0);
 h.prints[0].finish();await tick();assert.equal(h.jobs.length,1);
 assert.equal(h.values.get(preference),'Example Zebra');assert.ok(h.storageCalls.every(call=>call[1]===preference));
});
test('same identity with changed printed facts cancels the captured label before a job can be sent',async()=>{
 const variants=[{stock:'EXAMPLE456'},{vin:'UPDATEDFICTIONALVIN'},{vehicle:'Updated Example Model'},
  {client:'Different Fictional Customer'},{salesperson_name:'Updated Example Salesperson'},{trim:'Updated trim'},{colour:'Updated colour'}];
 for(const changed of variants){
  const h=harness();await h.snapshot();h.select();h.labels();h.print();assert.equal(h.prints[0].guard(),true);
  await h.refresh([{...example,...changed}]);assert.equal(h.prints[0].guard(),false,Object.keys(changed)[0]);h.prints[0].finish();await tick();
  assert.equal(h.jobs.length,0);assert.match(h.el('sales-label-status').textContent,/Vehicle access changed/);assert.equal(h.el('sales-print-labels').disabled,false);
  for(const value of Object.values(changed))assert.ok(h.el('sales-labels').innerHTML.includes(value));
 }
});
test('a status-only refresh keeps unchanged labels authorised and sends the captured exact queue once',async()=>{
 const h=harness();await h.snapshot();h.select();h.labels();h.connect();h.connections[0].resolve({connected:true,printers:['Example Zebra'],printer:'Example Zebra'});await tick();h.print();
 await h.refresh([{...example,toyota_status:'Vehicle Built',pmb_location:'Fictional location'}]);assert.equal(h.prints[0].guard(),true);
 h.prints[0].finish();await tick();assert.equal(h.jobs.length,1);assert.equal(h.jobs[0].printer,'Example Zebra');
 assert.deepEqual(h.calls.map(call=>call.name),['get_broome_sales_snapshot','get_broome_sales_snapshot']);
});
test('scope, selection, absence, hidden and unsold changes cancel an in-flight print',async()=>{
 for(const change of ['scope','selection','absent','hidden','unsold','view','signout']){
  const h=harness();await h.snapshot();h.select();h.labels();h.print();
  if(change==='scope')h.scope('AW');
  else if(change==='selection')h.el('vehicle-table').events.change({target:{dataset:{select:example.tracking_id},checked:false}});
  else if(change==='absent')await h.refresh([]);
  else if(change==='hidden')await h.refresh([{...example,sales_hidden:true}]);
  else if(change==='unsold')await h.refresh([{...example,cosi:'No'}]);
  else if(change==='view')h.el('nav-dashboard').events.click();
  else h.signout();
  assert.equal(h.prints[0].guard(),false,change);h.prints[0].finish();await tick();assert.equal(h.jobs.length,0,change);
  if(change==='signout')assert.equal(h.el('sales-label-status').textContent,'');
 }
});
test('unapproved or locked accounts cannot connect or print through forged button clicks',async()=>{
 for(const locked of [false,true]){
  const h=harness();if(locked){h.signout();h.calls[0].resolve({data:{context:{role:'administrator'},items:[example]}});await tick();}
  else await h.snapshot([example],'unapproved');
  h.labels();h.select();h.connect();h.print();assert.equal(h.connections.length,0);assert.equal(h.prints.length,0);assert.equal(h.jobs.length,0);
 }
});
