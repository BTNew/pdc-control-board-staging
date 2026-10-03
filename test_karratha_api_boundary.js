'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const apiPath = path.resolve(__dirname, './karratha/api.js');
const config = {projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',
 centreCode:'KARRATHA',authStorageKey:'karratha-pdc-auth-v1',publishableKey:'sb_publishable_fictional_fixture'};
const context = {centre:'KARRATHA',user_id:'fictional-user-a',role:'administrator',can_edit:true,can_admin:true,membership_version:1};

function harness(response) {
 delete require.cache[apiPath];
 const api = require(apiPath);
 let owner='fictional-user-a:1',ctx={...context};
 const calls=[];
 api.init({config,client:{rpc(name,params){calls.push({name,params});return typeof response==='function'?response(name,params):Promise.resolve(response);}},
   getOwner:()=>owner,getContext:()=>ctx,getUserId:()=>ctx?.user_id||'fictional-user-a'});
 return {api,calls,changeOwner(value){owner=value;},changeContext(value){ctx=value;}};
}

function snapshotResult(overrides={}) {
 return {data:{context:{...context},revision:1,vehicles:[],jobs:[],operations:[],bookings:[],bays:[],technicians:[],settings:[],history:[],...overrides},error:null};
}

test('configuration rejects missing, different project, department and shared namespace',()=>{
 const {api}=harness(snapshotResult());
 assert.equal(api.validConfig(config),true);
 for (const bad of [null,{...config,projectRef:'production'},{...config,url:'https://other.supabase.co'},
                    {...config,centreCode:'PMB'},{...config,authStorageKey:'sb-cdsmnqxtyyoeoznmbidd-auth-token'},
                    {...config,publishableKey:'service_role_fixture'}]) assert.equal(api.validConfig(bad),false);
});

test('snapshot uses only prefixed RPC and exact versioned range',async()=>{
 const {api,calls}=harness(snapshotResult());
 const result=await api.snapshot('2026-10-05','2026-10-11');
 assert.equal(result.context.centre,'KARRATHA');
 assert.deepEqual(calls,[{name:'get_karratha_pdc_snapshot',params:{p_date_from:'2026-10-05',p_date_to:'2026-10-11'}}]);
});

test('no membership context and unauthenticated owner do not call a data RPC',async()=>{
 const h=harness(snapshotResult());
 h.changeContext(null);
 await assert.rejects(h.api.snapshot('2026-10-05','2026-10-11'),/access has not been confirmed/);
 h.changeOwner('');
 await assert.rejects(h.api.context(),/Sign in/);
 assert.equal(h.calls.length,0);
});

test('owner change during pending success and pending network error drops response',async()=>{
 for(const reject of [false,true]) {
  let settle;
  const h=harness(()=>new Promise((resolve,rejectPromise)=>{settle=reject?rejectPromise:resolve;}));
  const request=h.api.snapshot('2026-10-05','2026-10-11');
  h.changeOwner('fictional-user-b:2');
  settle(reject?new Error('Fixture connection failure'):snapshotResult());
  await assert.rejects(request,error=>error.name==='StaleResponse');
 }
});

test('wrong centre or wrong account snapshot and malformed collections fail closed',async()=>{
 for (const overrides of [{context:{...context,centre:'PMB'}},{context:{...context,user_id:'fictional-user-b'}},{jobs:null}]) {
  const h=harness(snapshotResult(overrides));
  await assert.rejects(h.api.snapshot('2026-10-05','2026-10-11'));
 }
});

test('unapproved context, viewer editing and unknown PMB command fail without writes',async()=>{
 const h=harness({data:{record:{id:'fixture',version:1},revision:1},error:null});
 h.changeContext({...context,role:'viewer',can_edit:false,can_admin:false});
 await assert.rejects(h.api.save('parts','fixture',1,{received:true,request_id:'fixture-request'}),/read-only/);
 await assert.rejects(h.api.save('membership','fixture',1,{role:'administrator',request_id:'fixture-request'}),/administrator/);
 await assert.rejects(h.api.save('schedule_vehicle_work','fixture',1,{}),/unavailable/);
 assert.equal(h.calls.length,0);
});

test('explicit save sends actorless payload, valid nonce and expected version to own RPC',async()=>{
 const h=harness({data:{record:{id:'fictional-operation',version:2},revision:2},error:null});
 const payload={received:true,ordered:true,eta:null,location:'Own parts shelf',notes:'Fictional receipt'};
 await h.api.save('parts','fictional-operation',1,payload);
 const {request_id,...sent}=h.calls[0].params.p_data;
 assert.match(request_id,/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i);
 assert.deepEqual(h.calls,[{name:'save_karratha_pdc',params:{p_action:'parts',p_id:'fictional-operation',p_expected_version:1,p_data:{...payload,request_id}}}]);
 assert.deepEqual(sent,payload);
 assert.equal(Object.hasOwn(h.calls[0].params.p_data,'actor'),false);
});

test('uncertain network save retries retain nonce while changed payload gets another nonce',async()=>{
 let fail=true;
 const h=harness(()=>fail?Promise.reject(new Error('Fixture network interruption')):Promise.resolve({data:{record:{id:'fixture',version:2},revision:2},error:null}));
 await assert.rejects(h.api.save('parts','fixture',1,{received:true}));
 const first=h.calls[0].params.p_data.request_id;
 await assert.rejects(h.api.save('parts','fixture',1,{received:true}));
 assert.equal(h.calls[1].params.p_data.request_id,first);
 await assert.rejects(h.api.save('parts','fixture',1,{received:false}));
 assert.notEqual(h.calls[2].params.p_data.request_id,first);
 fail=false;
 await h.api.save('parts','fixture',1,{received:true});
 assert.equal(h.calls[3].params.p_data.request_id,first);
});

test('scope clear discards uncertain retry nonce and current membership must allow imports',async()=>{
 const h=harness(()=>Promise.reject(new Error('Fixture network interruption')));
 await assert.rejects(h.api.save('parts','fixture',1,{received:true}));
 const first=h.calls[0].params.p_data.request_id;
 h.api.clear();
 await assert.rejects(h.api.save('parts','fixture',1,{received:true}));
 assert.notEqual(h.calls[1].params.p_data.request_id,first);
 h.changeContext({...context,role:'viewer',can_edit:false,can_admin:false,can_import:false});
 await assert.rejects(h.api.preview('fixture.csv','0'.repeat(64),[]),/import access/);
 await assert.rejects(h.api.apply('fixture',1),/import access/);
 assert.equal(h.calls.length,2);
});

test('missing/stale expected version and unconfirmed server record are rejected',async()=>{
 const h=harness({data:{record:{id:'fixture',version:0},revision:1},error:null});
 for (const v of [null,undefined,NaN,-1,1.5]) await assert.rejects(h.api.save('parts','fixture',v,{}),/version/);
 await assert.rejects(h.api.save('parts','fixture',1,{}),/could not be confirmed/);
});

test('server permission/version failures are safe and not raw SQL disclosure',async()=>{
 for (const error of [{code:'42501',message:'SELECT SECRET auth.users'},
                     {code:'40001',message:'Internal stale version'},
                     {code:'99999',message:'SELECT password from private_schema'}]) {
  const h=harness({data:null,error});
  await assert.rejects(h.api.snapshot('2026-10-05','2026-10-11'),failure=>!failure.message.includes('SELECT')&&!failure.message.includes('password'));
 }
});

