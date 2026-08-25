'use strict';
const assert = require('assert');
const fs = require('fs');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
const renderStart = source.indexOf('renderHost.innerHTML = `<div class="${dedicatedStage');
const renderEnd = source.indexOf('<div class="workshop-date-summary">', renderStart);
assert.ok(renderStart >= 0 && renderEnd > renderStart, 'Workshop toolbar render exists');
const toolbar = source.slice(renderStart, renderEnd);
assert.doesNotMatch(toolbar, /data-workshop-link-readiness/,
  'identity-link diagnostic is not exposed in the ordinary Workshop toolbar');
assert.doesNotMatch(toolbar, /Review shared links/,
  'ordinary operators are not prompted to run identity-link diagnostics');

const handlerStart = source.indexOf("root.querySelectorAll('[data-workshop-best-slot-vehicle]')");
const handlerEnd = source.indexOf("root.querySelectorAll('[data-workshop-admin-block-id]')", handlerStart);
assert.ok(handlerStart >= 0 && handlerEnd > handlerStart, 'Best slot click handler exists');
const handler = source.slice(handlerStart, handlerEnd);
assert.match(handler, /addEventListener\('click', async event/);
assert.match(handler, /await workshopScheduleVehicleNextAvailable\(\{/,
  'Best slot click recomputes against current authoritative time and schedule');
assert.match(handler, /vehicleKeyValue: button\.dataset\.workshopBestSlotVehicle/);
assert.match(handler, /stage: button\.dataset\.workshopBestSlotStage/);
assert.match(handler, /hours: Number\(button\.dataset\.workshopBestSlotHours\)/);
assert.doesNotMatch(handler, /dateKey: button\.dataset\.workshopBestSlotDate/,
  'stale rendered date is not reused');
assert.doesNotMatch(handler, /startMinutes: Number\(button\.dataset\.workshopBestSlotStart\)/,
  'stale rendered start is not reused');
assert.doesNotMatch(handler, /bay: Number\(button\.dataset\.workshopBestSlotBay\)/,
  'stale rendered bay is not reused');
assert.match(handler, /aria-busy/);
assert.match(handler, /if \(button\.disabled\) return/);

const recomputeStart = source.indexOf('async function workshopScheduleVehicleNextAvailable');
const recomputeEnd = source.indexOf('async function scheduleWorkshopVehicle', recomputeStart);
const recompute = source.slice(recomputeStart, recomputeEnd);
assert.match(recompute, /const nextOperationalMoment = workshopNormalizeStartDate\(new Date\(\)\)/);
assert.match(recompute, /workshopBestStageSlot\(normalizedStage, windowStart, estimate, workshopLoadPlans\(\), notBeforeMinutes, windowEnd\)/);
console.log('Workshop diagnostics hidden and Best slot current-time recompute: PASS');
