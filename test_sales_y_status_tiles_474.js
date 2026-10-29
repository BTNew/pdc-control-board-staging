/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r474 (F87): Sales tracker tiles (Bryce Guthrie, 22 Oct). Only YH (or "yard hold" text) and unknown Y codes are YH / Yard Hold;
// YN / YR / YW follow the Toyota text (YW Ready For Transport = Released; YN Waiting PD1 / PD2 / Vehicle Delayed and YR Waiting For
// Wholesale = Hold/Waiting); In Transit To Eastern States = In Transit. Yard Hold sits right of Hold/Waiting. Made-up data only.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),cp=require('node:child_process');
const sales=require('./sales/sales.js'),acc=require('./sales/sales-accessories.js');
const MIG='supabase/migrations/20261022030000_r474_sales_y_status_tiles.sql',DOWN='supabase/rollbacks/20261022030000_r474_sales_y_status_tiles.down.sql';
const migration=fs.readFileSync(MIG,'utf8'),rollback=fs.readFileSync(DOWN,'utf8');
const r433=fs.readFileSync('supabase/migrations/20261021045534_r433_y_status_yard_hold_tile.sql','utf8');
const statuses=JSON.parse(fs.readFileSync('qa/sales-y-status-tiles-474-statuses.json','utf8')).cases;
const row=(location_status,toyota_status,extra={})=>({cosi:true,salesperson_code:'BG',stock:'S1',location_status,toyota_status,...extra});
const fnBody=sql=>sql.match(/CREATE OR REPLACE FUNCTION pdc_sales_private\.sales_tracker_tile\(p_item jsonb\)\nRETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS \$f\$([\s\S]*?)\$f\$;/)[1];
const md5=s=>require('node:crypto').createHash('md5').update(s).digest('hex');

test('Bryce\'s four rules on the screen',()=>{
  assert.equal(sales.category(row('IT','In Transit To Eastern States')),'transit','1. Eastern States is In Transit, not Production');
  assert.equal(sales.category(row('YW','Ready For Transport - From TWA')),'released','2. YW ready for transport is Released');
  for(const [code,text] of [['YN','Waiting PD1'],['YN','Waiting PD2'],['YN','Vehicle Delayed'],['YR','Vehicle Waiting For Wholesale']])
    assert.equal(sales.category(row(code,text)),'hold','3. '+code+' '+text+' is Hold/Waiting');
  assert.equal(sales.category(row('YH','Vehicle In Yard Hold')),'yardhold','4. YH stays');
  assert.equal(sales.category(row('','Vehicle In Yard Hold')),'yardhold','4. yard hold text stays');
  assert.equal(sales.category(row('YH','Waiting PD2')),'yardhold','4. YH wins over wait text');
  for(const code of ['YX','YZ','Y',' yq '])assert.equal(sales.category(row(code,'Waiting PD2')),'yardhold','4. unknown Y code '+code+' defaults to Yard Hold');
  assert.equal(sales.category(row('YN','')),'yardhold','YN with no recognised text defaults to Yard Hold');
  assert.equal(sales.category(row('YW','Some New Toyota Status')),'yardhold');
  assert.equal(sales.category(row('',"In Transit To O/S Wharf")),'production','overseas wharf is still Production');
});

test('dealer, Autocare dispatched and awaiting stock keep precedence over every Y rule',()=>{
  for(const [code,text] of [['YN','Waiting PD2'],['YW','Ready For Transport - From TWA'],['YH','Vehicle In Yard Hold'],['IT','In Transit To Eastern States']]){
    assert.equal(sales.category(row(code,text,{autocare_dispatched:true})),'autocare');
    assert.equal(sales.category(row(code,text,{stock:''})),'unconfirmed');assert.equal(sales.category(row(code,text,{stock:'TBA'})),'unconfirmed');
    assert.equal(sales.category(row(code,'Delivered - At Dealer')),'dealer');
  }
});

test('the screen matches every r474 server regression-check case (49)',()=>{
  const cases=[...migration.matchAll(/\('(\{[^']*\})'(?:::jsonb)?,'([a-z]+)'\)/g)].map(m=>[JSON.parse(m[1]),m[2]]);
  assert.equal(cases.length,49);
  for(const [r,want] of cases)assert.equal(sales.category(r),want,JSON.stringify(r));
});

