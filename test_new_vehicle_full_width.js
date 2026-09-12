'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const api=require('./pdc-new-vehicles.js');
test('full-width review puts missing hours first across stations without rewriting source order',()=>{
 const row={operations:[['valid','FITTING',0.17],['sublet','SUBLET',0],['missing','ELECTRICAL',null],['invalid','FITTING',0.166666],['valid2','TYRE',1]].map(([line_identity,stage_code,estimated_hours])=>({line_identity,stage_code,estimated_hours}))};
 const before=JSON.stringify(row);
 assert.deepEqual(api.reviewOrder(row).map(x=>x.line_identity),['missing','invalid','valid','sublet','valid2']);
 assert.deepEqual(api.reviewOrder(row,{missing:'SUBLET'},{invalid:0.17}).map(x=>x.line_identity),['valid','sublet','missing','invalid','valid2']);
 assert.equal(JSON.stringify(row),before);
});
