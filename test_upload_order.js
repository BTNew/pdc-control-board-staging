const assert = require('assert');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const stagingHtml = fs.readFileSync(path.join(__dirname, 'staging.html'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');

assert.ok(html.includes('<h2>1. Daily Navision import</h2>'), 'Production daily Navision import must remain the first upload');
assert.ok(stagingHtml.includes('<h2>1. Daily Navision import · shared backend</h2>'), 'Staging shared-backend flow must be clearly labelled as the first upload');
assert.ok(stagingHtml.includes('migration-037/038 shared staging service'), 'Staging shared upload must identify the migration-038 scoped safety layer');
assert.ok(html.includes('<h2>2. Upload job card / PD work</h2>'), 'Job-card/PD upload must follow Navision');
assert.ok(html.includes('<h2>2. Upload purchase order</h2>'), 'PO upload must be grouped with the second upload step');
assert.ok(css.includes('#import .navision-layout { order: 1; }'), 'Navision layout must render first');
assert.ok(css.includes('#import .po-job-layout { order: 2;'), 'PO/job-card layout must render second');
assert.ok(css.includes('#import .autocare-layout { order: 3; }'), 'Autocare layout must render after PO/job-card');
assert.ok(css.includes('#import .backup-layout { order: 4; }'), 'Backup/restore must render last');

['dashboard-import-pd','dashboard-clear-pd','dashboard-pd-upload','dashboard-pd-paste','dashboard-pd-status','po-upload','po-status-list'].forEach(id => {
  const count = (html.match(new RegExp(`id="${id}"`, 'g')) || []).length;
  assert.strictEqual(count, 1, `${id} should appear exactly once`);
});

console.log('Upload order regression checks passed');
