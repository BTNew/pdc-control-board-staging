const assert = require('assert');
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');

assert.ok(app.includes('function offerSalespersonChangeEmail'), 'Salesperson notification modal is missing');
assert.ok(app.includes('function draftSalespersonChangeEmail'), 'Salesperson change email draft is missing');
assert.ok(app.includes('function draftSelectedVehicleStatusEmail'), 'Selected-vehicle status email action is missing');
assert.ok(app.includes('function vehicleStatusUpdateEmailBody'), 'Detailed vehicle status email body is missing');
assert.ok(app.includes('data-sales-email-recipient'), 'Notification modal must allow the recipient address to be checked or edited');
assert.ok(app.includes('data-email-vehicle-update'), 'Vehicle detail must expose the EMAIL UPDATE button');
assert.ok(app.includes('Workshop / bay history:'), 'Status email must include workshop and bay history');
assert.ok(app.includes('Parts ETA:'), 'Status email must include Parts ETA when Parts is outstanding');
assert.ok(app.includes("title: eta ? 'Parts ETA updated' : 'Parts ETA cleared'"), 'Parts ETA updates must offer a salesperson email');
assert.ok(app.includes("title: 'Parts STOPPAGE recorded'"), 'Parts STOPPAGEs must offer a salesperson email');
assert.ok(app.includes("title: 'Parts completed'"), 'Parts completion must offer a salesperson email');
assert.ok(app.includes("subject: 'PDC STOPPAGE update'"), 'Production STOPPAGEs must offer a salesperson email');
assert.ok(app.includes("subject: 'PDC work completed'"), 'PDC job completions must offer a salesperson email');
assert.ok(app.includes("title: 'Vehicle completed and collected'"), 'Completed/collected vehicles must offer a salesperson email');
assert.ok(app.includes('salespersonForVehicle(vehicle)?.email'), 'Salesperson directory email lookup must take priority over the fallback');
assert.ok(app.includes('IMPORTANT UPDATE:'), 'Sales emails must prominently flag the reason for the update');
assert.ok(!app.match(/`Toyota Order:.*`/), 'Sales email templates must not include the Toyota order number');
assert.ok(app.includes("title: 'Vehicle ready for transport (RFT)'"), 'A single RFT transfer must offer a salesperson update email');
assert.ok(html.includes('id="salesperson-list-admin"'), 'Lists must include salesperson administration');
assert.ok(html.includes('data-new-customer-salesperson'), 'New vehicles must select a salesperson from the directory');
assert.ok(app.includes('DEFAULT_SALESPERSONS'), 'The supplied salesperson directory seed is missing');
assert.ok(css.includes('.sales-change-email-card'), 'Salesperson notification modal styling is missing');
assert.ok(css.includes('.sales-change-email-summary > strong'), 'The change reason needs prominent visual styling in the email prompt');

console.log('Salesperson notification regression checks passed');
