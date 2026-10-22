/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

test('Department 135 page keeps its scripts unloaded unless the restore flag is set', () => {
  const html = fs.readFileSync('karratha/index.html', 'utf8');
  assert.match(html, /data-pd135-board="paused"/);
  assert.match(html, /Department 135 is paused/);
  assert.match(html, /records and history have been preserved/);
  assert.ok(html.includes('inert'));
  const scripts = [...html.matchAll(/<script\b[^>]*>/g)].map(match => match[0]);
  const executable = scripts.filter(tag => !tag.includes('type="text/plain"'));
  assert.deepEqual(executable, [
    '<script src="pd135-visibility.js">',
    '<script src="pd135-board-loader.js">',
  ]);
  assert.ok(scripts.length > 40);
  const visibility = fs.readFileSync('karratha/pd135-visibility.js', 'utf8');
  assert.match(visibility, /PDC135_BOARD_ENABLED = false/);
  const loader = fs.readFileSync('karratha/pd135-board-loader.js', 'utf8');
  assert.match(loader, /PDC135_BOARD_ENABLED !== true\) return/);
});

test('the department switch keeps Karratha hidden unless the same flag is set', () => {
  const source = fs.readFileSync('pd-department-navigation.js', 'utf8');
  function mounted(enabled) {
    const options = [];
    const select = {
      id: '',
      disabled: false,
      value: '',
      setAttribute() {},
      addEventListener() {},
      append(option) { options.push(option); },
    };
    const label = { className: '', dataset: {}, hidden: false, append() {} };
    const website = { insertAdjacentElement() {} };
    const document = {
      body: { dataset: {} },
      createElement: tag => tag === 'select' ? select : tag === 'option' ? { value: '', textContent: '' } : label,
      querySelector: () => website,
    };
    const window = { PDC135_BOARD_ENABLED: enabled, addEventListener() {}, location: { href: 'https://example.test/' } };
    vm.runInNewContext(source, { window, document, URL });
    return options.map(option => option.value);
  }
  assert.deepEqual(mounted(false), ['pmb']);
  assert.deepEqual(mounted(undefined), ['pmb']);
  assert.deepEqual(mounted(true), ['pmb', 'karratha']);
  for (const file of ['index.html', 'sales/index.html']) {
    assert.equal(fs.readFileSync(file, 'utf8').includes('pd-department-navigation'), false, file);
  }
});