test('the screen gives the pinned tile for every item of the shared JS/SQL status list',()=>{
  assert.equal(statuses.length,608);
  for(const {j,want} of statuses)assert.equal(sales.category(j),want,JSON.stringify(j));
  const tiles=new Set(statuses.map(c=>c.want));
  for(const t of ['dealer','autocare','unconfirmed','yardhold','hold','released','production','transit','unknown'])assert.ok(tiles.has(t),t);
  assert.doesNotMatch(JSON.stringify(statuses),/"stock":"1\d{7}"/,'no real stock numbers');
});

function localPg(){try{cp.execSync("sudo -n -u postgres psql -Atc 'select 1'",{stdio:'pipe',timeout:5000});return true;}catch{return false;}}
test('JS and SQL agree on the same status list (local PostgreSQL harness: r433 -> r474 -> undo byte for byte)',{skip:!localPg()&&'no local PostgreSQL on this machine (run tests/r474_local_harness/run.sh where there is one)'},()=>{
  const out=cp.execSync('bash tests/r474_local_harness/run.sh',{encoding:'utf8',timeout:180000,stdio:['ignore','pipe','pipe']});
  assert.match(out,/r474 function vs sales\.js on the status list: 608 0/);
  assert.match(out,/r474 local harness: PASS/);
});

