'use strict';
const fs = require('fs');
const assert = require('assert');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const appVersion = (app.match(/const APP_VERSION = '([^']+)'/) || [])[1];
assert.ok(appVersion, 'app.js must define APP_VERSION');
for (const file of ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html']) {
  const html = fs.readFileSync(file, 'utf8');
  assert.ok(html.includes('data-view="emailreview"'), `${file} missing AI Intake Review navigation`);
  assert.ok(html.includes('id="email-intake-review-content"'), `${file} missing AI Intake Review host`);
  assert.ok(html.includes('id="ai-intake-upload"'), `${file} missing AI file assistant upload control`);
  assert.ok(html.includes('id="ai-intake-status"'), `${file} missing AI file assistant status host`);
  assert.ok(html.includes('data-view="sublet"'), `${file} missing Sublet navigation`);
  assert.ok(html.includes('id="sublet-home-content"'), `${file} missing Sublet booking host`);
  assert.ok(html.includes(`app.js?v=${appVersion}`), `${file} has stale cache key`);
}
assert.ok(app.includes('function applyEmailReview('));
assert.ok(app.includes('function analyzeAiFileAssistantUploads('));
assert.ok(app.includes('AI_FILE_ASSISTANT_REVIEWS_KEY'));
assert.ok(app.includes("'Reviewed Parts email applied'"));
assert.ok(app.includes('function renderSubletHome('));
assert.ok(app.includes('pmbSubletExpectedReturnDate'));
assert.ok(app.includes('function draftSubletProviderEmail('));
assert.ok(app.includes('function draftSubletSalesUpdate('));
assert.ok(app.includes('data-email-vehicle-review'));
assert.ok(app.includes('<details class="email-review-row email-vehicle-review'));
assert.ok(app.includes("row.addEventListener('toggle'"));
assert.ok(app.includes('function aiIntakeStockNavigationHtml('), 'AI Intake must render a safe vehicle-card link for a uniquely matched Stock number');
assert.ok(app.includes('function bindAiIntakeStockNavigation('), 'AI Intake Stock links must open the vehicle card');
assert.ok(app.includes('matches.length === 1'), 'AI Intake Stock navigation must fail closed on duplicate or missing Stock matches');
assert.ok(app.includes('aiIntakeStockNavigationHtml(item.stock_number'), 'Server-authoritative AI Intake rows must expose Stock navigation');
assert.ok(app.includes('aiIntakeStockNavigationHtml(review.stock'), 'Local review rows must expose Stock navigation after a matching vehicle exists');
assert.ok((app.match(/bindAiIntakeStockNavigation\(/g) || []).length >= 3, 'Both server and local AI Intake renderers must bind Stock navigation');
assert.ok(css.includes('.email-review-summary'));
assert.ok(css.includes("content: 'Open review'"));
assert.ok(!css.includes('.sublet-row.sublet-overdue'), 'Simplified provider queue must not retain obsolete expected-return overdue styling');
console.log('Stage 2 staff automation checks passed');
