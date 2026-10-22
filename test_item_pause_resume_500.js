/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r500 (F113, Craig 23 Oct 2026 7:25 am, fitter iPad screenshot): "I don't see the pause button on the fitter's bay now."
// The only pause control was the job-level 'Parts / other stoppage' button at the top of the job, so a fitter
// scrolled down to a started item ('running too long, tick Done or ask the controller to reset') had no Pause.
// Every started item / conversion section now shows Pause while the job is started (also running too long / over)
// and Resume while the job is stopped. Pause opens the existing stoppage panel under that item. Made-up data only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const fitters=require('./pdc-fitters.js');
const running={line_identity:'line-a',description:'Demo bar fit',stage_code:'FITTING',hours:4.5,completed:false,item_status:'running',item_start_seconds:0,item_elapsed_minutes:225,item_stale:true,scope_hash:'s'};

test('a started item shows Pause, also when it is running too long or over its hours',()=>{
  for(const line of [running,{...running,item_stale:false},{...running,item_elapsed_minutes:400}]){
    const html=fitters.fitterItemTicksHtml(line,{editable:true,disabled:false,pauseControl:'pause'});
    assert.match(html,/<button type="button" class="fitter-item-pause" data-fitter-pause="line-a" aria-label="Pause Demo bar fit">Pause<\/button>/);
    assert.doesNotMatch(html,/data-fitter-action="resume"/);
  }
  assert.match(fitters.fitterItemTicksHtml(running,{pauseControl:'pause'}),/running too long, tick Done or ask the controller to reset/);
  assert.match(fitters.fitterLineCardHtml(running,0,{editable:true,disabled:false,pauseControl:'pause'}),/is-running[^"]*is-stale[\s\S]*data-fitter-pause="line-a"/);
});

test('a paused (stopped) item shows Resume; not-started, done, supplier and view-only items show neither',()=>{
  const paused=fitters.fitterItemTicksHtml(running,{paused:true,disabled:true,pauseControl:'resume'});
  assert.match(paused,/<button type="button" class="fitter-item-resume" data-fitter-action="resume" aria-label="Resume Demo bar fit">Resume<\/button>/);
  assert.match(paused,/Paused · In progress/);
  assert.doesNotMatch(paused,/data-fitter-pause/);
  for(const line of [{...running,item_status:'not_started'},{...running,completed:true,item_status:'done',item_actual_minutes:60},{...running,external_work:true}])
    assert.doesNotMatch(fitters.fitterLineCardHtml(line,0,{editable:true,pauseControl:'pause'}),/fitter-item-pause|fitter-item-resume/);
  assert.doesNotMatch(fitters.fitterItemTicksHtml(running,{editable:false,pauseControl:''}),/<button/);
  assert.match(fitters.fitterItemTicksHtml(running,{pauseControl:'pause',pauseDisabled:true}),/data-fitter-pause="line-a" aria-label="Pause Demo bar fit" disabled>/);
});

test('a running conversion section shows Pause / Resume beside Start and Done',()=>{
  const line={line_identity:'conv-1',description:'Coaster',stage_code:'BUS_4X4',hours:3,conversion:{id:'coaster'}};
  const section={id:'5',label:'Section 5',description:'Demo front end',status:'in_progress',planned_minutes:180,elapsed_minutes:867,stale:true};
  assert.match(fitters.conversionSectionHtml(line,section,{booking:'b',pauseControl:'pause'}),/> Done<\/label><button type="button" class="fitter-item-pause" data-fitter-pause="conv-1"/);
  assert.match(fitters.conversionSectionHtml(line,section,{booking:'b',paused:true,pauseControl:'resume'}),/data-fitter-action="resume"/);
  assert.doesNotMatch(fitters.conversionSectionHtml(line,{...section,status:'complete'},{booking:'b',pauseControl:'pause'}),/fitter-item-pause/);
});

const reply=value=>({ok:true,status:200,json:async()=>value,text:async()=>JSON.stringify(value)});
const flush=async()=>{for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));};
function screen(){
  const calls=[],elements={},intervals=[];let html='',renders=0;
  const element=(name,extra={})=>elements[name]={handlers:{},addEventListener(type,fn){this.handlers[type]=fn;},...extra};
  const mechanic=element('#fitter-mechanic',{tagName:'SELECT'});
  const pause=element('[data-fitter-pause]',{dataset:{fitterPause:'line-a'}});
  const action=element('[data-fitter-action]',{dataset:{fitterAction:'resume'}});
  const confirmStop=element('[data-fitter-confirm-stop]');
  const reason=element('#fitter-stop-reason',{tagName:'TEXTAREA',scrolled:0,scrollIntoView(){this.scrolled++;},focus(){}});
  element('#fitter-stop-type',{tagName:'SELECT'});
  const host={get innerHTML(){return html;},set innerHTML(v){html=v;renders++;},querySelectorAll:s=>elements[s]?[elements[s]]:[],querySelector:s=>elements[s]||null,contains:n=>Object.values(elements).includes(n)};
  const doc={body:{dataset:{currentView:'fitters'}},hidden:false,activeElement:null,getElementById:id=>id==='fitters-host'?host:elements[`#${id}`]||null,addEventListener(){}};
  const data={jobs:[{id:'booking-a',version:1,status:'started',stage_name:'Fitting',bay_number:3,stock:'DEMO1',job_card:'J-DEMO'}],
    detail:{booking_id:'booking-a',version:1,status:'started',stage_code:'FITTING',catalog_hash:'scope-a',actual_start_at:'2026-09-16T00:00:00Z',
      timer:{elapsed_seconds:13500,running:true,as_of:'2026-09-16T03:45:00Z',next_change_at:'2026-09-16T06:00:00Z'},
      lines:[{...running,item_start_seconds:0},{line_identity:'line-b',description:'Demo snorkel',stage_code:'FITTING',hours:2.25,completed:true,item_status:'done',item_actual_minutes:69,scope_hash:'s'}],
      progress:{percent:33,total_hours:6.75,completed_hours:2.25,total_lines:2,completed_lines:1,running:1,can_complete:false,current:[]}}};
  const root={document:doc,PDC_AUTH_CONTEXT:{userId:'staff-a',role:'operator'},
    PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test',workshop:{sharedData:true}},
    performance:{now:()=>0},CustomEvent:class{constructor(t,o){this.type=t;this.detail=o.detail;}},dispatchEvent(){},crypto:{randomUUID:()=>`req-${calls.length}`},addEventListener(){},
    fetch:async(url,options)=>{const rpc=url.split('/').pop(),body=JSON.parse(options.body||'{}');calls.push({rpc,body});
      if(rpc==='get_fitter_roster')return reply({ok:true,technicians:[{id:'mechanic-a',name:'Demo fitter'}]});
      if(rpc==='get_fitter_jobs')return reply(JSON.parse(JSON.stringify({ok:true,jobs:data.jobs,bays:[]})));
      if(rpc==='get_fitter_job')return reply(JSON.parse(JSON.stringify({ok:true,...data.detail})));
      if(rpc==='fitter_job_command'){data.detail.version++;data.jobs[0].version++;
        data.detail.status=data.jobs[0].status=body.p_action==='stop'?'stoppage':'started';data.detail.stoppage_reason=body.p_action==='stop'?body.p_note:null;data.detail.timer.running=body.p_action!=='stop';
        return reply({ok:true,action:body.p_action,booking_id:'booking-a'});}
      throw Error(`Unexpected RPC ${rpc}`);}};
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-conversions.js'),'utf8'),{window:root});
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-fitters.js'),'utf8'),{window:root,getPdcSupabaseAccessToken:()=>'session',AbortController,setTimeout,clearTimeout,setInterval:fn=>intervals.push(fn)});
  return {root,calls,pause,action,confirmStop,reason,mechanic,poll:()=>intervals[0](),get html(){return html;},get renders(){return renders;},
    async open(){root.PdcFitters.open();await flush();mechanic.handlers.change({target:{value:'mechanic-a'}});await flush();}};
}

