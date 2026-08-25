'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');

assert.ok(styles.includes('#vehicle-modal') && styles.includes('z-index: 2000'), 'vehicle modal establishes a top stacking context');
assert.ok(styles.includes('body.modal-open #sublet select'), 'background Sublet selects are suppressed while the vehicle modal is open');
assert.ok(styles.includes('visibility: hidden'), 'native background selects cannot paint through the modal');
assert.ok(app.includes("document.body.classList.add('modal-open')"), 'opening vehicle modal marks the background as modal-blocked');
assert.ok(app.includes("document.body.classList.remove('modal-open')"), 'closing vehicle modal restores background controls');
assert.ok(app.includes("data-open-qc-vehicle"), 'legacy QC cards open the receipt-backed QC flow');

console.log('Sublet vehicle-modal stacking contract passed.');
