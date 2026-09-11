const test=require('node:test'),assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
const intake=require('./pdc-sublet-intake');
const source=fs.readFileSync('app.js','utf8');
const operations=['Signage','Window tint','Rust protection'].map((description,i)=>({lineIdentity:`source:00000000-0000-4000-8000-00000000000${i}`,description,stageCode:'SUBLET',active:true,completed:false,jobCardNumber:'TEST'}));
function vehicle(bookings=[]){return {id:'fixture',__emailVehicleServerAuthoritative:true,pdcQcOperationLinesProjectionPresent:true,pdcQcOperationLines:operations,pdcSubletBookings:bookings};}
function rows(v){const ctx={window:{PDC_SUBLET_INTAKE:intake},PDC_JOB_DEFS:[{key:'sublet'}],pdcJobRequired:()=>true,pdcJobComplete:()=>false,vehicleLocationBoardRows:()=>[v],vehicleKey:v=>v.id,pmbBaySubletProvider:v=>v.pmbSubletProvider,inferredPmbStage:()=> 'SUBLET'};vm.createContext(ctx);vm.runInContext(source.slice(source.indexOf('function subletRows()'),source.indexOf('function subletDateOrdinal')),ctx);return ctx.subletRows();}
test('three requirements become three independent to-book rows with one description each',()=>{
 const result=rows(vehicle());assert.equal(result.length,3);assert.equal(new Set(result.map(r=>r.__subletOperationKey)).size,3);
 result.forEach((r,i)=>{assert.equal(r.__subletOperationDescription,operations[i].description);assert.equal(r.pmbSubletNotes,'JC TEST · '+operations[i].description);assert.equal(r.pmbSubletBookingDate,'');});
});
test('booking or returning one requirement leaves the other two pending; cancellation makes it available again',()=>{
 for(const status of ['active','returned','cancelled']){
  const v=vehicle([{bookingId:'b',operationLineIdentity:operations[0].lineIdentity,status,outDate:'2026-09-12'}]);
  assert.equal(intake.pending(v).length,status==='cancelled'?3:2);
  assert.equal(rows(v).filter(r=>r.__subletOperationKey).length,status==='cancelled'?3:2);
 }
});
test('historical unlinked bookings do not claim unrelated operations',()=>{
 const v=vehicle([{bookingId:'legacy',status:'active'}]);assert.equal(rows(v).length,4);
 assert.equal(intake.detailsHtml({...v,__subletBookingId:'legacy'}),'');
 assert.equal(intake.notes(v,operations[1].lineIdentity),'JC TEST · Window tint');
});
test('service sends stable requirement identity to the independent booking RPC',async()=>{
 let request;const {createPdcEmailVehicleLocationService}=require('./pdc-email-vehicle-location-service');
 const service=createPdcEmailVehicleLocationService({config:{url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'test'},getAccessToken:()=> 'fixture',fetchImpl:async(url,options)=>{request={url,body:JSON.parse(options.body)};return {ok:true,status:200,json:async()=>({ok:true})};}});
 await service.createSubletBooking('vehicle',1,'provider','2026-09-12','2026-09-13','','Tint',operations[1].lineIdentity);
 assert(request.url.endsWith('/rpc/create_pdc_sublet_operation_booking'));assert.equal(request.body.p_operation_line_identity,operations[1].lineIdentity);
});
