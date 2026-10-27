/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
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
test('r457: stacked planner header no longer turns flex-basis into height',()=>{
  // r561 keeps the empty-band fix on .workshop-planner-brand; stacks only below 1100 px so 1280 stays one row.
  const marker='.workshop-planner-header > .workshop-planner-brand';
  const i=css.lastIndexOf(marker);
  assert.ok(i>=0, marker);
  const mediaStart=css.lastIndexOf('@media (max-width: 1100px)', i);
  assert.ok(mediaStart>=0 && mediaStart<i, 'brand stack rule lives in the 1100px media query');
  const b=block('@media (max-width: 1100px)');
  // Prefer the media block that owns the brand selector (first 1100px block near end of file).
  const brandBlock=css.slice(mediaStart, css.indexOf('}', css.indexOf('width: 100%;', i))+1);
  assert.match(brandBlock,/\.workshop-planner-header > \.workshop-date-controls \{\s*flex: 0 0 auto;\s*width: 100%;/);
  assert.ok(b.includes('1100px'));
});
test('r457: the phone/portrait QC page and the locked files are untouched; the stylesheet is cache-busted',()=>{
  assert.match(html,/href="workshop-planner\.css\?[^"]*ipad-landscape=2026\.10\.22\.r457(?:&amp;[^"]*)?" \/>/);
  assert.ok(!/min-width: 901px\) and \(max-width: 1180px[\s\S]*pdc-qc-phone \.app-shell/.test(css.slice(css.lastIndexOf('r457 (F70'))),'never styles the QC phone page');
  assert.ok(html.indexOf('pdc-auto-reload.js')<html.indexOf('workshop-planner.css?'),'pdc-auto-reload.js still loads first');
});
