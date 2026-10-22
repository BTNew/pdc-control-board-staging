'use strict';
// r433 (F44): every Navision location code starting with Y was in the Sales "YH / Yard Hold" tile. r474 (F87) replaces that rule
// (see test_sales_y_status_tiles_474.js); this file keeps the r433 migration / undo structure checks. Made-up stock and orders only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const sales=require('./sales/sales.js'),acc=require('./sales/sales-accessories.js');
const migration=fs.readFileSync('supabase/migrations/20261021045534_r433_y_status_yard_hold_tile.sql','utf8');
const rollback=fs.readFileSync('supabase/rollbacks/20261021045534_r433_y_status_yard_hold_tile.down.sql','utf8');
const row=(location_status,toyota_status,extra={})=>({cosi:true,salesperson_code:'BG',stock:'S1',location_status,toyota_status,...extra});

test('r433 server cases: superseded by r474 (F87); the screen follows the r474 cases, which differ only where the r474 rule says so',()=>{
  const cases=[...migration.matchAll(/\('(\{[^']*\})'(?:::jsonb)?,'([a-z]+)'\)/g)].map(m=>[JSON.parse(m[1]),m[2]]);
  assert.equal(cases.length,34);
  // r474: YN/YR wait text -> Hold/Waiting, YW ready for transport -> Released, IT Eastern States -> In Transit; everything else as r433.
  const changed=new Set(['YN|Waiting PD2','YN|Vehicle Delayed','YR|Vehicle Waiting For Wholesale','YW|Ready For Transport - From TWA','YW|Ready For Transport - From TWA','IT|In Transit To Eastern States']);
  for(const [r,want] of cases){
    const key=String(r.location_status||'').trim().toUpperCase()+'|'+(r.toyota_status||'');
    if(changed.has(key)&&r.stock==='S'&&!r.autocare_dispatched)assert.notEqual(sales.category(r),want,JSON.stringify(r));
    else assert.equal(sales.category(r),want,JSON.stringify(r));
  }
});

test('r474: only YH (or yard hold text) and unknown Y codes stay in YH / Yard Hold; YN / YR / YW follow the Toyota text',()=>{
  for(const [code,text,want] of [['YN','Waiting PD2','hold'],['YN','Vehicle Delayed','hold'],['YR','Vehicle Waiting For Wholesale','hold'],['YW','Ready For Transport - From TWA','released'],
    ['YH','Vehicle Yard Hold','yardhold'],['YH','In Transit','yardhold'],['YZ','Planned for Production','yardhold'],[' yw ','','yardhold'],['Y','','yardhold']])
    assert.equal(sales.category(row(code,text)),want,code+' '+text);
  for(const code of ['YN','YR','YW','YH','Yx'])assert.equal(sales.yardLocationCode(code),true,code);
  for(const code of ['','IT','OD','OC',null,undefined,'XY'])assert.equal(sales.yardLocationCode(code),false,String(code));
});

test('non-Y codes keep their old tiles (except r474 Eastern States); dealer, Autocare and awaiting stock still take precedence',()=>{
  assert.equal(sales.category(row('IT','In Transit To WA')),'transit');
  assert.equal(sales.category(row('','Planned for Production')),'production');
  assert.equal(sales.category(row('OD','Despatched - From TWA')),'released');
  assert.equal(sales.category(row('OD','Delivered - At Dealer')),'dealer');
  assert.equal(sales.category(row('','Waiting PD2')),'hold','a wait with no yard code is still Hold/Waiting');
  assert.equal(sales.category(row('YW','Ready For Transport - From TWA',{autocare_dispatched:true})),'autocare');
  assert.equal(sales.category(row('YN','Waiting PD2',{stock:''})),'unconfirmed');
  assert.equal(sales.category(row('YH','Delivered - At Dealer')),'dealer');
});

test('every tile Y code is at the yard for the r427 accessory delay rule (same yard family)',()=>{
  for(const code of ['YH','YN','YR','YW'])assert.equal(acc.yardHoldStageRank(code,''),2,code);
  assert.match(migration,/yard_hold_stage_rank\(j->>'location_status',j->>'toyota_status'\) rank/);
  assert.match(migration,/Y codes outside the r427 yard family/);
});

test('the migration only adds the private mirror, its pin and the check; the undo drops exactly those; staging and window guards',()=>{
  assert.match(migration,/CREATE FUNCTION pdc_sales_private\.sales_tracker_tile\(p_item jsonb\)\nRETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog/);
  assert.match(migration,/REVOKE ALL ON FUNCTION pdc_sales_private\.sales_tracker_tile\(jsonb\) FROM PUBLIC, anon, authenticated, service_role/);
  assert.doesNotMatch(migration,/CREATE OR REPLACE|ALTER |UPDATE |DELETE FROM|INSERT INTO public\.|cron\./);
  assert.equal((migration.match(/^(?:CREATE|INSERT|REVOKE)/gm)||[]).length,4,'one function, its revoke, one pin, one check');
  assert.match(migration,/'navision_y_status_maps_to_yard_hold','F44'/);assert.match(migration,/,true,231,'r433'\)/);
  for(const sql of [migration,rollback]){
    assert.match(sql,/NOT BETWEEN 2 AND 45/);assert.match(sql,/project_ref='cdsmnqxtyyoeoznmbidd'/);assert.match(sql,/pdc_production_environment_sentinel/);
    assert.doesNotMatch(sql,/vjdtsswhroyguxyfjdkt/);
  }
  assert.match(rollback,/DROP FUNCTION pdc_sales_private\.sales_tracker_tile\(jsonb\);/);
  assert.match(rollback,/DELETE FROM pdc_ops\.regression_checks WHERE check_name='navision_y_status_maps_to_yard_hold' AND added_in='r433';/);
  assert.match(rollback,/md5\(p\.prosrc\)='dea0658ecc8ec486568cc6d354a5bce2'/);
});

test('the YH / Yard Hold tile description (r474 wording) and the page still carries the r433 cache-bust tag',()=>{
  const src=fs.readFileSync('sales/sales.js','utf8');
  assert.match(src,/yardhold:'Navision YH yard hold \(and any new Y code\)'/);
  assert.match(fs.readFileSync('sales/index.html','utf8'),/sales\.js\?[^"]*y-yard-tile=2026\.10\.21\.05/);
});
