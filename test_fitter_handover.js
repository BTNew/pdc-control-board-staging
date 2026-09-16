const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {fitterJobFlow}=require('./pdc-fitters.js');

const job=(id,status='planned',extra={})=>({id,status,version:1,stage_code:'FITTING',stage_name:'Fitting',bay_number:1,
  stock:id.toUpperCase(),job_card:`JC-${id}`,customer:'Test customer',vehicle:'Test vehicle',
  start_at:'2026-09-16T02:00:00Z',end_at:'2026-09-16T03:00:00Z',...extra});
const ids=rows=>rows.map(row=>row.id);
test('job flow keeps a selected running or stopped booking and separates future work',()=>{
  const jobs=[job('running','started'),job('paused','stoppage'),job('next'),job('later','queued'),job('last')];
  const flow=fitterJobFlow(jobs,'paused');
  assert.equal(flow.current.id,'paused');assert.equal(flow.next.id,'next');
  assert.deepEqual(ids(flow.otherActive),['running']);assert.deepEqual(ids(flow.upcoming),['later','last']);
  assert.equal(new Set([flow.current.id,flow.next.id,...ids(flow.otherActive),...ids(flow.upcoming)]).size,5);
});
test('previewing a future job cannot replace running work and missing selections use the fresh queue',()=>{
  const jobs=[job('running','started'),job('next'),job('later')];
  for(const selected of ['later','removed',''])assert.equal(fitterJobFlow(jobs,selected).current.id,'running');
  const fresh=fitterJobFlow([job('next'),job('later')],'removed');
  assert.equal(fresh.current.id,'next');assert.equal(fresh.next.id,'later');assert.deepEqual(fresh.upcoming,[]);
});
test('stopped jobs stay available before future work and exhausted queues have no next job',()=>{
  const paused=fitterJobFlow([job('paused','stoppage'),job('next')],'');
  assert.equal(paused.current.id,'paused');assert.equal(paused.next.id,'next');
  const last=fitterJobFlow([job('last')],'');assert.equal(last.current.id,'last');assert.ok(last.next==null);
  const empty=fitterJobFlow([],'old');assert.ok(empty.current==null);assert.ok(empty.next==null);
  assert.deepEqual(empty.otherActive,[]);assert.deepEqual(empty.upcoming,[]);
});

