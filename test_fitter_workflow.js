'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createService,progressHtml,timerModel,timerHtml,formatElapsed,startConfirmationMessage,esc}=require('./pdc-fitters.js');
function fixture(fetch, options={}) {
  let context={actor:'staff-a',token:'test-session',role:'operator',config:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test-only',workshop:{sharedData:true}}};
  let seq=0;
  return {service:createService({context:()=>context,fetch,uuid:()=>`request-${++seq}`,timeoutMs:100,...options}),setContext:c=>{context={...context,...c};}};
}
const reply=body=>({ok:true,json:async()=>body});
test('fitter-only account can record work through the fitter command endpoint',async()=>{
  const calls=[];
  const f=fixture(async(url,options)=>{calls.push({url,options});return reply({ok:true});});
  f.setContext({role:'fitter'});
  assert.equal(f.service.canWrite(),true);
  await f.service.command({p_action:'line',p_technician_id:'mechanic-a',p_booking_id:'booking-a'});
  assert.equal(calls.length,1);
  assert.match(calls[0].url,/\/rpc\/fitter_job_command$/);
  f.setContext({role:'viewer'});
  assert.equal(f.service.canWrite(),false);
});
test('fitter RPC targets the existing authenticated staging project',async()=>{
  const calls=[];const {service}=fixture(async(url,options)=>{calls.push({url,options});return reply({ok:true,jobs:[]});});
  await service.jobs('mechanic-a');
  assert.equal(calls[0].url,'https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/get_fitter_jobs');
  assert.equal(calls[0].options.headers.Authorization,'Bearer test-session');
  assert.deepEqual(JSON.parse(calls[0].options.body),{p_technician_id:'mechanic-a'});
});
test('viewer, missing auth and wrong project cannot write',async()=>{
  for(const change of [{role:'viewer'},{token:''},{actor:''},{config:{projectRef:'wrong'}}]){
    let called=false;const f=fixture(async()=>{called=true;return reply({ok:true});});f.setContext(change);
    await assert.rejects(f.service.command({p_action:'start'}));assert.equal(called,false);
  }
});
test('rapid duplicate commands are blocked while a save is pending',async()=>{
  let release;const f=fixture(()=>new Promise(resolve=>release=resolve));
  const first=f.service.command({p_action:'line'});
  await assert.rejects(f.service.command({p_action:'line'}),e=>e.code==='busy');
  release(reply({ok:true}));await first;assert.equal(f.service.busy,false);
});
test('uncertain save retries the exact same idempotency key and payload',async()=>{
  const bodies=[];const f=fixture(async(_,o)=>{bodies.push(o.body);if(bodies.length===1)throw Error('offline');return reply({ok:true,replayed:true});});
  await assert.rejects(f.service.command({p_action:'line',p_note:'Bracket fitted'}),e=>e.code==='unconfirmed');
  assert.equal(f.service.retryPending,true);
  await assert.rejects(f.service.command({p_action:'complete'}),e=>e.code==='unconfirmed');
  const r=await f.service.retry();assert.equal(r.replayed,true);assert.equal(bodies[0],bodies[1]);assert.equal(f.service.retryPending,false);
});
test('session changes discard late responses and never replay under another actor',async()=>{
  let release;const f=fixture(()=>new Promise(resolve=>release=resolve));const pending=f.service.command({p_action:'start'});
  f.setContext({actor:'staff-b',token:'other-session'});release(reply({ok:true}));
  await assert.rejects(pending,e=>e.code==='session_changed');assert.equal(f.service.retryPending,false);
});
test('server conflicts remain errors and are not mistaken for successful progress',async()=>{
  const f=fixture(async()=>reply({ok:false,error:'version_conflict'}));
  await assert.rejects(f.service.command({p_action:'line'}),e=>e.code==='version_conflict');assert.equal(f.service.retryPending,false);
});
test('planned vehicle conflicts identify the exact station and bay without claiming work has started',async()=>{
  const f=fixture(async()=>reply({ok:false,error:'vehicle_overlap',blocker:{booking_id:'booking-tint',stage_code:'TINT',bay_number:2,status:'planned',start_at:'2026-09-16T02:00:00Z',end_at:'2026-09-16T03:00:00Z'}}));
  await assert.rejects(f.service.command({p_action:'start'}),e=>{
    assert.equal(e.code,'vehicle_overlap');assert.match(e.message,/Start blocked: this vehicle has a planned booking in Tint, Bay 2/);
    assert.match(e.message,/10:00 am/);assert.match(e.message,/11:00 am/);assert.match(e.message,/Perth time/);
    assert.match(e.message,/could not be moved safely/);assert.doesNotMatch(e.message,/work in progress|vehicle is working|review.*booking order/);return true;
  });
  assert.equal(f.service.retryPending,false);
});
test('conflict messaging distinguishes started, stopped and unidentified bookings',async()=>{
  for(const [status,phrase] of [['started','work in progress'],['stoppage','a stopped job'],['unknown','another booking']]) {
    const f=fixture(async()=>reply({ok:false,error:'vehicle_overlap',blocker:{stage_code:'FITTING',bay_number:3,status}}));
    await assert.rejects(f.service.command({p_action:'resume'}),e=>e.message.includes(`Resume blocked: this vehicle has ${phrase} in Fitting, Bay 3`));
  }
});
test('wrapped database calendar and bay conflicts have clear messages without raw error details',async()=>{
  for(const code of ['calendar_unavailable','calendar_duration_mismatch','fixed_booking_conflict','admin_block_conflict','technician_overlap']){
    const f=fixture(async()=>({ok:false,json:async()=>({code:'22023',message:`Workshop validation rejected: {"error":"${code}","private":"not for display"}`})}));
    await assert.rejects(f.service.command({p_action:'stop'}),e=>e.code===code&&!e.message.includes(code)&&!e.message.includes('private'));
  }
});
test('progress is clamped and accessible without making pills taller',()=>{
  assert.match(progressHtml({percent:30,total_hours:10,completed_hours:3}),/aria-valuenow="30"/);
  assert.match(progressHtml({percent:1000},true),/width:100%/);
  assert.match(progressHtml(null,true),/aria-valuenow="0"/);
  assert.match(progressHtml({percent:30},true),/is-compact/);
  assert.equal(esc('<img src=x onerror=alert(1)>'),'&lt;img src=x onerror=alert(1)&gt;');
});
test('start confirmation reports moved bookings only from confirmed priority metadata',()=>{
  assert.match(startConfirmationMessage({start_priority:true,shifted_count:1}),/1 affected booking moved later/);
  assert.match(startConfirmationMessage({start_priority:true,shifted_count:3}),/3 affected bookings moved later/);
  assert.match(startConfirmationMessage({start_priority:true,shifted_count:0}),/No other bookings needed to move/);
  for(const result of [{},{shifted_count:3},{start_priority:true,shifted_count:-1},{start_priority:true,shifted_count:'3'}]) {
    assert.equal(startConfirmationMessage(result),'Job started on the workshop planner.');
  }
  assert.equal(startConfirmationMessage({already_started:true,start_priority:false,shifted_count:0}),'This job is already running on the planner.');
});
test('timeout keeps a retry receipt rather than guessing whether the write committed',async()=>{
  const f=fixture(()=>new Promise(()=>{}));
  await assert.rejects(f.service.command({p_action:'start'}),e=>e.code==='unconfirmed');assert.equal(f.service.retryPending,true);
  f.service.invalidate();assert.equal(f.service.retryPending,false);
});
test('roster polling is cached for one minute and explicit refresh bypasses it',async()=>{
  let at=1000,calls=0;
  const f=fixture(async()=>{calls++;return reply({ok:true,technicians:[{id:'mechanic-a',name:'A'}]});},{now:()=>at});
  for(let i=0;i<6;i++){await f.service.roster();at+=10000;}
  assert.equal(calls,1,'six ten-second polls need only one roster read');
  await f.service.roster();assert.equal(calls,2,'the expired roster is fetched again');
  await f.service.roster({force:true});assert.equal(calls,3);
});
test('roster cache is invalidated by actor, token, role and explicit session invalidation',async()=>{
  let calls=0;const f=fixture(async()=>{calls++;return reply({ok:true,technicians:[]});});
  await f.service.roster();await f.service.roster();assert.equal(calls,1);
  for(const change of [{actor:'staff-b'},{token:'renewed-session'},{role:'viewer'}]){
    f.setContext(change);await f.service.roster();
  }
  assert.equal(calls,4);
  f.service.invalidate();await f.service.roster();assert.equal(calls,5);
  f.setContext({token:''});await assert.rejects(f.service.roster(),e=>e.code==='session_changed');assert.equal(calls,5);
});
test('concurrent roster reads coalesce and late former-user responses cannot seed the cache',async()=>{
  const releases=[];let calls=0;
  const f=fixture(()=>{calls++;return new Promise(resolve=>releases.push(resolve));});
  const old=f.service.roster(),duplicate=f.service.roster();assert.equal(calls,1);
  f.setContext({actor:'staff-b',token:'new-session'});
  const next=f.service.roster();assert.equal(calls,2);
  releases[1](reply({ok:true,technicians:[{id:'new'}]}));await next;
  releases[0](reply({ok:true,technicians:[{id:'old'}]}));
  await assert.rejects(old,e=>e.code==='session_changed');await assert.rejects(duplicate,e=>e.code==='session_changed');
  assert.equal((await f.service.roster()).technicians[0].id,'new');assert.equal(calls,2);
});

const flush=async()=>{for(let i=0;i<8;i++)await new Promise(resolve=>setImmediate(resolve));};
function screenFixture() {
  const vm=require('node:vm'),fs=require('node:fs');
  const calls=[],listeners={},intervals=[],elements={},events=[];let renders=0,html='',gate=null,commandGate=null,commandError=null,clockNow=0;
  const element=(name,extra={})=>elements[name]={handlers:{},addEventListener(type,fn){this.handlers[type]=fn;},...extra};
  const mechanic=element('#fitter-mechanic',{tagName:'SELECT'});
  const line=element('[data-fitter-line]',{dataset:{fitterLine:'line-a'},checked:false,tagName:'INPUT'});
  const note=element('[data-fitter-note]',{dataset:{fitterNote:'line-a'},value:'',tagName:'TEXTAREA'});
  const saveNote=element('[data-fitter-save-note]',{dataset:{fitterSaveNote:'line-a'}});
  const refresh=element('[data-fitter-refresh]');
  const busRetry=element('[data-bus-fitter-retry]');
  const stop=element('[data-fitter-stop]'),confirmStop=element('[data-fitter-confirm-stop]');
  const stopReason=element('#fitter-stop-reason',{tagName:'TEXTAREA',focus(){doc.activeElement=this;}});
  const stopType=element('#fitter-stop-type',{tagName:'SELECT'});
  const action=element('[data-fitter-action]',{dataset:{fitterAction:'resume'}});
  const sync={textContent:''};
  const clock={textContent:''},timerLabel={textContent:''},timerHint={textContent:''};
  const timerBox={className:'',querySelector:selector=>({'[data-fitter-clock]':clock,'[data-fitter-timer-label]':timerLabel,'[data-fitter-timer-hint]':timerHint}[selector]||null)};
  const host={get innerHTML(){return html;},set innerHTML(value){html=value;renders++;},
    querySelectorAll:selector=>elements[selector]?[elements[selector]]:[],
    querySelector:selector=>selector==='.fitter-sync'?sync:selector==='[data-fitter-timer]'&&html.includes('data-fitter-timer')?timerBox:elements[selector]||null,
    contains:node=>Object.values(elements).includes(node)};
  const doc={body:{dataset:{currentView:'fitters'}},hidden:false,activeElement:null,
    getElementById:id=>id==='fitters-host'?host:elements[`#${id}`]||null,addEventListener:(event,fn)=>{listeners[event]=fn;}};
  const data={jobs:[{id:'booking-a',version:1,status:'started',stage_name:'Fitting',bay_number:1,stock:'TEST',job_card:'J-TEST'}],
    detail:{booking_id:'booking-a',version:1,status:'started',stage_code:'FITTING',catalog_hash:'scope-a',actual_start_at:'2026-09-16T00:00:00Z',
      timer:{elapsed_seconds:120,running:true,as_of:'2026-09-16T00:02:00Z',next_change_at:'2026-09-16T01:00:00Z'},
      lines:[{line_identity:'line-a',description:'Fit bracket',stage_code:'FITTING',hours:1,completed:false,note:'',scope_hash:'scope-a'}],
      progress:{percent:0,total_hours:1,completed_hours:0,total_lines:1,completed_lines:0,can_complete:false}}};
  const snapshot=value=>JSON.parse(JSON.stringify(value));
  const root={document:doc,PDC_AUTH_CONTEXT:{userId:'staff-a',role:'operator'},
    PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test',workshop:{sharedData:true}},
    performance:{now:()=>clockNow},CustomEvent:class {constructor(type,options){this.type=type;this.detail=options.detail;}},dispatchEvent:event=>events.push(event),
    crypto:{randomUUID:()=>`request-${calls.length}`},addEventListener:(event,fn)=>{listeners[event]=fn;},
    fetch:async(url,options)=>{
      const rpc=url.split('/').pop(),body=JSON.parse(options.body);calls.push({rpc,body});
      if(rpc==='get_fitter_roster')return reply({ok:true,technicians:[{id:'mechanic-a',name:'Test mechanic'}]});
      if(rpc==='get_fitter_jobs'){
        const result=snapshot({ok:true,jobs:data.jobs,bays:[]});
        if(gate){const pending=gate;gate=null;await pending.promise;}
        return reply(result);
      }
      if(rpc==='get_fitter_job')return reply(snapshot({ok:true,...data.detail}));
      if(rpc==='fitter_job_command'){
        if(commandGate){const pending=commandGate;commandGate=null;await pending.promise;}
        assert.equal(body.p_expected_version,data.detail.version);
        assert.equal(body.p_catalog_hash,data.detail.catalog_hash);
        if(commandError){const error=commandError;commandError=null;if(error==='unconfirmed')throw Error('network');return reply({ok:false,error});}
        data.detail.version++;data.jobs[0].version++;
        if(['stop','resume','start'].includes(body.p_action)){
          data.detail.status=data.jobs[0].status=body.p_action==='stop'?'stoppage':'started';
          data.detail.stoppage_reason=body.p_action==='stop'?body.p_note:null;
          data.detail.timer.running=body.p_action!=='stop';
          if(body.p_action==='start'){data.detail.actual_start_at='2026-09-16T00:02:00Z';data.detail.timer.elapsed_seconds=0;}
          return reply({ok:true,action:body.p_action,booking_id:'booking-a',...data.commandResult});
        }
        data.detail.lines[0].completed=body.p_completed;data.detail.lines[0].note=body.p_note;
        data.detail.progress={...data.detail.progress,percent:body.p_completed?100:0,completed_hours:body.p_completed?1:0,completed_lines:body.p_completed?1:0};
        return reply({ok:true,action:'line'});
      }
      throw Error(`Unexpected RPC ${rpc}`);
    }};
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-fitters.js'),'utf8'),{window:root,
    getPdcSupabaseAccessToken:()=> 'session',AbortController,setTimeout,clearTimeout,setInterval:fn=>intervals.push(fn)});
  return {root,doc,data,calls,events,clock,timerLabel,timerBox,mechanic,line,note,saveNote,refresh,stop,confirmStop,stopReason,stopType,action,listeners,sync,busRetry,
    get renders(){return renders;},get html(){return html;},poll:()=>intervals[0](),
    delayJobs(){let resolve;const promise=new Promise(r=>resolve=r);gate={promise};return resolve;},
    delayCommand(){let resolve;const promise=new Promise(r=>resolve=r);commandGate={promise};return resolve;},
    advanceClock(ms){clockNow+=ms;intervals[1]();},
    rejectCommand(error){commandError=error;},
    async open(){root.PdcFitters.open();await flush();mechanic.handlers.change({target:{value:'mechanic-a'}});await flush();}};
}
test('unchanged background polls keep the current screen intact and use the cached roster',async()=>{
  const f=screenFixture();await f.open();const before=f.renders;
  for(let i=0;i<5;i++){f.poll();await flush();}
  assert.equal(f.renders,before,'polling must not replace the full checklist or flash loading');
  assert.equal(f.calls.filter(c=>c.rpc==='get_fitter_roster').length,1);
  assert.equal(f.calls.filter(c=>c.rpc==='get_fitter_jobs').length,6);
  assert.equal(f.calls.filter(c=>c.rpc==='get_fitter_job').length,6,'operation scope remains authoritative on every poll');
  assert.match(f.sync.textContent,/Connected · Updated/);
  f.refresh.handlers.click();await flush();assert.equal(f.calls.filter(c=>c.rpc==='get_fitter_roster').length,2);
});

