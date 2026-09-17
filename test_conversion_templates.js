'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const catalog=require('./docs/conversion-templates.json'),ui=require('./pdc-conversions.js');
test('both model allocations retain supplied section minutes and exact totals',()=>{
 for(const [key,pre,install,total,n] of [['coaster',450,3315,3765,15],['hiace_commuter',300,1980,2280,16]]){
  const t=catalog[key];assert.equal(t.sections.length,n);assert.equal(t.sections.reduce((sum,s)=>sum+s.planned_minutes,0),total);
  assert.equal(t.preassembly_minutes,pre);assert.equal(t.installation_minutes,install);assert.equal(t.sections.filter(s=>s.provisional).length,1);assert.equal(t.sections.at(-1).id,'12');
 }
});
test('conversion renders child checkboxes, provisional release gate and separate labour fields',()=>{
 const c={...catalog.coaster,metadata:{},current_sections:[],remaining_minutes:3765,actual_minutes:0,release_blocked:true,sections:catalog.coaster.sections.map(s=>({...s,status:'not_started',remaining_minutes:s.planned_minutes}))};
 const html=ui.html({conversion:c,line_identity:'source:fixture',scope_hash:'hash',description:'4x4 Conversion',hours:60},{editable:true,controller:false,booking:'booking'});
 assert.equal((html.match(/name="completed"/g)||[]).length,15);
 assert.match(html,/62h 45m/);assert.match(html,/name="helper_minutes"/);assert.match(html,/name="repair_minutes"/);assert.match(html,/Release blocked/);
 assert.doesNotMatch(html,/data-fitter-line=/);assert.doesNotMatch(html,/data-conversion-mode="checklist"/);
 assert.match(ui.html({conversion:c,line_identity:'fixture',scope_hash:'hash'},{controller:true}),/data-conversion-mode="checklist"/);
});
test('unconfirmed models cannot tick a guessed conversion and source descriptions are escaped',()=>{
 const html=ui.html({description:'<img onerror=bad>',conversion:{needs_review:true}});
 assert.match(html,/scope needs review/);assert.doesNotMatch(html,/<img|<input|<button/);assert.equal(ui.duration(null),'Unknown');
});

