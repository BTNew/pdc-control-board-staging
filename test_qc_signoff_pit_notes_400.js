'use strict';
// r400 (F09): QC must not require the external Pit inspection or job-card notes.
// Bhavesh, Key 208 / 13017935, 20 Oct 2026: "PIT AND WEIGH" (stage PIT_INSPECTION)
// could not be ticked, so "Sign off QC -> RFT" never appeared.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
function extract(name) {
  const start = app.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  let open = app.indexOf(') {', start) + 2, depth = 0;
  for (let i = open; i < app.length; i += 1) {
    if (app[i] === '{') depth += 1;
    if (app[i] === '}' && --depth === 0) return app.slice(start, i + 1);
  }
  throw new Error(name);
}
const ctx = {
  groupBy: (items, fn) => items.reduce((g, item) => ((g[fn(item)] ||= []).push(item), g), {}),
  escapeHtml: String, pmbStageLabel: v => v, qcPageVehicleKey: () => '13017935',
  qcPageOperationPending: new Map(), qcPagePendingKey: (k, l) => `${k}::${l}`,
};
vm.createContext(ctx);
vm.runInContext(['qcPageOperationLineIsDeferredPit', 'qcPageOperationLines', 'qcPageAllOperationLinesComplete', 'qcPageOperationHoursLabel', 'qcPageStageLabel', 'qcPageWorkItemsHtml'].map(extract).join('\n')
  + '\nthis.lines=qcPageOperationLines;this.done=qcPageAllOperationLinesComplete;this.html=qcPageWorkItemsHtml;', ctx);

const id = n => `source:0000000${n}-0000-4000-8000-00000000000${n}`;
const line = (n, stageCode, description, completed, hours = 1) => ({ lineIdentity: id(n), sourceKind: 'authenticated', sourceLineId: id(n).slice(7), operationNo: String(n), stageCode, description, estimatedHours: hours, completed, active: true, lineVersion: 0 });
const key208 = {
  pdcQcOperationLinesProjectionPresent: true, pdcEmailOperationLines: [],
  pdcQcOperationLines: [line(1, 'BUS_4X4', 'LED Lightbar - For Bull Bar', true), line(2, 'PIT_INSPECTION', 'PD018-B7100BA5 PIT AND WEIGH', false, 0.17), line(3, 'JOB_CARD_NOTES', 'PERTH DELIVERY', false, 0)],
};

test('Pit and job-card notes are not QC checklist lines', () => {
  assert.deepStrictEqual([...ctx.lines(key208)].map(l => l.stageCode), ['BUS_4X4']);
});
test('a 208-shaped vehicle is ready to sign off once the workshop work is ticked', () => {
  assert.strictEqual(ctx.done(key208), true);
  const open = { ...key208, pdcQcOperationLines: key208.pdcQcOperationLines.map((l, i) => i === 0 ? { ...l, completed: false } : l) };
  assert.strictEqual(ctx.done(open), false, 'real work still blocks sign-off');
});
test('Pit and notes show as information with no checkbox', () => {
  const html = ctx.html(key208);
  assert.match(html, /Not ticked in QC/);
  assert.match(html, /PIT AND WEIGH[\s\S]*external Department of Transport, after QC/);
  assert.match(html, /PERTH DELIVERY[\s\S]*information only/);
  assert.strictEqual((html.match(/type="checkbox"/g) || []).length, 1);
});
test('server migration uses the same rule and pins it', () => {
  const sql = fs.readFileSync('supabase/migrations/20261020114348_r400_qc_pit_notes_not_checkable.sql', 'utf8');
  for (const marker of ["'PIT_INSPECTION'", "'JOB_CARD_NOTES'", 'pdc_qc_line_not_checkable_400', 'pdc_qc_checkable_operation_lines_10700', 'pdc_qc_operation_line_is_deferred_pit_10700', 'pdc_ops.expected_function_md5', 'qc_checklist_has_only_tickable_lines', 'cdsmnqxtyyoeoznmbidd']) assert.ok(sql.includes(marker), marker);
  assert.ok(fs.existsSync('supabase/rollbacks/20261020114348_r400_qc_pit_notes_not_checkable.down.sql'));
});
