/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r470 (F83): after Find a workshop booking, the planner scrolled to the result on EVERY re-render (live refresh, clock
// update), so the page kept scrolling up and down by itself. It now scrolls (and pulses) once per selection.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const src=fs.readFileSync('workshop-planner.js','utf8');
const grab=name=>{const i=src.indexOf(`function ${name}(`);assert.ok(i>=0,name);let depth=0,j=src.indexOf('{',i);for(let k=j;k<src.length;k++){if(src[k]==='{')depth++;else if(src[k]==='}'){depth--;if(!depth)return src.slice(i,k+1);}}};
function harness(){
  const state={highlightVehicleKey:'',searchHighlightPlanId:'',highlightScrollRequest:0};
  const scrolls=[];const frames=[];
  const target={dataset:{workshopPlanId:'plan-1',workshopLocateKey:'veh-1'},classList:{remove(){}},getAttribute:()=>null,setAttribute(){},removeAttribute(){},focus(){},addEventListener(){},scrollIntoView:o=>scrolls.push(o)};
  let drawn=true;
  const root={querySelectorAll:sel=>drawn?[target]:[]};
  const ctx={state,scrolls,root,app:{},workshopState:()=>state,
    window:{requestAnimationFrame:f=>frames.push(f),matchMedia:()=>({matches:false}),setTimeout:()=>0,WorkshopNavigation:{replaceWorkshopHighlight(){}}}};
  vm.createContext(ctx);
  const code=src.slice(src.indexOf('let WORKSHOP_HIGHLIGHT_SCROLL_DONE'),src.indexOf('let WORKSHOP_HIGHLIGHT_SCROLL_DONE')+60).split('\n')[0]+'\n'+grab('workshopHighlightScrollSignature')+'\n'+grab('workshopScrollToHighlightedVehicle')+'\nthis.scroll=workshopScrollToHighlightedVehicle;';
  vm.runInContext(code,ctx);
  const render=()=>{ctx.scroll(root);while(frames.length)frames.shift()();};
  return {state,scrolls,render,setDrawn:v=>{drawn=v;}};
}
test('r470: one Find selection scrolls once, however many times the planner re-renders',()=>{
  const h=harness();
  h.state.highlightVehicleKey='veh-1';h.state.searchHighlightPlanId='plan-1';h.state.highlightScrollRequest++;
  for(let i=0;i<50;i++)h.render();          // live refreshes / clock updates
  assert.equal(h.scrolls.length,1);
  assert.equal(JSON.stringify(h.scrolls[0]),JSON.stringify({behavior:'smooth',block:'center',inline:'center'}));
});
test('r470: a new selection (even of the same booking) scrolls again once; clearing resets',()=>{
  const h=harness();
  h.state.searchHighlightPlanId='plan-1';h.state.highlightScrollRequest++;h.render();h.render();
  h.state.highlightScrollRequest++;h.render();h.render();
  assert.equal(h.scrolls.length,2);
  h.state.searchHighlightPlanId='';h.render();
  h.state.searchHighlightPlanId='plan-1';h.state.highlightScrollRequest++;h.render();h.render();
  assert.equal(h.scrolls.length,3);
});
test('r470: if the result is not drawn yet (planner still changing date), it scrolls on the first render where it appears',()=>{
  const h=harness();
  h.setDrawn(false);h.state.searchHighlightPlanId='plan-1';h.state.highlightScrollRequest++;h.render();h.render();
  assert.equal(h.scrolls.length,0);
  h.setDrawn(true);h.render();h.render();h.render();
  assert.equal(h.scrolls.length,1);
});
test('r470: every place that sets a highlight asks for exactly one scroll; workshop_clock_tick and app.js untouched',()=>{
  const sets=[...src.matchAll(/^\s*state\.(highlightVehicleKey|searchHighlightPlanId) = (?!'';)[^\n]+;\n(\s*state\.[^\n]+\n)?/gm)];
  assert.ok(sets.length>=6);
  const requests=(src.match(/state\.highlightScrollRequest = \(state\.highlightScrollRequest \|\| 0\) \+ 1;/g)||[]).length;
  assert.equal(requests,6);
  assert.doesNotMatch(src,/workshop_clock_tick/);
});
