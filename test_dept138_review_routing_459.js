/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r459 (F72): Dept 138 approval follows the reviewer's station (Craig's spec 21 Oct: "approving sends each line to its planner.
// Pit-external has no bay."). Root cause: approve_pdc_new_vehicle_review_446 used the saved routing station
// (operation_station) and accepted only Bus 4x4 / Tint / Tyre / Sublet, so a Pit Inspection line could never approve, while
// the page's Needs Review count used the category rule. Fixtures are synthetic; no live job or stock number.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const api=require('./pdc-new-vehicles.js');
const dir=n=>fs.readdirSync(n).filter(f=>/_r459_dept138_review_routing\./.test(f)).map(f=>path.join(n,f));
const [migPath]=dir('supabase/migrations'), [downPath]=dir('supabase/rollbacks');
const mig=fs.readFileSync(migPath,'utf8'), down=fs.readFileSync(downPath,'utf8');
const md5=s=>crypto.createHash('md5').update(s).digest('hex');
const body=(sql,name)=>{const i=sql.indexOf('CREATE OR REPLACE FUNCTION '+(name.includes('.')?name:'public.'+name)+'(');assert.ok(i>=0,name);const a=sql.indexOf('$f$',i)+3;return sql.slice(a,sql.indexOf('$f$',a));};
const op=(id,extra={})=>({line_identity:id,source_line_id:'s-'+id,department:'138',description:'Line '+id,stage_code:'UNALLOCATED_MAPPING_REVIEW',work_category:'UNALLOCATED_MAPPING_REVIEW',estimated_hours:1,active:true,completed:false,source_kind:'authenticated',...extra});
const card=ops=>({vehicle_id:'v1',status:'pending',snapshot_hash:'h',operations:ops});
const STATIONS=api.STATIONS_138.map(([c])=>c);

