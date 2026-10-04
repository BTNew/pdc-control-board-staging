'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'karratha/native-verification.js'),'utf8');
const verifier=require('./karratha/native-verification.js');
const hash='a'.repeat(64);
function success(){return {ok:true,phase:'complete',candidate_sha256:hash,compact_installer_sha256:hash,fixture_sha256:hash,genuine_website_transport:true,native_planner_gate_unchanged:true,synthetic_rows_rolled_back:true,readiness_still_false:true,native_acceptance:{ok:true,native_public_facades:true,no_backdated_work:true,persisted:false},installed_definition_proof:{ok:true,expected_methods:677,present_methods:677,exact_body_count:677,exact_definition_count:677,mismatches:[]},protected_fence:{protected:{ok:true,shared_sequences_reset:false}}};}
async function fixture(options={}){
 const elements=Object.fromEntries(['verify-native','verification-status','verification-result'].map(id=>[id,{textContent:'',hidden:id==='verification-result',disabled:false,handlers:{},addEventListener(type,handler){this.handlers[type]=handler;}}]));
 const events={},calls=[];let authHandler,captured;
 const session={user:{id:'fictional-own-user'}};Object.defineProperty(session,'access_token',{get(){assert.fail('Auth token must never be extracted');}});Object.defineProperty(session,'refresh_token',{get(){assert.fail('Refresh token must never be extracted');}});
 const client={auth:{getUser:options.getUser||(()=>Promise.resolve({data:{user:{id:'fictional-own-user'}},error:null})),getSession:options.getSession||(()=>Promise.resolve({data:{session},error:null})),onAuthStateChange(handler){authHandler=handler;}},rpc:async(name,payload)=>{calls.push({name,payload});return options.rpc?options.rpc(name,payload):{data:success(),error:null};}};
 const normal={centre:'135',ready:true,rpc:Object.freeze({get_workshop_snapshot:'k135_get_workshop_snapshot'})};
 const root={K135_API_MAP:normal,fetch:async()=>{throw Error('Network forbidden');},KARRATHA_CONFIG:{environment:'staging',centreCode:'KARRATHA',authStorageKey:'karratha-pdc-auth-v1',projectRef:'cdsmnqxtyyoeoznmbidd',url:'https://cdsmnqxtyyoeoznmbidd.supabase.co',publishableKey:'sb_publishable_FictionalOnly'},supabase:{createClient(url,key,settings){captured={url,key,settings};return client;}}};
 const document={readyState:'complete',getElementById:id=>elements[id],addEventListener:(type,handler)=>events[type]=handler};
 vm.runInNewContext(source,{window:root,document});await new Promise(resolve=>setImmediate(resolve));
 return {root,normal,elements,calls,get captured(){return captured;},click:()=>elements['verify-native'].handlers.click(),auth:event=>authHandler(event)};
}
test('safe projection excludes raw claims, tokens, customer rows, failure text and sequence states',()=>{
 const value=success();Object.assign(value,{access_token:'SECRET',failure_message:'Private customer detail',rows:[{customer:'PRIVATE'}],claims:{email:'private@example.test'}});value.protected_fence.own_sequence_advances=[{last_value:999}];value.installed_definition_proof.mismatches=[{body:'PRIVATE SQL'}];
 const output=JSON.stringify(verifier.project(value));assert.doesNotMatch(output,/SECRET|PRIVATE|private@example|failure_message|own_sequence_advances/);assert.match(output,/mismatch_count/);assert.match(output,/677/);assert.equal(verifier.project(value).native_acceptance.native_public_facades,true);
 value.fitter_request_path_acceptance={ok:true,checks:36,own_aliases:7,old_paths_denied:true,native_post_write_gate_preserved:true,separate_fitter_browser_session_tested:false,raw_rows:[{customer:'PRIVATE'}]};const fitter=verifier.project(value).fitter_request_path_acceptance;assert.equal(fitter.checks,36);assert.equal(fitter.separate_fitter_browser_session_tested,false);assert.equal(fitter.raw_rows,undefined);
});
test('passing output requires the genuine transport, rollback, closed gate and protected proof',()=>{
 assert.equal(verifier.passed(success()),true);for(const key of ['genuine_website_transport','native_planner_gate_unchanged','synthetic_rows_rolled_back','readiness_still_false']){const value=success();value[key]=false;assert.equal(verifier.passed(value),false,key);}const value=success();value.protected_fence.protected.ok=false;assert.equal(verifier.passed(value),false);
});

