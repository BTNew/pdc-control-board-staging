'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.resolve(process.env.PDC_RUNTIME_DIR||process.cwd(),'app.js'),'utf8');
function fn(name){const start=source.indexOf(`function ${name}(`);assert(start>=0,`${name} exists`);const rest=source.slice(start+1),next=rest.search(/\n(?:async )?function /);assert(next>=0,`${name} boundary exists`);return source.slice(start,start+1+next);}
function timing(){
  const context={Date,parseIsoTimestamp:value=>{if(!value)return null;const date=value instanceof Date?value:new Date(value);return Number.isFinite(date.getTime())?date:null;}};
  vm.createContext(context);
  for(const name of ['lifecycleHistoryForVehicle','lifecycleTimestamp','completedPmbStartDate','completedRftDate','completedPmbDays','lifecycleDurationDays','lifecycleDurationLabel','completedPmbDaysLabel','completedPmbStatisticsFromDays','completedPmbStatistics','shortDateAu'])vm.runInContext(fn(name),context);
  return context;
}
const interval={firstEnteredPmbAt:'2026-09-01T00:00:00Z',firstBecameRftAt:'2026-09-04T00:00:00Z'};
test('missing duration stays unknown instead of becoming a zero-day turnaround',()=>{
  const c=timing();
  for(const value of [undefined,null,'',' ',NaN,Infinity,-1,'invalid',false,true]){
    const vehicle={lifecycleHistory:{elapsedPmbToRftDays:value}};
    assert.equal(c.completedPmbDays(vehicle),null,`PMB days ${String(value)}`);
    assert.equal(c.lifecycleDurationDays(vehicle,'elapsedPmbToRft'),null,`duration ${String(value)}`);
    assert.equal(c.completedPmbDaysLabel(vehicle),'Unknown');
    assert.equal(c.lifecycleDurationLabel(vehicle,'elapsedPmbToRft'),'Unknown');
  }
});
test('null days use actual PMB and RFT dates, while an explicit zero remains valid',()=>{
  const c=timing();
  assert.equal(c.completedPmbDays({lifecycleHistory:{...interval,elapsedPmbToRftDays:null}}),3);
  assert.equal(c.lifecycleDurationDays({lifecycleHistory:{...interval,elapsedPmbToRftDays:null}},'elapsedPmbToRft'),3);
  for(const value of [0,'0']){
    const vehicle={lifecycleHistory:{elapsedPmbToRftDays:value,elapsedPmbToRftSeconds:0}};
    assert.equal(c.completedPmbDays(vehicle),0);assert.equal(c.lifecycleDurationDays(vehicle,'elapsedPmbToRft'),0);assert.equal(c.completedPmbDaysLabel(vehicle),'Same day');
  }
});
test('invalid, partial and reversed dates never invent a zero-day interval',()=>{
  const c=timing();
  for(const history of [{firstEnteredPmbAt:interval.firstEnteredPmbAt},{firstBecameRftAt:interval.firstBecameRftAt},{firstEnteredPmbAt:'invalid',firstBecameRftAt:interval.firstBecameRftAt},{firstEnteredPmbAt:interval.firstBecameRftAt,firstBecameRftAt:interval.firstEnteredPmbAt}]){
    assert.equal(c.completedPmbDays({lifecycleHistory:history}),null);assert.equal(c.lifecycleDurationDays({lifecycleHistory:history},'elapsedPmbToRft'),null);
  }
});
test('known duration without recorded seconds uses calculated seconds in its label',()=>{
  const c=timing();for(const value of [undefined,null,'',' ']){
    const label=c.lifecycleDurationLabel({lifecycleHistory:{...interval,elapsedPmbToRftDays:null,elapsedPmbToRftSeconds:value}},'elapsedPmbToRft');
    assert.match(label,/3 days/);assert.match(label,/259200 seconds/);assert.doesNotMatch(label,/null|undefined|\( seconds\)/);
  }
});
test('statistics exclude unknown intervals but retain legitimate zero durations',()=>{
  const c=timing();const vehicles=[{lifecycleHistory:{elapsedPmbToRftDays:0}},{lifecycleHistory:{...interval,elapsedPmbToRftDays:null}},{lifecycleHistory:{elapsedPmbToRftDays:null}},{lifecycleHistory:{elapsedPmbToRftDays:-1}}];
  const result=c.completedPmbStatistics(vehicles);assert.equal(result.total,4);assert.equal(result.known,2);assert.equal(result.unknown,2);assert.equal(result.average,1.5);assert.equal(result.median,1.5);assert.equal(result.fastest,0);assert.equal(result.longest,3);
});
test('short dates accept supplied date strings and Date objects without throwing',()=>{
  const c=timing();for(const value of ['2026-09-04','2026-09-04T00:00:00Z',new Date('2026-09-04T00:00:00Z')])assert.equal(c.shortDateAu(value),'04/09/2026');
  for(const value of [null,undefined,'','invalid',new Date(NaN)])assert.equal(c.shortDateAu(value),'');
});
