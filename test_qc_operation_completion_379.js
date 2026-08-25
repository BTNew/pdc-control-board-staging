'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const { mapServerVehicle, PDC_QC_OPERATION_COMPLETION_RPC } = require('./pdc-email-vehicle-location-service.js');

assert.strictEqual(PDC_QC_OPERATION_COMPLETION_RPC, 'set_pdc_qc_operation_completion_379');
const row = mapServerVehicle({ id: '00000000-0000-4000-8000-000000000379', stock_number: 'HERMES-TEST-QC-379', work_items: [], operation_lines: [], qc_operation_lines: [
  { line_identity: 'source:00000000-0000-4000-8000-000000000001', source_kind: 'authenticated', source_line_id: '00000000-0000-4000-8000-000000000001', operation_no: 'OP1', description: 'Duplicate description', job_card_number: 'HERMES-JC', estimated_hours: 0, stage_code: 'FITTING', active: true, completed: true, line_version: 2 },
  { line_identity: 'source:00000000-0000-4000-8000-000000000002', source_kind: 'authenticated', source_line_id: '00000000-0000-4000-8000-000000000002', operation_no: 'OP2', description: 'Duplicate description', job_card_number: 'HERMES-JC', estimated_hours: null, stage_code: 'FITTING', active: true, completed: false, line_version: 1 },
  { line_identity: 'manual:00000000-0000-4000-8000-000000000003', source_kind: 'manual', source_line_id: '00000000-0000-4000-8000-000000000003', operation_no: 'MANUAL', description: 'Audited manual line', estimated_hours: 1.25, stage_code: 'HOIST', active: true, completed: true, line_version: 1 },
  { line_identity: 'source:00000000-0000-4000-8000-000000000004', source_kind: 'authenticated', source_line_id: '00000000-0000-4000-8000-000000000004', operation_no: 'OP4', description: 'Relocated inactive line', estimated_hours: 2, stage_code: 'TYRE', active: false, completed: false, line_version: 0 },
] });
assert.strictEqual(row.pdcQcOperationLines.length, 3, 'inactive/deactivated lines are excluded');
assert.strictEqual(new Set(row.pdcQcOperationLines.map(line => line.lineIdentity)).size, 3, 'duplicate descriptions retain stable distinct identities');
assert.strictEqual(row.pdcQcOperationLines[0].estimatedHours, 0, 'explicit zero remains numeric zero');
assert.strictEqual(row.pdcQcOperationLines[1].estimatedHours, null, 'unknown hours remain null');

const missingProjectionRow = mapServerVehicle({ id: row.id, stock_number: 'HERMES-TEST-QC-MISSING', work_items: [], operation_lines: [] });
assert.strictEqual(missingProjectionRow.pdcQcOperationLinesProjectionPresent, false, 'missing QC projection is distinguishable from an empty projection');
assert.deepStrictEqual(missingProjectionRow.pdcQcOperationLines, [], 'missing QC projection remains fail-closed');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
assert.match(app, /const APP_VERSION = '2026\.08\.26\.02-qc-finalization-modal-identity'/);
assert.match(index, /pdc-email-vehicle-location-service\.js\?v=2026\.08\.26\.01-qc-finalization-399/);
assert.match(index, /app\.js\?v=2026\.08\.26\.02-qc-finalization-modal-identity/);
const start = app.indexOf('function qcPageOperationLines');
const end = app.indexOf('\nfunction qcPageVehicleCardHtml', start);
const context = {
  groupBy: (items, fn) => items.reduce((o, x) => ((o[fn(x)] ||= []).push(x), o), {}),
  escapeHtml: String,
  pmbStageLabel: value => value,
  qcPageVehicleKey: () => 'HERMES-TEST-QC-379',
  qcPageOperationPending: new Map(),
  qcPagePendingKey: (key, lineIdentity) => `${key}::${lineIdentity}`,
};
vm.createContext(context); vm.runInContext(app.slice(start, end), context);
assert.strictEqual(context.qcPageAllOperationLinesComplete(row), false);
const html = context.qcPageWorkItemsHtml(row);
assert.match(html, /OP1 · Duplicate description/);
assert.match(html, /OP2 · Duplicate description/);
assert.match(html, /0 h/);
assert.match(html, /Unknown hours/);
assert.match(html, /Audited manual line/);
assert.match(html, /data-qc-line-version="2"/);
assert.match(html, /data-qc-line-identity="source:00000000-0000-4000-8000-000000000002"[^>]*disabled[^>]*title="Unknown operation hours require review before QC completion"/);
const missingContext = {
  ...context,
  qcPageOperationLines: context.qcPageOperationLines,
};
vm.createContext(missingContext);
vm.runInContext(app.slice(start, end), missingContext);
const missingHtml = missingContext.qcPageWorkItemsHtml(missingProjectionRow);
assert.match(missingHtml, /QC operation lines are still loading/);
assert.match(missingHtml, /server snapshot is missing its QC projection/);
assert.doesNotMatch(missingHtml, /source operation evidence does not exist/i);

const sql = fs.readFileSync('supabase/staging_only/20260825160000_379_qc_per_operation_completion.sql', 'utf8');
for (const marker of ['pdc_qc_operation_completions_379','pdc_qc_operation_completion_history_379','pdc_qc_operation_completion_receipts_379',
  'set_pdc_qc_operation_completion_379','PDC_379_VEHICLE_VERSION_CONFLICT','PDC_379_LINE_VERSION_CONFLICT','PDC_379_IDEMPOTENCY_PAYLOAD_MISMATCH',
  'PDC_379_LINE_UNKNOWN_OR_INACTIVE','PDC_379_LINE_HOURS_UNKNOWN','pdc_qc_require_all_operations_complete_379','PDC_QC_OPERATION_LINES_INCOMPLETE_OR_UNKNOWN','department_complete'])
  assert.ok(sql.includes(marker), `migration missing ${marker}`);
assert.doesNotMatch(sql, /queue_vehicle_notification\s*\(/i);
console.log('QC per-operation completion contract: PASS');
