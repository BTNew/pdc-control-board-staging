'use strict';
const fs = require('fs');
const vm = require('vm');
function assert(value, message) { if (!value) throw new Error(message); }
const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function authenticatedOperationLineValid');
const end = source.indexOf('function incomingWorkChecklistHtml', start);
assert(start >= 0 && end > start && source.slice(start, end).includes('const AUTHENTICATED_OPERATION_STATION_ORDER'), 'Vehicle Locations must define a bounded station-grouped authenticated operation renderer');
const script = `${source.slice(start, end)}\nthis.render = authenticatedEmailOperationLinesHtml;`;
const context = {
  escapeHtml(value) { return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#039;'); },
};
vm.createContext(context);
vm.runInContext(script, context);
const html = context.render({ pdcEmailOperationLines: [
  { operation_no: 'OP4', work_key: 'electrical', description: 'Supply & fit light', estimatedHours: 1 },
  { operation_no: 'OP2', work_key: 'fitting', description: 'Pre-delivery inspection', estimatedHours: 0.7 },
  { operation_no: 'OP3', work_key: 'electrical', description: '<unsafe>', estimatedHours: 4 },
  { operation_no: 'OP16', work_key: 'pitinspection', description: 'Long tongue inspection' },
  { operation_no: 'OP8', work_key: 'unknown', description: 'Must not leak into a station' },
] });
assert((html.match(/class="authenticated-operation-station"/g) || []).length === 3, 'Only stations containing recognized jobs must render a column');
assert(html.indexOf('data-operation-station="FITTING"') < html.indexOf('data-operation-station="ELECTRICAL"'), 'Station columns must use canonical workshop order');
assert(html.indexOf('data-operation-station="ELECTRICAL"') < html.indexOf('data-operation-station="PIT_INSPECTION"'), 'Pit status work must remain after physical workshop columns');
const electrical = html.match(/data-operation-station="ELECTRICAL"[\s\S]*?<\/section>/)?.[0] || '';
assert(electrical.includes('OP3') && electrical.includes('OP4'), 'Electrical column must contain only its Electrical jobs');
assert(!electrical.includes('OP2') && !electrical.includes('OP16'), 'Electrical column must not contain jobs from other stations');
assert(electrical.indexOf('OP3') < electrical.indexOf('OP4'), 'Jobs must retain deterministic operation-number order inside each station');
assert(html.includes('data-operation-station="FITTING"') && html.includes('OP2'), 'Fitting job must render in the Fitting column');
assert(html.includes('data-operation-station="PIT_INSPECTION"') && html.includes('OP16'), 'Pit inspection must remain visible as a status-work column without becoming a planner bay');
assert(!html.includes('Must not leak into a station'), 'Unknown work keys must fail closed instead of appearing in an arbitrary station');
assert(html.includes('&lt;unsafe&gt;') && !html.includes('<unsafe>'), 'Untrusted job descriptions must remain escaped');
assert(html.includes('4.00 h') && html.includes('Hours not stated'), 'Each station card must retain authenticated estimated-hour evidence');
assert((html.match(/--station-colour:/g) || []).length === 3 && (html.match(/--station-tint:/g) || []).length === 3, 'Every rendered station column must carry its station colour and tint');
const css = fs.readFileSync('styles.css', 'utf8');
for (const required of ['.authenticated-operation-station-grid', '.authenticated-operation-station', '.authenticated-operation-station > header', 'var(--station-colour)', 'var(--station-tint)']) {
  assert(css.includes(required), `Station-column CSS is missing ${required}`);
}
console.log('Vehicle Locations authenticated jobs station-column regression checks passed');