function supplierFixture() {
  const f=screenFixture();let callback,dirty=true,fail=false,pending=false,authority='same',gate=null;
  const calls=[],confirmed=[];
  const supplier={line_identity:'supplier-line',scope_hash:'supplier-scope',version:3,stage_code:'TINT',description:'External window tint',status:'vendor_completed'};
  f.data.detail.vehicle_id='vehicle-a';f.data.detail.stage_code='BUS_4X4';f.data.jobs[0].stage_name='Bus 4×4';
  f.data.detail.lines[0]={...f.data.detail.lines[0],stage_code:'BUS_4X4',supplier_work:supplier};
  f.data.detail.supplier_lines=[supplier];
  const service={authorityKey:()=>authority,get retryPending(){return pending;},
    async supplier(change){calls.push(change);if(gate){const release=gate;gate=null;await release;}if(fail){fail=false;pending=true;throw Object.assign(Error('Supplier save unconfirmed'),{code:'unconfirmed'});}return{ok:true};},
    async retry(){calls.push('retry');pending=false;return{ok:true};},invalidate(){authority='other';pending=false;}};
  f.root.PdcBusWorkflow={service:()=>service,hasDrafts:()=>dirty,supplierHtml:(lines,opts)=>{assert.equal(lines[0].stage_code,'TINT');assert.equal(opts.bookingId,'booking-a');assert.equal(opts.technicianId,'mechanic-a');return '<p>Supplier physical check fixture</p>';},bindSuppliers:(_host,save)=>{callback=save;},confirmSupplierSave:key=>{confirmed.push(key);dirty=false;},reset:()=>{service.invalidate();dirty=false;}};
  return {...f,get html(){return f.html;},get renders(){return f.renders;},supplierCalls:calls,confirmed,
    save:()=>callback({vehicleId:'vehicle-a',lineIdentity:'supplier-line',scopeHash:'supplier-scope',version:3,status:'technician_verified',bookingId:'booking-a',technicianId:'mechanic-a',note:'Checked on vehicle',draftKey:'supplier-draft'}),
    failNext:()=>{fail=true;},changeAuthority:()=>{authority='different';},
    delaySave:()=>{let resolve;gate=new Promise(r=>resolve=r);return resolve;}};
}

