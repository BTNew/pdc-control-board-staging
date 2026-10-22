/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r466 (F79): slimline Emergency vehicle priority panel (title, stock input and
// Preview on one row; explanatory text only in hover titles). Behaviour unchanged.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const index = fs.readFileSync(require.resolve('./index.html'), 'utf8');
const section = (/<section class="workshop-emergency[^"]*" id="workshop-emergency"[\s\S]*?<\/section>/.exec(index) || [''])[0];
const js = fs.readFileSync(require.resolve('./pdc-emergency-priority.js'), 'utf8');
const css = fs.readFileSync(require.resolve('./pdc-emergency-slim.css'), 'utf8');
const T1 = 'Enter a stock number to bring its remaining work forward';
const T2 = 'Running jobs stay in place.';

test('the panel keeps the input, buttons and result the module wires up', () => {
  assert.ok(section, 'panel present');
  assert.match(js, /getElementById\('workshop-emergency'\)/);
  assert.match(js, /host\.querySelector\('input'\)/);
  const firstInput = /<input[^>]*>/.exec(section)[0];
  assert.match(firstInput, /id="emergency-stock"/, "host.querySelector('input') is still the stock number input");
  assert.equal((section.match(/<input/g) || []).length, 1);
  for (const attr of ['data-emergency-preview', 'data-emergency-apply', 'data-emergency-cancel', 'data-emergency-result']) {
    assert.equal((section.match(new RegExp(`${attr}[ >]`, 'g')) || []).length, 1, attr);
    assert.match(js, new RegExp(`\\[${attr}\\]`), attr + ' still queried by the module');
  }
  assert.match(section, /<button class="small-button" type="button" data-emergency-preview[^>]*>Preview emergency schedule<\/button>/);
  assert.match(section, /<button class="primary" type="button" data-emergency-apply hidden>/);
  assert.match(js, /previewButton\.addEventListener\('click'/);
});

test('the explanatory text lines are gone from view and kept as hover titles', () => {
  assert.doesNotMatch(section, /<p[\s>]/);
  const visible = section.replace(/<[^>]*>/g, ' ').replace(/<span id="workshop-emergency-help" hidden>[\s\S]*?<\/span>/, '');
  const shown = section.replace(/<span id="workshop-emergency-help" hidden>[\s\S]*?<\/span>/, '').replace(/<[^>]*>/g, ' ');
  assert.ok(!shown.includes(T1) && !shown.includes(T2), 'no visible explanatory text');
  assert.ok(visible);
  assert.match(section, new RegExp(`<h3 id="workshop-emergency-title" title="${T1}[^"]*${T2}`));
  assert.match(section, new RegExp(`data-emergency-preview title="${T1}`));
});

test('slim CSS is separate, scoped, one row, red accent kept, loaded after the original CSS', () => {
  assert.match(index, /pdc-emergency-priority\.css\?v=2026\.09\.15\.01">\n<link rel="stylesheet" href="pdc-emergency-slim\.css\?emergency-slim=2026\.10\.22\.r466">/);
  assert.match(css, /#workshop-emergency\.workshop-emergency\.is-slim \{ display:flex; flex-wrap:wrap; align-items:center/);
  assert.match(css, /\.emergency-result \{ flex:1 0 100%/);
  assert.doesNotMatch(css, /border-left-color|background:/, 'red border and pink background come from the original CSS');
  css.split('\n').filter(line => /\{/.test(line) && !/^\s*@media|^\s*\/\*/.test(line)).forEach(line => assert.match(line, /^\s*#workshop-emergency/, line));
  assert.match(fs.readFileSync(require.resolve('./scripts/build_pages_runtime.js'), 'utf8'), /'pdc-emergency-slim\.css'/);
});
