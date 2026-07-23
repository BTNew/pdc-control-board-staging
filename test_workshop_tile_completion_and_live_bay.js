'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = __dirname;
const planner = require('./workshop-planner.js');
const source = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/migrations/050_workshop_tile_completion_and_live_bay.sql'), 'utf8');
const applyScript = fs.readFileSync(path.join(root, 'scripts/apply_migration_050_staging.py'), 'utf8');

global.escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const startedActions = planner.workshopPlanLifecycleActionsHtml({ id: 'started-1', status: 'started' });
assert.match(startedActions, /data-workshop-stop-plan="started-1"[^>]*>STOPPAGE</, 'Started tile must expose generic STOPPAGE');
assert.match(startedActions, /data-workshop-complete-plan="started-1"[^>]*>Complete</, 'Started tile must expose Complete');
const stoppedActions = planner.workshopPlanLifecycleActionsHtml({ id: 'stopped-1', status: 'stoppage' });
assert.match(stoppedActions, /data-workshop-resume-plan="stopped-1"[^>]*>Resume job</, 'Stopped tile must retain Resume job');
assert.match(stoppedActions, /data-workshop-complete-plan="stopped-1"[^>]*>Complete</, 'Stopped tile must expose Complete');
assert.strictEqual(planner.workshopPlanLifecycleActionsHtml({ id: 'done-1', status: 'completed' }), '', 'Completed work must remain uneditable');

const conflictRows = [
  { id: 'fab-live', stage: 'FABRICATION', bay: 1, status: 'started' },
  { id: 'fab-planned', stage: 'FABRICATION', bay: 1, status: 'planned' },
  { id: 'tint-live', stage: 'TINT', bay: 1, status: 'started' },
];
assert.strictEqual(planner.workshopStartedBayConflict({ id: 'new-fab', stage: 'FABRICATION', bay: 1 }, conflictRows).id, 'fab-live', 'A bay must reject a second started job');
assert.strictEqual(planner.workshopStartedBayConflict({ id: 'new-tint', stage: 'TINT', bay: 1 }, [conflictRows[0]]), null, 'Bay 1 in different departments must remain independent');

assert.ok(source.includes('const queue = unscheduled;'), 'Booked vehicles must be removed from the Outstanding candidates pile');
assert.ok(source.includes('<strong>Outstanding candidates</strong><span>${queue.length}</span>'), 'Outstanding pile badge must count only unassigned candidates');
assert.ok(source.includes('customerName: vehicle.customer_name ||'), 'Shared planner vehicle mapping must retain the approved customer name');
assert.ok(source.includes('class="workshop-plan-customer"'), 'Customer name must have a stable visible tile element');
assert.ok(!/has-lifecycle-actions[^\{]*[\s\S]{0,160}small:first-of-type/.test(css), 'Lifecycle controls must not hide the customer name');
assert.ok(source.includes("querySelectorAll('[data-workshop-complete-plan]')"), 'Every rendered Complete button must be bound');
assert.ok(css.includes('.workshop-completed-card') && /\.workshop-completed-card[\s\S]*background:\s*#dcfce7/.test(css), 'Completed cards must be green');

assert.match(migration, /create unique index if not exists workshop_bookings_one_started_per_bay_uidx\s*on public\.workshop_bookings\s*\(bay_id\)\s*where deleted_at is null and status='started' and bay_id is not null;/i, 'Database must enforce one started job per physical bay UUID');
assert.ok(!/\(bay_number\)[\s\S]*status\s*=\s*'started'/i.test(migration), 'Started-job uniqueness must never use bay number globally across departments');
assert.match(migration, /update public\.vehicle_work_items[\s\S]*completed\s*=\s*true/i, 'Completing Workshop work must complete the matching canonical work item');
assert.match(migration, /'customer_name',v\.customer_name/i, 'Restricted station snapshot must supply customer name');
assert.ok(applyScript.includes('validate_release_backup') && applyScript.includes("expected_migration='049'") && applyScript.includes("versions != ['049']") && applyScript.includes('operational_hashes_unchanged'), 'Staging apply must require restore-proven migration-049 backup, exact ledger baseline and unchanged operational hashes');
assert.match(migration, /'bay_already_started'/, 'Concurrent starts must return a clear bay-already-started result');

console.log('Workshop tile completion and live-bay contracts passed');
