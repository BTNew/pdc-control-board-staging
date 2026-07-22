'use strict';
const assert = require('assert');

global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.cleanNavisionText = value => String(value || '').trim();
global.escapeHtml = value => String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
global.vehicleKey = vehicle => vehicle.id;
global.isPdcBlocked = () => false;
global.vehiclePdcLocation = vehicle => vehicle.current_location || 'PMB';
global.statusCategory = () => 'pmb';
global.partsDepartmentStatus = () => 'notrequired';
global.partsDepartmentStatusLabel = () => 'Not required';
global.partsWorstEtaLabel = () => '';
global.partsWorstEtaCountdownLabel = () => '';
global.vehicleJobcardNumber = vehicle => vehicle.jobCard || '';
global.displayStockNumber = vehicle => vehicle.stock || '';
global.vehicleCustomerName = () => '';
global.pmbStageLabel = stage => ({ HOIST: 'Hoist', FITTING: 'Fitting' }[stage] || stage);
global.pdcRequirementDefinitions = () => [
  { key: 'hoist', label: 'Hoist' },
  { key: 'sublet', label: 'Sublet' },
];
global.pdcJobRequired = (vehicle, def) => vehicle.pmbJobs?.[def.key]?.required === true;
global.pdcJobComplete = (vehicle, def) => vehicle.pmbJobs?.[def.key]?.completed === true;
global.parseIsoTimestamp = value => { const d = new Date(value); return Number.isNaN(d.getTime()) ? null : d; };

global.app = { data: [] };
const planner = require('./workshop-planner.js');

const bookedOutstanding = {
  id: 'vehicle-1', stock: 'SANITIZED-1', current_location: 'PMB',
  pmbJobs: { hoist: { required: true, completed: false }, sublet: { required: true, completed: false } },
  __workshopOutstanding: { existingBooking: true, scheduleEnabled: true, disabledReason: '' },
};
const html = planner.workshopQueueCardHtml(bookedOutstanding, 'HOIST', '2026-07-23', []);
assert(html.includes('Requirements: Hoist, Sublet'), 'left candidate column must show Sublet as a requirement');
assert(html.includes('Active booking exists · shown here because the requirement remains outstanding'), 'booked outstanding candidate must remain discoverable');
assert(html.includes('draggable="false"') && html.includes('Already booked'), 'booked candidate must not create a duplicate booking');
assert(!html.includes('data-workshop-best-slot-vehicle'), 'booked candidate must not offer another best slot');

const source = require('fs').readFileSync(require('path').join(__dirname, 'workshop-planner.js'), 'utf8');
assert(source.includes('const queue = outstanding;'), 'candidate panel must contain the full outstanding set');
assert(source.includes('const unscheduled = outstanding.filter'), 'unscheduled must be separately measured');
assert(source.includes('${todaysPlans.length} bookings on selected date'), 'calendar count must be date-specific and separately labelled');
assert(source.includes('<strong>Outstanding candidates</strong>'), 'left panel must be labelled with canonical semantics');

console.log('Planner outstanding/unscheduled/selected-date UI semantics passed');
