'use strict';
// r457 (F70, Craig 22 Oct, decision 5): iPad landscape / small laptops (901-1300 px). Frontend only, outside the
// locked styles.css. Screenshots at 1366, 1180, 1100 and 1024 px are in the release log (1366 unchanged).
// No database change, so no daily database check; this test is the check.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const css=fs.readFileSync('workshop-planner.css','utf8'),html=fs.readFileSync('index.html','utf8');
const block=(q)=>{const i=css.lastIndexOf(q);assert.ok(i>=0,q);let d=0,j=css.indexOf('{',i);for(let k=j;k<css.length;k++){if(css[k]==='{')d++;else if(css[k]==='}'&&--d===0)return css.slice(i,k+1);}throw new Error('unclosed '+q);};
test('r457: from 901 to 1180 px the side menu keeps one item per row and stays in view (not the stacked swipe grid)',()=>{
  const b=block('@media (min-width: 901px) and (max-width: 1180px)');
  assert.match(b,/:not\(\.pdc-qc-phone\)[^{]*:not\(\.sidebar-collapsed\) > \.sidebar \.nav \{\s*grid-template-columns: minmax\(0, 1fr\) !important;/);
  assert.match(b,/\.nav-scroll-cue \{\s*display: none !important;/);
  assert.match(b,/position: sticky;/);
});
test('r457: up to 1300 px the stacked planner header no longer turns flex-basis into height',()=>{
  const b=block('@media (max-width: 1300px) {\n  .workshop-planner-header > div:first-child');
  assert.match(b,/\.workshop-planner-header > \.workshop-date-controls \{\s*flex: 0 0 auto;\s*width: 100%;/);
});
test('r457: the phone/portrait QC page and the locked files are untouched; the stylesheet is cache-busted',()=>{
  assert.match(html,/href="workshop-planner\.css\?[^"]*ipad-landscape=2026\.10\.22\.r457" \/>/);
  assert.ok(!/min-width: 901px\) and \(max-width: 1180px[\s\S]*pdc-qc-phone \.app-shell/.test(css.slice(css.lastIndexOf('r457 (F70'))),'never styles the QC phone page');
  assert.ok(html.indexOf('pdc-auto-reload.js')<html.indexOf('workshop-planner.css?'),'pdc-auto-reload.js still loads first');
});
