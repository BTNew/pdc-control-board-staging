/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {run,fetchCheck,checkLegacyEntryRedirect,probeSignedOutAccess}=require('./tools/functional-monitor/check_website.cjs');

test('Public website monitor refuses report writes outside its private directory',async()=>{
 await assert.rejects(run({output:__dirname,skipNetwork:true}),/Reports must remain/);
});

test('Availability probes use only the explicit read RPCs and no staff bearer token',async()=>{
 const requests=[];
 const result=await probeSignedOutAccess('public-test-key',async(url,options)=>{requests.push({url,options});return{status:401};});
 assert.equal(result.length,3);
 assert.ok(result.every(x=>x.status==='PASS'));
 assert.deepEqual(requests.map(x=>x.url.split('/').at(-1)),['get_broome_sales_board_snapshot','get_workshop_configuration','get_pdc_usage_report_20260914']);
 for(const {url,options} of requests){assert.equal(new URL(url).origin,'https://cdsmnqxtyyoeoznmbidd.supabase.co');assert.equal(options.body,'{}');assert.equal(options.headers.Authorization,undefined);}
});

test('Unexpected public access or a network failure cannot be reported as a healthy backend',async()=>{
 const publicResult=await probeSignedOutAccess('public-test-key',async()=>({status:200}));
 assert.ok(publicResult.every(x=>x.status==='FAIL'));
 const failure=await probeSignedOutAccess('public-test-key',async()=>{throw new Error('Connection unavailable');});
 assert.ok(failure.every(x=>x.status==='FAIL'));
 await assert.rejects(fetchCheck('https://example.invalid/'),/Unexpected website target/);
});

test('Delivery fixture requires loopback and uses exact canonical dealer linkage',()=>{
 const sql=fs.readFileSync('tools/functional-monitor/dealer_delivery_rollback.sql','utf8');
 assert.ok(sql.includes("inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet"));
 assert.ok(sql.includes('source_batch_id'));
 assert.equal(sql.includes('12311009'),false);
 assert.match(sql,/ROLLBACK;/);
});


test('Canonical monitor reads every published entry and asset without following redirects',async()=>{
 const {ENTRY_POINTS}=require('./scripts/build_pages_runtime.js');
 const requests=[];
 const fetcher=async(url,options)=>{requests.push({url:String(url),options});return {ok:true,status:200,text:async()=>'<html>Public entry</html>'};};
 for(const file of ENTRY_POINTS) assert.equal((await fetchCheck(file,'GET',fetcher)).status,'PASS');
 assert.equal((await fetchCheck('app.js','HEAD',fetcher)).status,'PASS');
 assert.equal(requests.length,ENTRY_POINTS.length+1);
 for(const {url,options} of requests){
  assert.equal(new URL(url).origin,'https://pmgpdc.au');
  assert.equal(options.redirect,'error');
  assert.ok(options.signal instanceof AbortSignal);
  assert.equal(options.headers,undefined);
  assert.equal(options.body,undefined);
 }
 assert.equal(requests.at(-1).options.method,'HEAD');
});

test('Monitor rejects arbitrary targets and write methods before sending a request',async()=>{
 let calls=0;
 const fetcher=async()=>{calls++;throw Error('must not fetch');};
 for(const file of ['https://pmgpdc.au/index.html','https://example.invalid/','//example.invalid/index.html','../index.html','index.html?redirect=elsewhere','index.html#test','/index.html','unlisted.html']){
  await assert.rejects(fetchCheck(file,'GET',fetcher),/Unexpected website target/);
  await assert.rejects(checkLegacyEntryRedirect(file,fetcher),/Unexpected legacy entry point/);
 }
 for(const method of ['POST','PUT','DELETE','PATCH']) await assert.rejects(fetchCheck('index.html',method,fetcher),/Only read-only website methods/);
 await assert.rejects(checkLegacyEntryRedirect('app.js',fetcher),/Unexpected legacy entry point/);
 assert.equal(calls,0);
});

test('Legacy entry checks allow only direct permanent redirects to matching canonical paths',async()=>{
 const {ENTRY_POINTS}=require('./scripts/build_pages_runtime.js');
 for(const status of [301,308]) for(const file of ENTRY_POINTS){
  let calls=0;
  const result=await checkLegacyEntryRedirect(file,async(url,options)=>{
   calls++;assert.equal(String(url),'https://btnew.github.io/pdc-control-board-staging/'+file);
   assert.equal(options.method,'HEAD');assert.equal(options.redirect,'manual');
   assert.equal(options.headers,undefined);assert.equal(options.body,undefined);
   return {status,headers:new Headers({location:'https://pmgpdc.au/'+file})};
  });
  assert.equal(calls,1,'The legacy check must not follow its redirect');
  assert.equal(result.status,'PASS');assert.equal(result.http_status,status);
 }
});

test('Legacy wrong-host, wrong-path, temporary, missing or decorated redirects fail closed',async()=>{
 for(const location of [null,'https://example.invalid/index.html','https://pmgpdc.au/sales/index.html','https://pmgpdc.au.evil.invalid/index.html','http://pmgpdc.au/index.html','https://user@pmgpdc.au/index.html','https://pmgpdc.au/index.html?next=elsewhere','https://pmgpdc.au/index.html#fragment','/index.html']){
  let calls=0;
  await assert.rejects(checkLegacyEntryRedirect('index.html',async()=>{calls++;return{status:301,headers:new Headers(location?{location}:{})};}),/exact canonical HTTPS URL/);
  assert.equal(calls,1);
 }
 for(const status of [200,302,303,307,404,500]) await assert.rejects(checkLegacyEntryRedirect('index.html',async()=>({status,headers:new Headers({location:'https://pmgpdc.au/index.html'})})),/exact canonical HTTPS URL/);
});

test('Canonical content failures and redirect/network errors remain failures',async()=>{
 await assert.rejects(fetchCheck('index.html','GET',async()=>({ok:false,status:404})),/HTTP 404/);
 await assert.rejects(fetchCheck('index.html','GET',async()=>({ok:true,text:async()=>'{"ok":true}'})),/HTML entry point missing/);
 await assert.rejects(fetchCheck('index.html','GET',async()=>{throw Error('unexpected redirect');}),/unexpected redirect/);
 await assert.rejects(checkLegacyEntryRedirect('index.html',async()=>{throw Error('network unavailable');}),/network unavailable/);
});
