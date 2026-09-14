'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {UsageQueue,cleanPage}=require('./pdc-staff-usage.js');
const make=()=>{let n=0;return new UsageQueue(()=>String(++n));};
test('Usage does not collect while signed out',()=>{
 const q=make();q.visit('dashboard');q.click();assert.equal(q.next(),undefined);
});
test('Refresh notifications do not duplicate a visit and failed batches retain identity',()=>{
 const q=make();q.identify('a');q.visit('dashboard');q.visit('dashboard');q.click();
 const batch=q.next();assert.deepEqual(q.next(),batch);assert.equal(batch.p_visit,true);assert.equal(batch.p_clicks,1);
 q.acknowledge(batch.p_batch_id);assert.equal(q.next(),undefined);
});
test('Changing users drops queued activity from the previous user',()=>{
 const q=make();q.identify('a');q.visit('parts');q.click();const old=q.next();
 q.identify('b');q.visit('dashboard');q.acknowledge(old.p_batch_id);
 assert.equal(q.next().p_page,'dashboard');assert.equal(q.next().p_clicks,0);
});
test('Page changes keep clicks attached to the page where they happened',()=>{
 const q=make();q.identify('a');q.visit('parts');q.click();q.visit('sublet');q.click();q.click();
 assert.equal(q.next().p_page,'parts');assert.equal(q.next().p_clicks,1);q.acknowledge(q.next().p_batch_id);
 assert.equal(q.next().p_page,'sublet');assert.equal(q.next().p_clicks,2);
});
test('Only allowlisted page names and numeric click totals enter a batch',()=>{
 const q=make();q.identify('a');q.visit('secret customer text');for(let i=0;i<300;i++)q.click();
 assert.equal(cleanPage('secret customer text'),'other');
 assert.deepEqual(Object.keys(q.next()).sort(),['p_batch_id','p_clicks','p_page','p_visit']);
 assert.equal(q.next().p_clicks,200);
});
