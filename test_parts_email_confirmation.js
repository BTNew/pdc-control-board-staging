'use strict';
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const context = {
  window: {PDC_SUPABASE_CONFIG:{projectRef:'cdsmnqxtyyoeoznmbidd'}},
  importedPartsStatus: v => v.parts_flags,
  partsStateComplete: v => v.original_complete === true,
  partsDepartmentStatusClass: () => 'original-class',
  partsLastUpdateLabel: () => 'Imported earlier',
  importedPartsTitle: () => 'Original import status'
};
vm.createContext(context);
const source = fs.readFileSync('pdc-parts-confirmation.js','utf8');
vm.runInContext(source,context);
const vehicle = {parts_flags:{parts_complete:true,override_source:'authorised_email_confirmation',label:'Parts complete — confirmed by Wayne',confirmed_at:'2026-09-12T00:00:00Z',import_status:{colour:'orange'}}};
assert.equal(context.partsStateComplete(vehicle),true);
assert.equal(context.partsStateComplete({parts_flags:{colour:'green'}}),false);
assert.equal(context.partsDepartmentStatusClass('import:Parts complete — confirmed by Wayne'),'parts-status-complete');
assert.equal(context.partsDepartmentStatusClass('import:Unknown / Needs review'),'original-class');
assert.match(context.partsLastUpdateLabel(vehicle),/Confirmed by Wayne/);
assert.match(context.importedPartsTitle(vehicle),/overrides import backorder flags/);
assert.equal(context.importedPartsTitle({}),'Original import status');
vm.runInContext(source,context);
assert.equal(context.partsStateComplete(vehicle),true);
assert.equal(vehicle.parts_flags.import_status.colour,'orange');
console.log('Parts email priority, date, complete styling, fallback and replay installation: PASS');
