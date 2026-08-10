'use strict';
const assert = require('assert');
const fs = require('fs');

const read = name => fs.readFileSync(name, 'utf8');
const app = read('app.js');
const css = read('styles.css');

for (const name of ['index.html', 'staging.html']) {
  const html = read(name);
  const setupStart = html.indexOf('<section id="lists" class="view">');
  const setupEnd = html.indexOf('<section id="backup" class="view">', setupStart);
  const salesperson = html.indexOf('id="salesperson-list-admin"', setupStart);
  const backup = html.indexOf('id="backup-status-panel"', setupStart);
  assert(setupStart >= 0 && salesperson >= 0 && backup > salesperson && backup < setupEnd,
    `${name}: automated backup status must be the final panel in Setup`);
  assert(html.includes('class="panel pdc-list-panel backup-status-panel compact-backup-status-panel"'),
    `${name}: backup status panel must use its compact scoped class`);
}

assert(css.includes('.compact-backup-status-panel .backup-status-grid'), 'Compact backup grid styling must be scoped to the backup panel');
assert(css.includes('grid-template-columns: repeat(4, minmax(0, 1fr))'), 'Desktop backup status must render as a compact four-column, two-row strip');
assert(css.includes('.compact-backup-status-panel .visibility-card strong'), 'Compact backup values need a scoped type scale');
assert(app.includes('>Encrypted off-database</strong>'), 'Long backup-location prose must be replaced by a slim status value');
assert(app.includes('<strong>7d / 30d / 12w / 12mo</strong>'), 'Retention must use the compact status value');
assert(!app.includes('<strong>Encrypted file store (server-side, outside the live database)</strong>'), 'Oversized backup-location value must be removed');

console.log('Slim bottom-of-Setup backup status layout contract passed');
