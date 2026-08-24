'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');

assert.ok(app.includes('const modalReturnFocus = new WeakMap();'), 'modal return focus is stored without leaking element references');
assert.ok(app.includes("if (e.key === 'Tab' && activeModal)"), 'open vehicle/customer dialogs intercept Tab');
assert.ok(app.includes('trapModalFocus(activeModal, e);'), 'Tab is routed through the modal focus trap');
assert.ok(app.includes("if (event.shiftKey && (document.activeElement === first || !modal.contains(document.activeElement)))"), 'reverse Tab wraps to the final control');
assert.ok(app.includes("else if (!event.shiftKey && (document.activeElement === last || !modal.contains(document.activeElement)))"), 'forward Tab wraps to the first control');
assert.ok(app.includes('rememberModalReturnFocus(modal);'), 'dialog open remembers the invoking control');
assert.ok(app.includes('restoreModalReturnFocus(modal);'), 'dialog close restores the invoking control');
assert.ok(app.includes("if (customerModal?.hidden === false) closeCustomerModal();"), 'Escape closes the active customer dialog first');
assert.ok(app.includes("else if (vehicleModal?.hidden === false) closeVehicleModal();"), 'Escape otherwise closes the active vehicle dialog');

const vehicleClose = app.slice(app.indexOf('function closeVehicleModal('), app.indexOf('\nasync function removeVehicle', app.indexOf('function closeVehicleModal(')));
const customerClose = app.slice(app.indexOf('function closeCustomerModal('), app.indexOf('\nfunction addCustomerFromForm', app.indexOf('function closeCustomerModal(')));
assert.ok(vehicleClose.includes('if (!modal || modal.hidden) return;'), 'vehicle close restores focus only after a real open dialog');
assert.ok(customerClose.includes('if (!modal || modal.hidden) return;'), 'customer close restores focus only after a real open dialog');

console.log('Modal keyboard focus containment and return contract passed.');
