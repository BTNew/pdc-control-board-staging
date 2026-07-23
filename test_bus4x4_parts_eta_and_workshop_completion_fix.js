'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const read = name => fs.readFileSync(path.join(__dirname, name), 'utf8');

const app = read('app.js');
const planner = read('workshop-planner.js');
const css = read('styles.css');
const migration = read('supabase/migrations/051_bus4x4_eight_bays_and_completion_hardening.sql');
const applyScript = read('scripts/apply_migration_051_staging.py');
const migration052 = read('supabase/migrations/052_bus4x4_concurrency_safe_bay_reconciliation.sql');
const applyScript052 = read('scripts/apply_migration_052_staging.py');

assert(/BUS_4X4:\s*8,/.test(app), 'Bus 4x4 frontend capacity must be eight bays');
assert(app.includes("BUS_4X4: '8 bays'"), 'Bus 4x4 capacity label must say 8 bays');
assert(migration.includes("where code = 'BUS_4X4' and active and is_physical"));
assert(migration.includes('from generate_series(1, 8)'));
assert(migration.includes('if v_active_count <> 8'));
assert(migration.includes("booking.status in ('queued','planned','started','stoppage')"), 'migration must block rather than hide active work outside bays 1..8');
assert(!/update\s+public\.workshop_bookings/i.test(migration), 'Migration 051 must not move or rewrite bookings');
for (const gate of ["expected_migration='050'", "versions != ['050']", "operational_hashes_unchanged", "bus4x4_active_bays"]) {
  assert(applyScript.includes(gate), `Migration 051 staging runner missing gate: ${gate}`);
}
assert(migration052.includes('lock table public.workshop_bookings in share row exclusive mode'), 'Migration 052 must serialize bay reconciliation against booking DML');
assert(migration052.includes("wb.status in ('planned', 'started', 'stoppage')"), 'Migration 052 must recheck every active booking lifecycle');
assert(!/update\s+public\.workshop_bookings/i.test(migration052), 'Migration 052 must not move or rewrite bookings');
for (const gate of ["expected_migration='051'", "versions != ['051']", 'hidden_active_bus4x4_bookings', 'operational_hashes_unchanged']) {
  assert(applyScript052.includes(gate), `Migration 052 staging runner missing gate: ${gate}`);
}

for (const label of ['Parts Not Ordered', 'Parts Ordered', 'Parts Overdue', 'Parts STOPPAGE']) assert(app.includes(label));
for (const label of ['+${days}', 'Overdue', 'Parts STOPPAGE']) assert(app.includes(label), `missing Parts contract ${label}`);
assert(app.includes('data-parts-worst-eta='));
assert(app.includes('<th>Parts ETA</th><th>ETA counter</th>'), 'ETA counter must be immediately right of Parts ETA');
assert(app.includes("if (isActivePartsStoppage(vehicle)) return 'stoppage';"), 'Parts STOPPAGE must take precedence over issued state');
assert(app.includes('Add issued vehicle to Parts STOPPAGE'), 'Issued vehicles must have a manual path back into Parts STOPPAGE');
assert(!app.includes('if (def) updates[def.completeKey] = false;'), 'Parts STOPPAGE must preserve issued/completed state');
assert(css.includes('.parts-eta-countdown.positive') && css.includes('color: #15803d'));
assert(css.includes('.parts-eta-countdown.negative') && css.includes('color: #dc2626'));
assert(planner.includes('>STOPPAGE</button>'), 'generic Workshop stoppage action must say STOPPAGE');

assert(migration.includes("v_booking.status not in ('started','stoppage')"), 'planned work must not be directly completable');
assert(migration.includes("date_trunc('minute', coalesce(p_actual_end_at, statement_timestamp()))"), 'null completion timestamp must use database time');
assert(migration.includes('completed_at = v_end'));
assert(migration.includes("'not_completable'"));
assert(migration.includes('pg_get_expr(i.indpred, i.indrelid)'), 'migration must validate the actual partial-index predicate');
assert(migration.includes('not coalesce(v_index_unique, false)'), 'migration must validate index uniqueness');
assert(migration.includes('set search_path = pg_catalog, public'));
assert(migration.includes('revoke all on function public.complete_workshop_work'));
assert(migration.includes('grant execute on function public.complete_workshop_work'));

console.log('Bus 4x4, Parts ETA/stoppage, and Workshop completion hardening contracts passed');
