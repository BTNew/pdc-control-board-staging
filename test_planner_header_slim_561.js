/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r561 (F175): Workshop Planner top chrome is one slim header. Frontend only; no SQL.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

const headerStart = source.indexOf('<header class="workshop-planner-header">');
const headerEnd = source.indexOf('</header>', headerStart);
assert.ok(headerStart >= 0 && headerEnd > headerStart, 'planner header markup exists');
const header = source.slice(headerStart, headerEnd);

test('r561: single small planner title sits in the header brand row', () => {
  assert.match(header, /workshop-planner-brand/);
  assert.match(header, /workshop-planner-title/);
  assert.equal((header.match(/<h2/g) || []).length, 1);
  assert.doesNotMatch(header, /<p>/);
  assert.doesNotMatch(source, /\$\{sharedBanner\}\s*<header class="workshop-planner-header">/);
});

test('r561: connection status is a blue/grey/red dot with tooltip, not a full banner', () => {
  assert.match(source, /workshop-connection-dot/);
  assert.match(source, /title="\$\{label\}"/);
  assert.match(source, /aria-label="\$\{label\}"/);
  const ok = css.match(/\.workshop-connection-ok\s*\{[^}]+\}/);
  const warn = css.match(/\.workshop-connection-warn\s*\{[^}]+\}/);
  const error = css.match(/\.workshop-connection-error\s*\{[^}]+\}/);
  assert.ok(ok && warn && error, 'connection colour rules exist');
  assert.match(ok[0], /#2563eb/);
  assert.match(warn[0], /#64748b/);
  assert.match(error[0], /#dc2626/);
  assert.doesNotMatch(`${ok[0]}\n${warn[0]}\n${error[0]}`, /#fef3c7|#fbbf24|#f59e0b|orange/i);
});

test('r561: header controls and handlers still exist in one date-controls row', () => {
  assert.match(header, /data-workshop-date/);
  assert.match(header, /data-workshop-date-shift="-1"/);
  assert.match(header, /data-workshop-date-shift="1"/);
  assert.match(header, /data-workshop-today/);
  assert.match(header, /data-workshop-refresh-vehicle/);
  assert.match(header, /data-workshop-add-admin-block/);
  assert.match(header, /workshop-header-primary-extras/);
  assert.match(header, /workshop-header-more/);
  const chrome = source.slice(source.indexOf('const primaryExtras'), headerEnd);
  assert.match(chrome, /data-workshop-admin-palette/);
  assert.match(chrome, /data-workshop-admin-palette-tile/);
  assert.match(chrome, /data-workshop-admin-palette-unit/);
  assert.match(chrome, /data-workshop-admin-palette-duration/);
  assert.match(chrome, /data-workshop-parts-warning/);
  assert.match(fs.readFileSync('pdc-planner-capacity.js', 'utf8'), /data-planner-close-gaps/);
  assert.match(fs.readFileSync('pdc-planner-capacity.js', 'utf8'), /data-workshop-refresh-vehicle/);
});

test('r561: app Sign out stays reachable and the duplicate page title is collapsed on workshop view', () => {
  assert.match(html, /id="pdc-auth-signout"/);
  assert.match(html, /id="page-title"/);
  assert.match(css, /body\[data-current-view="workshop"\] \.main > \.topbar/);
  assert.match(css, /#pdc-auth-signout/);
});

test('r561: search row stays the two-box Find control', () => {
  assert.match(source, /data-workshop-search-key/);
  assert.match(source, /data-workshop-search[^-]/);
  assert.match(source, /data-workshop-search-clear/);
});

test('r561: cache-bust tags the planner script and stylesheet', () => {
  assert.equal((app.match(/r561=2026\.10\.27\.r561/g) || []).length, 2);
  assert.match(html, /workshop-planner\.css\?[^"]*r561=2026\.10\.27\.r561/);
});