const flush=async()=>{for(let i=0;i<12;i++)await new Promise(resolve=>setImmediate(resolve));};
const reply=body=>({ok:true,json:async()=>structuredClone(body)});
function screenFixture() {
  const calls=[],events=[],listeners={},intervals=[],scrolls=[];
  let html='',elements=[],renders=0,commandGate=null,listError=false,commandError=null,loseConfirmation=false;
  const data={jobs:[job('current-a','started'),job('next-b'),job('later-c')],details:new Map(),receipts:new Map()};
  function detail(row) {
    return {ok:true,booking_id:row.id,version:row.version,status:row.status,stage_code:row.stage_code,catalog_hash:`scope-${row.id}`,
      actual_start_at:row.status==='started'?'2026-09-16T01:00:00Z':null,
      timer:{elapsed_seconds:row.status==='started'?3600:0,running:row.status==='started',as_of:'2026-09-16T02:00:00Z',next_change_at:'2026-09-16T03:00:00Z',history_complete:true},
      lines:[{line_identity:`line-${row.id}`,description:`Operation for ${row.stock}`,stage_code:row.stage_code,hours:1,completed:row.status==='started',note:'',scope_hash:`scope-${row.id}`}],
      progress:{percent:row.status==='started'?100:0,total_hours:1,completed_hours:row.status==='started'?1:0,total_lines:1,completed_lines:row.status==='started'?1:0,can_complete:row.status==='started',unknown_hours:0}};
  }
  for(const row of data.jobs)data.details.set(row.id,detail(row));
  function matches(node,selector) {
    if(selector.includes(' '))return false;
    const attrs=[...selector.matchAll(/\[([^=\]]+)(?:="([^"]*)")?\]/g)];
    if(attrs.some(([,key,value])=>!Object.hasOwn(node.attrs,key)||(value!==undefined&&node.attrs[key]!==value)))return false;
    const cls=selector.match(/^\.([\w-]+)/);if(cls&&!String(node.attrs.class||'').split(/\s+/).includes(cls[1]))return false;
    const id=selector.match(/^#([\w-]+)/);if(id&&node.attrs.id!==id[1])return false;
    const tag=selector.match(/^[a-z]+/i);return !tag||node.tagName===tag[0].toUpperCase();
  }
  const host={get innerHTML(){return html;},set innerHTML(value){
    html=value;renders++;elements=[];
    for(const match of value.matchAll(/<([a-z][\w-]*)(\s[^>]*|)>/gi)) {
      const attrs={};for(const a of match[2].matchAll(/([\w-]+)(?:="([^"]*)")?/g))attrs[a[1]]=a[2]??'';
      const node={tagName:match[1].toUpperCase(),attrs,dataset:{},handlers:{},value:'',textContent:'',
        addEventListener(type,fn){this.handlers[type]=fn;},setAttribute(name,value){this.attrs[name]=String(value);},
        querySelector(){return null;},focus(){doc.activeElement=this;},
        scrollIntoView(options){scrolls.push({attrs:{...this.attrs},options});}};
      for(const [key,val]of Object.entries(attrs))if(key.startsWith('data-'))node.dataset[key.slice(5).replace(/-([a-z])/g,(_,letter)=>letter.toUpperCase())]=val;
      elements.push(node);
    }
  },querySelectorAll:selector=>elements.filter(node=>matches(node,selector)),
    querySelector:selector=>elements.find(node=>matches(node,selector))||null,
    contains:node=>elements.includes(node)};
  const doc={body:{dataset:{currentView:'fitters'}},hidden:false,activeElement:null,
    getElementById:id=>id==='fitters-host'?host:host.querySelector(`#${id}`),
    querySelector:selector=>host.querySelector(selector),addEventListener:(type,fn)=>{listeners[type]=fn;}};
  const root={document:doc,PDC_AUTH_CONTEXT:{userId:'staff-test',role:'operator'},
    PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test',workshop:{sharedData:true}},
    crypto:{randomUUID:()=>`request-${calls.length}`},performance:{now:()=>0},requestAnimationFrame:fn=>fn(),
    CustomEvent:class {constructor(type,options){this.type=type;this.detail=options.detail;}},dispatchEvent:event=>events.push(event),
    addEventListener:(type,fn)=>{listeners[type]=fn;},scrollTo:options=>scrolls.push(options),
    fetch:async(url,options)=>{
      const rpc=url.split('/').pop(),body=JSON.parse(options.body);calls.push({rpc,body});
      if(rpc==='get_fitter_roster')return reply({ok:true,technicians:[{id:'mechanic-a',name:'Test mechanic'}]});
      if(rpc==='get_fitter_jobs'){
        if(listError)throw Error('Queue unavailable');
        return reply({ok:true,bays:[],jobs:data.jobs.filter(row=>!row.reassigned&&['planned','queued','started','stoppage'].includes(row.status))});
      }
      if(rpc==='get_fitter_job'){
        const row=data.jobs.find(row=>row.id===body.p_booking_id&&!row.reassigned);
        return reply(row?data.details.get(row.id):{ok:false,error:'assignment_changed'});
      }
      if(rpc==='fitter_job_command'){
        if(commandGate){const pending=commandGate;commandGate=null;await pending.promise;}
        if(data.receipts.has(body.p_request_id))return reply(data.receipts.get(body.p_request_id));
        if(commandError){const code=commandError;commandError=null;return reply({ok:false,error:code});}
        const row=data.jobs.find(row=>row.id===body.p_booking_id),info=data.details.get(row.id);
        assert.equal(body.p_expected_version,row.version);assert.equal(body.p_catalog_hash,info.catalog_hash);
        assert.equal(body.p_action,'complete','handover must not automatically start the next job');
        assert.equal(row.status,'started');assert.equal(info.progress.can_complete,true);
        row.status=info.status='completed';row.version++;info.version=row.version;info.timer.running=false;
        const result={ok:true,action:'complete',booking_id:row.id,status:'completed',version:row.version};
        data.receipts.set(body.p_request_id,result);
        if(loseConfirmation){loseConfirmation=false;throw Error('Response lost after commit');}
        return reply(result);
      }
      throw Error(`Unexpected RPC ${rpc}`);
    }};
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-fitters.js'),'utf8'),{window:root,
    getPdcSupabaseAccessToken:()=> 'test-session',AbortController,setTimeout,clearTimeout,
    requestAnimationFrame:fn=>fn(),setInterval:fn=>intervals.push(fn)});
  function click(selector) {
    const element=host.querySelector(selector);assert.ok(element,`Missing ${selector}`);
    assert.equal(Object.hasOwn(element.attrs,'disabled'),false,`${selector} must be enabled`);
    element.handlers.click({currentTarget:element,target:element});
  }
  return {root,doc,data,calls,events,listeners,scrolls,click,get html(){return html;},get renders(){return renders;},
    poll:()=>intervals[0](),
    failList(value=true){listError=value;},rejectCommand(code){commandError=code;},loseCompletionResponse(){loseConfirmation=true;},
    delayCommand(){let resolve;const promise=new Promise(r=>resolve=r);commandGate={promise};return resolve;},
    async open(){root.PdcFitters.open();await flush();const picker=host.querySelector('#fitter-mechanic');
      picker.handlers.change({target:{value:'mechanic-a'}});await flush();}};
}
const selectedRead=f=>f.calls.filter(call=>call.rpc==='get_fitter_job').at(-1)?.body.p_booking_id;

test('confirmed completion opens fresh next job without starting it and late completion cannot double-save',async()=>{
  const f=screenFixture();await f.open();const release=f.delayCommand();
  f.click('[data-fitter-action="complete"]');await flush();
  assert.equal(selectedRead(f),'current-a');assert.equal(f.events.length,0);assert.match(f.html,/Completing/);
  release();await flush();
  assert.equal(selectedRead(f),'next-b');assert.match(f.html,/<h2[^>]*>NEXT-B\b/);
  assert.match(f.html,/Start job/);assert.equal(f.data.jobs[1].status,'planned');
  assert.equal(f.calls.filter(call=>call.rpc==='fitter_job_command').length,1);
  assert.equal(f.events.length,1);assert.equal(f.events[0].detail.action,'complete');
  assert.ok(f.scrolls.length>0,'the next job heading must be brought into view after completion');
});
test('handover uses fresh assignments rather than the next-job preview',async()=>{
  const f=screenFixture();await f.open();const release=f.delayCommand();f.click('[data-fitter-action="complete"]');
  f.data.jobs[1].reassigned=true;release();await flush();
  assert.equal(selectedRead(f),'later-c');assert.match(f.html,/<h2[^>]*>LATER-C\b/);
  assert.equal(f.calls.filter(call=>call.rpc==='get_fitter_job'&&call.body.p_booking_id==='next-b').length,0);
});
test('completion returns a multi-bay mechanic to remaining stopped work before planned jobs',async()=>{
  const f=screenFixture();const stopped=job('paused-other','stoppage',{bay_number:2});
  f.data.jobs.splice(1,0,stopped);
  f.data.details.set(stopped.id,{...structuredClone(f.data.details.get('current-a')),booking_id:stopped.id,
    status:'stoppage',stoppage_reason:'Awaiting part',catalog_hash:`scope-${stopped.id}`,
    timer:{elapsed_seconds:900,running:false,as_of:'2026-09-16T02:00:00Z',next_change_at:null}});
  await f.open();f.click('[data-fitter-action="complete"]');await flush();
  assert.equal(selectedRead(f),'paused-other');assert.match(f.html,/<h2[^>]*>PAUSED-OTHER\b/);
  assert.match(f.html,/Resume job/);assert.equal(f.calls.filter(call=>call.rpc==='fitter_job_command').length,1);
});
test('rejected completion keeps the current job and does not announce handover',async()=>{
  const f=screenFixture();await f.open();f.rejectCommand('scope_changed');f.click('[data-fitter-action="complete"]');await flush();
  assert.equal(selectedRead(f),'current-a');assert.match(f.html,/operation list or hours changed/);
  assert.doesNotMatch(f.html,/<h2[^>]*>NEXT-B\b/);assert.equal(f.events.length,0);
});
test('lost completion response holds the current job until the same receipt confirms completion',async()=>{
  const f=screenFixture();await f.open();f.loseCompletionResponse();f.click('[data-fitter-action="complete"]');await flush();
  assert.equal(selectedRead(f),'current-a');assert.match(f.html,/Completion not confirmed/);
  assert.doesNotMatch(f.html,/<h2[^>]*>NEXT-B\b/);assert.equal(f.events.length,0);
  f.poll();await flush();assert.equal(selectedRead(f),'current-a','an ordinary poll cannot bypass an uncertain command');
  f.click('[data-fitter-retry]');await flush();
  const writes=f.calls.filter(call=>call.rpc==='fitter_job_command');
  assert.equal(writes.length,2);assert.deepEqual(writes[1].body,writes[0].body);
  assert.equal(f.data.jobs[0].version,2,'the completed booking is changed only once');assert.equal(selectedRead(f),'next-b');
});
test('confirmed completion followed by a failed queue read disables old work until refresh recovers',async()=>{
  const f=screenFixture();await f.open();f.failList();f.click('[data-fitter-action="complete"]');await flush();
  assert.equal(f.data.jobs[0].status,'completed');assert.equal(f.events.length,1);
  assert.match(f.html,/complet/i);assert.doesNotMatch(f.html,/<h2[^>]*>NEXT-B\b/);
  assert.doesNotMatch(f.html,/<button(?=[^>]*data-fitter-action="complete")(?:(?!disabled)[^>])*>/,
    'a confirmed completed booking must not offer an enabled completion action');
  f.failList(false);f.click('[data-fitter-refresh]');await flush();
  assert.equal(selectedRead(f),'next-b');assert.equal(f.calls.filter(call=>call.rpc==='fitter_job_command').length,1);
});
test('completing the final assigned job shows an exhausted queue without a stale start action',async()=>{
  const f=screenFixture();f.data.jobs=f.data.jobs.slice(0,1);await f.open();
  f.click('[data-fitter-action="complete"]');await flush();
  assert.match(f.html,/No (?:active |more |remaining |upcoming )?jobs|All (?:assigned )?jobs.*complet|Nothing.*assigned/i);
  assert.doesNotMatch(f.html,/data-fitter-action="(?:start|complete)"/);
  assert.equal(f.calls.filter(call=>call.rpc==='fitter_job_command').length,1);
});
