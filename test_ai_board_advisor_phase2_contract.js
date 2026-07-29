'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const dataService = fs.readFileSync(path.join(root, 'workshop-data-service.js'), 'utf8').replace(/\r\n/g, '\n');
const auth = fs.readFileSync(path.join(root, 'pdc-auth.js'), 'utf8');
const start = app.indexOf('function aiBoardNormalizeStockIdentity');
const end = app.indexOf('function loadAiFileAssistantReviews');
assert.ok(start >= 0 && end > start, 'Phase Two advisor adapter/renderer block must exist');
const advisorBlock = app.slice(start, end);

assert.ok(advisorBlock.includes('function aiBoardAdvisorInput'), 'read-only DTO adapter must exist');
assert.ok(advisorBlock.includes('function renderAiBoardAdvisor'), 'advisor renderer must exist');
assert.ok(advisorBlock.includes("bookingCoverage: false, bookingSource: 'shared'"), 'shared mode without a trusted snapshot must omit booking rules rather than fall back to stale local data');
assert.ok(advisorBlock.includes("window.PDC_SUPABASE_CONFIG?.workshop?.sharedData === true"), 'shared booking authority must be detected explicitly');
assert.ok(advisorBlock.includes("typeof service.getTrustedSnapshot !== 'function'"), 'shared advice must require the narrow trusted-snapshot API');
assert.ok(advisorBlock.includes('const snapshot = service.getTrustedSnapshot()'), 'shared advice must never consume the retained planner snapshot directly');
assert.ok(dataService.includes('let snapshotTrusted = false'), 'data service must track advisory trust separately from retained planner data');
assert.ok(dataService.includes('getTrustedSnapshot: () => ('), 'data service must expose a fail-closed advisory snapshot accessor');
assert.ok(dataService.includes('result.status === 401 || result.status === 403') && dataService.includes('invalidateAuthority(WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED)'), '401/403 responses must atomically purge snapshot authority and surface permission denial');
assert.ok(dataService.includes('if (!token)'), 'advisory snapshot loads must require positive individual access-token evidence');
assert.ok(dataService.includes('if (destroyed || generation !== lifecycleGeneration) return null'), 'late in-flight snapshot responses must be generation-guarded after teardown');
assert.ok(dataService.includes('lastSnapshot = null;\n    lastRevision = null;'), 'service teardown must purge retained prior-session snapshot data');
assert.ok(dataService.includes("return { ok: false, error: 'destroyed', state };"), 'captured destroyed services must expose no mutation path');
assert.ok(advisorBlock.includes("booking?.booking_id || booking?.id"), 'shared booking IDs must use the authoritative snapshot DTO field');
assert.ok(advisorBlock.includes("booking?.vehicle_id || booking?.vehicle?.id"), 'shared booking identity must prefer the canonical minimal DTO vehicle_id');
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

const pages = ['index.html', 'test-50.html', 'test-75.html', 'test-100.html', 'no-vehicles.html'];
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

assert.ok(app.includes("on($('#ai-board-refresh'), 'click', () => renderAiBoardAdvisor());"), 'refresh control must recalculate with a fresh valid clock rather than passing the click event as nowIso');
assert.ok(app.includes('renderAiBoardAdvisor();\n  updateAiFileAssistantButtons();'), 'advisor must render with the existing AI review view');
assert.ok(auth.includes("new CustomEvent('pdc-auth-locked'"), 'every session revalidation/teardown must dispatch the operational-data lock event');
const lockHandler = app.slice(app.indexOf("window.addEventListener?.('pdc-auth-locked'"), app.indexOf('function renderWorkshopPlannerWhenReady'));
assert.ok(lockHandler.includes("document.getElementById('ai-board-advisor-content')"), 'auth lock handler must target the rendered advisor data');
assert.ok(lockHandler.includes('advisorHost.replaceChildren()'), 'auth lock handler must clear prior-session advisory business data');
const staging = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');
assert.strictEqual((staging.match(/id="ai-board-advisor-title"/g) || []).length, 0, 'staging moves Board Advisor out of AI Intake');
assert.ok(staging.includes('id="ai-auditor"') && staging.includes('BETA – READ ONLY / APPROVAL REQUIRED'), 'staging must expose the separate Stage A Auditor');

console.log('Phase Two advisory AI integration and authority contracts passed');