test('private verification projects bounded catalogue MD5 and own allocator proof without raw rows',()=>{
 const state={last_value:123,log_cnt:31,is_called:true},value=success();
 value.protected_fence.protected={ok:true,catalogue_digest:'b'.repeat(32),catalogue_objects:22709,protected_relations:82,own_relations_restored:227,own_sequence_gaps_reported:10,shared_sequences_reset:false,claims:{secret:'PRIVATE'}};
 value.protected_fence.concurrent_cron_allocator={before_state:state,after_state:{...state,last_value:125},captured_from:'2026-10-03T06:00:00+00:00',captured_to:'2026-10-03T06:01:00+00:00',protected_job_ids:Array.from({length:105},(_,i)=>i+1),first_runid:124,last_runid:125,requires_external_proof:true,rows:[{customer:'PRIVATE'}]};
 value.protected_fence.own_sequence_advances=[{schema_name:'karratha135_pdc',table_name:'own_sequence',before_state:state,after_state:{...state,last_value:124},customer:'PRIVATE'},{schema_name:'public',table_name:'pmb_sequence',before_state:state,after_state:state},{schema_name:'karratha135_pdc',table_name:'bad-name',before_state:state,after_state:state}];
 const safe=verifier.project(value).protected_fence;assert.equal(safe.catalogue_digest,'b'.repeat(32));assert.equal(safe.catalogue_objects,22709);assert.equal(safe.concurrent_cron_allocator.protected_job_ids.length,100);assert.equal(safe.concurrent_cron_allocator.protected_job_id_count,105);assert.equal(safe.concurrent_cron_allocator.protected_job_ids_truncated,true);assert.equal(safe.concurrent_cron_allocator.requires_external_proof,true);assert.equal(safe.own_sequence_advances.length,1);assert.equal(safe.own_sequence_advances[0].after_state.last_value,124);assert.doesNotMatch(JSON.stringify(safe),/PRIVATE|claims|customer|pmb_sequence|bad-name/);
});
test('temporary SDK leaves normal board transport unchanged and calls only the approved own fixture',async()=>{
 const f=await fixture();assert.equal(f.normal.rpc.verification_fixture,undefined);assert.equal(f.root.K135_API_MAP,f.normal);assert.equal(typeof f.captured.settings.global.fetch,'function');assert.equal(f.captured.settings.auth.storageKey,'karratha-pdc-auth-v1');assert.equal(f.captured.settings.auth.detectSessionInUrl,false);
 await f.click();assert.equal(f.calls.length,1);assert.equal(f.calls[0].name,'k135_verify_native_fixture');assert.deepEqual(JSON.parse(JSON.stringify(f.calls[0].payload)),{});assert.match(f.elements['verification-status'].textContent,/passed/);assert.equal(f.elements['verification-result'].hidden,false);
});
test('signed-out or mismatched account cannot call the fixture',async()=>{
 for(const getSession of [async()=>({data:{session:null},error:null}),async()=>({data:{session:{user:{id:'different'}}},error:null})]){const f=await fixture({getSession});await f.click();assert.equal(f.calls.length,0);assert.equal(f.elements['verification-result'].hidden,true);}
});
test('logout while a verification is pending discards its delayed digest',async()=>{
 let done;const f=await fixture({rpc:()=>new Promise(resolve=>done=resolve)});const pending=f.click();await new Promise(resolve=>setImmediate(resolve));f.auth('SIGNED_OUT');done({data:success(),error:null});await pending;assert.equal(f.elements['verification-result'].hidden,true);assert.equal(f.elements['verification-result'].textContent,'');assert.doesNotMatch(f.elements['verification-status'].textContent,/passed/);
});
test('auth replacement during account proof prevents dispatch and duplicate clicks are ignored',async()=>{
 let proof,ready=false;const f=await fixture({getUser:()=>ready?new Promise(resolve=>proof=resolve):Promise.resolve({data:{user:{id:'fictional-own-user'}},error:null})});ready=true;
 const first=f.click();await f.click();assert.equal(f.calls.length,0);f.auth('SIGNED_IN');proof({data:{user:{id:'fictional-own-user'}},error:null});await first;assert.equal(f.calls.length,0);
});
test('server failure displays only a generic message without raw error text',async()=>{
 const f=await fixture({rpc:async()=>({data:null,error:{message:'Private customer and SECRET access token'}})});await f.click();assert.equal(f.elements['verification-result'].hidden,true);assert.doesNotMatch(f.elements['verification-status'].textContent,/Private|SECRET/);
});

