'use strict';
const assert=require('assert');
const {createWorkshopDataService,WORKSHOP_CONNECTION_STATE}=require('./workshop-data-service.js');
(async()=>{
 const calls=[];const snapshot={revision:7840,bookings:[],vehicles:[],work_items:[],bays:[],stages:[],admin_blocks:[]};
 const service=createWorkshopDataService({
  config:{workshop:{sharedData:true}},scope:{stageCode:'FITTING',dateFrom:'2026-08-26',dateTo:'2026-08-26'},
  getAccessToken:()=> 'token',getRole:()=> 'administrator',
  client:{rpc:async(_token,name)=>{calls.push(name);if(name==='recover_overdue_planned_workshop_bookings')throw new Error('bay_overlap recovery transport failure');if(name==='get_station_workshop_snapshot')return{ok:true,status:200,body:snapshot};throw new Error(name);}},
 });
 const result=await service.loadSnapshot('recovery-failure-regression');
 assert.strictEqual(result,snapshot,'valid scoped snapshot remains visible');
 assert.deepStrictEqual(calls,['recover_overdue_planned_workshop_bookings','get_station_workshop_snapshot']);
 assert.strictEqual(service.getState(),WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE);
 assert.strictEqual(service.getTrustedSnapshot(),snapshot);
 console.log('Workshop recovery failure cannot blank station snapshot: PASS');
})().catch(error=>{console.error(error);process.exitCode=1;});
