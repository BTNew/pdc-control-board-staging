'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('workshop-planner.js','utf8');
function extract(name){const m=new RegExp('(?:async )?function '+name+'\\(').exec(source);const tail=source.slice(m.index);const next=/\n(?:async )?function \w+\(/.exec(tail);return next?tail.slice(0,next.index):tail;}
function fixture(){
 const events={},classes=new Set(),data={},frames=new Map(),scrolls=[];
 let id=0,preview=null,trusted=true,match={vehicleIdentity:'shared:v',vehicleKey:'v',candidateAvailable:true,bookings:[],returnedBookings:[]};
 const button={dataset:{workshopSearchDragVehicle:'shared:v'},addEventListener:(k,v)=>events[k]=v};
 const root={isConnected:true,dataset:{},querySelectorAll:()=>[button],querySelector:()=>({classList:{add:x=>classes.add(x),remove:x=>classes.delete(x)},getBoundingClientRect:()=>({left:0,right:900,top:0,bottom:700}),scrollLeft:0}),addEventListener:(k,v)=>events['root-'+k]=v};
 const c={window:{__workshopDataService:{getTrustedSnapshot:()=>trusted?{}:null},innerHeight:700,innerWidth:900,scrollBy:(x,y)=>scrolls.push(y),requestAnimationFrame:fn=>{frames.set(++id,fn);return id;},cancelAnimationFrame:k=>frames.delete(k)},
  workshopState:()=>({search:'v',stage:'FITTING'}),workshopSearchMatches:()=>[match],workshopLoadPlans:()=>[],
  workshopVehicle:()=>({}),workshopSchedulingDuration:()=>({hours:2}),workshopSetDragPreview:p=>preview=p,
  workshopCurrentDragPreview:()=>preview,workshopClearLanePreviews:()=>{},workshopReturnedPlanForAction:id=>id==='r'?{id:'r',hours:3}:null,Date};
 vm.createContext(c);vm.runInContext(['workshopBindSearchDragResults','workshopBindDragAutoScroll'].map(extract).join('\n'),c);
 const fire=()=>{let prevented=false;events.dragstart({dataTransfer:{setData:(k,v)=>data[k]=v},preventDefault:()=>prevented=true});return prevented;};
 return {c,root,button,events,data,classes,frames,scrolls,fire,setTrusted:x=>trusted=x,setMatch:x=>match=x,getPreview:()=>preview,tick(){const callbacks=[...frames.values()];frames.clear();callbacks.forEach(fn=>fn());}};
}
test('fresh unbooked search result drags the canonical candidate; cancelled drag clears overlay',()=>{
 const f=fixture();f.c.workshopBindSearchDragResults(f.root);assert.equal(f.fire(),false);
 assert.equal(f.data['application/x-workshop-vehicle-key'],'v');assert.equal(f.getPreview().hours,2);
 assert.ok(f.classes.has('is-dragging'));f.events.dragend();assert.equal(f.getPreview(),null);assert.equal(f.classes.size,0);
});
test('returned search result reuses its reservation, never creates another',()=>{
 const f=fixture();f.button.dataset={workshopSearchDragPlan:'r'};f.c.workshopBindSearchDragResults(f.root);assert.equal(f.fire(),false);
 assert.equal(f.data['application/x-workshop-plan-id'],'r');assert.equal(f.data['application/x-workshop-vehicle-key'],undefined);
});
test('stale authority, blocked, archived, failed and already-booked results cannot drag',()=>{
 for(const patch of [{candidateAvailable:false},{archived:true},{bookingLookupError:'denied'},{bookings:[{id:'booked'}]},{returnedBookings:[{id:'r'}]}]){
  const f=fixture();f.setMatch({vehicleIdentity:'shared:v',candidateAvailable:true,bookings:[],...patch});f.c.workshopBindSearchDragResults(f.root);
  assert.equal(f.fire(),true);assert.deepEqual(f.data,{});
 }
 const f=fixture();f.c.workshopBindSearchDragResults(f.root);f.setTrusted(false);assert.equal(f.fire(),true);
});
test('edge scrolling follows drag, stops on drop, and has one listener per root',()=>{
 const f=fixture();f.c.workshopBindSearchDragResults(f.root);f.fire();f.c.workshopBindDragAutoScroll(f.root);
 const handler=f.events['root-dragover'];f.c.workshopBindDragAutoScroll(f.root);assert.equal(f.events['root-dragover'],handler);
 handler({clientX:200,clientY:690});f.tick();assert.ok(f.scrolls[0]>0);assert.equal(f.frames.size,1);
 f.events['root-drop']();assert.equal(f.frames.size,0);assert.equal(f.classes.size,0);
 handler({clientX:200,clientY:5});f.tick();assert.ok(f.scrolls.at(-1)<0);
 f.root.isConnected=false;f.tick();assert.equal(f.frames.size,0);
});
test('both search action types expose native drag handles',()=>{
 const html=extract('workshopSearchResultsHtml');
 assert.match(html,/draggable="true" data-workshop-search-drag-plan/);
 assert.match(html,/draggable="true" data-workshop-search-drag-vehicle/);
});
