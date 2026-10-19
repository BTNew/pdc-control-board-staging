'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('Broome Sales links the project icon instead of the site-root favicon.ico', () => {
  const html = fs.readFileSync(path.join(__dirname, 'sales/index.html'), 'utf8');
  const head = html.slice(html.indexOf('<head>'), html.indexOf('</head>'));
  const icon = head.match(/<link\s+rel="icon"\s+href="([^"]+)"\s+type="image\/svg\+xml">/);
  assert.ok(icon, 'sales head must declare an svg icon');
  assert.equal(icon[1], '../favicon.svg');
  assert.doesNotMatch(html, /favicon\.ico/);
  const resolved = path.resolve(__dirname, 'sales', icon[1]);
  assert.equal(path.basename(resolved), 'favicon.svg');
  assert.equal(fs.existsSync(resolved), true);
  assert.match(fs.readFileSync(resolved, 'utf8'), /<svg[\s>]/);
});
