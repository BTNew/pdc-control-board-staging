'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createService,progressHtml,esc}=require('./pdc-fitters.js');
function fixture(fetch, options={}) {
  let context={actor:'staff-a',token:'test-session',role:'operator',config:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test-only',workshop:{sharedData:true}}};
  let seq=0;
  return {service:createService({context:()=>context,fetch,uuid:()=>`request-${++seq}`,timeoutMs:100,...options}),setContext:c=>{context={...context,...c};}};
}
const reply=body=>({ok:true,json:async()=>body});
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
test('wrapped database calendar and bay conflicts have clear messages without raw error details',async()=>{
  for(const code of ['calendar_unavailable','calendar_duration_mismatch','fixed_booking_conflict','admin_block_conflict']){
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
  const calls=[],listeners={},intervals=[],elements={};let renders=0,html='',gate=null,commandError=null;
  const element=(name,extra={})=>elements[name]={handlers:{},addEventListener(type,fn){this.handlers[type]=fn;},...extra};
  const mechanic=element('#fitter-mechanic',{tagName:'SELECT'});
  const line=element('[data-fitter-line]',{dataset:{fitterLine:'line-a'},checked:false,tagName:'INPUT'});
  const note=element('[data-fitter-note]',{dataset:{fitterNote:'line-a'},value:'',tagName:'TEXTAREA'});
  const saveNote=element('[data-fitter-save-note]',{dataset:{fitterSaveNote:'line-a'}});
  const refresh=element('[data-fitter-refresh]');
  const stop=element('[data-fitter-stop]'),confirmStop=element('[data-fitter-confirm-stop]');
  const stopReason=element('#fitter-stop-reason',{tagName:'TEXTAREA',focus(){doc.activeElement=this;}});
  const stopType=element('#fitter-stop-type',{tagName:'SELECT'});
  const action=element('[data-fitter-action]',{dataset:{fitterAction:'resume'}});
  const sync={textContent:''};
  const host={get innerHTML(){return html;},set innerHTML(value){html=value;renders++;},
    querySelectorAll:selector=>elements[selector]?[elements[selector]]:[],
    querySelector:selector=>selector==='.fitter-sync'?sync:null,
    contains:node=>Object.values(elements).includes(node)};
  const doc={body:{dataset:{currentView:'fitters'}},hidden:false,activeElement:null,
    getElementById:id=>id==='fitters-host'?host:elements[`#${id}`]||null,addEventListener:(event,fn)=>{listeners[event]=fn;}};
  const data={jobs:[{id:'booking-a',version:1,status:'started',stage_name:'Fitting',bay_number:1,stock:'TEST',job_card:'J-TEST'}],
    detail:{booking_id:'booking-a',version:1,status:'started',stage_code:'FITTING',catalog_hash:'scope-a',
      lines:[{line_identity:'line-a',description:'Fit bracket',stage_code:'FITTING',hours:1,completed:false,note:'',scope_hash:'scope-a'}],
      progress:{percent:0,total_hours:1,completed_hours:0,total_lines:1,completed_lines:0,can_complete:false}}};
  const snapshot=value=>JSON.parse(JSON.stringify(value));
  const root={document:doc,PDC_AUTH_CONTEXT:{userId:'staff-a',role:'operator'},
    PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test',workshop:{sharedData:true}},
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
        assert.equal(body.p_expected_version,data.detail.version);
        assert.equal(body.p_catalog_hash,data.detail.catalog_hash);
        if(commandError){const error=commandError;commandError=null;return reply({ok:false,error});}
        data.detail.version++;data.jobs[0].version++;
        if(body.p_action==='stop'||body.p_action==='resume'){
          data.detail.status=data.jobs[0].status=body.p_action==='stop'?'stoppage':'started';
          data.detail.stoppage_reason=body.p_action==='stop'?body.p_note:null;
          return reply({ok:true,action:body.p_action});
        }
        data.detail.lines[0].completed=body.p_completed;data.detail.lines[0].note=body.p_note;
        data.detail.progress={...data.detail.progress,percent:body.p_completed?100:0,completed_hours:body.p_completed?1:0,completed_lines:body.p_completed?1:0};
        return reply({ok:true,action:'line'});
      }
      throw Error(`Unexpected RPC ${rpc}`);
    }};
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-fitters.js'),'utf8'),{window:root,
    getPdcSupabaseAccessToken:()=> 'session',AbortController,setTimeout,clearTimeout,setInterval:fn=>intervals.push(fn)});
  return {root,doc,data,calls,mechanic,line,note,saveNote,refresh,stop,confirmStop,stopReason,stopType,action,listeners,sync,
    get renders(){return renders;},get html(){return html;},poll:()=>intervals[0](),
    delayJobs(){let resolve;const promise=new Promise(r=>resolve=r);gate={promise};return resolve;},
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