test('fitter bay screen: Pause on the running-too-long item opens the stoppage panel under it; Resume then shows on the item',async()=>{
  const f=screen();await f.open();
  const items=f.html.slice(f.html.indexOf('Items for this bay'));
  assert.match(items,/Demo bar fit[\s\S]*running too long[\s\S]*data-fitter-pause="line-a"[^>]*>Pause<\/button>/);
  assert.match(f.html,/data-fitter-stop >Pause · parts \/ other stoppage<\/button>/);
  assert.doesNotMatch(f.html,/fitter-stop-panel/);
  f.pause.handlers.click({currentTarget:f.pause});
  assert.equal(f.reason.scrolled,1,'the reason box is scrolled into view');
  const at=f.html.indexOf('fitter-stop-panel');
  assert.ok(at>f.html.indexOf('data-fitter-pause="line-a"')&&at<f.html.indexOf('Demo snorkel'),'panel sits right under the paused item');
  assert.equal((f.html.match(/fitter-stop-panel/g)||[]).length,1,'one panel only');
  assert.match(f.html,/Pause this job<\/strong> · the job clock stops for every item in this bay until you press Resume/);
  f.root.document.getElementById('fitter-stop-reason').handlers.input({target:{value:'Waiting on bracket'}});
  f.confirmStop.handlers.click();await flush();
  const stop=f.calls.find(c=>c.rpc==='fitter_job_command');
  assert.equal(stop.body.p_action,'stop');assert.equal(stop.body.p_note,'Parts: Waiting on bracket');
  assert.match(f.html,/Job stopped/);
  assert.match(f.html,/class="fitter-item-resume" data-fitter-action="resume" aria-label="Resume Demo bar fit">Resume<\/button>/);
  assert.doesNotMatch(f.html,/data-fitter-pause=/);
  f.action.handlers.click({currentTarget:f.action});await flush();
  assert.equal(f.calls.filter(c=>c.rpc==='fitter_job_command').at(-1).body.p_action,'resume');
  assert.match(f.html,/data-fitter-pause="line-a"/);
});

