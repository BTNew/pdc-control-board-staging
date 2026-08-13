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
['ai-auditor-operation-state', 'ai-auditor-operation-refresh', 'ai-auditor-operation-apply', 'ai-auditor-operation-undo'].forEach(id => assert.ok(auditorSection.includes(`id="${id}"`), `${id} signed-gateway control must exist`));
assert.ok(auditorSection.includes('Browser code never receives the scoped bot token or HMAC key'), 'website operation control must disclose the secret boundary');
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
assert.ok(block.includes("event: 'INSERT', schema: 'public', table: 'pdc_auditor_workshop_revisions'"), 'operation Realtime must observe INSERT only on migration-229 whole-run revisions');
assert.ok(!block.includes("table: 'pdc_auditor_revision'"), 'operation-control consumer must not use the legacy Stage A revision table');
assert.ok(block.includes("client.channel('pdc_auditor_workshop_revisions_read_only')"), 'operation Realtime channel must identify the migration-229 source');
assert.ok(block.includes('filter: `dealer_code=eq.${dealer}`'), 'Realtime invalidation must be explicitly filtered to the authenticated snapshot dealer');
assert.ok(block.includes('pdcAuditorRevisionCursor'), 'each browser consumer must maintain its own whole-run revision cursor');
assert.ok(block.includes('revision <= cursor') && block.includes('pdcAuditorRealtimePendingKeys.has(key)'), 'covered revisions and duplicate pending event keys must not trigger another refetch');
assert.ok(block.includes("'typed_plan_applied_253'") && block.includes("'typed_run_undone_253'"), 'migration-253 apply and undo events must invalidate snapshots');
assert.ok(block.includes("row?.environment !== 'staging'"), 'Realtime rows must be staging-only');
assert.ok(block.includes('pdcAuditorRealtimeUuid(row?.typed_run_id_253)'), 'typed migration-253 events must carry a UUID typed run identity');
assert.ok(block.includes('refreshPdcAuditorAfterRealtimeInvalidation'), 'Realtime refreshes must be serialized and coalesced');
assert.ok(block.includes('if (pending !== null) app.pdcAuditorRevisionCursor = String(pending)'), 'cursor advances only after successful authoritative refresh');
assert.ok(block.includes("status === 'SUBSCRIBED'") && block.includes('snapshot/subscription race'), 'subscription acknowledgement must reconcile the initial race');
assert.ok(block.includes("['CHANNEL_ERROR', 'TIMED_OUT', 'CLOSED'].includes(status)"), 'terminal channel states must invalidate and tear down');
assert.ok(app.includes('pdcAuditorRealtimePendingGeneration > app.pdcAuditorRealtimeCoveredGeneration'), 'hidden invalidation must refresh when the view is shown');
assert.ok(block.includes('Realtime is invalidation only'), 'Realtime events must refetch rather than become authority');
assert.ok(block.includes('pdcAuditorFilteredFindings'), 'display filters must be isolated from authoritative summary totals');
assert.ok(block.includes('function pdcAuditorOperationGatewayConfig'), 'operation control must use a separate configured gateway boundary');
assert.ok(block.includes("String(window.PDC_AUTH_CONTEXT?.role || '').toLowerCase() === 'administrator'"), 'browser confirmation must require authenticated Administrator authority');
assert.ok(block.includes("confirmation = action === 'apply' ? 'Apply these corrections'"), 'Apply must use the exact confirmation instruction');
assert.ok(block.includes("action === 'undo' ? 'Undo the selected Auditor run'"), 'Undo must use the exact runtime/SQL instruction');
assert.ok(block.includes('proposal_hash') && block.includes('run_revision_after'), 'operation confirmation must display immutable proposal/run bindings');
assert.ok(block.includes('No direct database fallback exists'), 'missing gateway must fail closed without direct RPC fallback');
assert.ok(!block.includes('PDC_AUDITOR_GATEWAY_HMAC_KEY_HEX') && !block.includes('PDC_AUDITOR_ACCESS_TOKEN'), 'browser source must contain no scoped bot or HMAC secret');
assert.ok(!block.includes('/rest/v1/rpc/apply_pdc_auditor_typed_plan_253') && !block.includes('/rest/v1/rpc/undo_last_pdc_auditor_typed_run_253'), 'browser must not bypass the signing gateway with direct typed RPC calls');
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
assert.ok(jobStart >= 0 && jobEnd > jobStart, 'compact work-row renderer must exist');
const jobBlock = app.slice(jobStart, jobEnd);
assert.ok(jobBlock.includes('<div class="vehicle-workshop-lines">'), 'Vehicle Detail must render compact work rows');
assert.ok(!jobBlock.includes('<table class="vehicle-workshop-job-card">') && !jobBlock.includes('scope="col"'), 'Vehicle Detail must not render the audit export table');
['Department', 'Provenance', 'Parts dependency / status', 'Sublet provider', 'Source ref', 'Completion'].forEach(label => assert.ok(!jobBlock.includes(`<th scope="col">${label}</th>`), `slimline Vehicle Detail must omit ${label}`));
assert.ok(jobBlock.includes('vehicle-workshop-line-description') && jobBlock.includes('vehicle-workshop-line-hours') && jobBlock.includes('vehicle-workshop-line-booking') && jobBlock.includes('vehicle-workshop-line-actions'), 'compact rows must retain description, hours, booking state and actions');
assert.ok(jobBlock.includes('vehicleWorkshopBookingsForLine'), 'line bookings must use explicit line relations rather than duplicating every station booking');
['Confirmed hours', 'Historical estimate', 'Supplier estimate', 'AI estimate', 'Unknown hours'].forEach(label => assert.ok(jobBlock.includes(label), `job-card must distinguish ${label}`));
assert.ok(app.includes("document.getElementById('ai-auditor')?.classList.contains('active')"), 'Vehicle Detail opened from the auditor must suppress all job-card edit controls');

console.log('Stage A AI Auditor, accessibility, source-boundary and job-card contracts passed');
