'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const html = read('staging.html');
const app = read('app.js');
const css = read('ai-auditor.css');

assert.strictEqual((html.match(/data-view="ai-auditor"/g) || []).length, 1, 'staging must expose one dedicated AI Auditor navigation item');
assert.ok(html.includes('>AI Auditor<'), 'navigation must use the exact AI Auditor label');
assert.strictEqual((html.match(/id="ai-auditor"/g) || []).length, 1, 'staging must expose one dedicated auditor view');
assert.ok(html.includes('BETA – HUMAN REVIEW / NO AUTOMATIC CHANGES'), 'the persistent non-execution banner must be present in markup');
assert.ok(!html.includes('class="ai-board-advisor-panel"'), 'Board Advisor must be removed from staging AI Intake');
assert.ok(html.includes('ai-auditor.css?'), 'staging must load the isolated auditor stylesheet');

const auditorSection = html.slice(html.indexOf('<section id="ai-auditor"'), html.indexOf('<section id="sublet"'));
['Morning Workshop Briefing', 'Midday Risk Review', 'End-of-Day Carryover', 'Critical Issues'].forEach(label => assert.ok(auditorSection.includes(`>${label}<`), `${label} manual report view must exist`));
assert.ok(auditorSection.includes('Approval is not execution'), 'the decision safety boundary must be explicit');
assert.ok(!auditorSection.includes('>Snooze<'), 'the requested review workflow must expose only Approve and Deny');
assert.ok(auditorSection.includes('role="tablist"') && auditorSection.includes('role="tabpanel"'), 'manual report views must use accessible tab semantics');
assert.ok(auditorSection.includes('aria-live="polite"') && auditorSection.includes('aria-busy="true"'), 'auditor load state must be announced accessibly');
['ai-auditor-severity-filter', 'ai-auditor-category-filter', 'ai-auditor-search', 'ai-auditor-filter-summary'].forEach(id => assert.ok(auditorSection.includes(`id="${id}"`), `${id} must exist`));
assert.ok(auditorSection.includes('Authoritative totals are not changed by filters.'), 'filters must disclose that summary totals remain authoritative');
assert.ok(!/schedule|delivery|send|email|export|download/i.test(auditorSection.replace(/approval required/gi, '')), 'Stage A auditor must expose no scheduling or report-delivery surface');

