'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {createService}=require('./pdc-fitters.js');
const reply=body=>({ok:true,json:async()=>body});
const copy=value=>JSON.parse(JSON.stringify(value));
const flush=async()=>{for(let i=0;i<8;i++)await new Promise(resolve=>setImmediate(resolve));};
function fixture() {
  let context={actor:'staff',token:'session',role:'fitter',config:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test',workshop:{sharedData:true}}};
  let pause=null;
  const calls=[],data={revision:'r1',jobs:[{id:'job',status:'started',version:1}],bays:[],
    detail:{booking_id:'job',status:'started',version:1,catalog_hash:'scope',stage_code:'FITTING',actual_start_at:'2026-09-17T00:00:00Z',
      lines:[{line_identity:'line',description:'Fit bracket',stage_code:'FITTING',scope_hash:'scope',note:'Confirmed',completed:false,hours:1}],
      progress:{percent:0,total_hours:1,completed_hours:0},
      server_now:'2026-09-17T00:01:00Z',timer:{elapsed_seconds:60,running:true,as_of:'2026-09-17T00:01:00Z',next_change_at:'2026-09-17T01:00:00Z'}}};
  const fetch=async(url,options)=>{
    const name=url.split('/').pop(),body=JSON.parse(options.body);calls.push({name,body});
    if(name==='get_fitter_roster')return reply({ok:true,refresh_supported:true,technicians:[{id:'mechanic',name:'Mechanic'}]});
    if(name==='fitter_job_command') {
      data.revision+='x';data.detail.version++;
      if(body.p_action==='line'){data.detail.lines[0].note=body.p_note;data.detail.lines[0].completed=body.p_completed;}
      if(body.p_action==='stop'){data.detail.status=data.jobs[0].status='stoppage';data.detail.timer.running=false;}
      if(body.p_action==='resume'){data.detail.status=data.jobs[0].status='started';data.detail.timer.running=true;}
      if(body.p_action==='complete'){data.jobs=[];data.detail=null;}
      return reply({ok:true,action:body.p_action,booking_id:'job'});
    }
    assert.equal(name,'get_fitter_refresh','optimized screen must not read the two legacy endpoints');
    const response=body.p_known_revision===data.revision
      ? {ok:true,unchanged:true,revision:data.revision,booking_id:data.detail?.booking_id||null,timing:data.detail?{server_now:data.detail.server_now,timer:data.detail.timer}:null}
      : {ok:true,unchanged:false,...data,booking_id:data.detail?.booking_id||null};
    const result=copy(response);
    if(pause){const gate=pause;pause=null;await gate;}
    return reply(result);
  };
  return {data,calls,fetch,service:createService({context:()=>context,fetch,uuid:()=>`request-${calls.length}`}),
    setContext:update=>{context={...context,...update};},hold(){let release;pause=new Promise(resolve=>release=resolve);return release;}};
}
test('unchanged fitter polls use one small revision/timer response and retain the confirmed checklist',async()=>{
  const f=fixture();const first=await f.service.refresh('mechanic','');
  f.data.detail.timer.elapsed_seconds=70;
  const next=await f.service.refresh('mechanic','job');
  assert.equal(f.calls.length,2);assert.equal(f.calls[1].body.p_known_revision,'r1');
  assert.equal(next.detail.lines,first.detail.lines);assert.equal(next.jobs,first.jobs);
  assert.equal(next.detail.timer.elapsed_seconds,70);assert.equal(next.detail.lines[0].note,'Confirmed');
});
test('scope, note and queue changes refresh together even when booking version is unchanged',async()=>{
  const f=fixture();await f.service.refresh('mechanic','');
  f.data.revision='source-change';f.data.detail.catalog_hash='scope-2';f.data.detail.lines[0].note='Other fitter note';
  f.data.jobs.push({id:'next',status:'queued',version:1});
  const updated=await f.service.refresh('mechanic','job');
  assert.equal(updated.detail.version,1);assert.equal(updated.detail.catalog_hash,'scope-2');
  assert.equal(updated.detail.lines[0].note,'Other fitter note');assert.equal(updated.jobs.length,2);
});
test('manual refresh, mechanic and selected-booking changes cannot reuse a different snapshot',async()=>{
  const f=fixture();await f.service.refresh('mechanic','');
  await f.service.refresh('mechanic','job',{force:true});
  await f.service.refresh('other-mechanic','job');
  await f.service.refresh('other-mechanic','');
  assert.ok(f.calls.every(c=>c.body.p_known_revision===null));
});
test('simultaneous fitter focus and timer reads share one request',async()=>{
  const f=fixture();await f.service.refresh('mechanic','');const release=f.hold();
  const a=f.service.refresh('mechanic','job'),b=f.service.refresh('mechanic','job');
  assert.equal(f.calls.length,2);release();assert.equal(await a,await b);
});
test('a late former-mechanic response cannot replace the current mechanic revision baseline',async()=>{
  const f=fixture();await f.service.refresh('mechanic','');const release=f.hold();
  const old=f.service.refresh('mechanic','job');
  await f.service.refresh('other-mechanic','job');release();
  await assert.rejects(old,e=>e.code==='session_changed');
  await f.service.refresh('other-mechanic','job');assert.equal(f.calls.at(-1).body.p_known_revision,'r1');
});
test('auth changes and close discard late incremental reads without caching them',async()=>{
  for(const change of [{actor:'different'},{token:'renewed'},{role:'viewer'},null]) {
    const f=fixture();await f.service.refresh('mechanic','');const release=f.hold();
    const pending=f.service.refresh('mechanic','job');
    if(change)f.setContext(change);else f.service.invalidateReads();
    release();await assert.rejects(pending,e=>e.code==='session_changed');
    await f.service.refresh('mechanic','job');assert.equal(f.calls.at(-1).body.p_known_revision,null);
  }
});
test('a command supersedes its in-flight poll and always forces the next confirmed read',async()=>{
  const f=fixture();await f.service.refresh('mechanic','');const release=f.hold();
  const pending=f.service.refresh('mechanic','job');
  await f.service.command({p_action:'line',p_note:'Saved new note',p_completed:true});
  release();await assert.rejects(pending,e=>e.code==='session_changed');
  const result=await f.service.refresh('mechanic','job');
  assert.equal(f.calls.at(-1).body.p_known_revision,null);assert.equal(result.detail.lines[0].note,'Saved new note');
});
test('unverifiable unchanged replies cannot establish a snapshot baseline',async()=>{
  let calls=0;
  const service=createService({context:()=>({actor:'a',token:'t',role:'fitter',config}),fetch:async()=>{calls++;return reply({ok:true,unchanged:true,revision:'r1',booking_id:'job'});}});
  const config={projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',workshop:{sharedData:true}};
  await assert.rejects(service.refresh('mechanic','job'),e=>e.code==='invalid_refresh');assert.equal(calls,1);
});
function screen() {
  const f=fixture(),events={},elements={},intervals=[];let html='',renders=0;
  const element=(selector,extra={})=>elements[selector]={handlers:{},addEventListener(type,fn){this.handlers[type]=fn;},...extra};
  const mechanic=element('#fitter-mechanic',{tagName:'SELECT'});
  const note=element('[data-fitter-note]',{tagName:'TEXTAREA',dataset:{fitterNote:'line'},value:''});
  const line=element('[data-fitter-line]',{tagName:'INPUT',dataset:{fitterLine:'line'},checked:false});
  const action=element('[data-fitter-action]',{dataset:{fitterAction:'complete'}});
  const manual=element('[data-fitter-refresh]');
  const saveNote=element('[data-fitter-save-note]',{dataset:{fitterSaveNote:'line'}});
  const host={set innerHTML(value){html=value;renders++;},get innerHTML(){return html;},
    querySelectorAll:selector=>elements[selector]?[elements[selector]]:[],querySelector:()=>null,contains:node=>Object.values(elements).includes(node)};
  const doc={body:{dataset:{currentView:'fitters'}},hidden:false,activeElement:null,
    getElementById:id=>id==='fitters-host'?host:elements[`#${id}`],addEventListener:(type,fn)=>{events[type]=fn;}};
  const root={document:doc,PDC_AUTH_CONTEXT:{userId:'staff',role:'fitter'},
    PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test',workshop:{sharedData:true}},
    crypto:{randomUUID:()=>`request-${f.calls.length}`},fetch:f.fetch,addEventListener:(type,fn)=>{events[type]=fn;}};
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-fitters.js'),'utf8'),{window:root,getPdcSupabaseAccessToken:()=> 'session',
    setTimeout,clearTimeout,setInterval:(fn,ms)=>intervals.push({fn,ms}),AbortController,Date,performance,console});
  return {...f,root,doc,events,mechanic,note,line,action,manual,saveNote,get html(){return html;},get renders(){return renders;},
    poll:()=>intervals.find(i=>i.ms===10000).fn(),async open(){root.PdcFitters.open();await flush();mechanic.handlers.change({target:{value:'mechanic'}});await flush();}};
}
test('optimized UI keeps checklist DOM and note drafts while using fresh timing only',async()=>{
  const s=screen();await s.open();const before=s.renders;
  s.note.value='Unsaved draft';s.note.handlers.input({target:s.note});
  s.data.detail.timer.elapsed_seconds=75;s.poll();await flush();
  assert.equal(s.renders,before);assert.equal(s.calls.at(-1).body.p_known_revision,'r1');
  s.data.revision='scopechange';s.data.detail.lines[0].scope_hash='scope-2';s.poll();await flush();
  assert.match(s.html,/Unsaved draft/);
  const commands=s.calls.filter(c=>c.name==='fitter_job_command').length;
  s.saveNote.handlers.click({currentTarget:s.saveNote});await flush();
  assert.match(s.html,/changed while you were writing/);assert.equal(s.calls.filter(c=>c.name==='fitter_job_command').length,commands);
});
test('hidden or other-route fitter screens do no polling and return with an authoritative refresh',async()=>{
  const s=screen();await s.open();let count=s.calls.length;
  s.doc.hidden=true;s.poll();s.events.focus();await flush();assert.equal(s.calls.length,count);
  s.doc.hidden=false;s.doc.body.dataset.currentView='dashboard';s.root.PdcFitters.close();s.poll();await flush();assert.equal(s.calls.length,count);
  s.doc.body.dataset.currentView='fitters';s.root.PdcFitters.open();await flush();
  assert.equal(s.calls.at(-1).body.p_known_revision,null);
});
test('optimized checkbox saves and completion force immediate full refreshes and handover',async()=>{
  const s=screen();await s.open();s.line.checked=true;s.line.handlers.change({currentTarget:s.line});await flush();
  assert.equal(s.data.detail.lines[0].completed,true);assert.equal(s.calls.at(-1).body.p_known_revision,null);
  s.action.handlers.click({currentTarget:s.action});await flush();
  assert.equal(s.calls.at(-1).body.p_known_revision,null);assert.match(s.html,/No more jobs assigned/);
});
