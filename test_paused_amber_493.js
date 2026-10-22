/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r493 (F106, Craig 22 Oct 2026): "They do hit pause, can we change the chips to a yellow or an orange? That means it's paused."
// Display only. Paused = the job clock is held (stoppage, break, end of day, weekend, holiday / closure, waiting allocation).
// Paused work shows amber with a "Paused" label; running stays blue; STOPPAGE tiles keep their red. Made-up data only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
global.parseIsoTimestamp=v=>{const d=new Date(v);return Number.isNaN(d.getTime())?null:d;};global.cleanNavisionText=v=>String(v??'').trim();
global.escapeHtml=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fitters=require('./pdc-fitters.js');
const slim=require('./pdc-planner-slim.js');
const planner=require('./workshop-planner.js'),config=planner.WORKSHOP_CONFIG;
Object.assign(config,{dayStartMinutes:360,dayEndMinutes:990,dayLengthMinutes:630,workingDayIndexes:[1,2,3,4,5],closureDateKeys:['2026-10-06'],breakWindowsByDateOrScope:[{startMinutes:720,endMinutes:750,dateKey:'',scope:'global'}],overtimeWindowsByDateOrScope:[]});
const read=f=>fs.readFileSync(f,'utf8');
const progress={percent:41,completed_hours:4,total_hours:10,running:1,stale:0,current:[{booking_id:'b1',line_identity:'l1',section:'5',description:'Section 5 — Demo front end',technician:'Demo fitter',elapsed_minutes:90,allowance_minutes:180,stale:false}]};
const perth=(day,hhmm)=>new Date(`${day}T${hhmm}:00+08:00`);

