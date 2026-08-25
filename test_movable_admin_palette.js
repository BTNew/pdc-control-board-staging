'use strict';

const assert = require('assert');
const fs = require('fs');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');

assert.ok(planner.includes('async function workshopCurrentGlobalRevision(fallback = null)'), 'Admin mutations have a global revision reader');
assert.ok(planner.includes('/rest/v1/workshop_revision?select=revision&id=eq.1'), 'Admin mutations read the global Workshop revision');
assert.ok(planner.includes('expectedRevision: Number(expectedRevision)'), 'Admin creation sends the global revision to the RPC');
assert.ok(planner.includes('data-workshop-admin-palette-tile'), 'Admin palette tile exists');
assert.ok(planner.includes('application/x-workshop-admin-palette'), 'Admin palette drag type exists');
assert.ok(planner.includes('workshopAdminPaletteDurationMinutes = 30'), 'Admin palette defaults to 30 minutes');
assert.ok(planner.includes('data-admin-palette-duration="${workshopAdminPaletteDurationMinutes}"'), 'Admin palette tile advertises the current exact duration while the hours control owns its value');
assert.ok(planner.includes('application/x-workshop-admin-duration-minutes'), 'Admin drag carries duration');
assert.ok(planner.includes('workshopCreatePaletteAdminBlock'), 'Admin drop creates a shared Admin block');
assert.ok(planner.includes('data-workshop-admin-palette-duration'), 'Admin palette duration is editable');
assert.ok(planner.includes('data-admin-block-resize'), 'Placed Admin blocks retain extension controls');
assert.ok(css.includes('.workshop-admin-palette') && css.includes('.workshop-admin-palette-tile'), 'Admin palette has pill/tile styling');
console.log('Movable Admin palette duration contract passed.');
