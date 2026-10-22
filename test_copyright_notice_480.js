/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r480 (F93): copyright / proprietary notice. Footer on the board, Sales and sign-in screens; LICENSE at the root;
// package.json UNLICENSED; locked and pinned files untouched.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8');
const NOTICE = '© 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved.';
const FOOTER = `<small class="pdc-copyright" data-pdc-copyright>${NOTICE}</small>`;

test('LICENSE exists and is a proprietary all-rights-reserved licence for the owner', () => {
  const lic = read('LICENSE');
  assert.match(lic, /Specialise Pty Ltd ATFT Specialise Trust \(ABN 33 539 964 819\)/);
  assert.match(lic, /All rights reserved/);
  for (const word of [/copy/i, /modify/i, /distribute/i, /sublicense/i, /resell/i, /commercial/i, /written permission/i, /authorised/i, /Broome Toyota/, /PMG/])
    assert.match(lic, word);
  assert.doesNotMatch(lic, /legal advice|solicitor/i, 'the legal-advice note belongs in the release README, not the LICENSE');
});

test('the copyright footer is on the board sidebar and sign-in screen (index.html)', () => {
  const html = read('index.html');
  assert.equal(html.split(FOOTER).length - 1, 2);
  const gate = html.slice(html.indexOf('<main class="pdc-auth-gate"'), html.indexOf('</main>') + 7);
  assert.ok(gate.includes(FOOTER), 'sign-in screen');
  const aside = html.slice(html.indexOf('<aside class="sidebar"'), html.indexOf('</aside>'));
  assert.ok(aside.trimEnd().endsWith(FOOTER), 'last item in the sidebar');
  assert.match(html, /<link rel="stylesheet" href="pdc-copyright\.css\?copyright=2026\.10\.22\.r480">/);
});

test('the copyright footer is on the Sales sidebar and Sales sign-in screen', () => {
  const html = read('sales/index.html');
  assert.equal(html.split(FOOTER).length - 1, 2);
  assert.ok(html.slice(html.indexOf('<aside class="sidebar"'), html.indexOf('</aside>')).endsWith(FOOTER));
  assert.match(html, /<link rel="stylesheet" href="\.\.\/pdc-copyright\.css\?copyright=2026\.10\.22\.r480">/);
});

test('footer styling is small grey text pushed to the sidebar foot, hidden when collapsed', () => {
  const css = read('pdc-copyright.css');
  assert.match(css, /\.pdc-copyright \{[^}]*font-size: 10px;[^}]*\}/s);
  assert.match(css, /\.pdc-copyright \{[^}]*color: #8a94a3;/s);
  assert.match(css, /\.sidebar > \.pdc-copyright \{[^}]*margin-top: auto;/s);
  assert.match(css, /\.app-shell\.sidebar-collapsed \.sidebar > \.pdc-copyright/);
  assert.ok(read('scripts/build_pages_runtime.js').includes("'pdc-copyright.css',"), 'published with the Pages artifact');
});

test('package.json is private and UNLICENSED', () => {
  const pkg = JSON.parse(read('package.json'));
  assert.equal(pkg.private, true);
  assert.equal(pkg.license, 'UNLICENSED');
});

test('own source carries the header; locked, pinned, vendored and migration files do not', () => {
  for (const f of ['pdc-copyright.css', 'pdc-vehicle-slideout.js', 'sales/sales.js', 'sales/sales.css', 'scripts/build_pages_runtime.js'])
    assert.match(read(f).slice(0, 400), /Specialise Pty Ltd ATFT Specialise Trust/, f);
  for (const f of ['app.js', 'styles.css', 'workshop-planner.js', 'canonical-entry.js', 'vendor/pdfjs/pdf.min.js'])
    assert.doesNotMatch(read(f).slice(0, 2000), /Specialise Pty Ltd/, f);
  const mig = fs.readdirSync(path.join(root, 'supabase/migrations')).filter((f) => f.endsWith('.sql'));
  assert.ok(mig.length > 0);
  for (const f of mig) assert.doesNotMatch(read(path.join('supabase/migrations', f)).slice(0, 400), /Specialise Pty Ltd/, f);
});
