'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {run,fetchCheck,probeSignedOutAccess}=require('./tools/functional-monitor/check_website.cjs');

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
