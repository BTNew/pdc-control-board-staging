'use strict';
const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const deleted = app.slice(app.indexOf('function deletedVehicleSnapshotRecord('), app.indexOf('function sharedNavisionVisibleData('));

assert(app.includes('if (deletedNav) deletedNav.hidden = !vehicleLifecycleAdministratorActive();'), 'Deleted Vehicles navigation must be hidden from non-admin users');
assert(deleted.includes("if (!vehicleLifecycleAdministratorActive())"), 'Deleted Vehicles list must gate non-admin users');
assert(deleted.includes('Administrator access required'), 'Non-admin list must show an access-required state');
assert(deleted.includes('adminDeletedVehicleSnapshot'), 'Deleted Vehicles must use server tombstone snapshot');
assert(deleted.includes('Stock Number</b>'), 'Tombstone must show Stock Number');
assert(deleted.includes('Customer</b>'), 'Tombstone must show customer');
assert(deleted.includes('Vehicle UUID</b>'), 'Tombstone must show UUID');
assert(deleted.includes('Deleted at</b>'), 'Tombstone must show deletion time');
assert(deleted.includes('Deleted by</b>'), 'Tombstone must show actor');
assert(deleted.includes('Reason</b>'), 'Tombstone must show reason');
assert(deleted.includes('>Restore Vehicle</button>'), 'Deleted list must offer Restore Vehicle');
assert(deleted.includes('>Allow one controlled recreation</button>'), 'Deleted list must offer one controlled recreation');
assert(deleted.includes("action === 'restore' ? 'adminRestoreVehicle' : 'adminAllowOneVehicleRecreation'"), 'Buttons must dispatch exact bridge methods');
assert(deleted.includes('await refreshVehicleLifecycleLocationsAndRender()'), 'Successful deleted-list actions must refresh shared locations and render');
assert(!app.includes('cdsmnqxtyyoeoznmbidd'), 'Production-shipped app.js must not contain the staging project ref');
assert(app.includes('vehicleLifecycleResolverRollbackEnabled(config, location)'), 'Reset guard must delegate to the staging-config identity contract');
assert(app.includes("app.emailVehicleLocationService.subscribe(() => {"), 'Existing vehicle/revision subscription must refresh lifecycle state for two-user updates');
console.log('Administrator Delete/Restore/Reset UI contracts passed');