test('diagnostic projection accepts only SQLSTATE and exact approved guard messages',()=>{
 const messages={
  'Genuine website POST required':'transport_guard',
  'Repeatable-read verification transaction required':'isolation_guard',
  'Exact staging required':'staging_guard',
  'Exact approved verifier identity required':'identity_guard',
  'Only an unreleased engine can run this fixed fixture':'readiness_guard',
  'Unexpected pre-existing fixture state':'fixture_state_guard',
  'Live protected fence requires a consistent transaction snapshot':'snapshot_guard',
  'Unreviewed concurrent cron allocator properties':'allocator_guard'};
 for(const [message,guard] of Object.entries(messages)){
  const safe=verifier.projectError({code:'42501',message,details:'PRIVATE SQL customer',hint:'SECRET',claims:{user:'PRIVATE'}});
  assert.equal(safe.error_code,'42501');assert.equal(safe.error_guard,guard);assert.doesNotMatch(JSON.stringify(safe),/PRIVATE|SECRET|details|hint|claims/);
 }
 for(const message of ['Genuine website POST required PRIVATE','Exact staging required\nSECRET','toString','__proto__'])assert.equal(verifier.projectError({code:'25001',message}).error_guard,undefined);
 for(const code of ['42501 SECRET','PGRST202','25001\n',42501,null])assert.equal(verifier.projectError({code,message:'Private customer data'}).error_code,undefined);
});

test('known failed request shows bounded diagnostic without arbitrary response data',async()=>{
 const f=await fixture({rpc:async()=>({data:null,error:{code:'25001',message:'Repeatable-read verification transaction required',details:'PRIVATE SQL',hint:'SECRET'}})});
 await f.click();const shown=JSON.parse(f.elements['verification-result'].textContent);assert.equal(shown.error_code,'25001');assert.equal(shown.error_guard,'isolation_guard');assert.equal(f.elements['verification-result'].hidden,false);assert.doesNotMatch(f.elements['verification-result'].textContent,/PRIVATE|SECRET|details|hint/);assert.doesNotMatch(f.elements['verification-status'].textContent,/passed/);
});
test('temporary page has no credentials form and script does not fetch, extract or log credentials',()=>{
 const html=fs.readFileSync(path.join(__dirname,'karratha/native-verification.html'),'utf8');assert.doesNotMatch(html,/<input|<form|https:\/\/[^c]/);assert.match(html,/href="\.\/"/);assert.match(html,/script-src 'self'/);assert.doesNotMatch(source,/(?:\.|\[["\'])(?:access_token|refresh_token)|localStorage|sessionStorage|Authorization|console\./);
 assert.doesNotMatch(source,/K135_API_MAP|PDC_SUPABASE_CONFIG/);
});

test('temporary SDK fetch rejects all PMB, arbitrary REST, Storage and credential mutations',async()=>{
 const requests=[],fetcher=verifier.guardedFetch(async(input,options)=>{requests.push({input:String(input),options});return new Response('{}');});
 for(const [url,method] of [['https://cdsmnqxtyyoeoznmbidd.supabase.co/auth/v1/user','GET'],['https://cdsmnqxtyyoeoznmbidd.supabase.co/auth/v1/token?grant_type=refresh_token','POST'],['https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/k135_verify_native_fixture','POST']])await fetcher(url,{method});
 assert.equal(requests.length,3);for(const request of requests)assert.equal(request.options.redirect,'error');
 for(const [path,method] of [['/rest/v1/rpc/get_workshop_snapshot','POST'],['/rest/v1/rpc/k135_get_workshop_snapshot','POST'],['/rest/v1/vehicles','GET'],['/storage/v1/object/pdc-qc-evidence-staging/a','POST'],['/auth/v1/user','PUT'],['/auth/v1/token?grant_type=password','POST'],['/auth/v1/signup','POST'],['/rest/v1/rpc/k135_verify_native_fixture?x=1','POST'],['/rest/v1/rpc/k135_verify_native_fixture','GET']])await assert.rejects(fetcher('https://cdsmnqxtyyoeoznmbidd.supabase.co'+path,{method}));
 await assert.rejects(fetcher('https://elsewhere.invalid/rest/v1/rpc/k135_verify_native_fixture',{method:'POST'}));assert.equal(requests.length,3);
});
