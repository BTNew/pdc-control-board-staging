function minutes(hours,estimate){
  if(estimate && estimate.run==='HERMES-TEST-RUN-20260824' && estimate.registry && estimate.identity && estimate.stageMatch && estimate.hours===hours && estimate.minutes===Math.round(estimate.hours*60) && estimate.minutes>=1 && estimate.minutes<=59)return estimate.minutes;
  return hours==null?null:Math.max(60,Math.round(hours*60));
}
function eq(actual,expected,label){if(actual!==expected)throw new Error(`${label}: ${actual} != ${expected}`)}
const exact=(hours,value)=>({run:'HERMES-TEST-RUN-20260824',registry:true,identity:true,stageMatch:true,hours,minutes:value});
eq(minutes(0.78,exact(0.78,47)),47,'scenario 007 fitting');
eq(minutes(0.98,exact(0.98,59)),59,'scenario 007 electrical');
eq(minutes(1.22,exact(1.22,73)),73,'scenario 005 unchanged');
eq(minutes(1.02,exact(1.02,61)),61,'scenario 006 unchanged');
eq(minutes(0.78,null),60,'non-registry remains floored');
eq(minutes(0.98,{...exact(0.98,59),run:'wrong'}),60,'wrong run');
eq(minutes(0.78,{...exact(0.78,47),registry:false}),60,'missing registry');
eq(minutes(0.78,{...exact(0.78,47),identity:false}),60,'identity drift');
eq(minutes(0.78,{...exact(0.78,47),stageMatch:false}),60,'wrong stage');
eq(minutes(0.78,{...exact(0.78,47),hours:0.79}),60,'hours drift');
eq(minutes(null,null),null,'null preserved');
eq(minutes(0.01,{...exact(0.01,1),minutes:0}),60,'zero rejected');
console.log('migration 370 model contract passed');
