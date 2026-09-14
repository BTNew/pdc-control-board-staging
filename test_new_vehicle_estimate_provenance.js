const test=require('node:test');
const assert=require('node:assert/strict');
const {operationHoursPresentation:present,operationHoursHtml:html}=require('./pdc-new-vehicles.js');
const line=(extra={})=>({line_identity:'fixture-line',stage_code:'FITTING',estimated_hours:3,source_estimated_hours:3,source_contract:'pilbara_service_open_jobcards_v1',...extra});

test('AI estimate displays its effective time and review evidence',()=>{
  const item=line({hours_provenance:'ai_estimated',review_note:'Confirm kit fitment.',estimate_basis:'Comparable fitting allowance.'});
  assert.deepEqual(present(item),{label:'AI estimate · 3 hours',detail:'Confirm kit fitment.\nComparable fitting allowance.'});
  assert.match(html(item),/>AI estimate · 3 hours<\/small>$/);
});
test('Confirmed Tune hours are separate from AI estimates and unknown sources stay neutral',()=>{
  assert.equal(present(line({estimated_hours:1.25,source_estimated_hours:1.25,hours_provenance:'source_explicit'})).label,'Tune hours · 1.25 hours');
  assert.equal(present(line({source_contract:undefined,hours_provenance:undefined})).label,'Hours confirmed');
});
test('Tune label requires matching positive imported hours',()=>{
  for(const source of [0,null,undefined,'',1.5]){
    assert.equal(present(line({source_estimated_hours:source})).label,'Hours confirmed');
    assert.equal(present(line({source_estimated_hours:source,hours_provenance:'source_explicit'})).label,'Hours confirmed');
  }
  assert.equal(present(line({source_contract:undefined,hours_provenance:'source_explicit',source_estimated_hours:'3.00'})).label,'Tune hours · 3 hours');
});
test('unestimable scope is explicit until the user enters hours',()=>{
  const item=line({hours_provenance:'estimate_unable',estimated_hours:null,source_estimated_hours:0,review_note:'Confirm the number of rows.'});
  assert.deepEqual(present(item),{label:'Unable to estimate — confirm scope',detail:'Confirm the number of rows.'});
  assert.equal(present(item,{'fixture-line':1}).label,'Your estimate');
  assert.equal(present(item,{'fixture-line':''}).label,'Hours required before approval');
  assert.equal(present(item,{},'SUBLET').label,'Hours not required');
});
test('existing owner and description labels remain intact',()=>{
  assert.equal(present(line({hours_provenance:'craig_standard_pre_delivery_1_hour',estimated_hours:1})).label,'Pre-delivery · 1 hour standard');
  assert.equal(present(line({hours_provenance:'craig_electrical_default_1_5_hours',estimated_hours:1.5})).label,'Electrical default · 1.5 hours');
  assert.equal(present(line({hours_provenance:'explicit_description_time'})).label,'Estimate stated in description');
  assert.equal(present(line({hours_provenance:'craig_tyres_default_1_hour',estimated_hours:1})).label,'Hours confirmed');
});
test('edited hours replace the imported AI label and identify original basis',()=>{
  const item=line({hours_provenance:'ai_estimated',estimate_basis:'Original allowance'});
  const drafts={'fixture-line':'4.5'};
  assert.deepEqual(present(item,drafts),{label:'Your estimate',detail:'Original estimate basis: Original allowance'});
  assert.doesNotMatch(html(item,drafts),/AI estimate/);
  assert.equal(item.estimated_hours,3);
});
test('invalid edited and missing AI hours preserve the approval warning',()=>{
  for(const value of [null,undefined,'',0,'bad',Infinity,0.1666666]){
    assert.equal(present(line({hours_provenance:'ai_estimated',estimated_hours:value})).label,'Hours required before approval');
  }
  assert.equal(present(line({hours_provenance:'ai_estimated'}),{'fixture-line':''}).label,'Hours required before approval');
});
test('Sublet never displays an AI workshop-hour estimate',()=>{
  const item=line({hours_provenance:'ai_estimated',review_note:'Supplier fitting.'});
  assert.deepEqual(present(item,{},'SUBLET'),{label:'Hours not required',detail:'Supplier fitting.'});
  assert.doesNotMatch(html(item,{},'SUBLET'),/AI estimate/);
});
test('untrusted review evidence is escaped in markup',()=>{
  const item=line({hours_provenance:'ai_estimated',review_note:'" onmouseover="alert(1) <img src=x>',estimate_basis:"<script>alert('x')</script> & note"});
  const result=html(item);
  assert.doesNotMatch(result,/<img|<script|title="" onmouseover/);
  assert.match(result,/&quot; onmouseover=&quot;/);
  assert.match(result,/&lt;script&gt;alert\(&#39;x&#39;\)&lt;\/script&gt; &amp; note/);
});
test('missing or malformed evidence renders without meaningless tooltip text',()=>{
  assert.equal(html(line({review_note:null,estimate_basis:{page:1}})),'<small class="nv-hours-hint">Tune hours · 3 hours</small>');
  assert.equal(present().label,'Hours required before approval');
  assert.equal(present(line({review_note:' same ',estimate_basis:'same'})).detail,'same');
});
