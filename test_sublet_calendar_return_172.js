'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = process.env.PDC_TEST_ROOT ? path.resolve(process.env.PDC_TEST_ROOT) : __dirname;
const sql = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '172_sublet_calendar_return_station_completion.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const lower = sql.toLowerCase();

assert(lower.includes("version='171' and name='release_safety_corrections'"), 'Migration 172 must require the exact installed predecessor');
assert(lower.includes("version::integer>171") && lower.includes("version='172'"), 'Migration 172 must reject newer or repeated ledgers');
assert(lower.includes('rename to return_pdc_sublet_booking_pre172'), 'The installed return authority must be retained behind the wrapper');
assert(lower.includes('perform public.pdc_lock_canonical_sublet_vehicle(v_vehicle_id)'), 'Return and station completion must serialize per vehicle');
assert(lower.includes('v_result:=public.return_pdc_sublet_booking_pre172'), 'The wrapper must preserve canonical version and history behavior');
assert(lower.includes("where vehicle_id=v_vehicle_id and status='active'"), 'Station completion must count every remaining active provider booking');
assert(lower.includes("public.workshop_stage_code_for_work_key(wi.work_key)='sublet'"), 'Only canonical Sublet station work may be completed');
assert(lower.includes('if v_active_count=0 then'), 'Sublet station completion must be gated on the last active booking');
assert(lower.includes("'source','sublet_calendar_return_172'"), 'Automatic station completion must be audited');
assert(lower.includes('return_pdc_sublet_booking_pre172(uuid,bigint,timestamptz) from public,anon,authenticated,service_role'), 'Retained implementation must not be callable');
assert(lower.includes('grant execute on function public.return_pdc_sublet_booking(uuid,bigint,timestamptz) to authenticated'), 'Only authenticated staff may use the public return RPC');

assert(app.includes("event.type === 'due-back' && event.bookingId"), 'Only canonical Due Back pills may expose the return checkbox');
assert(app.includes('data-sublet-calendar-returned="${escapeHtml(event.mutationKey)}"'), 'Due Back pills must expose a booking-scoped return checkbox');
assert(app.includes('data-sublet-calendar-out-date="${escapeHtml(event.bookingDate)}"'), 'Calendar return control must retain the canonical outgoing date');
assert(app.includes('const outDate = plainDateValue(current.pmbSubletBookingDate)'), 'Return action must resolve the current canonical Going Out date');
assert(app.includes('if (outDate && businessDate < outDate)'), 'Future Going Out dates must fail before the return RPC is called');
assert(app.includes('Correct the Going Out date first.'), 'Future-date failures must explain the correction required');
assert(app.includes('await setSubletReturned(input.dataset.subletCalendarReturned, true)'), 'Calendar checkbox must use the canonical return action without fabricating a future return date');
assert(app.includes("event.keyNumber ? `Key ${event.keyNumber}` : ''"), 'Every Sublet calendar pill must include the key number when available');
assert(app.includes("event.target?.closest?.('[data-sublet-calendar-returned]')"), 'Using the checkbox must not accidentally start a calendar drag');
assert(app.includes("if (!saved) {\n      input.checked = false;"), 'Failed returns must reset the checkbox');
assert(css.includes('.sublet-calendar-returned-check'), 'Calendar return checkbox must have an explicit compact style');
assert(css.includes('position: absolute; top: 4px; right: 5px'), 'Back control must stay on the stock identity row without increasing pill height');

console.log('Sublet calendar return and last-booking station completion contract passed');