test('running strip: Running in blue by default, Paused in amber with the reason in the hover title',()=>{
  const run=fitters.progressHtml(progress,true,{resettable:true});
  assert.match(run,/<span class="fitter-running" title="Section 5/);
  assert.match(run,/<b>Running: 1<\/b>/);
  assert.doesNotMatch(run,/is-paused|Paused/);
  const paused=fitters.progressHtml(progress,true,{resettable:true,paused:'Outside working time'});
  assert.match(paused,/class="fitter-progress is-compact has-running is-paused"/);
  assert.match(paused,/<span class="fitter-running is-paused" title="Paused · Outside working time\nSection 5/);
  assert.match(paused,/<b>Paused: 1<\/b> <span>Now: Section 5 — Demo front end · Demo fitter · 1h 30m of 3h 00m<\/span>/);
  assert.match(paused,/41% work completed · 4 of 10 h · 1 paused/);
  assert.match(fitters.runningHtml(progress,{paused:'Paused · Stoppage'}),/title="Paused · Stoppage\n/);
  assert.match(fitters.runningHtml(progress,{paused:true}),/<b>Paused: 1<\/b>/);
});

test('paused never shows without started items, and stale items still say running too long',()=>{
  assert.equal(fitters.progressHtml({percent:50,completed_hours:1,total_hours:2,current:[]},true,{paused:'Stoppage'}).includes('is-paused'),false);
  const stale={...progress,stale:1,current:[{...progress.current[0],elapsed_minutes:867,stale:true}]};
  const html=fitters.progressHtml(stale,true,{resettable:true,paused:'Outside working time'});
  assert.match(html,/class="fitter-running is-stale is-paused"/);
  assert.match(html,/1 running too long/);
  assert.match(html,/data-fitter-item-reset="b1"/);
});

test('fitter iPad: a started item and a started conversion section turn amber with a Paused label while the clock is held',()=>{
  const line={line_identity:'l1',description:'Demo bar',hours:3,item_status:'running',item_start_seconds:0,item_elapsed_minutes:60,stage_code:'FITTING'};
  const running=fitters.fitterLineCardHtml(line,0,{editable:true,disabled:false,paused:false,jobSeconds:3600});
  assert.match(running,/class="fitter-line is-running"/);
  assert.match(running,/In progress · 1h 00m of 3h 00m/);
  assert.doesNotMatch(running,/Paused/);
  const paused=fitters.fitterLineCardHtml(line,0,{editable:true,disabled:false,paused:true,jobSeconds:3600});
  assert.match(paused,/class="fitter-line is-running is-paused"/);
  assert.match(paused,/Paused · In progress · 1h 00m of 3h 00m/);
  assert.match(paused,/class="conv-bar is-paused"/);
  const section={id:'5',label:'Section 5',description:'Demo front end',planned_minutes:180,status:'in_progress',elapsed_minutes:90};
  const conv={line_identity:'c1',description:'Demo conversion',stage_code:'BUS_4X4',hours:10,conversion:{id:'coaster',sections:[section]}};
  assert.match(fitters.conversionSectionHtml(conv,section,{booking:'b1',paused:false}),/class="conv-section is-running" /);
  const s=fitters.conversionSectionHtml(conv,section,{booking:'b1',paused:true});
  assert.match(s,/class="conv-section is-running is-paused" /);
  assert.match(s,/Paused · In progress · 1h 30m of 3h 00m/);
  assert.doesNotMatch(fitters.conversionSectionHtml(conv,{...section,status:'complete',actual_minutes:100},{booking:'b1',paused:true}),/is-paused|Paused/);
});

test('fitter iPad wiring: the job progress strip uses the clock tone, and sections pause with the job clock',()=>{
  const src=read('pdc-fitters.js');
  assert.match(src,/progressHtml\(detail\.progress,false,\{paused:fitterPausedLabel\(detail\)\}\)/);
  assert.match(src,/function fitterPausedLabel\(d\)[\s\S]*?clock\.tone==='paused' \? clock\.label : ''/);
  assert.match(src,/paused:detail\?\.status!=='started'\|\|clock\.tone!=='running'/);
  for(const [status,timer,label] of [['stoppage',{elapsed_seconds:60,running:false},'Paused · Stoppage'],['started',{elapsed_seconds:60,running:false},'Outside working time']])
    assert.equal(fitters.timerModel({status,actual_start_at:'2026-10-20T01:00:00Z',timer}).label,label);
});

test('planner: a started job is paused outside its bay working time (Bus bays 6 am – 3 pm, other bays 6 am – 4:30 pm, breaks, weekends, closures)',()=>{
  const bus={status:'started',stage:'BUS_4X4',bay:3},fit={status:'started',stage:'FITTING',bay:1};
  assert.equal(planner.workshopEntryPausedNow(bus,perth('2026-10-22','10:00')),false);
  assert.equal(planner.workshopEntryPausedNow(bus,perth('2026-10-22','12:10')),true,'break');
  assert.equal(planner.workshopEntryPausedNow(bus,perth('2026-10-22','15:30')),true,'Bus bays close at 3 pm');
  assert.equal(planner.workshopEntryPausedNow({...bus,bay:8},perth('2026-10-22','14:30')),true,'Bus bays 8 / 9 close at 2 pm');
  assert.equal(planner.workshopEntryPausedNow(bus,perth('2026-10-22','18:04')),true,'Craig screenshot time');
  assert.equal(planner.workshopEntryPausedNow(fit,perth('2026-10-22','15:30')),false,'Fitting is open until 4:30 pm');
  assert.equal(planner.workshopEntryPausedNow(fit,perth('2026-10-22','16:45')),true);
  assert.equal(planner.workshopEntryPausedNow(fit,perth('2026-10-24','10:00')),true,'Saturday');
  assert.equal(planner.workshopEntryPausedNow(fit,perth('2026-10-06','10:00')),true,'closure');
  assert.equal(planner.workshopEntryPausedNow(fit,perth('2026-10-22','05:30')),true,'before opening');
  for(const status of ['planned','queued','stoppage','completed']) assert.equal(planner.workshopEntryPausedNow({...fit,status},perth('2026-10-22','18:00')),false,status);
});

test('planner tile: Paused label, amber class and the running strip reason; STOPPAGE stays red with an amber Paused strip',()=>{
  const src=read('workshop-planner.js');
  assert.match(src,/const pausedNow = started && typeof workshopEntryPausedNow === 'function' && workshopEntryPausedNow\(entry\);/);
  assert.match(src,/started \? 'is-started' : '', pausedNow \? 'is-paused' : ''/);
  assert.match(src,/entry\.status === 'started' \? \(pausedNow \? 'PAUSED' : 'LIVE'\)/);
  assert.match(src,/paused: entry\.status === 'stoppage' \? 'Stoppage' : pausedNow \? 'Outside working time' : ''/);
  const label=slim.summaryHtml({key:'900',jc:'J900',stock:'DEMO1',customer:'Demo Customer',model:'Demo',status:'paused'});
  assert.match(label,/<span class="planner-work-state is-paused">Paused · <\/span>Key 900 · JC J900/);
  assert.match(slim.summaryHtml({key:'900',status:'started'}),/<span class="planner-work-state">Running · <\/span>/);
  assert.match(slim.summaryHtml({key:'900',status:'stoppage'}),/<span class="planner-work-state">Stopped · <\/span>/);
  assert.match(read('pdc-planner-slim.js'),/workshopEntryPausedNow\(entry\) \? 'paused' : entry\.status/);
  assert.match(read('control-board-overview.js'),/paused: item\.status === 'stoppage' \? 'Stoppage' : ''/);
});

test('amber CSS: paused tile beats the blue pulse; STOPPAGE red untouched; fitter amber only on paused items',()=>{
  const row=read('pdc-running-row.css'),ticks=read('pdc-conversion-ticks.css'),plannerCss=read('workshop-planner.css');
  assert.match(row,/\.workshop-plan-chip\.is-started\.is-paused \{ border-color:#d97706; border-left-color:#b45309; background:#fef3c7; animation:none; \}/);
  assert.match(plannerCss,/\.workshop-plan-chip\.is-stoppage \{ border-color: #991b1b; border-left-color: #7f1d1d; background: #fee2e2; \}/);
  assert.match(ticks,/\.fitter-running\.is-paused b\{background:#fde68a;color:#78350f\}/);
  assert.match(ticks,/\.fitter-progress\.is-paused>\.fitter-progress-run\{[^}]*animation:none\}/);
  assert.match(ticks,/\.fitter-line\.is-running\.is-paused,\.conv-section\.is-running\.is-paused\{border-color:#d97706;background:#fffbeb\}/);
  assert.match(ticks,/\.conv-bar\.is-paused>span\{background:#d97706\}/);
});

test('cache-bust tags: r493 on every changed runtime file',()=>{
  const index=read('index.html');
  for(const f of ['pdc-fitters\\.js','pdc-conversion-ticks\\.css','pdc-running-row\\.css','control-board-overview\\.js','canonical-entry\\.js'])
    assert.match(index,new RegExp(`${f}\\?[^"]*r493=2026\\.10\\.22\\.r493`),f);
  assert.equal((read('app.js').match(/workshop-planner\.js\?station-scope=[^`]*&r493=2026\.10\.22\.r493&/g)||[]).length,2);
  assert.match(read('canonical-entry.js'),/pdc-planner-slim\.js\?[^']*r493=2026\.10\.22\.r493/);
  assert.match(read('docs/FAULT_LOG.md'),/\| F106 \|/);
});
