/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r487 (F100): Sales > Alerts cards show only what changed, one plain line per station, short dates and the r483 bay names.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const crm=require('./sales/crm-workspace.js');
const now=new Date('2026-10-22T07:40:00Z');
const B=o=>({booking_id:null,progress:null,stage_code:null,stoppage_reason:null,stoppage_started_at:null,actual_start_at:null,actual_end_at:null,scheduled_end_at:null,...o});
const tint=B({booking_id:'b-tint',stage:'Tint',bay:'Tint Bay 01',status:'planned',scheduled_start_at:'2026-11-15T23:20:00+00:00',scheduled_end_at:'2026-11-16T01:20:00+00:00'});
const hoist=B({booking_id:'b-hoist',stage:'Hoist',bay:'Express / Pits Hoist - PMB Bay 01',status:'planned',scheduled_start_at:'2026-11-16T01:20:00+00:00'});
const fab=B({booking_id:'b-fab',stage:'Fab',bay:'Internal Fabrication - PMB Bay 11',status:'planned',scheduled_start_at:'2026-11-17T06:31:00+00:00'});
const elec=B({booking_id:'b-elec',stage:'Elec',bay:'Electrical - PMB Bay 13',status:'planned',scheduled_start_at:'2026-11-18T02:01:00+00:00'});
const fitQueued=B({booking_id:'b-fit',stage:'Fitting',bay:null,status:'queued'});
const lines=(before,after)=>crm.alertSummary({event_type:'workshop_changed',details:{before,after}},now);
const texts=summary=>summary.lines.map(crm.lineText);

