'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'pdc-sublet-intake.js'),'utf8');

function fixture(vehicles){
  const state={projections:0,legacyLookups:0,rows:[],bookings:[]};
  const rows=vehicles.map(vehicle=>({querySelector(selector){
    if(selector==='[data-sublet-toggle]')return {dataset:{subletToggle:vehicle.__subletBookingId||vehicle.__subletOperationKey||vehicle.id}};
    if(selector==='.sublet-work-required')return {insertAdjacentHTML(_where,html){state.rows.push(html);}};
    return null;
  },querySelectorAll:()=>[]}));
  const ctx={renderSubletHome:()=> 'rendered',document:{getElementById:()=>({querySelectorAll:()=>rows})},
    subletRows:()=>{state.projections++;return vehicles.map(vehicle=>({...vehicle}));},vehicleKey:vehicle=>vehicle.id,
    subletVehicleByKey:key=>{state.legacyLookups++;return ctx.subletRows().find(vehicle=>[vehicle.id,vehicle.__subletBookingId,vehicle.__subletOperationKey].includes(key));},
    detailsHtml:vehicle=>vehicle.description};
  vm.createContext(ctx);vm.runInContext(source.slice(source.indexOf('  const oldRender=renderSubletHome;'),source.indexOf("  if(app.currentView==='sublet')")),ctx);
  return {ctx,state};
}

test('Sublet decorates 1000 requirement rows with one projection instead of rebuilding the queue for every row',()=>{
  const vehicles=Array.from({length:1000},(_,i)=>({id:`vehicle-${Math.floor(i/4)}`,__subletOperationKey:`operation-${i}`,description:`Required work ${i}`}));
  const f=fixture(vehicles);assert.equal(f.ctx.renderSubletHome(),'rendered');
  assert.equal(f.state.projections,1);assert.equal(f.state.legacyLookups,0);assert.deepEqual(f.state.rows,vehicles.map(v=>v.description));
});

test('one Sublet render retains distinct pending, booked, returned and legacy row identities',()=>{
  const vehicles=[{id:'same-vehicle',__subletOperationKey:'pending1',description:'Window tint'},{id:'same-vehicle',__subletOperationKey:'pending2',description:'Seat covers'},
    {id:'same-vehicle',__subletBookingId:'booked1',description:'Canopy'},{id:'same-vehicle',__subletBookingId:'returned1',description:'Returned signage'},
    {id:'legacy-vehicle',description:'Legacy provider work'}];
  const before=JSON.stringify(vehicles),f=fixture(vehicles);f.ctx.renderSubletHome();
  assert.deepEqual(f.state.rows,vehicles.map(v=>v.description));assert.equal(JSON.stringify(vehicles),before);
});
