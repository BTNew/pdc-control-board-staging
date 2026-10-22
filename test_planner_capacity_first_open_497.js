/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r497 (F110): the first planner open after a page load must not throw
// "Cannot read properties of undefined (reading 'actor')" from pdc-planner-capacity.js.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'pdc-planner-capacity.js'), 'utf8');

test('cache reads are guarded before comparing service, actor and token', () => {
  assert.doesNotMatch(source, /cached\?\.service === current\.service && cached\.actor/);
  assert.doesNotMatch(source, /previous\?\.service === current\.service && previous\.actor/);
  assert.match(source, /if \(cached && cached\.service === current\.service && cached\.actor === current\.actor/);
  assert.match(source, /if \(previous && previous\.service === current\.service && previous\.actor === current\.actor/);
});

test('efficiencyPercent with an empty cache and no workshop service yet does not throw', () => {
  const start = source.indexOf('  function efficiencyPercent(stage, bay) {');
  const end = source.indexOf('\n  function loadConfiguration(stage) {', start);
  assert.ok(start > 0 && end > start);
  const body = source.slice(start, end);
  const sandbox = { result: undefined };
  vm.runInNewContext(`
    const configurationCache = new Map();
    const context = () => ({ actor: undefined, token: '', service: undefined });
    const referenceBay = () => null;
    const selectEfficiency = (row, ref) => (row ? 'row' : 'default');
    ${body}
    result = efficiencyPercent('MECH', 1);
  `, sandbox);
  assert.equal(sandbox.result, 'default');
});

test('index.html cache bust names r497 on pdc-planner-capacity.js', () => {
  const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  assert.match(html, /pdc-planner-capacity\.js\?[^"]*&amp;r497=2026\.10\.22\.r497"/);
});

test('Karratha keeps its frozen copy', () => {
  const karratha = fs.readFileSync(path.join(__dirname, 'karratha/pdc-planner-capacity.js'), 'utf8');
  assert.doesNotMatch(fs.readFileSync(path.join(__dirname, 'karratha/index.html'), 'utf8'), /r497=/);
  assert.ok(karratha.length > 0);
});
