'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const html = read('staging.html');
const app = read('app.js');
const css = read('ai-auditor.css');

assert.strictEqual((html.match(/data-view="ai-auditor"/g) || []).length, 1, 'staging must expose one dedicated AI Auditor navigation item');
assert.ok(html.includes('>BETA – AI Auditor<'), 'navigation must use the exact beta label');
assert.strictEqual((html.match(/id="ai-auditor"/g) || []).length, 1, 'staging must expose one dedicated auditor view');
assert.ok(html.includes('BETA – READ ONLY / APPROVAL REQUIRED'), 'the persistent authority banner must be present in markup');
assert.ok(!html.includes('class="ai-board-advisor-panel"'), 'Board Advisor must be removed from staging AI Intake');
assert.ok(html.includes('ai-auditor.css?'), 'staging must load the isolated auditor stylesheet');

const auditorSection = html.slice(html.indexOf('<section id="ai-auditor"'), html.indexOf('<section id="sublet"'));
['Morning Workshop Briefing', 'Midday Risk Review', 'End-of-Day Carryover', 'Critical Issues'].forEach(label => assert.ok(auditorSection.includes(`>${label}<`), `${label} manual report view must exist`));
['Approve', 'Deny', 'Snooze'].forEach(label => assert.ok(new RegExp(`disabled[^>]*>${label}<|>${label}<[^]*?disabled`).test(auditorSection), `${label} must be visibly disabled`));
assert.ok(auditorSection.includes('Stage C decision workflow not enabled'), 'Stage C disabled copy must be exact');
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
assert.ok(snapshotDetailBlock.includes('BETA – READ ONLY / APPROVAL REQUIRED'), 'snapshot Vehicle Detail must retain the read-only authority banner');
assert.ok(!/(approve|deny|snooze|save|edit|delete|schedule|mutate|rpc\/)\s*[\("']/i.test(snapshotDetailBlock), 'snapshot Vehicle Detail fallback must expose no operational action path');
assert.ok(block.includes('Stage C decision workflow not enabled'), 'rendered decision state must preserve exact disabled copy');
assert.ok(block.includes('reportMembership') && block.includes('evaluated.reports'), 'manual report tabs must consume deterministic engine report projections');
assert.ok(block.includes('return result?.hasReportProjections ? explicitlyScoped : findings'), 'an intentionally empty deterministic report projection must remain empty rather than falling back to every finding');
assert.ok(block.includes('has_more: false') && block.includes('next_vehicle_id: null'), 'merged authoritative pagination must be normalized as complete before strict adaptation');
[
  'pdcSheetVehicles(', 'localStorage', 'sessionStorage', 'loadJson(', 'saveJson(',
  'saveVehicleEdits(', '.mutate(', 'applyEmailReview(', 'rejectEmailReview('
].forEach(token => assert.ok(!block.includes(token), `auditor block must not depend on ${token}`));
assert.ok(!/rpc\/[a-z0-9_]*(schedule|move|update|apply|approve|deny|snooze|send)/i.test(block), 'auditor block must contain no operational RPC endpoint');

assert.ok(css.includes('.ai-auditor-read-only-banner'), 'persistent read-only banner must be styled');
assert.ok(css.includes('.ai-auditor-summary-grid'), 'summary cards must be styled');
assert.ok(css.includes(':focus-visible'), 'auditor controls must have visible keyboard focus');
assert.ok(css.includes('@media (max-width: 760px)'), 'auditor view must have constrained-width treatment');

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