test('one file pair, one release: F72 / sort 258 / r459, staging guards, lock_timeout 2s and the :02-:45 window',()=>{
  assert.ok(migPath&&downPath);
  for(const sql of [mig,down]) {
    assert.match(sql,/lock_timeout\s*=?\s*'?2s/i);
    assert.match(sql,/NOT BETWEEN 2 AND 45/);
    assert.match(sql,/cdsmnqxtyyoeoznmbidd/);
    assert.doesNotMatch(sql,/vjdtsswhroyguxyfjdkt/);
    assert.doesNotMatch(sql,/CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/i);
    assert.doesNotMatch(sql,/\b(DELETE FROM|TRUNCATE)\s+(public\.)?pdc_(pilbara|vehicles|new_vehicle)/i);
  }
  assert.match(mig,/'F72'/); assert.match(mig,/258/); assert.match(mig,/dept138_review_routing_459/);
  assert.doesNotMatch(mig,/'F6[4-9]'|'F7[01]'/);
});

test('the server accepts exactly the page\'s 8 Dept 138 stations and maps them the same way',()=>{
  const a446=body(mig,'approve_pdc_new_vehicle_review_446');
  for(const code of STATIONS) assert.ok(a446.includes(`'${code}'`),code);
  assert.doesNotMatch(a446,/dept138_station_needs_review|dept138_sublet_needs_hours/);
  assert.match(a446,/LIKE 'BUS\\_%' THEN 'BUS_4X4'/);
  for(const code of STATIONS) assert.equal(api.routingStation138(code),code.startsWith('BUS_')?'BUS_4X4':code);
  assert.equal(api.routingStation138('BUS_PIT'),'BUS_4X4','Pit – external rides on the Bus 4x4 card; it has no bay');
  assert.equal(api.plannerStage138('BUS_PIT'),'PIT_INSPECTION');
  for(const bad of ['','FITTING','HOIST','BUS_4X4','PIT_INSPECTION','UNALLOCATED_MAPPING_REVIEW']) assert.equal(api.routingStation138(bad),'',bad);
});

test('pins equal the shipped bodies; the undo restores the exact r446 / r410 bodies and pins',()=>{
  const a446=body(mig,'approve_pdc_new_vehicle_review_446'), opst=body(mig,'pdc_bus_private.operation_station');
  assert.equal(md5(a446),'a50e6a6988ae3a106f959e3163b4121c');
  assert.equal(md5(opst),'03e96225dc36891ec0d122aecd87b967');
  assert.ok(mig.includes('a50e6a6988ae3a106f959e3163b4121c')&&mig.includes('03e96225dc36891ec0d122aecd87b967'));
  assert.equal(md5(body(down,'approve_pdc_new_vehicle_review_446')),'f4ca4be91871a1de8e8125bbb2c82021');
  assert.equal(md5(body(down,'pdc_bus_private.operation_station')),'f7ab4745fb8e97fcd58a209145cfab0f');
  assert.match(down,/operation_review_station_459_undone/);
  assert.match(opst,/operation_review_station_459/);
});

test('the routing table is private and has no foreign key (creating or dropping it never locks the operations table)',()=>{
  const ddl=mig.slice(mig.indexOf('CREATE TABLE pdc_bus_private.operation_review_station_459'));
  const table=ddl.slice(0,ddl.indexOf(');')+2);
  assert.doesNotMatch(table,/REFERENCES/i);
  assert.match(mig,/ENABLE ROW LEVEL SECURITY/i);
  assert.match(mig,/REVOKE ALL ON (TABLE )?pdc_bus_private\.operation_review_station_459 FROM PUBLIC, anon, authenticated, service_role/i);
});

test('Needs Review and the approval check use one rule, so the count and approval always agree',()=>{
  const row=card([op('a'),op('b',{work_category:'BUS_PIT',stage_code:'PIT_INSPECTION'}),op('c'),op('d')]);
  const picks={a:'BUS_MECHANICAL',b:'SUBLET',c:'BUS_ACCESSORIES'};
  const needs=api.stationGroups(row,picks).find(g=>g.code==='');
  assert.deepEqual(needs.lines.map(l=>l.line_identity),['d']);
  assert.ok(api.problems(row,picks).length);
  picks.d='BUS_MECHANICAL';
  assert.equal(api.stationGroups(row,picks).find(g=>g.code==='').lines.length,0);
  assert.deepEqual(api.problems(row,picks),[]);
  for(const combo of [{},{a:'FITTING'},{a:'BUS_PIT',b:'BUS_PIT',c:'TINT',d:'TYRE'},{a:'',b:'SUBLET',c:'BUS_QA',d:'BUS_ELECTRICAL'}]) {
    const count=api.stationGroups(row,combo).find(g=>g.code==='').lines.length;
    assert.equal(count===0,api.problems(row,combo).length===0,JSON.stringify(combo));
    assert.equal(count,row.operations.filter(l=>api.needsReview(l,combo)).length);
  }
});

test('a Pit Inspection line picked as Sublet or Pit – external is sent and verified on its planner',()=>{
  const pit=op('p',{description:'ENGINEERING CERTIFICATION / PIT INSPECTION',work_category:'UNALLOCATED_MAPPING_REVIEW',stage_code:'UNALLOCATED_MAPPING_REVIEW'});
  const row=card([pit]);
  for(const [choice,sent,planner] of [['SUBLET','SUBLET','SUBLET'],['BUS_PIT','BUS_4X4','PIT_INSPECTION']]) {
    const choices={p:choice};
    assert.deepEqual(api.problems(row,choices),[]);
    assert.equal(api.assignmentsFor(row,choices,{})[0].stage_code,sent);
    const receipt=stage=>({ok:true,data:{vehicle_id:'v1',visible_on_board:true,bookings_created:0,operations:[{...pit,stage_code:stage,work_category:choice}]}});
    assert.equal(api.verifyApproval(receipt(planner),row,choices),true);
    assert.equal(api.verifyApproval(receipt('TYRE'),row,choices),false);
  }
});

test('the page version and cache-bust tags ship r459 and pdc-auto-reload.js stays first',()=>{
  assert.match(fs.readFileSync('pdc-new-vehicles.js','utf8'),/PDC_NEW_VEHICLES_VERSION='2026\.10\.22\.r459'/);
  assert.match(fs.readFileSync('canonical-entry.js','utf8'),/pdc-new-vehicles\.js\?[^']*r459=2026\.10\.22\.r459/);
  const html=fs.readFileSync('index.html','utf8');
  assert.match(html,/canonical-entry\.js\?[^"]*r459=2026\.10\.22\.r459/);
  const scripts=[...html.matchAll(/<script[^>]*src="([^"]+)"/g)].map(m=>m[1]);
  assert.match(scripts[0],/^pdc-auto-reload\.js/);
});
