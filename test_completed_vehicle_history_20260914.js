'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const source=fs.readFileSync(path.resolve(process.env.PDC_RUNTIME_DIR||process.cwd(),'app.js'),'utf8');
function fn(name){const start=source.indexOf(`function ${name}(`);assert(start>=0,`${name} exists`);const next=source.slice(start+1).search(/\n(?:async )?function /);assert(next>=0,`${name} boundary exists`);return source.slice(start,start+1+next);}
const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const stamp={pmb:'2026-09-01T00:00:00Z',rft:'2026-09-03T03:04:00Z',od:'2026-09-05T06:04:00Z'};
function runtime(){
  const nodes={'completed-search':{value:''},'completed-pmb-statistics':{innerHTML:''},'completed-vehicles-content':{innerHTML:''}};
  const c={Date,app:{data:[],emailVehicleLocationRows:[],sharedNavisionVisibleRows:[]},escapeHtml,
    $:selector=>nodes[selector.slice(1)],$$:()=>[],
    sharedNavisionIdentityToken:value=>String(value||'').trim().toUpperCase(),cleanNavisionText:value=>String(value??'').trim(),
    displayStockNumber:v=>String(v.stock||''),vehicleKeyNumber:v=>v.keyNumber||'',vehicleJobcardNumber:v=>v.jobCardNumber||'',
    vehicleCustomerName:v=>v.client||v.toyotaCustomer||'',displayVehicle:v=>v.vehicle||'',pdcCompletedJobsText:v=>v.completedJobs||'',pdcGridCompletedJobsText:v=>v.completedJobs||'',
    bindRftCollectedInputs:()=>{},openVehicleModal:()=>{throw Error('No vehicle mutation or open is needed to render history');},nodes};
  vm.createContext(c);
  const base=['isBlankStock','vehicleKey','parseIsoTimestamp','lifecycleHistoryForVehicle','lifecycleTimestamp','completedPmbStartDate','completedRftDate','completedPmbDays','lifecycleDurationDays','lifecycleDurationLabel','completedPmbDaysLabel','completedPmbStatisticsFromDays','completedPmbStatistics','completedPmbStatisticDaysLabel','shortDateAu','vehicleCollectedFromRft','isHermesSyntheticVehicle','sharedNavisionLocationVehicle','completedVehicleRows','renderCompletedPmbStatistics','renderCompletedVehicles','csvEscape'];
  const history=[...source.matchAll(/^function (completedHistory\w*)\(/gm)].map(x=>x[1]);
  for(const name of new Set([...base,...history]))vm.runInContext(fn(name),c);
  return c;
}
function vehicle(id='canonical-a',stock='00123',extra={}){return {__emailVehicleId:id,__emailVehicleServerAuthoritative:true,stock,pdcLifecycleState:'completed',vehicleDeliveredState:true,client:'Synthetic customer',vehicle:'Hilux',jobCardNumber:'JC-TEST',lifecycleHistory:{firstEnteredPmbAt:stamp.pmb,firstBecameRftAt:stamp.rft},dealerTransitClosedAt:stamp.od,...extra};}
test('milestones prefer preserved history and authoritative delivery, never ETA or collection',()=>{
  const c=runtime();const v=vehicle('canonical-a','00123',{dateToPmb:'2020-01-01',dateToRft:'2020-01-02',deliveredToDealerDate:'2020-01-03',rftTransferredAt:'2020-01-04T00:00:00Z',rftCollectedAt:'2020-01-05T00:00:00Z',navisionKewdaleEta:'2019-01-01'});const before=JSON.stringify(v),m=c.completedHistoryMilestones(v);
  assert.equal(m.pmb.value,stamp.pmb);assert.equal(m.rft.value,stamp.rft);assert.equal(m.delivered.value,stamp.od);assert.equal(m.pmb.dateOnly,false);assert.equal(m.delivered.dateOnly,false);assert.equal(JSON.stringify(v),before);
  const missing=c.completedHistoryMilestones({rftCollectedAt:stamp.od,navisionKewdaleEta:stamp.pmb});assert.equal(missing.pmb,null);assert.equal(missing.rft,null);assert.equal(missing.delivered,null);
});
test('exact PMB-to-RFT, RFT-to-OD and total intervals retain elapsed minutes',()=>{
  const c=runtime(),v=vehicle();
  for(const [key,seconds,label] of [['pmbToRft',183840,'2d 3h 4m'],['rftToOd',183600,'2d 3h'],['pmbToOd',367440,'4d 6h 4m']]){
    const interval=c.completedHistoryInterval(v,key);assert.equal(interval.seconds,seconds);assert.equal(interval.days,seconds/86400);assert.equal(interval.dateOnly,false);assert.equal(c.completedHistoryDurationLabel(interval),label);
  }
});
test('date-only endpoints report calendar days without inventing exact hours',()=>{
  const c=runtime(),v=vehicle('canonical-a','00123',{lifecycleHistory:{},dateToPmb:'2026-09-01',dateToRft:'2026-09-03',dealerTransitClosedAt:'',deliveredToDealerDate:'2026-09-06'});
  for(const [key,days] of [['pmbToRft',2],['rftToOd',3],['pmbToOd',5]]){const interval=c.completedHistoryInterval(v,key);assert.equal(interval.days,days);assert.equal(interval.seconds,null);assert.equal(interval.dateOnly,true);assert.equal(c.completedHistoryDurationLabel(interval),`${days} days (date only)`);}
  const mixed=vehicle('canonical-a','00123',{lifecycleHistory:{firstBecameRftAt:'2026-09-02T18:00:00Z'},dealerTransitClosedAt:'',deliveredToDealerDate:'2026-09-06'});assert.equal(c.completedHistoryInterval(mixed,'rftToOd').days,3,'UTC milestone maps to the Perth calendar date');
});
test('missing, invalid and reversed timestamps produce Unknown, but same moment is valid zero',()=>{
  const c=runtime();for(const v of [vehicle('a','00123',{lifecycleHistory:{},dealerTransitClosedAt:''}),vehicle('a','00123',{lifecycleHistory:{firstEnteredPmbAt:'invalid',firstBecameRftAt:'invalid'},dealerTransitClosedAt:'invalid'}),vehicle('a','00123',{lifecycleHistory:{firstEnteredPmbAt:stamp.od,firstBecameRftAt:stamp.rft},dealerTransitClosedAt:stamp.pmb})])for(const key of ['pmbToRft','rftToOd','pmbToOd']){const interval=c.completedHistoryInterval(v,key);assert.equal(interval,null);assert.equal(c.completedHistoryDurationLabel(interval),'Unknown');}
  const same=vehicle('a','00123',{lifecycleHistory:{firstEnteredPmbAt:stamp.pmb,firstBecameRftAt:stamp.pmb},dealerTransitClosedAt:stamp.pmb});for(const key of ['pmbToRft','rftToOd','pmbToOd'])assert.equal(c.completedHistoryInterval(same,key).seconds,0);
});
test('completed history includes records without a collection event and deduplicates by canonical identity',()=>{
  const c=runtime();c.app.data=[vehicle(),vehicle('canonical-b','00123',{client:'Second dealer customer'}),vehicle('active','00222',{pdcLifecycleState:'rft',vehicleDeliveredState:false,dealerTransitClosedAt:''}),vehicle('hermes','HERMES-TEST-HISTORY')];
  c.app.sharedNavisionVisibleRows=[{id:'mirror-a',canonical_vehicle_id:'canonical-a',stock_number:'00123',lifecycle_state:'completed',is_current:false,customer_name:'Thinner mirror',model:'',lifecycle_history:{},dealer_transit_closed_at:'2026-09-07T00:00:00Z'},{id:'retained-only',canonical_vehicle_id:'retained-c',stock_number:'00888',lifecycle_state:'completed',is_current:false,board_activated:false,customer_name:'Retained import customer',model:'Prado',date_to_pmb:'2026-09-01',date_to_rft:'2026-09-04',delivered_to_dealer_date:'2026-09-10'}];
  const before=JSON.stringify({data:c.app.data,shared:c.app.sharedNavisionVisibleRows}),rows=c.completedHistoryRows();assert.equal(rows.length,3);assert.equal(rows.filter(v=>v.stock==='00123').length,2,'same stock with different canonical IDs stays separate');assert.equal(JSON.stringify({data:c.app.data,shared:c.app.sharedNavisionVisibleRows}),before);
  const canonical=rows.find(v=>v.__emailVehicleId==='canonical-a');assert.equal(canonical.client,'Synthetic customer');assert.equal(canonical.vehicle,'Hilux');assert.equal(canonical.jobCardNumber,'JC-TEST');assert.equal(canonical.lifecycleHistory.firstEnteredPmbAt,stamp.pmb);assert.equal(canonical.dealerTransitClosedAt,stamp.od);
  const retained=rows.find(v=>v.stock==='00888');assert.equal(retained.canonicalVehicleId,'retained-c');assert.equal(retained.client,'Retained import customer');assert.equal(retained.dateToPmb,'2026-09-01');assert.equal(retained.deliveredToDealerDate,'2026-09-10');assert.equal(retained.vehicleDeliveredState,true);
  assert(rows.every(v=>!v.rftCollectedAt),'pickup is not a requirement for completed history');
});
test('search, displayed rows and statistics use the same preserved history',()=>{
  const c=runtime();c.app.data=[vehicle('canonical-a','00123'),vehicle('canonical-b','00456',{client:'Second customer',lifecycleHistory:{},dealerTransitClosedAt:''})];c.nodes['completed-search'].value='00123';
  const rows=c.completedVehicleRows();assert.equal(rows.length,1);assert.equal(rows[0].stock,'00123');assert.doesNotThrow(()=>c.renderCompletedVehicles());const html=c.nodes['completed-vehicles-content'].innerHTML,stats=c.nodes['completed-pmb-statistics'].innerHTML;
  assert.match(html,/00123/);assert.doesNotMatch(html,/00456/);assert.match(stats,/1 of 1 vehicle with known dates/);assert.match(html,/01\/09\/2026/);assert.match(html,/03\/09\/2026/);assert.match(html,/05\/09\/2026/);assert.doesNotMatch(html,/checked disabled[^>]*.*Collected/s,'delivery must not claim an unrecorded pickup');
  c.nodes['completed-search'].value='Second customer';assert.equal(c.completedVehicleRows().length,1);c.nodes['completed-search'].value='no-match';c.renderCompletedVehicles();assert.match(c.nodes['completed-pmb-statistics'].innerHTML,/0 of 0 vehicles with known dates/);
});
test('CSV exports the same milestone and interval values while keeping collection separate',()=>{
  const c=runtime(),v=vehicle('canonical-a','00123',{client:'Customer, with comma',rftCollectedAt:'2026-09-04T00:00:00Z'}),before=JSON.stringify(v);const csv=c.completedHistoryCsv([v]);
  assert.equal(typeof csv,'string');assert.match(csv,/Stock/i);assert.match(csv,/PMB/i);assert.match(csv,/RFT/i);assert.match(csv,/OD|Delivered/i);assert.match(csv,/Collected/i);assert.match(csv,/00123/);assert.match(csv,/Customer, with comma/);assert.match(csv,/2026-09-05|05\/09\/2026/);assert.match(csv,/2026-09-04|04\/09\/2026/);assert.equal(JSON.stringify(v),before);
});
test('retained Navision dates render directly and keep OD confirmation separate from collection',()=>{
  const c=runtime();
  c.app.sharedNavisionVisibleRows=[{id:'retained-od',canonical_vehicle_id:'canonical-od',stock_number:'00077',lifecycle_state:'completed',vehicle_status:'OD',is_current:false,board_activated:false,customer_name:'Retained history customer',model:'Prado',date_to_pmb:'2026-09-01',date_to_rft:'2026-09-03',delivered_to_dealer_date:'2026-09-06',rft_collected_at:'2026-09-04T00:00:00Z'}];
  const [v]=c.completedVehicleRows();assert.equal(v.stock,'00077');assert.equal(v.navisionLocationStatus,'OD');assert.equal(c.completedHistoryMilestones(v).delivered.value,'2026-09-06');assert.doesNotThrow(()=>c.renderCompletedVehicles());
  const html=c.nodes['completed-vehicles-content'].innerHTML;assert.match(html,/01\/09\/2026 \(date only\)/);assert.match(html,/03\/09\/2026 \(date only\)/);assert.match(html,/06\/09\/2026 \(date only\)/);assert.match(html,/04\/09\/2026/);assert.match(html,/2 days \(date only\)/);assert.match(html,/3 days \(date only\)/);assert.match(html,/5 days \(date only\)/);
  const lines=c.completedHistoryCsv([v]).split('\n'),headers=lines[0].split(','),values=lines[1].split(',');const record=Object.fromEntries(headers.map((key,index)=>[key,values[index]]));
  assert.equal(record.Stock,'00077');assert.equal(record['PMB Recorded'],'2026-09-01');assert.equal(record.RFT,'2026-09-03');assert.equal(record['OD Recorded'],'2026-09-06');assert.equal(record['Collected At'],'2026-09-04T00:00:00Z');assert.equal(record['OD Precision'],'date only');assert.equal(record['RFT to OD Days'],'3');assert.equal(record['Total PMB to OD Days'],'5');assert.equal(record['RFT to OD Seconds'],'');
  c.nodes['completed-search'].value='Retained history customer';assert.equal(c.completedVehicleRows().length,1);c.renderCompletedVehicles();assert.match(c.nodes['completed-pmb-statistics'].innerHTML,/1 of 1 vehicle with known dates/);
});
test('impossible calendar dates and absent delivery stay unknown in rendered history',()=>{
  const c=runtime();assert.equal(c.completedHistoryMilestone('2026-02-30'),null);assert.equal(c.completedHistoryMilestone('2026-13-01'),null);
  c.app.data=[vehicle('unknown-od','00999',{dealerTransitClosedAt:'',deliveredToDealerDate:'',rftCollectedAt:'2026-09-04T00:00:00Z',lifecycleHistory:{},dateToPmb:'2026-02-30',dateToRft:'2026-09-03'})];
  const [v]=c.completedVehicleRows();assert.equal(c.completedHistoryMilestones(v).pmb,null);assert.equal(c.completedHistoryMilestones(v).delivered,null);c.renderCompletedVehicles();assert.match(c.nodes['completed-vehicles-content'].innerHTML,/Not recorded/);assert.match(c.nodes['completed-vehicles-content'].innerHTML,/Unknown/);assert.match(c.nodes['completed-pmb-statistics'].innerHTML,/0 of 1 vehicle with known dates/);
  const lines=c.completedHistoryCsv([v]).split('\n'),headers=lines[0].split(','),values=lines[1].split(',');const record=Object.fromEntries(headers.map((key,index)=>[key,values[index]]));assert.equal(record['OD Recorded'],'');assert.equal(record['OD Precision'],'unknown');assert.equal(record['RFT to OD Days'],'');assert.equal(record['Collected At'],'2026-09-04T00:00:00Z');
});
test('unlinked history with the same stock across dealers is retained as separate records',()=>{
  const c=runtime();c.app.data=[vehicle('canonical-a','00123',{client:'Canonical dealer customer'})];
  c.app.sharedNavisionVisibleRows=[{id:'dealer-a-record',dealer_code:'DEALER-A',stock_number:'00123',lifecycle_state:'completed',is_current:false,customer_name:'First unlinked customer',date_to_pmb:'2026-09-01'},{id:'dealer-b-record',dealer_code:'DEALER-B',stock_number:'00123',lifecycle_state:'completed',is_current:false,customer_name:'Second unlinked customer',date_to_pmb:'2026-09-02'}];
  const rows=c.completedHistoryRows();assert.equal(rows.length,3);assert.deepEqual(Array.from(rows.map(v=>v.client)).sort(),['Canonical dealer customer','First unlinked customer','Second unlinked customer']);
  const unlinked=rows.filter(v=>v.__sharedNavisionRecordId);assert.equal(unlinked.length,2);assert(unlinked.every(v=>!v.__emailVehicleId&&!v.canonicalVehicleId));assert.equal(unlinked.find(v=>v.__sharedNavisionDealerCode==='DEALER-A').dateToPmb,'2026-09-01');assert.equal(unlinked.find(v=>v.__sharedNavisionDealerCode==='DEALER-B').dateToPmb,'2026-09-02');
});
test('history shows Open only for an unambiguous matching local canonical record',()=>{
  const c=runtime(),mirror={id:'retained-open',canonical_vehicle_id:'canonical-a',stock_number:'00123',lifecycle_state:'completed',is_current:false,customer_name:'Historical customer'};
  c.app.sharedNavisionVisibleRows=[mirror];let [historical]=c.completedHistoryRows();assert.equal(c.completedHistoryCanOpen(historical),false);c.renderCompletedVehicles();assert.doesNotMatch(c.nodes['completed-vehicles-content'].innerHTML,/data-open-stock/);assert.match(c.nodes['completed-vehicles-content'].innerHTML,/<summary>Details<\/summary>/);
  c.app.data=[vehicle('canonical-other','00123')];assert.equal(c.completedHistoryCanOpen(historical),false,'a stock match alone must not open another canonical vehicle');
  c.app.data=[vehicle('canonical-a','00123'),vehicle('canonical-b','00123')];assert(c.completedHistoryRows().every(v=>c.completedHistoryCanOpen(v)===false));c.renderCompletedVehicles();assert.doesNotMatch(c.nodes['completed-vehicles-content'].innerHTML,/data-open-stock/);
  c.app.data=[vehicle('canonical-a','00123')];[historical]=c.completedHistoryRows();assert.equal(c.completedHistoryCanOpen(historical),true);c.renderCompletedVehicles();assert.match(c.nodes['completed-vehicles-content'].innerHTML,/data-open-stock="00123"/);assert.match(c.nodes['completed-vehicles-content'].innerHTML,/Open vehicle/);
});
