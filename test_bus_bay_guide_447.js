/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r447 (F60, Bhavesh 21 Oct 18:19, approved by Craig): Dept 138 bay work-type guide.
// Bays 1-4 Mechanical and Accessories, 5-6 overflow (any Bus work), 7 QA, 8-10 Electrical and
// Accessories, all with no warning; anything else asks to confirm (r417). Best slot and Book all
// use only a category's own bays, never the overflow. Mirrors pdc_work_categories_private
// preferred_bay / allowed_bay (check bus_bay_guide_447).
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const departments=require('./pdc-workshop-departments.js');
const slice=(file,from,to)=>{const s=fs.readFileSync(file,'utf8');const a=s.indexOf(from),b=s.indexOf(to,a+1);assert.ok(a>=0&&b>a,from);return s.slice(a,b);};
const GRID={BUS_MECHANICAL:{own:[1,2,3,4],free:[1,2,3,4,5,6]},BUS_ACCESSORIES:{own:[1,2,3,4,8,9,10],free:[1,2,3,4,5,6,8,9,10]},
  BUS_ELECTRICAL:{own:[8,9,10],free:[5,6,8,9,10]},BUS_QA:{own:[7],free:[5,6,7]}};

test('the 4 x 10 grid matches the bay guide (same cells as the database check)',()=>{
  for(const [code,{own,free}] of Object.entries(GRID)){
    assert.deepEqual(departments.preferredBays(code),own,code+' own');
    assert.deepEqual(departments.allowedBays(code),free,code+' free');
    for(const bay of [5,6]) assert.ok(departments.allowedBays(code).includes(bay)&&!departments.preferredBays(code).includes(bay),code+' overflow '+bay);
  }
  assert.ok(!departments.allowedBays('BUS_MECHANICAL').includes(9)&&!departments.allowedBays('BUS_MECHANICAL').includes(10),'Mechanical in 9-10 now asks to confirm');
  assert.ok(!departments.allowedBays('BUS_ELECTRICAL').includes(1),'Electrical in 1-4 asks to confirm');
  assert.ok(!departments.allowedBays('BUS_QA').includes(8),'QA outside 5-7 asks to confirm');
  assert.deepEqual(departments.preferredBays('BUS_PIT'),[]);assert.equal(departments.preferredBays('NOPE'),null);
  // planner views (tabs) are unchanged
  assert.deepEqual(departments.BUS_GROUPS.map(g=>g.bays.join(',')),['1,2,3,4','5,6','7','8,9','10']);
});

test('own bays first in the schedule list; Best slot uses own bays only',()=>{
  const c={window:{},workshopSelectedBusGroup:()=>null,workshopStageBayCount:()=>10,workshopDepartmentLayout:()=>departments};
  vm.createContext(c);
  vm.runInContext(slice('workshop-planner.js','function workshopCategoryBays(','function workshopBayChoiceLabel('),c);
  assert.deepEqual([...c.workshopCategoryBays('BUS_4X4','BUS_ACCESSORIES')],[1,2,3,4,8,9,10,5,6]);
  assert.deepEqual([...c.workshopCategoryOwnBays('BUS_4X4','BUS_ACCESSORIES')],[1,2,3,4,8,9,10]);
  assert.deepEqual([...c.workshopCategoryOwnBays('BUS_4X4','BUS_ELECTRICAL')],[8,9,10]);
  assert.deepEqual([...c.workshopCategoryOwnBays('BUS_4X4','BUS_QA')],[7]);
  assert.equal(c.workshopCategoryOwnBays('BUS_4X4','').length,10);
  assert.deepEqual([...c.workshopCategoryOwnBays('FITTING','BUS_QA')].length,10);
  // a selected planner view still limits the list
  c.workshopSelectedBusGroup=()=>({bays:[5,6]});
  assert.deepEqual([...c.workshopCategoryBays('BUS_4X4','BUS_MECHANICAL')],[5,6]);
  assert.deepEqual([...c.workshopCategoryOwnBays('BUS_4X4','BUS_MECHANICAL')],[]);
  const planner=fs.readFileSync('workshop-planner.js','utf8');
  assert.match(planner,/const bay = categoryBays\.find\(number => schedulableBays\.includes\(number\)/);
});

test('the refusal text names the new guide and the confirm route',()=>{
  const planner=fs.readFileSync('workshop-planner.js','utf8');
  const line=planner.split('\n').find(l=>l.includes("error === 'category_bay_mismatch'"));
  assert.match(line,/Bays 1–4 take Mechanical and Accessories/);assert.match(line,/Bays 5–6 take any work/);
  assert.match(line,/Bay 7 takes QA/);assert.match(line,/Bays 8–10 take Electrical and Accessories/);assert.match(line,/override is logged/);
  assert.doesNotMatch(line,/9 or 10/);
});

test('migration, undo and rolled-back test are in the repo and consistent',()=>{
  const mig=fs.readdirSync('supabase/migrations').find(f=>/_r447_dept138_bay_guide\.sql$/.test(f));
  assert.ok(mig,'r447 migration');
  const up=fs.readFileSync('supabase/migrations/'+mig,'utf8'),down=fs.readFileSync('supabase/rollbacks/'+mig.replace('.sql','.down.sql'),'utf8');
  assert.match(up,/WHEN 'BUS_ACCESSORIES' THEN bay IN\(1,2,3,4,8,9,10\) WHEN 'BUS_ELECTRICAL' THEN bay IN\(8,9,10\)/);
  assert.match(up,/bay IN \(5,6\) AND category IN \('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES','BUS_QA'\)/);
  assert.match(up,/r447_grandfathered/);assert.match(up,/'bus_bay_guide_447','F60'/);assert.match(up,/SET LOCAL lock_timeout = '2s'/);
  assert.match(down,/OR \(bay IN \(9,10\) AND category IN \('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES'\)\)/);
  assert.match(down,/r447_undo_kept/);assert.match(down,/9a785c3f4301213c4dae78e3717611ee/);assert.match(down,/a9e529f8e2153924fd8a5d323084f1c1/);
  assert.ok(fs.existsSync('tests/bay_guide_447_rollback.sql'));
});