test('performance: the Pause control adds no reads; polls stay one job read each and do not redraw an unchanged screen',async()=>{
  const f=screen();await f.open();const reads=f.calls.length,renders=f.renders;
  for(let i=0;i<3;i++){f.poll();await flush();}
  assert.equal(f.calls.length-reads,6,'3 polls = 3 job-list reads + 3 job reads');
  assert.equal(f.renders,renders);
  const src=fs.readFileSync('pdc-fitters.js','utf8'),fn=src.slice(src.indexOf('function itemPauseHtml'),src.indexOf('const conversionDuration'));
  assert.doesNotMatch(fn,/fetch|rpc|command|for\s*\(|\.map\(|\.filter\(/);
});

test('cache bust r500 on pdc-fitters.js and pdc-conversion-ticks.css; Karratha copy untouched',()=>{
  const index=fs.readFileSync('index.html','utf8');
  assert.match(index,/pdc-fitters\.js\?[^"]*r500=2026\.10\.23\.r500/);
  assert.match(index,/pdc-conversion-ticks\.css\?[^"]*r500=2026\.10\.23\.r500/);
  assert.doesNotMatch(fs.readFileSync('karratha/pdc-fitters.js','utf8'),/r500|data-fitter-pause/);
  assert.match(fs.readFileSync('pdc-conversion-ticks.css','utf8'),/\.fitter-app \.fitter-item-pause\{color:#92400e;background:#fef3c7;border-color:#d97706\}/);
});