test('fitter supplier controls include same-vehicle Tint and route physical checks through dedicated service',async()=>{
  const f=supplierFixture();await f.open();
  assert.match(f.html,/Supplier physical check fixture/);assert.match(f.html,/Physical verification below/);
  assert.doesNotMatch(f.html,/data-fitter-line="line-a"/,'supplier lines cannot use ordinary completion checkbox');
  f.save();await flush();
  assert.equal(f.supplierCalls.length,1);assert.equal(f.supplierCalls[0].status,'technician_verified');
  assert.deepEqual(f.confirmed,['supplier-draft']);
  assert.equal(f.calls.filter(c=>c.rpc==='fitter_job_command').length,0);
  assert.equal(f.events.length,1);assert.equal(f.events[0].detail.action,'supplier');
});

test('unconfirmed supplier save locks other writes and polling, then retries and clears the same draft',async()=>{
  const f=supplierFixture();await f.open();f.failNext();f.save();await flush();
  assert.match(f.html,/supplier save is unconfirmed/);assert.equal(f.confirmed.length,0);assert.equal(f.events.length,0);
  const count=f.calls.length;f.poll();await flush();assert.equal(f.calls.length,count);
  f.action.handlers.click({currentTarget:f.action});f.line.handlers.change({currentTarget:f.line});await flush();
  assert.equal(f.calls.filter(c=>c.rpc==='fitter_job_command').length,0);
  f.busRetry.handlers.click();await flush();
  assert.equal(f.supplierCalls[1],'retry');assert.deepEqual(f.confirmed,['supplier-draft']);assert.equal(f.events.length,1);
});

