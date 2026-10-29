// r737 (F346): sales dashboard "At PMB" tile. A car with a key number sits in At PMB instead of its Toyota status tile.
const assert=require('assert');
const s=require('./sales/sales.js');
const row=(x)=>({cosi:true,salesperson_code:'BG',stock:'S1',toyota_status:'Delivered - At Body Builder',...x});
assert.deepStrictEqual(s.categories.map(c=>c[0]).slice(5,8),['yardhold','pmb','released'],'At PMB sits between Yard Hold and Released');
assert.strictEqual(s.tileOf(row({key_number:'448'})),'pmb','keyed car is At PMB');
assert.strictEqual(s.tileOf(row({})),'released','no key keeps its Toyota tile');
assert.strictEqual(s.tileOf(row({key_number:'448',autocare_dispatched:true})),'autocare','Autocare dispatch still wins');
assert.strictEqual(s.tileOf(row({key_number:'448',toyota_status:'Delivered - At Dealer'})),'dealer','dealer still wins');
assert.strictEqual(s.tileOf(row({key_number:'448',lifecycle_state:'completed'})),'released','completed car leaves At PMB');
assert.strictEqual(s.category(row({key_number:'448'})),'released','category() unchanged (status pill and server mirror)');
const rows=[row({key_number:'448'}),row({stock:'S2'}),row({stock:'S3',key_number:'9'})];
assert.strictEqual(s.selectRows(rows,{category:'pmb',salesperson:'',sort:'stock',direction:1}).length,2,'At PMB filter');
assert.strictEqual(s.selectRows(rows,{category:'released',salesperson:'',sort:'stock',direction:1}).length,1,'Released excludes keyed cars');
// tiles still add up to All vehicles
const keys=s.categories.map(c=>c[0]).filter(k=>k!=='all');
assert.strictEqual(keys.reduce((n,k)=>n+rows.filter(r=>s.tileOf(r)===k).length,0),rows.length,'tiles partition all vehicles');
console.log('ok test_sales_pmb_tile_737');
