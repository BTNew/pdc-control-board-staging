/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r493b (F106b, Craig 22 Oct 2026, planner screenshot 6:43 pm): "Why are these ones showing in white? They should be black text."
// A started job that is Paused (amber, r493) and also running over its time (is-overtime) kept the overtime
// white text, so it could not be read on amber. Paused tiles use dark text; the amber 'Paused' label stays #92400e.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const read=f=>fs.readFileSync(f,'utf8');
const row=read('pdc-running-row.css'),plannerCss=read('workshop-planner.css'),index=read('index.html');
const rules=css=>css.replace(/\/\*[\s\S]*?\*\//g,'').match(/[^{}]+\{[^{}]*\}/g).map(r=>{const [sel,body]=r.split('{');return {selectors:sel.split(',').map(s=>s.trim()),body};});
const spec=s=>{const m=s.replace(/::?[a-z-]+(\([^)]*\))?/g,'').match(/\.[\w-]+|#[\w-]+|(?:^|[\s>+~])[a-z]+/g)||[];return [m.filter(x=>x.startsWith('#')).length,m.filter(x=>x.startsWith('.')).length,m.filter(x=>/^[\s>+~]?[a-z]/.test(x)).length];};
const beats=(a,b)=>{for(let i=0;i<3;i++){if(a[i]!==b[i])return a[i]>b[i];}return true;};// equal = later file wins (pdc-running-row.css loads after workshop-planner.css)

test('paused overtime chips use dark text (#0f172a !important) on the tile, its button and small text',()=>{
  for(const sel of ['.workshop-plan-chip.is-paused.is-overtime','.workshop-plan-chip.is-paused.is-overtime > button','.workshop-plan-chip.is-paused.is-overtime small']){
    const rule=rules(row).find(r=>r.selectors.includes(sel));
    assert.ok(rule,sel);
    assert.match(rule.body,/color:#0f172a !important/,sel);
  }
  assert.match(row,/\.workshop-plan-chip\.is-paused \.planner-work-state\.is-paused \{ color:#92400e !important; \}/);
});

test('the dark text out-ranks the overtime white text it replaces',()=>{
  assert.match(plannerCss,/\.workshop-plan-chip\.is-overtime > button,\n\.workshop-plan-chip\.is-overtime small \{ color: #fff !important; \}/);
  assert.ok(beats(spec('.workshop-plan-chip.is-paused.is-overtime > button'),spec('.workshop-plan-chip.is-overtime > button')));
  assert.ok(beats(spec('.workshop-plan-chip.is-paused.is-overtime small'),spec('.workshop-plan-chip.is-overtime small')));
  assert.ok(beats(spec('.workshop-plan-chip.is-paused.is-overtime'),spec('.workshop-plan-chip.is-overtime')));
});

test('a paused overtime tile stays amber: no red flash, no reduced-motion red background',()=>{
  const rule=rules(row).find(r=>r.selectors.includes('.workshop-plan-chip.is-started.is-paused.is-overtime'));
  assert.ok(rule);
  assert.match(rule.body,/background:#fef3c7/);assert.match(rule.body,/animation:none/);
  assert.match(plannerCss,/@media \(prefers-reduced-motion: reduce\) \{[\s\S]*?\.workshop-plan-chip\.is-overtime \{ background: #b91c1c; color: #fff; \}/);
  assert.ok(beats(spec('.workshop-plan-chip.is-started.is-paused.is-overtime'),spec('.workshop-plan-chip.is-overtime')));
});

test('other combos stay readable: ETA-risk and blocked never beat the amber tile; ETA-risk label keeps its red',()=>{
  const amber=spec('.workshop-plan-chip.is-started.is-paused');
  for(const sel of ['.workshop-plan-chip.is-eta-risk','.workshop-plan-chip.is-blocked','.workshop-plan-chip.is-overtime'])assert.ok(beats(amber,spec(sel)),sel);
  assert.match(plannerCss,/\.workshop-plan-chip \.workshop-eta-risk-label \{ color: #b91c1c !important; font-weight: 950; \}/);
  assert.match(row,/\.workshop-plan-chip\.is-paused\.is-overtime small\.workshop-eta-risk-label \{ color:#b91c1c !important; \}/);
  assert.ok(beats(spec('.workshop-plan-chip.is-paused.is-overtime small.workshop-eta-risk-label'),spec('.workshop-plan-chip.is-paused.is-overtime small')));
  // nothing in the running-row file sets white text
  assert.doesNotMatch(row.replace(/\/\*[\s\S]*?\*\//g,''),/color:\s*#fff\b/);
});

test('cache-bust: r493b on pdc-running-row.css; FAULT_LOG row F106b',()=>{
  assert.match(index,/pdc-running-row\.css\?running-row=2026\.10\.22\.r465&amp;r493=2026\.10\.22\.r493&amp;r493b=2026\.10\.22\.r493b"/);
  assert.match(read('docs/FAULT_LOG.md'),/\| F106b \|/);
});
