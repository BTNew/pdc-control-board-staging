'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const start = app.indexOf('function aiBoardNormalizeStockIdentity');
const end = app.indexOf('function loadAiFileAssistantReviews');
assert.ok(start >= 0 && end > start, 'Phase Two advisor adapter/renderer block must exist');
const advisorBlock = app.slice(start, end);

assert.ok(advisorBlock.includes('function aiBoardAdvisorInput'), 'read-only DTO adapter must exist');
assert.ok(advisorBlock.includes('function renderAiBoardAdvisor'), 'advisor renderer must exist');
assert.ok(advisorBlock.includes("bookingCoverage: false, bookings: []"), 'shared mode without a snapshot must omit booking rules rather than fall back to stale local data');
assert.ok(advisorBlock.includes("window.PDC_SUPABASE_CONFIG?.workshop?.sharedData === true"), 'shared booking authority must be detected explicitly');
assert.ok(advisorBlock.includes("!['connected_read_only', 'connected_editable'].includes(service.getState())"), 'stale, loading, offline and permission-denied shared snapshots must be omitted');
assert.ok(advisorBlock.includes("booking?.booking_id || booking?.id"), 'shared booking IDs must use the authoritative snapshot DTO field');
assert.ok(advisorBlock.includes("booking?.vehicle?.id"), 'shared booking identity must come from its canonical nested vehicle UUID');
assert.ok(advisorBlock.includes("booking?.default_duration_minutes"), 'shared booking end time must use the authoritative duration when no end timestamp is supplied');
assert.ok(advisorBlock.includes('stageAgeLimitDays: pmbLaneAgeLimit(inferredPmbStage(vehicle))'), 'stage ageing must use the existing stage-specific operational threshold');
assert.ok(advisorBlock.includes("Math.max(50, priorityFindings.length)"), 'priority view must include every critical/high finding before capping review cards');
assert.ok(advisorBlock.includes('Human review:'), 'recommendations must be labelled as human review');
assert.ok(advisorBlock.includes('Coverage limit:'), 'missing booking coverage must be disclosed');
[
  'saveJson(',
  'saveVehicleEdits(',
  'saveAddedVehicles(',
  'runStorageTransaction(',
  'recordVehicleAudit(',
  '.mutate(',
  '.rpc(',
  'fetch(',
  'XMLHttpRequest',
  'WebSocket',
  'applyEmailReview(',
  'rejectEmailReview(',
].forEach(token => assert.ok(!advisorBlock.includes(token), `advisor adapter/renderer must not contain ${token}`));

assert.ok(css.includes('/* Phase 2 read-only AI Board Advisor. */'));
assert.ok(css.includes('.ai-board-advisor-panel'));
assert.ok(css.includes('.ai-board-finding.ai-board-critical'));

const pages = ['index.html', 'staging.html', 'test-50.html', 'test-75.html', 'test-100.html', 'no-vehicles.html'];
pages.forEach(file => {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  assert.strictEqual((html.match(/id="ai-board-advisor-title"/g) || []).length, 1, `${file} needs one labelled advisor heading`);
  assert.strictEqual((html.match(/id="ai-board-advisor-content"/g) || []).length, 1, `${file} needs one advisor result host`);
  assert.strictEqual((html.match(/id="ai-board-refresh"/g) || []).length, 1, `${file} needs one refresh-only advisor control`);
  assert.ok(html.includes('Advisory only'), `${file} must state the authority boundary`);
  assert.ok(html.includes('cannot change vehicles, bookings, Parts, workflow or messages'), `${file} must state prohibited changes`);
  const moduleIndex = html.indexOf('ai-board-advisor.js?');
  const appIndex = html.indexOf('app.js?');
  assert.ok(moduleIndex >= 0 && appIndex > moduleIndex, `${file} must load the pure advisor before app.js`);
  const sectionStart = html.indexOf('<section class="ai-board-advisor-panel"');
  const sectionEnd = html.indexOf('</section>', sectionStart);
  const section = html.slice(sectionStart, sectionEnd);
  ['Apply', 'Approve', 'Move vehicle', 'Complete', 'Send'].forEach(label => {
    assert.ok(!section.includes(`>${label}<`) && !section.includes(`>${label} `), `${file} advisor section must not expose mutating ${label} controls`);
  });
});

assert.ok(app.includes("on($('#ai-board-refresh'), 'click', renderAiBoardAdvisor);"), 'refresh control must only recalculate advice');
assert.ok(app.includes('renderAiBoardAdvisor();\n  updateAiFileAssistantButtons();'), 'advisor must render with the existing AI review view');

console.log('Phase Two advisory AI integration and authority contracts passed');
