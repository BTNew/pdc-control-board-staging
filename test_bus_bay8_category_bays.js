'use strict';
// r399: Bay 8 refused a Mechanical card in the all-bays view and showed a raw
// database code. These checks keep the bay list, error mapping and the
// "done before the board" control in line with the database rules.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const departments=require('./pdc-workshop-departments.js');
const slice=(file,from,to)=>{const s=fs.readFileSync(file,'utf8');const a=s.indexOf(from),b=s.indexOf(to,a+1);assert.ok(a>=0&&b>a,from);return s.slice(a,b);};

test('each Bus 4x4 category lists the bays the database accepts',()=>{
  const want={BUS_MECHANICAL:[1,2,3,4,9,10],BUS_ELECTRICAL:[8,9,10],BUS_ACCESSORIES:[9,10],BUS_QA:[7],BUS_PIT:[]};
  for(const [code,bays] of Object.entries(want)) assert.deepEqual(departments.allowedBays(code),bays,code);
  assert.equal(departments.allowedBays('NOPE'),null);
  assert.deepEqual([...departments.category('BUS_ELECTRICAL').bays],[8,9]);
  assert.ok(departments.allowedBays('BUS_ELECTRICAL').includes(8)&&!departments.allowedBays('BUS_MECHANICAL').includes(8));
});

test('all-bays booking choices are filtered by the card category',()=>{
  const c={window:{},workshopSelectedBusGroup:()=>null,workshopStageBayCount:()=>10,workshopDepartmentLayout:()=>departments};
  vm.createContext(c);
  vm.runInContext(slice('workshop-planner.js','function workshopCategoryBays(','function workshopBayChoiceLabel('),c);
  assert.deepEqual([...c.workshopCategoryBays('BUS_4X4','BUS_MECHANICAL')],[1,2,3,4,9,10]);
  assert.deepEqual([...c.workshopCategoryBays('BUS_4X4','BUS_ELECTRICAL')],[8,9,10]);
  assert.deepEqual([...c.workshopCategoryBays('BUS_4X4','BUS_QA')],[7]);
  assert.equal(c.workshopCategoryBays('BUS_4X4','').length,10);
  const planner=fs.readFileSync('workshop-planner.js','utf8');
  assert.match(planner,/const bayOptions = categoryBays\.map/);
  assert.match(planner,/const slotBays = workshopCategoryBays\(normalizedStage, slotCategory\)/);
});

test('a bare category_bay_mismatch error is recognised, not shown raw',()=>{
  const c={};vm.createContext(c);
  vm.runInContext(slice('workshop-data-service.js','const WORKSHOP_CANONICAL_MUTATION_ERRORS','// Display only')+';this.f=workshopCanonicalMutationError;',c);
  assert.equal(c.f({code:'22023',error:'22023',message:'category_bay_mismatch'}),'category_bay_mismatch');
  assert.equal(c.f({message:'{"error":"bay_overlap"}'}),'bay_overlap');
  assert.equal(c.f({message:'something else'}),'');
  const planner=fs.readFileSync('workshop-planner.js','utf8');
  const line=planner.split('\n').find(l=>l.includes("error === 'category_bay_mismatch'"));
  assert.match(line,/Electrical in Bays 8–10/);assert.match(line,/Work tab/);
});

test('done-before-the-board control: categories, guards and RPCs',()=>{
  const c={app:{vehicleWorkshopDetailCache:new Map([['v1',{detail:{vehicle_version:7,work_categories:[{work_category:'BUS_ELECTRICAL',offboard_confirmed:true}]}}]])},
    vehicleWorkshopCanEditLines:()=>true,vehicleWorkshopDetailCanonicalId:()=> 'v1',escapeHtml:s=>String(s)};
  vm.createContext(c);
  vm.runInContext(slice('app.js','const VEHICLE_WORKSHOP_OFFBOARD_CATEGORIES','async function vehicleWorkshopOffboardCall('),c);
  const h=(g,complete=false,whole=null)=>c.vehicleWorkshopOffboardHtml({bookings:[],...g},{},complete,whole);
  assert.match(h({category:'BUS_MECHANICAL',label:'Mechanical'}),/data-vehicle-workshop-offboard-done[^>]*data-category="BUS_MECHANICAL" data-vehicle-version="7"/);
  assert.equal(h({category:'BUS_QA'}),'');
  assert.equal(h({category:'BUS_MECHANICAL'},true),'');
  assert.equal(h({category:'BUS_MECHANICAL'},false,{booking_id:'x'}),'');
  assert.equal(h({category:'BUS_MECHANICAL',bookings:[{work_category:'BUS_MECHANICAL',actual_start_at:'2026-10-20',status:'planned'}]}),'');
  assert.match(h({category:'BUS_ELECTRICAL'}),/data-vehicle-workshop-offboard-undo/);
  c.vehicleWorkshopCanEditLines=()=>false;assert.equal(h({category:'BUS_MECHANICAL'}),'');
  const app=fs.readFileSync('app.js','utf8');
  assert.match(app,/rpc\/\$\{undo \? 'undo_bus_category_done' : 'confirm_bus_category_done'\}/);
  assert.match(app,/\[data-vehicle-workshop-offboard-done\]/);
});