const start = app.indexOf('const PDC_AUDITOR_CATEGORY_DEFS');
const end = app.indexOf('function loadAiFileAssistantReviews', start);
assert.ok(start >= 0 && end > start, 'isolated Stage A auditor implementation block must exist');
const block = app.slice(start, end);
[
  'critical_issues', 'high_priority', 'invalid_job_booking', 'missing_hours', 'parts_risk',
  'double_bookings', 'active_stoppages', 'forgotten_vehicles', 'workflow_problems', 'awaiting_approval'
].forEach(category => assert.ok(block.includes(`key: '${category}'`), `fixed ${category} summary category must exist`));
assert.ok(block.includes('function createPdcAuditorSnapshotService'), 'auditor must have a narrow service boundary');
assert.ok(block.includes("get_pdc_auditor_snapshot"), 'service must call only the auditor snapshot RPC');
assert.ok(block.includes('getAuditorSnapshot'), 'auditor UI must consume the narrowly named snapshot method');
assert.ok(block.includes('window.PdcAiAuditorStageA'), 'the pure Stage A engine must be consumed when available');
assert.ok(block.includes('generation !== lifecycleGeneration'), 'stale service callbacks must be generation guarded');
assert.ok(block.includes('authority !== auditorAuthorityIdentity()'), 'stale callbacks must be principal guarded');
assert.ok(block.includes('resetPdcAuditorAuthorityState'), 'auth loss must have one synchronous reset path');
assert.ok(block.includes('subscribePdcAuditorRealtime'), 'auditor must subscribe to revision invalidation');
assert.ok(block.includes("table: 'pdc_auditor_revision'"), 'Realtime must observe only the auditor revision table');
assert.ok(block.includes('filter: `dealer_code=eq.${dealer}`'), 'Realtime invalidation must be explicitly filtered to the authenticated snapshot dealer');
assert.ok(block.includes('Realtime is invalidation only'), 'Realtime events must refetch rather than become authority');
assert.ok(block.includes('pdcAuditorFilteredFindings'), 'display filters must be isolated from authoritative summary totals');
assert.ok(block.includes('Summary cards remain authoritative totals.'), 'filter result copy must preserve total semantics');
assert.ok(block.includes('View Evidence'), 'evidence disclosure must be plainly labelled');
assert.ok(block.includes('details class="ai-auditor-evidence"'), 'findings must expose a native keyboard-safe evidence drawer');
assert.ok(block.includes('data-ai-auditor-open-vehicle'), 'findings must expose Open Vehicle');
assert.ok(block.includes('function openPdcAuditorSnapshotVehicleDetail'), 'Open Vehicle must have an authenticated-snapshot read-only fallback');
assert.ok(block.includes("String(row?.vehicle_id || '').trim() === id"), 'snapshot Vehicle Detail fallback must require one exact authoritative vehicle identity');
const openVehicleStart = block.indexOf('function openPdcAuditorVehicle');
const openVehicleEnd = block.indexOf('function pdcAuditorSeverityRank', openVehicleStart);
const openVehicleBlock = block.slice(openVehicleStart, openVehicleEnd);
['selectedVehicle(', 'openVehicleModal(', 'emailVehicleLocationRows', '__workshopDataService'].forEach(token => assert.ok(!openVehicleBlock.includes(token), `Open Vehicle must never reach adjacent authority via ${token}`));
const snapshotDetailStart = block.indexOf('function openPdcAuditorSnapshotVehicleDetail');
const snapshotDetailEnd = block.indexOf('function openPdcAuditorVehicle', snapshotDetailStart);
const snapshotDetailBlock = block.slice(snapshotDetailStart, snapshotDetailEnd);
assert.ok(snapshotDetailBlock.includes('BETA – HUMAN REVIEW / NO AUTOMATIC CHANGES'), 'snapshot Vehicle Detail must retain the non-execution authority banner');
assert.ok(!/(approve|deny|snooze|save|edit|delete|schedule|mutate|rpc\/)\s*[\("']/i.test(snapshotDetailBlock), 'snapshot Vehicle Detail fallback must expose no operational action path');
assert.ok(block.includes('data-ai-auditor-decision="approved"') && block.includes('data-ai-auditor-decision="denied"'), 'rendered recommendations must expose Approve and Deny review controls');
assert.ok(block.includes('Approval is not execution') || html.includes('Approval is not execution'), 'decision rendering must preserve the non-execution boundary');
assert.ok(block.includes('operational_change !== false') && block.includes('execution_reference != null'), 'the client must reject any decision receipt that implies execution');
assert.ok(block.includes('reportMembership') && block.includes('evaluated?.projections?.reports'), 'manual report tabs must consume deterministic engine report projections');
assert.ok(block.includes('return result?.hasReportProjections ? explicitlyScoped : findings'), 'an intentionally empty deterministic report projection must remain empty rather than falling back to every finding');
assert.ok(block.includes('function pdcAuditorDecisionDate'), 'recorded Auditor decisions must use a dedicated safe date formatter');
assert.ok(!block.includes('formatDate(recorded.decidedAt)'), 'recorded decisions must not call an undefined generic date formatter');
assert.ok(block.includes('pdcAuditorDecisionDate(recorded.decidedAt)'), 'recorded decision rendering must call the tested Auditor formatter');
assert.ok(block.includes('has_more: false') && block.includes('next_vehicle_id: null'), 'merged authoritative pagination must be normalized as complete before strict adaptation');
[
  'pdcSheetVehicles(', 'localStorage', 'sessionStorage', 'loadJson(', 'saveJson(',
  'saveVehicleEdits(', '.mutate(', 'applyEmailReview(', 'rejectEmailReview('
].forEach(token => assert.ok(!block.includes(token), `auditor block must not depend on ${token}`));
assert.ok(!/rpc\/[a-z0-9_]*(schedule|move|update|apply|approve|deny|snooze|send)/i.test(block), 'auditor block must contain no operational RPC endpoint');

const projectionStart = block.indexOf('function pdcAuditorProjectedReports');
const projectionEnd = block.indexOf('function pdcAuditorEvaluateSnapshot', projectionStart);
const projectedReports = vm.runInNewContext(`(${block.slice(projectionStart, projectionEnd).replace(/^function pdcAuditorProjectedReports/, 'function')})`);
const projectionFixture = { projections: { reports: { morning: [{ recommendationId: 'one' }], midday: [], eod: [] } } };
assert.deepStrictEqual(JSON.parse(JSON.stringify(projectedReports(projectionFixture))), projectionFixture.projections.reports, 'engine-to-UI report projection boundary must execute against projections.reports');
assert.strictEqual(projectedReports({ reports: projectionFixture.projections.reports }), null, 'legacy top-level reports must not masquerade as the deterministic projection contract');
const evaluationEnd = block.indexOf('function resetPdcAuditorAuthorityState', projectionStart);
const engineFixture = {
  version: 'test',
  findings: [{ id: 'one' }, { id: 'two' }],
  projections: { reports: { morning: [{ recommendationId: 'one' }, { recommendationId: 'two' }], midday: [], eod: [{ recommendationId: 'two' }], critical: [] } },
};
const evaluationContext = vm.createContext({
  window: { PdcAiAuditorStageA: { analyze: () => engineFixture } },
  pdcAuditorNormalizeFinding: finding => finding,
  pdcAuditorBindReviewFindings: findings => findings,
  pdcAuditorSafeText: value => String(value),
});
vm.runInContext(block.slice(projectionStart, evaluationEnd), evaluationContext);
const boundaryResult = vm.runInContext('pdcAuditorEvaluateSnapshot({ revision: "r1" })', evaluationContext);
assert.deepStrictEqual(JSON.parse(JSON.stringify(boundaryResult.findings.map(finding => [finding.id, finding.report_views]))), [
  ['one', ['morning']],
  ['two', ['morning', 'eod']],
], 'engine report arrays and recommendationId membership must cross the UI boundary without fallback');
assert.strictEqual(boundaryResult.hasReportProjections, true, 'intentionally empty deterministic projections must remain authoritative');

assert.ok(css.includes('.ai-auditor-read-only-banner'), 'persistent read-only banner must be styled');
assert.ok(css.includes('.ai-auditor-summary-grid'), 'summary cards must be styled');
assert.ok(css.includes(':focus-visible'), 'auditor controls must have visible keyboard focus');
assert.ok(css.includes('@media (max-width: 760px)'), 'auditor view must have constrained-width treatment');
assert.ok(css.includes('padding-right: 68px'), 'vehicle modal read-only copy must reserve space for the close control');
assert.ok(css.includes('.vehicle-detail-page > .summary-grid article { display: grid; gap: 3px; }'), 'auditor snapshot detail labels and values must remain visually separated');

const jobStart = app.indexOf('function vehicleWorkshopJobCardValue');
const jobEnd = app.indexOf('function renderVehicleWorkshopWorkPage', jobStart);
assert.ok(jobStart >= 0 && jobEnd > jobStart, 'job-card column renderer must exist');
const jobBlock = app.slice(jobStart, jobEnd);
[
  'Description', 'Department', 'Estimated hours', 'Class', 'Provenance',
  'Booked / actual', 'Parts dependency / status', 'Sublet provider',
  'Booking', 'Status', 'Source ref', 'Completion'
].forEach(label => assert.ok(jobBlock.includes(label), `job-card must show ${label}`));
assert.ok(jobBlock.includes('scope="col"'), 'job-card columns must use accessible table headers');
assert.ok(jobBlock.includes('vehicleWorkshopBookingsForLine'), 'line bookings must use explicit line relations rather than duplicating every station booking');
['Confirmed hours', 'Historical estimate', 'Supplier estimate', 'AI estimate', 'Unknown hours'].forEach(label => assert.ok(jobBlock.includes(label), `job-card must distinguish ${label}`));
assert.ok(app.includes("document.getElementById('ai-auditor')?.classList.contains('active')"), 'Vehicle Detail opened from the auditor must suppress all job-card edit controls');

console.log('Stage A AI Auditor, accessibility, source-boundary and job-card contracts passed');