test('only the stations that changed are listed, one plain line each',()=>{
  const fitBooked={...fitQueued,bay:'Fitting - PMB Bay 06',status:'planned',scheduled_start_at:'2026-11-16T01:20:00Z'};
  const elecStarted={...elec,status:'started',actual_start_at:'2026-10-19T23:12:00Z'};
  const s=lines([tint,hoist,fitQueued,fab,elec],[tint,hoist,fitBooked,fab,elecStarted]);
  assert.deepEqual(texts(s),['Fitting · Bay 06 · 16 Nov, 9:20 am (was: not booked)','Elec · Work started 20 Oct, 7:12 am · Electrical Bay 13']);
  assert.equal(s.title,'Work started');
  for(const line of texts(s))assert.doesNotMatch(line,/Tint|Hoist|Fabrication|b-|\[object Object\]|2026/);
});
test('a moved booking shows the new bay and time with only the old values that changed',()=>{
  const moved={...hoist,bay:'Express - PMB Bay 02',scheduled_start_at:'2026-11-16T02:20:00Z'};
  const s=lines([tint,hoist],[tint,moved]);
  assert.equal(s.title,'Bay booking changed');
  assert.deepEqual(texts(s),['Hoist · Express Bay 02 · 16 Nov, 10:20 am (was: Express / Pits Hoist Bay 01, 16 Nov, 9:20 am)']);
  const later={...tint,scheduled_start_at:'2026-11-16T02:01:00Z',scheduled_end_at:'2026-11-16T04:01:00Z'};
  assert.deepEqual(texts(lines([tint,hoist],[later,hoist])),['Tint · Bay 01 · 16 Nov, 10:01 am (was: 16 Nov, 7:20 am)']);
});
test('bay names use the current r483 names and numbers, including old stored names',()=>{
  assert.equal(crm.bayText('Hoist','Hoist Bay 01'),'Express / Pits Hoist Bay 01');
  assert.equal(crm.bayText('Hoist','Hoist Bay 02'),'Express Bay 02');
  assert.equal(crm.bayText('Hoist','Hoist Bay 03'),'Bay 03');
  assert.equal(crm.bayText('Fitting','Fitting Bay 01'),'Bay 06');
  assert.equal(crm.bayText('Fitting','Fitting Bay 05'),'Bay 10');
  assert.equal(crm.bayText('Fab','Fab Bay 01'),'Internal Fabrication Bay 11');
  assert.equal(crm.bayText('Fab','Fab Bay 02'),'External Fabrication Bay 12');
  assert.equal(crm.bayText('Elec','Elec Bay 01'),'Electrical Bay 13');
  assert.equal(crm.bayText('Elec','Elec Bay 10'),'Electrical Bay 22');
  assert.equal(crm.bayText('Fitting','Fitting - PMB Bay 07'),'Bay 07');
  assert.equal(crm.bayText('Tint','Tint Bay 01'),'Bay 01');
  assert.equal(crm.bayText('Tyre',null),'Bay not recorded');
});
test('nothing meaningful changed (bay rename, order, timestamp format, progress) gives no lines and no card',()=>{
  const oldNames=[{...hoist,bay:'Hoist Bay 01'},{...fab,bay:'Fab Bay 01'},{...elec,bay:'Elec Bay 01'},{...tint,scheduled_start_at:'2026-11-15T23:20:00Z',scheduled_end_at:'2026-11-16T01:20:00Z',progress:1}];
  assert.deepEqual(lines(oldNames,[elec,tint,fab,hoist]).lines,[]);
  const alerts=[{id:'noise',tracking_id:'v1',event_type:'workshop_changed',occurred_at:'2026-10-22T07:36:00Z',details:{before:oldNames,after:[tint,hoist,fab,elec]}},
    {id:'eta-noise',tracking_id:'v1',event_type:'eta_changed',occurred_at:'2026-10-22T07:00:00Z',details:{before:{kewdale_eta:'5/11/2026',dealer_eta:null},after:{kewdale_eta:'05/11/2026',dealer_eta:''}}}];
  assert.deepEqual(crm.groupAlerts(alerts,now),[]);
});
test('stopped, resumed, finished, removed and new bookings read in plain words',()=>{
  const stopped={...elec,status:'stoppage',actual_start_at:'2026-10-19T23:12:00Z',stoppage_started_at:'2026-10-20T01:00:00Z',stoppage_reason:'Waiting on parts'};
  const started={...elec,status:'started',actual_start_at:'2026-10-19T23:12:00Z'};
  let s=lines([started],[stopped]);assert.equal(s.title,'Work stopped');assert.deepEqual(texts(s),['Elec · Work stopped 20 Oct, 9:00 am · Waiting on parts · Electrical Bay 13']);
  s=lines([stopped],[{...stopped,status:'started'}]);assert.equal(s.title,'Work resumed');
  s=lines([started],[{...started,status:'completed',actual_end_at:'2026-10-20T07:30:00Z'}]);assert.equal(s.title,'Work finished');assert.deepEqual(texts(s),['Elec · Work finished 20 Oct, 3:30 pm · Electrical Bay 13']);
  s=lines([tint,hoist],[tint]);assert.equal(s.title,'Booking removed');assert.deepEqual(texts(s),['Hoist · Booking removed (was: Express / Pits Hoist Bay 01, 16 Nov, 9:20 am)']);
  s=lines([],[hoist]);assert.equal(s.title,'Bay booked');assert.deepEqual(texts(s),['Hoist · Express / Pits Hoist Bay 01 · 16 Nov, 9:20 am (was: not booked)']);
});
test('the year appears only when a date is outside the current Perth year',()=>{
  assert.equal(crm.shortWhen('2026-11-16T01:20:00Z',now),'16 Nov, 9:20 am');
  assert.equal(crm.shortWhen('2027-01-04T00:05:00Z',now),'4 Jan 2027, 8:05 am');
  assert.equal(crm.shortWhen('2026-12-31T16:30:00Z',now),'1 Jan 2027, 12:30 am');
  assert.equal(crm.shortDay('15/07/2026',now),'15 Jul');
  assert.equal(crm.shortDay('2025-07-15',now),'15 Jul 2025');
});
test('stock, ETA and location alerts use the same short format',()=>{
  const eta=crm.alertSummary({event_type:'eta_changed',title:'ETA changed',details:{before:{kewdale_eta:'15/07/2026',dealer_eta:'26/11/2026',port_plant_eta:'31/10/2026'},after:{kewdale_eta:'22/07/2026',dealer_eta:'26/11/2026',port_plant_eta:'1/11/2026'}}},now);
  assert.equal(eta.title,'ETA changed');assert.deepEqual(texts(eta),['Kewdale ETA: 15 Jul → 22 Jul','Port / plant ETA: 31 Oct → 1 Nov']);
  const loc=crm.alertSummary({event_type:'location_changed',title:'Vehicle location or status changed',details:{before:{toyota_status:'In transit',pmb_location:'Yard',workshop_status:'planned',pmb_arrival_date:null},after:{toyota_status:'At PMB',pmb_location:'Yard',workshop_status:'started',pmb_arrival_date:'2026-10-20'}}},now);
  assert.equal(loc.title,'Location or status changed');
  assert.deepEqual(texts(loc),['Toyota status: In transit → At PMB','Workshop status: Booked → Work started','PMB arrival: Not recorded → 20 Oct']);
  assert.deepEqual(texts(crm.alertSummary({event_type:'stock_allocated',title:'Stock number allocated',details:{before:'',after:'13001'}},now)),['Stock number: Awaiting allocation → 13001']);
});
test('alerts for one vehicle a few minutes apart collapse into one card with the net change',()=>{
  const a1={id:'a1',tracking_id:'v1',event_type:'workshop_changed',occurred_at:'2026-10-22T07:36:00Z',details:{before:[tint,hoist],after:[{...tint,scheduled_start_at:'2026-11-16T00:00:00Z'},hoist]}};
  const a2={id:'a2',tracking_id:'v1',event_type:'workshop_changed',occurred_at:'2026-10-22T07:37:00Z',details:{before:a1.details.after,after:[{...tint,scheduled_start_at:'2026-11-16T02:01:00Z'},hoist]}};
  const other={id:'o1',tracking_id:'v2',event_type:'workshop_changed',occurred_at:'2026-10-22T07:37:00Z',details:{before:[],after:[elec]}};
  const old={id:'a0',tracking_id:'v1',event_type:'eta_changed',title:'ETA changed',occurred_at:'2026-10-22T06:00:00Z',details:{before:{kewdale_eta:'15/07/2026'},after:{kewdale_eta:'22/07/2026'}}};
  const cards=crm.groupAlerts([a1,other,old,a2],now);
  assert.equal(cards.length,3);
  const burst=cards.find(c=>c.ids.includes('a2'));
  assert.deepEqual(burst.ids,['a2','a1']);assert.equal(burst.count,2);
  assert.deepEqual(burst.lines.map(crm.lineText),['Tint · Bay 01 · 16 Nov, 10:01 am (was: 16 Nov, 7:20 am)']);
  assert.deepEqual(cards.map(c=>c.ids.join('+')).sort(),['a0','a2+a1','o1']);assert.deepEqual(cards[2].ids,['a0']);
  const back={...a2,details:{before:a1.details.after,after:a1.details.before}};
  assert.deepEqual(crm.groupAlerts([a1,back],now)[0].lines.map(crm.lineText),['Changed, then changed back']);
});
function element(id){return {id,innerHTML:'',dataset:{},events:{},addEventListener(type,fn){this.events[type]=fn;},querySelector(){return null;},scrollIntoView(){}};}
test('the Alerts page renders tidy cards and Dismiss clears every alert on a collapsed card',async()=>{
  const elements=new Map(),calls=[],el=id=>{if(!elements.has(id))elements.set(id,element(id));return elements.get(id);};
  const rows=[{tracking_id:'v1',cosi:true,salesperson_code:'BG',stock:'10001',client:'Sample Client One',vehicle:'HiLux'}];
  const host={crypto:require('node:crypto'),PDC_AUTH_CONTEXT:{userId:'u',role:'salesperson'},document:{getElementById:el},addEventListener(){},PDC_SUPABASE:{rpc(name,args){calls.push({name,args});return Promise.resolve({data:{record:{id:args.p_id,tracking_id:args.p_tracking_id,version:2,dismissed_at:'2026-10-22T07:41:00Z'}}});}}};
  const api=crm.createWorkspace(host);api.init({getRows:()=>rows,getContext:()=>({role:'salesperson'}),getSalesperson:()=>'BG',openVehicle(){},showView(){},onChanged(){}});
  const a1={id:'a1',tracking_id:'v1',version:1,event_type:'workshop_changed',title:'Workshop booking or progress changed',occurred_at:'2026-10-22T07:36:00Z',details:{before:[tint,hoist,fitQueued],after:[tint,hoist,{...fitQueued,bay:'Fitting - PMB Bay 06',status:'planned',scheduled_start_at:'2026-11-16T01:20:00Z'}]}};
  const a2={id:'a2',tracking_id:'v1',version:1,event_type:'eta_changed',title:'ETA changed',occurred_at:'2026-10-22T07:37:00Z',details:{before:{kewdale_eta:'15/07/2026'},after:{kewdale_eta:'22/07/2026'}}};
  const noise={id:'n1',tracking_id:'v1',version:1,event_type:'workshop_changed',title:'Workshop booking or progress changed',occurred_at:'2026-10-22T05:00:00Z',details:{before:[{...hoist,bay:'Hoist Bay 01'}],after:[hoist]}};
  api.setWorkspace({context:{can_edit_finance:false},alerts:[a1,a2,noise],order_refs:rows});
  api.render('alerts');const html=el('sales-alerts').innerHTML,text=html.replace(/<[^>]+>/g,'');
  assert.equal((html.match(/<article/g)||[]).length,1);
  assert.match(text,/Stock 10001 · Sample Client One/);assert.match(text,/2 updates/);
  assert.match(text,/Bay booked · ETA changed/);
  assert.ok(text.includes('Fitting · Bay 06 · 16 Nov, 9:20 am (was: not booked)'),text);
  assert.ok(text.includes('Kewdale ETA: 15 Jul → 22 Jul'),text);
  assert.doesNotMatch(text,/Workshop booking or progress changed|Bay bookings:|Tint|Express|b-hoist|\[object Object\]/);
  assert.match(html,/data-crm-open="v1"/);assert.match(html,/data-crm-dismiss="a2,a1"/);
  await el('sales-alerts').events.click({target:{dataset:{crmDismiss:'a2,a1'},disabled:false,closest(){return this;}}});
  assert.deepEqual(calls.map(c=>[c.args.p_kind,c.args.p_id]),[['dismiss_alert','a2'],['dismiss_alert','a1']]);
  assert.match(el('sales-alerts').innerHTML,/No new vehicle alerts/);
});
test('the change is front-end only and cache-busted',()=>{
  const html=fs.readFileSync('sales/index.html','utf8');
  assert.match(html,/crm-workspace\.js\?v=[^"]*alerts=2026\.10\.22\.487/);assert.match(html,/crm-workspace\.css\?v=[^"]*alerts=2026\.10\.22\.487/);
  assert.match(fs.readFileSync('sales/crm-workspace.css','utf8'),/\.crm-alert-lines/);
});
