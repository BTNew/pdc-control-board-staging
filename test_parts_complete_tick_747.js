/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r747 (F353, Craig 30 Oct): a Parts complete tick beside Place as STOPPAGE in the side panel turns the Parts Jita box green.
const assert = require('assert');
const fs = require('fs');
const api = require('./pdc-parts-stoppage.js');
const src = fs.readFileSync('pdc-parts-stoppage.js', 'utf8');
const conf = fs.readFileSync('pdc-parts-confirmation.js', 'utf8');
const sql = fs.readFileSync('supabase/migrations/20261030095500_r747_parts_complete_tick.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030095500_r747_parts_complete_tick.down.sql', 'utf8');
const entry = fs.readFileSync('canonical-entry.js', 'utf8');
const vid = '11111111-2222-4333-8444-555555555555';

assert.strictEqual(api.VERSION, '2026.10.30.r747');
assert.strictEqual(api.COMPLETE_RPC, 'set_pdc_parts_board_complete_747');

// The tick sits in the same row as Set date, Place as STOPPAGE and History.
const base = { vehicleId: vid, canEdit: true, today: '2026-10-30', manual: null, placed: false };
const open = api.detailHtml({ ...base, partsDone: false });
const lead = open.slice(open.indexOf('pdc-parts-stoppage-lead'), open.indexOf('</span>', open.indexOf('data-pdc-stoppage-history')));
assert.ok(lead.includes('Place as STOPPAGE') && lead.includes(`data-pdc-parts-complete="${vid}"`) && lead.includes('History'), 'STOPPAGE, Parts complete and History share one row');
assert.ok(lead.indexOf('Place as STOPPAGE') < lead.indexOf('Parts complete'), 'Parts complete sits right of STOPPAGE');
assert.ok(!/data-pdc-parts-complete="[^"]*" checked/.test(open), 'not ticked when parts are not complete');

const ticked = api.detailHtml({ ...base, partsDone: true, partsBoard: true, partsWho: 'craig@x' });
assert.ok(/data-pdc-parts-complete="[^"]*" checked\/>/.test(ticked) && ticked.includes('is-done'), 'ticked here: checked, can be unticked');
// r803 (F418): a green import can be unticked (marks parts outstanding); only a confirmation email stays locked.
const imported = api.detailHtml({ ...base, partsDone: true, partsBoard: false });
assert.ok(/checked\/>/.test(imported) && !/checked disabled/.test(imported), 'complete from the import: ticked, can be unticked');
const emailed = api.detailHtml({ ...base, partsDone: true, partsBoard: false, partsEmail: true });
assert.ok(/checked disabled/.test(emailed), 'complete from a confirmation email: ticked, locked');
assert.ok(!api.detailHtml({ ...base, canEdit: false, partsDone: false }).includes('data-pdc-parts-complete'), 'read-only users get no tick');
assert.ok(!api.detailHtml({ ...base, editing: true }).includes('data-pdc-parts-complete'), 'hidden while the date form is open');
const placed = api.detailHtml({ ...base, placed: true });
assert.ok(placed.includes('pdc-parts-stoppage-place is-placed') && !placed.includes('<small class="pdc-parts-stoppage-placed">'), 'placed STOPPAGE is one chip, no second badge');

// Flags the board shows: green on, the import status back off.
const review = { colour: 'review', label: 'Parts requirements need review', parts_complete: false, feed: 'separate_parts_status', jobs: [{ colour: 'review' }] };
const on = api.boardCompleteFlags(review, true, 'craig@x', '2026-10-30T00:30:00Z');
assert.strictEqual(on.colour, 'green');
assert.strictEqual(on.parts_complete, true);
assert.strictEqual(on.override_source, 'board_parts_complete');
assert.strictEqual(on.feed, 'separate_parts_status');
assert.deepStrictEqual(on.import_status, review);
assert.strictEqual(on.jobs[0].colour, 'green');
assert.deepStrictEqual(api.partsFlagsState(on), { done: true, board: true, email: false, red: false, eta: '', who: 'craig@x', at: '2026-10-30T00:30:00Z' });
assert.deepStrictEqual(api.boardCompleteFlags(on, false), review, 'untick restores the import status');
assert.strictEqual(api.boardCompleteFlags(null, false), null);
assert.strictEqual(api.boardCompleteFlags(null, true).colour, 'green', 'a vehicle with no import status still goes green');
const email = { colour: 'green', parts_complete: true, override_source: 'authorised_email_confirmation' };
assert.strictEqual(api.boardCompleteFlags(email, true), email, 'an email confirmation still wins');
assert.deepStrictEqual(api.partsFlagsState(email), { done: true, board: false, email: true, red: false, eta: '', who: '', at: '' });

// Runtime wiring.
assert.ok(src.includes("document.addEventListener('change', event => {\n    const box = event.target?.closest?.('[data-pdc-parts-complete]');"), 'tick handler bound');
assert.ok(/async function setPartsComplete[\s\S]*?rpc\(COMPLETE_RPC[\s\S]*?placedById\.has\(vid\)[\s\S]*?p_place: false[\s\S]*?repaintPartsBox\(vid\)/.test(src), 'tick saves, lifts STOPPAGE, repaints the Parts Jita box');
assert.ok(src.includes(".pdc-parts-stoppage-place,.pdc-parts-complete-tick{display:inline-flex;flex:0 0 auto;") && src.includes('white-space:nowrap'), 'STOPPAGE chip no longer wraps');
assert.ok(conf.includes("status.override_source === 'board_parts_complete'") && conf.includes("'import:Parts complete — marked on the board'"), 'parts confirmation treats the tick as complete');
assert.ok(/&r747=2026\.10\.30\.r747(?:&r803=2026\.11\.01\.r803)?(?:&r804=2026\.11\.01\.r804)?'/.test(entry) && entry.includes('person-confirmed.1&r747=2026.10.30.r747'), 'loaders cache-busted');

// Database.
assert.ok(sql.includes('CREATE FUNCTION public.set_pdc_parts_board_complete_747(p_vehicle_id uuid, p_complete boolean)'));
assert.ok(sql.includes("'importer'") && sql.includes("'operator'") && sql.includes("'administrator'") && sql.includes("'not_authorized'"));
assert.ok(sql.includes('UPDATE public.pdc_email_vehicle_revision SET revision = revision + 1'), 'snapshot cache refreshes');
assert.ok(sql.includes("'override_source','board_parts_complete'") && sql.includes("'label','Parts complete — marked on the board'"));
assert.ok(sql.includes('REVOKE ALL ON public.pdc_parts_board_complete_747, public.pdc_parts_board_complete_history_747 FROM PUBLIC, anon, authenticated;'));
assert.ok(sql.indexOf('pdc_parts_completion_email_confirmations WHERE vehicle_id=p_vehicle_id AND active;\n IF FOUND THEN') > 0, 'email confirmation is read first');
assert.ok(down.includes('DROP FUNCTION IF EXISTS public.set_pdc_parts_board_complete_747') && !down.includes('board_parts_complete'), 'rollback restores the old flags body');
console.log('r747 Parts complete tick passed.');
