'use strict';
const fs = require('fs');
const assert = require('assert');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
for (const file of ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html']) {
  const html = fs.readFileSync(file, 'utf8');
  assert.ok(html.includes('data-view="emailreview"'), `${file} missing AI Intake Review navigation`);
  assert.ok(html.includes('id="email-intake-review-content"'), `${file} missing AI Intake Review host`);
  assert.ok(html.includes('data-view="sublet"'), `${file} missing Sublet navigation`);
  assert.ok(html.includes('id="sublet-home-content"'), `${file} missing Sublet booking host`);
  assert.ok(html.includes('2026.07.14.13-workshop-safety-hardening'), `${file} has stale cache key`);
}
assert.ok(app.includes('function applyEmailReview('));
assert.ok(app.includes("'Reviewed Parts email applied'"));
assert.ok(app.includes('function renderSubletHome('));
assert.ok(app.includes('pmbSubletExpectedReturnDate'));
assert.ok(app.includes('function draftSubletProviderEmail('));
assert.ok(app.includes('function draftSubletSalesUpdate('));
assert.ok(css.includes('.email-review-row'));
assert.ok(css.includes('.sublet-row.sublet-overdue'));
console.log('Stage 2 staff automation checks passed');
