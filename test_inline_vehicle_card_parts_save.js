'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const handlerStart = app.indexOf("$$('[data-flag-stock]', table)");
const handlerEnd = app.indexOf("$$('[data-action-stock]', table)", handlerStart);
assert.ok(handlerStart >= 0 && handlerEnd > handlerStart, 'vehicle table flag handler exists');
const handler = app.slice(handlerStart, handlerEnd);
assert.ok(handler.includes('async () =>'), 'inline vehicle card handler supports authoritative async save');
assert.ok(handler.includes('vehicle?.__emailVehicleServerAuthoritative === true'), 'inline handler detects authoritative email vehicles');
assert.ok(handler.includes('await saveInlineSharedVehicleWorkState('), 'inline handler uses shared work-state RPC');
assert.ok(!handler.includes('saveVehicleEdits(input.dataset.flagStock, updates);') || handler.indexOf('saveVehicleEdits(input.dataset.flagStock, updates);') > handler.indexOf('if (vehicle?.__emailVehicleServerAuthoritative'), 'local fallback remains only after shared branch');
assert.ok(app.includes('function buildInlineSharedVehicleWorkStates('), 'inline shared state map exists');
console.log('Inline vehicle-card Parts shared save contract passed.');
