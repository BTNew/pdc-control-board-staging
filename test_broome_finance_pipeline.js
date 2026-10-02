'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),finance=require('./sales/finance-pipeline.js');
test('finance table contains only the screenshot fields',()=>assert.deepEqual(finance.columns.map(x=>x[1]),['Customer','New / Used','Financier','Group','Approval','Finance Comm','DOF/DAF','MVI','RSA','Total Comm','NAF','Settlement','Notes','Access','Payout Complete']));
test('commission total excludes NAF and uses decimal cents',()=>{assert.equal(finance.total({finance_comm:272,dof_daf:912,mvi:0,rsa:0,naf:38919}),1184);assert.equal(finance.total({finance_comm:.1,dof_daf:.2}),.3);assert.equal(finance.money(''),null);for(const value of ['-1','1.234','1e6','NaN','Infinity','1000000000'])assert.throws(()=>finance.money(value));});
test('only the requested application fields can be edited',()=>{assert.deepEqual(finance.patch('settlement','Yes'),{settlement:'Yes'});assert.deepEqual(finance.patch('notes',' application received '),{notes:'application received'});for(const key of ['total_comm','documents_status','current_location','bay','current_application'])assert.throws(()=>finance.patch(key,'test'));assert.throws(()=>finance.patch('approval','approved'));assert.throws(()=>finance.patch('customer',''));});
test('salesperson summaries use saved linked applications only and exclude money',()=>{
 const list=finance.projection([{id:'old',tracking_id:'vehicle',created_at:'2026-10-01',approval:'No',notes:'Older application'},{id:'new',tracking_id:'vehicle',created_at:'2026-10-02',approval:'Yes',settlement:'No',access:'Yes',payout_complete:'No',notes:'Approved',finance_comm:272,naf:38919},{id:'standalone',tracking_id:null,created_at:'2026-10-02',approval:'Yes'}]);
 assert.equal(list.length,1);assert.equal(list[0].id,'new');assert.equal(list[0].approval_status,'approved');assert.equal(list[0].settlement_status,'pending');assert.equal(list[0].shared_update,'Approved');assert.equal('finance_comm' in list[0],false);assert.equal('naf' in list[0],false);assert.deepEqual(finance.projection([]),[]);
});
test('saved settlement dates and unrecorded Access stay accurate in salesperson summaries',()=>{
 const rows=[{id:'saved',tracking_id:'vehicle',created_at:'2026-10-01',settlement:'Yes',settlement_date:'2026-09-30',access:'',naf:38919,finance_comm:272},{id:'no-date',tracking_id:'other',created_at:'2026-10-01',settlement:'Yes',settlement_date:''}];
 const before=JSON.stringify(rows),list=finance.projection(rows);
 assert.equal(list[0].settlement_date,'2026-09-30');assert.equal(list[0].access_status,'');assert.equal(list[1].settlement_date,'');assert.equal(list[1].access_status,'');assert.equal(list[0].payout_status,'');assert.equal(list[1].payout_status,'');
 for(const row of list)assert.equal('naf' in row||'finance_comm' in row,false);
 assert.equal(JSON.stringify(rows),before);
 for(const [access,status] of [['Yes','active'],['No','not_required']])assert.equal(finance.projection([{...rows[0],access}])[0].access_status,status);
 for(const [payout_complete,status] of [['Yes','complete'],['No','pending']])assert.equal(finance.projection([{...rows[0],payout_complete}])[0].payout_status,status);
});