test('migration: md5-guarded replace of the mirror only, pin moved (count unchanged), r433 check updated; window, staging and lock guards',()=>{
  assert.equal(md5(fnBody(migration)),'8db0c1c1d2b8b62a55e27384df84d41a');
  assert.match(migration,/md5\(p\.prosrc\)='dea0658ecc8ec486568cc6d354a5bce2'/,'refuses unless the live function is the r433 version');
  assert.match(migration,/UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5='8db0c1c1d2b8b62a55e27384df84d41a',release='r474'/);
  assert.match(migration,/WHERE check_name='navision_y_status_maps_to_yard_hold' AND added_in='r433' AND md5\(check_sql\)='13a9f786621910cc3ea3f64a9ce3f5bc';/);
  assert.match(migration,/md5\(check_sql\)='b9beff4c9a45984f3a593f2efe7d9a77' AND fault_id='F87'/);
  const chk=migration.match(/check_sql=\$chk\$([\s\S]*?)\$chk\$/)[1];assert.equal(md5(chk),'b9beff4c9a45984f3a593f2efe7d9a77');
  assert.doesNotMatch(migration,/yard_hold_stage_rank\(p_|CREATE OR REPLACE FUNCTION pdc_sales_private\.yard_hold_stage_rank|DELETE FROM|INSERT INTO|DROP |workshop_bookings|vehicles SET|cron\./);
  assert.equal((migration.match(/^(?:CREATE|UPDATE|INSERT|DELETE|DROP|ALTER|GRANT|REVOKE)/gm)||[]).length,3,'one function, one pin update, one check update');
  for(const sql of [migration,rollback]){
    assert.match(sql,/SET LOCAL lock_timeout = '2s';/);assert.match(sql,/NOT BETWEEN 2 AND 45/);
    assert.match(sql,/project_ref='cdsmnqxtyyoeoznmbidd'/);assert.match(sql,/pdc_production_environment_sentinel/);assert.doesNotMatch(sql,/vjdtsswhroyguxyfjdkt/);
    assert.match(sql,/yard_hold_stage_rank\(text,text\)'::regprocedure\)<>'a441a598a1a6477e36d0a73ad7c5d354'/,'r427 rank must be unchanged');
    assert.match(sql,/workshop_clock_tick\(boolean,timestamptz\)'::regprocedure\) IS DISTINCT FROM \(SELECT prosrc_md5 FROM pdc_ops\.expected_function_md5/);
  }
});

test('undo restores the r433 function, pin and check byte for byte',()=>{
  assert.equal(fnBody(rollback),r433.match(/AS \$f\$([\s\S]*?)\$f\$;/)[1]);
  assert.equal(md5(fnBody(rollback)),'dea0658ecc8ec486568cc6d354a5bce2');
  assert.equal(rollback.match(/check_sql=\$chk\$([\s\S]*?)\$chk\$/)[1],r433.match(/\$chk\$([\s\S]*?)\$chk\$/)[1]);
  assert.match(rollback,/SET prosrc_md5='dea0658ecc8ec486568cc6d354a5bce2',release='r433',note='r433 \(F44\): server mirror of the Sales tracker tile rule; Y location codes are Yard Hold',updated_at='2026-10-21 04:55:34.280817\+00'/);
  assert.match(rollback,/SET fault_id='F44',/);assert.match(rollback,/md5\(p\.prosrc\)='8db0c1c1d2b8b62a55e27384df84d41a'/);
});

test('r427 / r418 accessory yard-hold delay unchanged: every Y code is still at the yard for the delay rule',()=>{
  for(const code of ['YH','YN','YR','YW'])assert.equal(acc.yardHoldStageRank(code,''),2,code);
  assert.equal(acc.yardHoldStageRank('IT','In Transit To Eastern States'),1);
});

test('tile row: Yard Hold sits immediately right of Hold/Waiting; descriptions; cache-bust',()=>{
  const keys=sales.categories.map(c=>c[0]);
  assert.deepEqual(keys,['all','unconfirmed','production','transit','hold','yardhold','pmb','released','autocare','dealer','unknown']); // r737: At PMB between Yard Hold and Released
  assert.equal(keys.indexOf('yardhold'),keys.indexOf('hold')+1);
  const src=fs.readFileSync('sales/sales.js','utf8');
  assert.match(src,/yardhold:'Navision YH yard hold \(and any new Y code\)'/);
  assert.match(src,/hold:'Waiting PD1 \/ PD2, delayed and waiting for wholesale'/);
  assert.match(src,/transit:'Shipment, WA and Eastern States transit, wharf'/);
  assert.match(src,/released:'Body builder, TWA despatch and ready for transport'/);
  assert.match(fs.readFileSync('sales/index.html','utf8'),/sales\.js\?[^"]*&amp;y-status-tiles=2026\.10\.22\.r474&amp;/);
});

test('rendered Sales page: tile order and counts follow the new rule',async()=>{
  const elements=new Map(),calls=[];
  function el(id){if(!elements.has(id))elements.set(id,{innerHTML:'',textContent:'',hidden:false,disabled:false,value:'',closed:true,dataset:{},classList:{toggle(){}},
    setAttribute(){},removeAttribute(){},events:{},addEventListener(n,f){this.events[n]=f;},close(){},showModal(){},scrollIntoView(){},focus(){}});return elements.get(id);}
  const nav=['dashboard','pipeline','labels','finance'].map(v=>{const e=el('nav-'+v);e.dataset.salesView=v;return e;});
  const window={document:{hidden:false,getElementById:el,querySelectorAll:()=>nav,addEventListener(){}},BROOME_ZEBRA_LABELS:require('./sales/zebra-labels.js'),
    PDC_AUTH_CONTEXT:{role:'administrator',userId:'admin-example'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}},addEventListener(){},setInterval(){}};
  vm.runInNewContext(fs.readFileSync('sales/sales.js','utf8'),{window,globalThis:window,module:undefined,Set,Map,Date,console});
  const mk=(i,location_status,toyota_status)=>({tracking_id:'t'+i,stock:'EX'+i,order:'O'+i,salesperson_code:'BG',cosi:true,location_status,toyota_status,client:'Example',vehicle:'Example'});
  const items=[mk(1,'YH','Vehicle In Yard Hold'),mk(2,'YN','Waiting PD2'),mk(3,'YN','Waiting PD1'),mk(4,'YN','Vehicle Delayed'),mk(5,'YR','Vehicle Waiting For Wholesale'),
    mk(6,'YW','Ready For Transport - From TWA'),mk(7,'IT','In Transit To Eastern States'),mk(8,'','Planned for Production'),mk(9,'YQ','Waiting PD2')];
  calls.at(-1).resolve({data:{context:{role:'administrator',display_name:'Administrator example'},items}});await new Promise(r=>setImmediate(r));
  const html=el('status-tabs').innerHTML;
  const order=[...html.matchAll(/data-category="([a-z]+)"/g)].map(m=>m[1]);
  assert.equal(order.indexOf('yardhold'),order.indexOf('hold')+1);
  const count=k=>Number(html.match(new RegExp('data-category="'+k+'"[^>]*>[\\s\\S]*?<strong>(\\d+)</strong>'))[1]);
  assert.equal(count('yardhold'),2);assert.equal(count('hold'),4);assert.equal(count('released'),1);assert.equal(count('transit'),1);assert.equal(count('production'),1);
});
