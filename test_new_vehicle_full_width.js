'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const api=require('./pdc-new-vehicles.js');
const fixture=lines=>({operations:lines.map(([line_identity,stage_code,estimated_hours])=>({line_identity,stage_code,estimated_hours}))});
const ids=(row,choices,drafts)=>api.reviewOrder(row,choices,drafts).map(line=>line.line_identity);

test('compact review groups stations in bucket order with Needs Review first',()=>{
 const row=fixture([['sublet','SUBLET',0],['tyre','TYRE',null],['bus','BUS_4X4',1],['tint','TINT',1],['elec','ELECTRICAL',null],['hoist','HOIST',1],['fab','FABRICATION',1],['fitting','FITTING',1],['review','UNALLOCATED_MAPPING_REVIEW',1]]);
 assert.deepEqual(ids(row),['review','fitting','elec','fab','hoist','tint','tyre','bus','sublet']);
});

test('each station puts missing and invalid hours first while equal-priority lines keep source order',()=>{
 const row=fixture([['e-valid','ELECTRICAL',1],['f-valid','FITTING',0.17],['s-valid','SUBLET',2],['f-invalid','FITTING',0.166666],['s-null','SUBLET',null],['e-missing','ELECTRICAL',null],['f-missing','FITTING',null],['f-valid2','FITTING',2],['s-zero','SUBLET',0],['f-zero','FITTING',0],['f-blank','FITTING','']]);
 assert.deepEqual(ids(row),['f-invalid','f-missing','f-zero','f-blank','f-valid','f-valid2','e-missing','e-valid','s-valid','s-null','s-zero']);
});

test('station choices and draft hours determine grouping without rewriting immutable source data',()=>{
 const row=fixture([['a','FITTING',1],['b','ELECTRICAL',null],['c','FITTING',null],['d','TYRE',1],['e','SUBLET',0],['f','FITTING',2],['g','UNALLOCATED_MAPPING_REVIEW',0]]);
 row.operations.forEach(Object.freeze);Object.freeze(row.operations);Object.freeze(row);
 const choices=Object.freeze({b:'FITTING',e:'HOIST',g:'SUBLET'}),drafts=Object.freeze({c:'0.25',e:'3'}),before=JSON.stringify({row,choices,drafts});
 assert.deepEqual(ids(row),['g','c','a','f','b','d','e']);
 assert.deepEqual(ids(row,choices,drafts),['b','a','c','f','e','d','g']);
 assert.deepEqual(ids(row,{...choices,b:'SUBLET'},{...drafts,c:''}),['c','a','f','e','d','b','g']);
 assert.equal(JSON.stringify({row,choices,drafts}),before);
 assert(api.reviewOrder(row,choices,drafts).every(line=>row.operations.includes(line)));
});

test('unknown assignments stay in Needs Review and Department138 fallback follows Bus4x4',()=>{
 const row=fixture([['tyre','TYRE',1],['unknown','UNALLOCATED_MAPPING_REVIEW',1],['department','UNALLOCATED_MAPPING_REVIEW',1],['review','',null]]);
 row.operations[2].department='138';
 assert.deepEqual(ids(row),['review','unknown','tyre','department']);
 assert.deepEqual(ids(row,{department:'SUBLET',tyre:'UNRECOGNISED_STATION'}),['review','tyre','unknown','department']);
 assert.deepEqual(api.reviewOrder(null),[]);
});
