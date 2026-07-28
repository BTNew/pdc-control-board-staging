'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/088_vehicle_workshop_detail_page.sql', 'utf8');

assert(app.includes('role="tablist"') && app.includes('data-vehicle-detail-tab="details"') && app.includes('data-vehicle-detail-tab="work"'), 'Vehicle detail header must expose two accessible pages');
assert(app.includes('Vehicle details') && app.includes('Work & bookings'), 'Both vehicle-detail page names must be visible');
assert(app.includes('data-vehicle-workshop-booking-id'), 'Booked work rows must expose a selectable booking target');
assert(app.includes('openVehicleWorkshopBooking'), 'Booking selection must route through the dedicated planner-link handler');
assert(app.includes('app.pendingWorkshopBookingLink'), 'Planner deep link must retain exact booking, station and date through lazy route loading');
assert(planner.includes('pendingWorkshopBookingLink') && planner.includes('searchHighlightPlanId'), 'Planner render must consume the exact pending booking and highlight it');
assert(app.includes('Booking data unavailable') && app.includes('Not booked'), 'Every required line must have a truthful booking-time state');
assert(app.includes('Estimated hours') && app.includes('Estimate not set'), 'Every required line must have an explicit estimate state without guessing');
assert(app.includes('vehicleWorkshopLineDescription'), 'Every required line must render a non-empty description');
const selectedVehicleBody = app.match(/function selectedVehicle\([^]*?\r?\n}\r?\n\r?\nfunction saveVehicleEdits/)?.[0] || '';
assert(selectedVehicleBody.indexOf('if (canonicalMatches.length > 1)') < selectedVehicleBody.indexOf('const boardMatches'), 'Ambiguous raw canonical identity must fail closed before reconciliation');
assert(selectedVehicleBody.includes('if (boardVehicle) return boardVehicle;'), 'Vehicle detail must preserve the unique non-conflicting authoritative board snapshot and canonical UUID');
assert(selectedVehicleBody.indexOf("if (boardVehicle?.__emailVehicleIdentityConflict === true || boardVehicle?.__locationIdentityReadOnly === true)") < selectedVehicleBody.indexOf('if (boardVehicle) return boardVehicle;'), 'Identity conflicts must fail closed before authoritative board selection');
assert(selectedVehicleBody.includes("__emailVehicleIdentityConflict") && selectedVehicleBody.includes("__locationIdentityReadOnly"), 'Conflicting reconciled identity must fail closed');
const workshopGroupsBody = app.match(/function vehicleWorkshopGroups\([^]*?\r?\n}\r?\n\r?\nfunction vehicleWorkshopStationHtml/)?.[0] || '';
assert(workshopGroupsBody.includes('pdcEmailOperationLines'), 'Vehicle Work & bookings must consume authenticated job-card operation lines');
assert(workshopGroupsBody.includes('operation_no'), 'Authenticated operation numbers must remain available to the detail renderer');
assert(workshopGroupsBody.includes('groups.get(stage).lines.push'), 'Authenticated operation lines must be placed into their canonical station group');
assert(css.includes('.vehicle-workshop-station') && css.includes('--station-colour'), 'Station groups must be colour coded through a shared station colour token');
assert(css.includes('.vehicle-detail-tabs') && css.includes('@media (max-width: 760px)'), 'Tabs and work rows must have responsive treatment');

assert(/create or replace function public\.get_vehicle_workshop_detail\(p_vehicle_id uuid\)/i.test(sql), 'Migration must add one narrow viewer-readable vehicle workshop detail RPC');
assert(/perform public\.require_pdc_role\('viewer'\)/i.test(sql), 'Vehicle workshop detail RPC must enforce authenticated viewer authority');
assert(/from public\.vehicle_work_items/i.test(sql) && /from public\.workshop_bookings/i.test(sql), 'RPC must source canonical requirements and bookings');
assert(/default_duration_minutes/i.test(sql) && /scheduled_start_at/i.test(sql) && /bay_number/i.test(sql), 'RPC must return authoritative duration, booking time and bay');
assert(/revoke all on function public\.get_vehicle_workshop_detail\(uuid\) from public, anon/i.test(sql), 'Anonymous callers must not execute the detail RPC');
assert(!/['\"]customer_name['\"]|['\"]notes['\"]|wi\.notes/i.test(sql), 'Narrow workshop detail RPC must not leak customer or free-text notes');

console.log('Vehicle detail work-and-bookings contract passed');
