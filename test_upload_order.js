const assert = require('assert');
const fs = require('fs');

const html = fs.readFileSync('index.html', 'utf8');
const staging = fs.readFileSync('staging.html', 'utf8');
const fallback = fs.readFileSync('no-vehicles.html', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');

for (const [name, shell] of [['source', html], ['staging', staging], ['fallback', fallback]]) {
  assert.ok(shell.includes('>Navision Uploads</button>'), `${name} shell exposes Navision Uploads`);
  assert.ok(shell.includes('>Backup / Restore</button>'), `${name} shell exposes Backup / Restore as its own tab`);
  assert.ok(shell.includes('id="backup" class="view"'), `${name} shell has a separate backup view`);
  assert.ok(shell.includes('Autocare Despatch Upload'), `${name} shell labels Autocare upload`);
  assert.ok(!shell.includes('Upload PD Document'), `${name} shell removes PD Document upload`);
  assert.ok(!shell.includes('dashboard-pd-upload'), `${name} shell removes PD Document controls`);
  assert.ok(!shell.includes('Export current local Navision data'), `${name} shell removes local Navision export`);
}

assert.ok(staging.includes('Select Dealer to Import'), 'staging labels the exact dealer selector clearly');
const navisionPanelStart = staging.indexOf('<h2>Navision import results</h2>');
const navisionPanelEnd = staging.indexOf('</section>', navisionPanelStart);
const navisionPanel = staging.slice(navisionPanelStart, navisionPanelEnd);
const controls = ['>Preview Data</button>', '>Confirm and Apply</button>', '>Clear</button>'];
const positions = controls.map(text => navisionPanel.indexOf(text));
assert.ok(positions.every(position => position >= 0), 'staging contains Preview Data, Confirm and Apply, and Clear');
assert.ok(positions[0] < positions[1] && positions[1] < positions[2], 'staging action order is Preview Data, Confirm and Apply, Clear');
assert.ok(!html.includes('id="navision-dealer-code"') && !html.includes('id="apply-navision-shared"'), 'production template does not expose staging-only shared import RPC controls');
const adminRoutes = app.match(/const adminViews = new Set\(\[([^\]]+)\]\)/);
assert.ok(adminRoutes && adminRoutes[1].includes("'backup'"), 'backup route remains administrator-only');
assert.ok(app.includes("backup: 'Backup / Restore'"), 'backup view has its own title');
assert.ok(!html.includes('id="po-scan-card"') && !staging.includes('id="po-scan-card"'), 'purchase-order upload remains absent');

console.log('Admin upload and backup layout regression checks passed');
