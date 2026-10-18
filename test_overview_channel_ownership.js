'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('app.js','utf8');
test('Control Board and planner own independent all-station subscriptions',()=>{
 const channels=new Map(),events=[];
 const client={channel(name){
   if(channels.has(name))return channels.get(name);
   const c={name,on(){return c;},subscribe(fn){assert.ok(!c.callback,'channel already subscribed');c.callback=fn;fn('SUBSCRIBED');return c;}};
   channels.set(name,c);return c;
 },removeChannel(c){channels.delete(c.name);c.callback('CLOSED');}};
 const context={window:{PDC_SUPABASE:client}};
 vm.createContext(context);
 vm.runInContext(source.slice(source.indexOf('function createPdcSupabaseRealtimeSubscription('),source.indexOf('function createPdcSupabaseTableRealtimeSubscription(')),context);
 const planner=context.createPdcSupabaseRealtimeSubscription({}, {onSubscribed:()=>events.push('planner ready'),onClosed:()=>events.push('planner closed')}, {allStations:true});
 const overview=context.createPdcSupabaseRealtimeSubscription({}, {onSubscribed:()=>events.push('overview ready'),onClosed:()=>events.push('overview closed')}, {allStations:true,overview:true});
 assert.equal(channels.size,2);
 overview.unsubscribe();
 assert.deepEqual(events,['planner ready','overview ready','overview closed']);
 assert.equal(channels.size,1);
 planner.unsubscribe();
});
test('overview wiring requests its own channel',()=>{
 const start=source.indexOf('function workshopEligibilityOverviewSubscribe(');
 const fn=source.slice(start,source.indexOf('\nfunction ',start+10));
 assert.match(fn,/allStations: true, overview: true/);
});