test('late supplier response after authority changes cannot clear drafts or announce saved work',async()=>{
  const f=supplierFixture();await f.open();const release=f.delaySave();f.save();f.changeAuthority();release();await flush();
  assert.equal(f.confirmed.length,0);assert.equal(f.events.length,0);assert.doesNotMatch(f.html,/Supplier work verification saved/);
});
test('a line tap during background polling saves immediately and supersedes the old read',async()=>{
  const f=screenFixture();await f.open();const release=f.delayJobs();f.poll();await flush();
  f.line.checked=true;f.line.handlers.change({currentTarget:f.line});await flush();
  assert.equal(f.calls.filter(c=>c.rpc==='fitter_job_command').length,1,'polling must not silently discard a fitter tap');
  assert.match(f.html,/aria-valuenow="100"/);const afterSave=f.renders;
  release();await flush();assert.equal(f.renders,afterSave,'late polling response is inert');assert.match(f.html,/aria-valuenow="100"/);
});
test('note drafts survive changed snapshots and changed operation scope prevents saving them',async()=>{
  const f=screenFixture();await f.open();f.note.value='Bracket needs review';
  f.note.handlers.input({target:f.note});f.doc.activeElement=f.note;
  const calls=f.calls.length;f.poll();await flush();assert.equal(f.calls.length,calls,'typing suppresses background polling');
  f.doc.activeElement=null;f.data.detail.catalog_hash='scope-b';f.data.detail.lines[0].scope_hash='scope-b';
  f.poll();await flush();assert.match(f.html,/Bracket needs review/);
  f.saveNote.handlers.click({currentTarget:f.saveNote});await flush();
  assert.equal(f.calls.filter(c=>c.rpc==='fitter_job_command').length,0);
  assert.match(f.html,/This item changed while you were writing/);
});
test('stoppage validates a reason, saves during polling, and resumes the same canonical booking',async()=>{
  const f=screenFixture();await f.open();f.stop.handlers.click();
  assert.match(f.html,/Record a workshop stoppage/);
  f.confirmStop.handlers.click();await flush();
  assert.equal(f.calls.filter(c=>c.rpc==='fitter_job_command').length,0);
  assert.match(f.html,/Enter a short reason/);
  f.stopReason.handlers.input({target:{value:'  Waiting for bracket  '}});f.doc.activeElement=null;
  const release=f.delayJobs();f.poll();await flush();
  f.confirmStop.handlers.click();await flush();
  const stop=f.calls.find(c=>c.rpc==='fitter_job_command').body;
  assert.equal(stop.p_booking_id,'booking-a');assert.equal(stop.p_action,'stop');assert.equal(stop.p_note,'Parts: Waiting for bracket');
  assert.match(f.html,/Job stopped/);assert.match(f.html,/Resume job/);
  release();await flush();assert.match(f.html,/Job stopped/);
  f.action.handlers.click({currentTarget:f.action});await flush();
  assert.equal(f.calls.filter(c=>c.rpc==='fitter_job_command')[1].body.p_action,'resume');
  assert.match(f.html,/In progress/);assert.doesNotMatch(f.html,/<strong>Job stopped<\/strong>/);
});
test('rejected stoppage retains its reason and can be deliberately retried after refresh',async()=>{
  const f=screenFixture();await f.open();f.stop.handlers.click();
  f.stopType.handlers.change({target:{value:'Other'}});
  f.stopReason.handlers.input({target:{value:'Awaiting customer decision'}});
  f.rejectCommand('version_conflict');f.confirmStop.handlers.click();await flush();
  assert.match(f.html,/This job changed on another screen/);assert.match(f.html,/Awaiting customer decision/);
  assert.match(f.html,/Record a workshop stoppage/);assert.doesNotMatch(f.html,/<strong>Job stopped<\/strong>/);
  f.confirmStop.handlers.click();await flush();
  const saved=f.calls.filter(c=>c.rpc==='fitter_job_command')[1].body;
  assert.equal(saved.p_note,'Other: Awaiting customer decision');assert.match(f.html,/Job stopped/);
});
test('a stoppage draft never follows a booking that disappears onto the next vehicle',async()=>{
  const f=screenFixture();await f.open();f.stop.handlers.click();
  f.stopReason.handlers.input({target:{value:'Bracket missing from first vehicle'}});f.doc.activeElement=null;
  f.data.jobs=[{...f.data.jobs[0],id:'booking-b',stock:'OTHER-TEST'}];f.data.detail.booking_id='booking-b';
  f.poll();await flush();assert.doesNotMatch(f.html,/Record a workshop stoppage/);
  f.stop.handlers.click();assert.doesNotMatch(f.html,/Bracket missing from first vehicle/);
});
test('timer advances confirmed work time, respects breaks and pauses, and cannot invent a start',()=>{
  const detail={status:'started',actual_start_at:'2026-09-16T00:00:00Z',timer:{elapsed_seconds:120,running:true,as_of:'2026-09-16T00:02:00Z',next_change_at:'2026-09-16T00:02:20Z'}};
  assert.equal(formatElapsed(timerModel(detail,{connected:true,receivedAt:1000,now:6500}).seconds),'00:02:05');
  const boundary=timerModel(detail,{receivedAt:1000,now:26000});assert.equal(boundary.tone,'paused');assert.equal(boundary.seconds,140);
  assert.equal(timerModel({...detail,status:'stoppage'},{now:999999}).seconds,120);
  assert.equal(timerModel({...detail,timer:{...detail.timer,running:false}},{now:999999}).seconds,120);
  assert.equal(timerModel({...detail,status:'planned'}).label,'Not started');
  assert.notEqual(timerModel({...detail,actual_start_at:null}).tone,'running');
  assert.notEqual(timerModel(detail,{unconfirmed:true}).tone,'running');
  for(const [action,label] of [['start','Start'],['resume','Resume'],['stop','Stoppage'],['complete','Completion'],['line','Save']]) {
    const uncertain=timerModel(detail,{unconfirmed:true,unconfirmedAction:action,now:15000});
    assert.equal(uncertain.label,`${label} not confirmed`);assert.equal(uncertain.seconds,120);
  }
  assert.notEqual(timerModel(detail,{connected:false}).tone,'running');
  assert.equal(formatElapsed(360005),'100:00:05');assert.equal(formatElapsed(null),'--:--:--');
  assert.match(timerModel({...detail,timer:{...detail.timer,history_complete:false}}).hint,/Approximate.*history is incomplete/);
  assert.match(timerHtml(detail,{pendingAction:'start'}),/Starting job/);
  assert.doesNotMatch(timerHtml(detail,{pendingAction:'start'}),/is-running/);
});
test('long-disconnected timer freezes at the last supported interval rather than claiming continued work',()=>{
  const detail={status:'started',actual_start_at:'2026-09-16T00:00:00Z',timer:{elapsed_seconds:120,running:true,as_of:'2026-09-16T00:02:00Z',next_change_at:'2026-09-16T01:00:00Z'}};
  const stale=timerModel(detail,{receivedAt:0,now:600000});
  assert.equal(stale.tone,'unconfirmed');assert.equal(stale.seconds,150);
});
test('Start shows pending immediately, then a confirmed running timer and canonical planner event',async()=>{
  const f=screenFixture();f.data.detail.status=f.data.jobs[0].status='planned';f.data.detail.actual_start_at=null;await f.open();
  const release=f.delayCommand();f.action.dataset.fitterAction='start';f.action.handlers.click({currentTarget:f.action});
  assert.match(f.html,/Starting job…/);assert.doesNotMatch(f.html,/fitter-timer is-running/);assert.equal(f.events.length,0);
  release();await flush();assert.match(f.html,/fitter-timer is-running/);assert.match(f.html,/Job started on the workshop planner/);
  assert.equal(f.events.length,1);assert.equal(f.events[0].type,'pdc-fitter-workshop-saved');
  assert.equal(f.events[0].detail.bookingId,'booking-a');assert.equal(f.events[0].detail.stageCode,'FITTING');assert.equal(f.events[0].detail.action,'start');
  f.advanceClock(5000);assert.equal(f.clock.textContent,'00:00:05');assert.equal(f.timerLabel.textContent,'Running');
});
test('fitter Start leaves same-vehicle planned conflicts and priority reordering to the server',async()=>{
  const f=screenFixture();f.data.detail.status=f.data.jobs[0].status='planned';f.data.detail.actual_start_at=null;
  f.data.jobs[0].vehicle_id='vehicle-a';
  f.data.jobs.push({id:'tint-booking',version:1,status:'planned',vehicle_id:'vehicle-a',stage_code:'TINT',stage_name:'Tint',bay_number:2,
    stock:'TEST',job_card:'J-TEST',start_at:'2026-09-16T00:00:00Z',end_at:'2026-09-16T01:00:00Z'});
  await f.open();const release=f.delayCommand();f.action.dataset.fitterAction='start';f.action.handlers.click({currentTarget:f.action});
  const write=f.calls.find(call=>call.rpc==='fitter_job_command');assert.ok(write);
  assert.equal(write.body.p_action,'start');assert.equal(write.body.p_booking_id,'booking-a');
  assert.equal(write.body.p_expected_version,1);assert.equal(f.data.jobs[0].status,'planned');assert.equal(f.events.length,0);
  assert.match(f.html,/Checking the schedule and moving affected unstarted bookings/);
  assert.equal(f.data.jobs[1].start_at,'2026-09-16T00:00:00Z','the browser must not move the other booking optimistically');
  // Only the canonical server result and subsequent fresh queue provide these changes.
  f.data.jobs[1].start_at='2026-09-16T04:00:00Z';f.data.jobs[1].end_at='2026-09-16T05:00:00Z';
  f.data.commandResult={start_priority:true,shifted_count:1};
  release();await flush();
  assert.equal(f.events.length,1);assert.match(f.html,/Job started on the workshop planner/);
  assert.match(f.html,/1 affected booking moved later/);assert.match(f.html,/fitter-timer is-running/);
  assert.equal(f.calls.filter(call=>call.rpc==='fitter_job_command').length,1);
});
test('rejected and unconfirmed starts never show running or notify the planner of success',async()=>{
  for(const error of ['bay_already_started','parts_incomplete_entry','technician_overlap','unconfirmed']){
    const f=screenFixture();f.data.detail.status=f.data.jobs[0].status='planned';f.data.detail.actual_start_at=null;await f.open();
    f.rejectCommand(error);f.action.dataset.fitterAction='start';f.action.handlers.click({currentTarget:f.action});await flush();
    assert.equal(f.events.length,0);assert.doesNotMatch(f.html,/fitter-timer is-running/);
    if(error==='unconfirmed')assert.match(f.html,/Start not confirmed/);
    else if(error==='parts_incomplete_entry')assert.match(f.html,/Parts are not marked ready/);
    else if(error==='technician_overlap')assert.match(f.html,/mechanic already has another running or stopped job/);
    else assert.match(f.html,/bay already has a running or stopped job/);
  }
});
test('timer-only snapshots and one-second ticks do not replace the checklist or make extra requests',async()=>{
  const f=screenFixture();await f.open();const renders=f.renders,calls=f.calls.length;
  f.advanceClock(5000);assert.equal(f.clock.textContent,'00:02:05');assert.equal(f.renders,renders);assert.equal(f.calls.length,calls);
  f.data.detail.timer.elapsed_seconds=130;f.data.detail.timer.as_of='2026-09-16T00:02:10Z';
  f.poll();await flush();assert.equal(f.renders,renders);assert.equal(f.clock.textContent,'00:02:10');
  f.root.PdcFitters.close();f.root.PdcFitters.open();await flush();
  assert.match(f.html,/00:02:10/);assert.match(f.html,/fitter-timer is-running/);
});
test('pending stoppage freezes the displayed interval until authoritative paused timing arrives',async()=>{
  const f=screenFixture();await f.open();f.advanceClock(7000);
  assert.equal(f.clock.textContent,'00:02:07');
  f.stop.handlers.click();f.stopReason.handlers.input({target:{value:'Waiting for parts'}});
  const release=f.delayCommand();f.confirmStop.handlers.click();
  assert.match(f.html,/Recording stoppage…/);assert.match(f.html,/00:02:07/);
  f.advanceClock(5000);
  assert.equal(f.clock.textContent,'00:02:07','pending state must neither rewind to the old poll nor keep counting');
  assert.equal(f.timerLabel.textContent,'Recording stoppage…');assert.equal(f.events.length,0);
  f.data.detail.timer.elapsed_seconds=132;f.data.detail.timer.as_of='2026-09-16T00:02:12Z';
  release();await flush();
  assert.match(f.html,/Paused · Stoppage/);assert.match(f.html,/00:02:12/);
  f.advanceClock(5000);assert.equal(f.clock.textContent,'00:02:12');
});
test('an unconfirmed stoppage retains its visible frozen time through reads without claiming a stop',async()=>{
  const f=screenFixture();await f.open();f.advanceClock(7000);
  f.stop.handlers.click();f.stopReason.handlers.input({target:{value:'Waiting for parts'}});
  const release=f.delayCommand();f.rejectCommand('unconfirmed');f.confirmStop.handlers.click();
  f.advanceClock(4000);release();await flush();
  assert.match(f.html,/Stoppage not confirmed/);assert.match(f.html,/00:02:07/);
  assert.equal(f.events.length,0);assert.equal(f.data.detail.status,'started');
  f.data.detail.timer.elapsed_seconds=135;f.data.detail.timer.as_of='2026-09-16T00:02:15Z';
  f.doc.activeElement=null;f.poll();await flush();f.advanceClock(4000);
  assert.equal(f.clock.textContent,'00:02:07');assert.equal(f.timerLabel.textContent,'Stoppage not confirmed');
});
test('offline timing freezes at the displayed value and a new authoritative snapshot can correct it',async()=>{
  const f=screenFixture();await f.open();f.advanceClock(7000);f.listeners.offline();
  assert.match(f.html,/00:02:07/);f.advanceClock(4000);
  assert.equal(f.clock.textContent,'00:02:07');assert.equal(f.timerLabel.textContent,'Last confirmed time');
  f.data.detail.status=f.data.jobs[0].status='stoppage';f.data.detail.timer.running=false;
  f.data.detail.timer.elapsed_seconds=125;f.data.detail.timer.as_of='2026-09-16T00:02:11Z';
  f.listeners.online();await flush();
  assert.match(f.html,/00:02:05/,'fresh server timing must not be overridden by a stale display freeze');
  assert.match(f.html,/Paused · Stoppage/);
});
