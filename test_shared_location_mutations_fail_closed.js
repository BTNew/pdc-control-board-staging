const fs = require('fs');
const assert = require('assert');

const source = fs.readFileSync('app.js', 'utf8');

function body(name) {
  const start = source.indexOf(`function ${name}(`);
  assert(start >= 0, `missing ${name}`);
  const signatureEnd = source.indexOf(') {', start);
  assert(signatureEnd >= 0, `missing body for ${name}`);
  const brace = signatureEnd + 2;
  let depth = 0;
  for (let i = brace; i < source.length; i += 1) {
    if (source[i] === '{') depth += 1;
    if (source[i] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, i + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const bulkOverride = body('overrideSelectedVehiclesToYh');
const bulkTransfer = body('transferSelectedYhVehiclesToPmb');
const singleTransfer = body('transferYhVehicleToPmb');
const eligibility = body('canTransferVehicleToPmb');
const incomingRow = body('incomingVehicleDetailRow');
const inlineBar = body('updateInlineSelectionBars');
const bulkBar = body('updateBulkSelectionPanel');

assert.match(bulkOverride, /sharedVehicleLocationMutationUnavailable\('override to Yard Hold'\)/);
assert.ok(bulkOverride.indexOf("sharedVehicleLocationMutationUnavailable('override to Yard Hold')") < bulkOverride.indexOf('selectedVehiclesForBulkEmail()'));
assert.match(bulkTransfer, /sharedVehicleLocationMutationUnavailable\('bulk transfer to PMB'\)/);
assert.ok(bulkTransfer.indexOf("sharedVehicleLocationMutationUnavailable('bulk transfer to PMB')") < bulkTransfer.indexOf('selectedVehiclesForBulkEmail()'));
assert.match(singleTransfer, /sharedVehicleLocationMutationUnavailable\('transfer to PMB', vehicle\)/);
assert.ok(singleTransfer.indexOf("sharedVehicleLocationMutationUnavailable('transfer to PMB', vehicle)") < singleTransfer.indexOf('window.confirm'));
assert.match(eligibility, /vehicleLifecycleSharedModeActive\(\).*__emailVehicleServerAuthoritative/);
assert.match(incomingRow, /sharedVehicleLocationMutationUnavailable\('render transfer to PMB', vehicle, \{ silent: true \}\)/);
assert.match(inlineBar, /sharedVehicleLocationMutationUnavailable\('bulk transfer to PMB', null, \{ silent: true \}\)/);
assert.match(bulkBar, /sharedVehicleLocationMutationUnavailable\('override to Yard Hold', null, \{ silent: true \}\)/);
assert.doesNotMatch(bulkTransfer.slice(0, bulkTransfer.indexOf("sharedVehicleLocationMutationUnavailable('bulk transfer to PMB')") + 1), /loadVehicleEdits|saveJson|recordVehicleAudit|window\.confirm/);

console.log('PASS shared vehicle-location mutations fail closed before browser-local authority');
