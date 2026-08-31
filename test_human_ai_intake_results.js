'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const appSource = fs.readFileSync('app.js', 'utf8');
const staging = fs.readFileSync('staging.html', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/071_human_ai_intake_change_summary.sql', 'utf8').toLowerCase();

function source(name, next) {
  const start = appSource.indexOf(`function ${name}`);
  const end = appSource.indexOf(`function ${next}`, start + 1);
  assert(start >= 0 && end > start, `Unable to extract ${name}`);
  return appSource.slice(start, end);
}

const context = {
  PDC_JOB_DEFS: [{ key: 'sublet', label: 'SUBLET' }, { key: 'parts', label: 'PARTS' }],
  escapeHtml: value => String(value ?? ''),
};
vm.createContext(context);
vm.runInContext(
  source('aiIntakeAuditChangeSummary', 'aiIntakeHumanOutcome')
  + source('aiIntakeHumanOutcome', 'aiIntakeHumanChangesHtml')
  + source('aiIntakeHumanChangesHtml', 'aiIntakeVehicleForStock'),
  context,
);

const activated = context.aiIntakeHumanOutcome({
  status: 'applied', action_type: 'review_only', board_activation_created: true,
  change_events: [{ action: 'insert', table_name: 'vehicles', before_data: null, after_data: { stock_number: '13032821' } }],
});
assert.strictEqual(activated.badge, 'CAR ACTIVATED');
assert(activated.changes.some(change => change.label === 'Control Board' && change.after === 'Car activated'));

const modified = context.aiIntakeHumanOutcome({
  status: 'applied', action_type: 'review_only',
  change_events: [{ action: 'update', table_name: 'vehicles', before_data: { customer_name: 'Old Name', current_location: 'PMB' }, after_data: { customer_name: 'New Name', current_location: 'PMB' } }],
});
assert.strictEqual(modified.badge, 'CAR MODIFIED');
assert.deepStrictEqual(JSON.parse(JSON.stringify(modified.changes)), [{ label: 'Customer', before: 'Old Name', after: 'New Name' }]);

const unchanged = context.aiIntakeHumanOutcome({ status: 'applied', action_type: 'review_only', change_events: [] });
assert.strictEqual(unchanged.badge, 'RECEIVED');
assert.strictEqual(unchanged.activated, false);
assert(/No recorded car changes/.test(unchanged.message));

assert(staging.includes('Successor receipt projection is read-only.'));
assert(staging.includes('id="pdc-email-ai-successor-inbox"'));
assert(staging.includes('id="ai-intake-legacy-fallback" hidden'));
assert(staging.includes('Approve or deny the items that need a decision.'));
assert(appSource.includes('Rows that need attention') && appSource.includes('Fix these rows in the source file'));
assert(appSource.includes('Cars activated or moved') && appSource.includes('Nothing was imported or changed'));
assert(appSource.includes('await enrichSharedNavisionPreviewChanges') && appSource.includes('navisionFieldChanges(existing.normalized_data || {}, incoming)'));
assert(styles.includes('.ai-intake-human-grid') && styles.includes('.navision-human-errors'));
assert(sql.includes("v_role is distinct from 'administrator'") && sql.includes("a.metadata->>'source_hash'=p.source_hash"));
assert(sql.includes("a.table_name in ('vehicles','vehicle_work_items','vehicle_parts_updates')"));
assert(sql.includes('board_activation_created') && sql.includes("n.action='board_activate'"));
assert(!sql.includes("'before_data',a.before_data") && !sql.includes("'after_data',a.after_data"), 'snapshot must expose only bounded staff-facing audit fields');
assert(appSource.includes('const previewItems = new Map') && appSource.includes('field_changes: previewItem.field_changes'), 'applied result must retain exact preview field changes');

console.log('Human AI Intake and Navision result tests passed');
