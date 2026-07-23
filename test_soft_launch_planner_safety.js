'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const planner = require('./workshop-planner.js');

global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value || '').trim();

const root = __dirname;
const source = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const plannerCss = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');
const globalCss = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const migration46 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '046_workshop_authoritative_validation_and_lifecycle.sql'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '049_soft_launch_planner_safety.sql'), 'utf8');
assert.ok(migration46.includes("to_regprocedure('public.workshop_block_legacy_ambiguous_booking_mutation()')"), '046 backfill must require the installed 048 quarantine guard');
assert.match(migration46, /set legacy_ambiguity_quarantined=true[\s\S]*s\.code='HOIST'/, '046 may tag only the exact quarantined Hoist class');
assert.match(migration46, /not legacy_ambiguity_quarantined and status in \('queued','planned','started','stoppage'\)/, 'Vehicle exclusion must continue protecting every non-quarantined active booking');

const now = new Date(2030, 6, 15, 12, 0, 0, 0);
const past = {
  id: 'past-planned',
  stage: 'TINT',
  bay: 1,
  startAt: new Date(2030, 6, 15, 11, 0, 0, 0).toISOString(),
  hours: 1,
  status: 'planned',
};
const future = { ...past, id: 'future-planned', startAt: new Date(2030, 6, 15, 13, 0, 0, 0).toISOString() };
assert.strictEqual(planner.workshopNewBookingValidation(past, now).error, 'past_start', 'Frontend must reject a planned booking placed before the current minute');
assert.strictEqual(planner.workshopNewBookingValidation(future, now).ok, true, 'Frontend must continue accepting a valid future booking');

assert.ok(migration.includes("p_status IN ('queued', 'planned')"), 'Effective backend migration must gate queued/planned past starts');
assert.ok(migration.includes("p_scheduled_start_at < date_trunc('minute', statement_timestamp())"), 'Backend must compare requested start with the authoritative database clock');
assert.match(migration, /not exists\s*\([\s\S]*?from public\.workshop_bookings existing[\s\S]*?existing\.scheduled_start_at=p_scheduled_start_at[\s\S]*?existing\.scheduled_end_at=p_scheduled_end_at/, 'Past-start guard must allow status-only lifecycle changes that retain an existing historical interval');
assert.match(migration, /ALTER FUNCTION public\.cascade_workshop_schedule[\s\S]*SET search_path = pg_catalog, public;/, 'Browser-callable cascade RPC must resolve pg_catalog before public');

assert.ok(source.includes("const started = String(entry.status || '').toLowerCase() === 'started';"), 'Started visual class must derive from lifecycle status, not legacy bay text');
assert.match(plannerCss, /\.workshop-plan-chip\s*\{[\s\S]*?background:\s*#dbeafe;/, 'Queued/planned cards must render blue');
assert.match(plannerCss, /\.workshop-plan-chip\.is-started\s*\{[\s\S]*?animation:\s*workshop-started-blue-pulse/, 'Started cards must visibly flash blue');
assert.match(plannerCss, /\.workshop-plan-chip\.is-overtime\s*\{[\s\S]*?background:\s*#fecdd3/, 'Overdue cards must render red');
assert.match(plannerCss, /prefers-reduced-motion:[\s\S]*?\.workshop-plan-chip\.is-started/, 'Started flashing must respect reduced-motion settings');

assert.match(globalCss, /@media \(max-width: 820px\)[\s\S]*?\.app-shell\s*\{\s*grid-template-columns:\s*1fr\s*!important;/, 'Mobile shell must not sacrifice the viewport to a fixed left sidebar');
assert.match(plannerCss, /@media \(max-width: 820px\)[\s\S]*?\.workshop-board-shell\s*\{\s*grid-template-columns:\s*minmax\(0, 1fr\)/, 'Mobile planner must stack its queue and timeline instead of clipping a desktop-width grid');
assert.match(plannerCss, /@media \(max-width: 1050px\)[\s\S]*?\.workshop-board-shell\s*\{[\s\S]*?grid-template-columns:\s*minmax\(0, 1fr\)/, 'Small-laptop planner must switch to one column before its 880px internal grid clips');
assert.ok(source.includes('Swipe or scroll schedule horizontally'), 'Narrow planner must expose a durable horizontal-scroll instruction');
assert.match(plannerCss, /\.workshop-scroll-cue\s*\{[\s\S]*?position:\s*sticky/, 'Planner scroll cue must stay visible while the timeline moves');
assert.match(plannerCss, /prefers-reduced-motion:[\s\S]*?\.workshop-plan-chip\.is-overtime[\s\S]*?background:\s*#b91c1c/, 'Reduced-motion overdue cards must retain readable red contrast');
assert.match(globalCss, /\.control-board-work-vehicle\s*\{[^}]*min-width:\s*0\s*!important;/, 'Expanded Control Board rows must be allowed to shrink on mobile');

console.log('Soft-launch planner safety and responsive contracts passed');
