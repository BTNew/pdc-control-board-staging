/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r434 (F45, change request): the Sales "PMB Status" box is blue while the Workshop Planner has a Running job for the vehicle.
// Running = a booking with status "started" on any bay (the planner's "Running · Key …" blue chip). Made-up rows only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sales=require('./sales/sales.js');
const css=fs.readFileSync('sales/sales.css','utf8'),js=fs.readFileSync('sales/sales.js','utf8'),index=fs.readFileSync('sales/index.html','utf8');
const plannerCss=fs.readFileSync('workshop-planner.css','utf8');
const bk=(status,stage='Fitting',bay='Bay 01',extra={})=>({status,stage,bay,scheduled_start_at:'2026-01-05T01:00:00Z',scheduled_end_at:'2026-01-05T03:00:00Z',...extra});
const row=(bookings,extra={})=>({tracking_id:'t1',canonical_vehicle_id:'v1',stock:'S1',pmb_location:'PMB',bay_bookings:bookings,...extra});
const blue=r=>sales.pmbStatusTone(sales.pmbSummary(r))==='running';

test('a Running (started) job on any bay makes the PMB Status box blue',()=>{
  assert.equal(blue(row([bk('started')])),true);
  assert.equal(blue(row([bk('started','Hoist','Bay 05')])),true);
  const cell=sales.pmbStatusCell(row([bk('started')]));
  assert.match(cell,/^<td class="pmb-status-cell pmb-running" data-pmb-tone="running" title="Being worked on · Work started · Fitting \/ Bay 01 · PMB/);
  assert.match(cell,/<strong>Work started · Fitting \/ Bay 01<\/strong> PMB<\/span><div class="sales-station-scroll">/);
  assert.match(cell,/pdc-station-fitting[^"]*is-started/);
  assert.match(cell,/pdc-station-fitting[\s\S]*?<span class="incoming-work-box" aria-hidden="true">!<\/span>/);
  assert.match(cell,/<\/div><\/td>$/);
});

test('blue beats planned, queued and stopped jobs on other bays (vehicle is still being worked on)',()=>{
  const mixed=row([bk('queued','Tyre'),bk('planned','Elec','Bay 08'),bk('stoppage','Fab','Bay 04'),bk('started','Fitting','Bay 01')]);
  assert.equal(blue(mixed),true);
  assert.equal(blue(row([bk('planned'),bk('started','Hoist')],{active_workshop_booking_id:'x'})),true);
  // a vehicle-level parts stoppage does not hide a job the planner shows Running
  assert.equal(blue(row([bk('started')],{pmb_stoppage_started_at:'2026-01-05T00:00:00Z'})),true);
});

test('stopped, paused, planned, queued, completed and unlinked vehicles are not blue',()=>{
  for(const bookings of [[],[bk('stoppage')],[bk('planned')],[bk('queued',undefined,undefined,{actual_start_at:'2026-01-05T01:00:00Z'})],
    [bk('completed')],[bk('deleted')],[bk('stoppage'),bk('planned')],[{status:null}]])
    assert.equal(blue(row(bookings)),false,JSON.stringify(bookings));
  assert.equal(blue(row([bk('stoppage')],{pmb_stoppage_started_at:'2026-01-05T00:00:00Z'})),false);
  assert.equal(blue(row([bk('started')],{canonical_vehicle_id:null})),false,'not linked to PMB');
  assert.equal(blue(row(null)),false);
  const cell=sales.pmbStatusCell(row([bk('stoppage')]));
  assert.match(cell,/^<td class="pmb-status-cell" title="Work stopped/);
  assert.doesNotMatch(cell,/pmb-running|data-pmb-tone/);
});

test('finished and complete states win over blue',()=>{
  assert.equal(blue(row([bk('started')],{lifecycle_state:'completed'})),false);
  assert.equal(blue(row([bk('started')],{pmb_location:' Completed '})),false);
  assert.equal(sales.pmbSummary(row([bk('started')],{lifecycle_state:'completed'})).status,'Completed · Delivered to dealer');
});

test('existing PMB Status text is unchanged; only the tone is added',()=>{
  assert.equal(sales.pmbSummary(row([bk('started')])).status,'Work started · Fitting / Bay 01');
  assert.equal(sales.pmbSummary(row([bk('planned')])).status,'Booked · Fitting / Bay 01');
  assert.equal(sales.pmbSummary(row([bk('stoppage')])).status,'Work stopped · Fitting / Bay 01');
  assert.equal(sales.pmbSummary(row([])).running,undefined);
  const v=sales.pmbStatusCell(row([bk('started')],{pmb_location:'<b>x</b>'}));
  assert.doesNotMatch(v,/<b>x<\/b>/);
});

test('table, mobile card and detail panel all use the blue tone; colours match the planner Running chip and stay readable',()=>{
  assert.match(js,/if \(key==='pmb_location'\) return pmbStatusCell\(row\);/);
  assert.match(js,/class="mobile-pmb'\+\(pmbStatusTone\(pmbSummary\(row\)\)\?' pmb-running':''\)/);
  assert.match(js,/class="pmb-current'\+\(pmbStatusTone\(summary\)\?' pmb-running':''\)/);
  assert.match(plannerCss,/\.workshop-plan-chip\.is-started \{[^}]*border-color: #2563eb;[^}]*background: #dbeafe;/);
  assert.match(css,/#vehicle-table td\.pmb-status-cell\.pmb-running,\.data-table td\.pmb-status-cell\.pmb-running\{background:#dbeafe;box-shadow:inset 3px 0 0 #2563eb;color:#1e3a8a\}/);
  assert.match(css,/\.mobile-pmb\.pmb-running\{background:#dbeafe;[^}]*color:#1e3a8a/);
  assert.match(css,/\.pmb-current\.pmb-running\{background:#dbeafe;[^}]*color:#1e3a8a/);
  const lum=h=>{const c=[1,3,5].map(i=>parseInt(h.slice(i,i+2),16)/255).map(v=>v<=0.03928?v/12.92:((v+0.055)/1.055)**2.4);return 0.2126*c[0]+0.7152*c[1]+0.0722*c[2];};
  const ratio=(a,b)=>{const [x,y]=[lum(a),lum(b)].sort((p,q)=>q-p);return (x+0.05)/(y+0.05);};
  assert.ok(ratio('#1e3a8a','#dbeafe')>=7,'AAA contrast');
});

test('Sales feed still carries each booking status from the server; cache bust on sales.js and sales.css',()=>{
  const feed=fs.readFileSync('supabase/migrations/20261021002331_r420_sales_feed_visibility.sql','utf8');
  for(const fn of ['visibility_source_snapshot','board_visibility_source_snapshot']){
    const start=feed.indexOf('FUNCTION pdc_sales_private.'+fn+'(');assert.ok(start>=0,fn);
    const body=feed.slice(start,feed.indexOf('$function$',feed.indexOf('$function$',start)+10));
    assert.match(body,/'bay_bookings',coalesce\(\(SELECT jsonb_agg\(jsonb_build_object\(\s*'stage',s\.display_name,'bay',b\.display_name,'status',w\.status/,fn);
    assert.match(body,/WHERE w\.vehicle_id=v\.id AND w\.deleted_at IS NULL/,fn);
  }
  assert.match(index,/sales\.js\?[^"]*pmb-running=2026\.10\.21\.06/);
  assert.match(index,/sales\.css\?[^"]*pmb-running=2026\.10\.21\.06/);
});
