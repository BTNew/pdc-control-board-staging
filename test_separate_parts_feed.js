const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');
function context() {
  const c = {window:{PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd'}},
    importedPartsStatus:v=>v.pdcPartsFlags,
    partsStateComplete:v=>v.pdcPartsReceived===true,
    partsDepartmentStatusClass:()=> 'parts-status-unknown',partsLastUpdateLabel:()=>'',importedPartsTitle:()=>'',
    partsMatchesOperationalFilter:(v, f)=>v.legacyFilter===f,
    partsWorstEtaDaysUntil:v=>v.days,
    isActivePartsStoppage:v=>v.stoppage===true,
    escapeHtml:s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('"','&quot;'),
    partsQueueRowHtml:()=>'<tr><td><span class="parts-status-pill parts-status-ordered">Parts outstanding</span></td></tr>'};
  vm.createContext(c);vm.runInContext(fs.readFileSync('pdc-parts-confirmation.js','utf8'),c);return c;
}
test('a legacy received tick cannot hide an active R/O backorder',()=>{
  const c=context(); assert.equal(c.partsStateComplete({pdcPartsReceived:true,pdcPartsFlags:{feed:'separate_parts_status',parts_complete:false,colour:'orange'}}),false);
  assert.equal(c.partsDepartmentStatusClass('import:Parts outstanding — see job cards'),'parts-status-ordered');
});
test('all-active-job readiness supplies the green tick',()=>{
  const c=context();assert.equal(c.partsStateComplete({pdcPartsFlags:{feed:'separate_parts_status',parts_complete:true}}),true);
});
test('unresolved zero flags are not complete even with an old received flag',()=>{
  assert.equal(context().partsStateComplete({pdcPartsReceived:true,pdcPartsFlags:{feed:'separate_parts_status',parts_complete:false,colour:'grey'}}),false);
});
test('job detail identifies separate R/Os and PO coverage',()=>{
  const title=context().importedPartsTitle({pdcPartsFlags:{feed:'separate_parts_status',label:'Parts outstanding',jobs:[{job_number:'J1',company:'01',division:'1',label:'Parts attached — no recorded backorders'},{job_number:'J2',company:'01',division:'1',label:'Parts outstanding — check PO'}]}});
  assert.match(title,/R\/O J1/);assert.match(title,/R\/O J2.*check PO/);assert.match(title,/Parts snapshot: Not recorded/);
});
test('explicit Wayne confirmation retains its separate owner-authorised priority',()=>{
  assert.equal(context().partsStateComplete({pdcPartsFlags:{parts_complete:true,override_source:'authorised_email_confirmation'}}),true);
});
test('separate orange and unresolved flags enter the correct Parts filters',()=>{
  const c=context();
  const orange={pdcPartsFlags:{feed:'separate_parts_status',colour:'orange',parts_complete:false}};
  const grey={pdcPartsFlags:{feed:'separate_parts_status',colour:'grey',parts_complete:false}};
  assert.equal(c.partsMatchesOperationalFilter(orange,'ordered'),true);
  assert.equal(c.partsMatchesOperationalFilter(orange,'notordered'),false);
  assert.equal(c.partsMatchesOperationalFilter(grey,'notordered'),true);
  assert.equal(c.partsMatchesOperationalFilter(grey,'ordered'),false);
  assert.equal(c.partsMatchesOperationalFilter({...grey,days:null},'overdue'),false);
  assert.equal(c.partsMatchesOperationalFilter({...orange,days:-1},'overdue'),true);
  assert.equal(c.partsMatchesOperationalFilter({...orange,stoppage:true},'stoppage'),true);
  assert.equal(c.partsMatchesOperationalFilter({legacyFilter:'ordered'},'ordered'),true);
});
test('parts rows show each R/O and escape source labels',()=>{
  const html=context().partsQueueRowHtml({pdcPartsFlags:{feed:'separate_parts_status',label:'Parts outstanding',jobs:[
    {job_number:'J1',label:'Ready'},{job_number:'J2',label:'Outstanding <unsafe>'}]}});
  assert.match(html,/R\/O J1: Ready/);assert.match(html,/R\/O J2: Outstanding &lt;unsafe>/);
  assert.match(html,/title="/);assert.doesNotMatch(html,/<unsafe>/);
});
