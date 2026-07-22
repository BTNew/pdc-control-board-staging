'use strict';
const assert=require('assert'); const fs=require('fs'); const vm=require('vm');
const source=fs.readFileSync(require('path').join(__dirname,'app.js'),'utf8');
function functionBlock(name){let start=source.indexOf(`function ${name}(`);assert(start>=0,name);if(source.slice(Math.max(0,start-6),start)==='async ')start-=6;let brace=source.indexOf('{',start),depth=0;for(let i=brace;i<source.length;i++){if(source[i]==='{')depth++;else if(source[i]==='}'&&--depth===0)return source.slice(start,i+1);}throw new Error(name);}
(async()=>{
 let handlers=null,fetches=0,renders=0,subscriptions=0,timerCallback=null,deferNext=false,deferredResolve=null;
 const app={workshopEligibilityRealtime:null,workshopEligibilityReconnectTimer:null,workshopEligibilityRevisionPending:false,workshopEligibilitySnapshot:{stale:true},workshopEligibilityState:'connected',workshopEligibilityError:'',workshopEligibilityRequestGeneration:0,currentView:'workflow'};
 const context={app,console,window:null,
  getPdcSupabaseAccessToken:()=> 'token',renderWorkflowBoard:()=>{renders++;},
  setTimeout:callback=>{timerCallback=callback;return 1;},clearTimeout:()=>{timerCallback=null;},
  createPdcSupabaseRealtimeSubscription:(_config,next)=>{subscriptions++;handlers=next;return {unsubscribe(){}};},
  fetch:async()=>{fetches++;const revision=fetches;if(deferNext){deferNext=false;await new Promise(resolve=>{deferredResolve=resolve;});}return {ok:true,json:async()=>({stages:[],candidates:[],revision})};},
  WORKSHOP_ELIGIBILITY:{canonicalWorkshopStage:value=>value},workshopEligibilityCandidateVehicle:value=>value,
  displayStockNumber:()=>'',vehicleKey:()=>''};
 context.window=context; context.PDC_SUPABASE_CONFIG={url:'https://staging.invalid',publishableKey:'public',workshop:{sharedData:true}};
 vm.runInNewContext([functionBlock('workshopEligibilitySharedAuthorityEnabled'),functionBlock('workshopEligibilityOverviewSubscribe'),functionBlock('loadWorkshopEligibilitySnapshot'),functionBlock('authoritativeWorkshopVehiclesForStage')].join('\n'),context);
 const first=await context.loadWorkshopEligibilitySnapshot('manual');
 assert.strictEqual(first,null); assert.strictEqual(fetches,0,'fetch must not precede subscription trust'); assert(handlers); assert.strictEqual(app.workshopEligibilitySnapshot,null); assert.strictEqual(app.workshopEligibilityState,'reconnecting');
 await handlers.onSubscribed(); assert.strictEqual(fetches,1); assert.strictEqual(app.workshopEligibilityState,'connected'); assert.strictEqual(app.workshopEligibilitySnapshot.revision,1);
 app.workshopEligibilitySnapshot={stale:true}; handlers.onError('CHANNEL_ERROR'); assert.strictEqual(app.workshopEligibilitySnapshot,null); assert.strictEqual(context.authoritativeWorkshopVehiclesForStage('HOIST').length,0);
 await handlers.onSubscribed(); assert.strictEqual(fetches,2,'reconnect must resync'); assert.strictEqual(app.workshopEligibilityState,'connected');
 await handlers.onChange(); await new Promise(resolve=>setImmediate(resolve)); assert.strictEqual(fetches,3,'revision signal must refetch');
 deferNext=true; const racing=context.loadWorkshopEligibilitySnapshot('race'); await new Promise(resolve=>setImmediate(resolve)); assert.strictEqual(app.workshopEligibilityState,'loading'); handlers.onChange(); assert.strictEqual(app.workshopEligibilityRevisionPending,true,'revision during resync must be retained'); deferredResolve(); await racing; assert.strictEqual(fetches,5,'revision during resync must force a trailing fetch'); assert.strictEqual(app.workshopEligibilitySnapshot.revision,5); assert.strictEqual(app.workshopEligibilityRevisionPending,false);
 app.workshopEligibilitySnapshot={stale:true}; handlers.onClosed(); assert.strictEqual(app.workshopEligibilitySnapshot,null); assert.strictEqual(app.workshopEligibilityState,'reconnecting'); assert.strictEqual(app.workshopEligibilityRealtime,null); assert(timerCallback,'closed channel must schedule a replacement');
 timerCallback(); assert.strictEqual(subscriptions,2,'closed channel must be replaced'); await handlers.onSubscribed(); assert.strictEqual(fetches,6,'replacement subscription must resync');
 assert(renders>0); console.log('All-station Realtime authority handshake: passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
