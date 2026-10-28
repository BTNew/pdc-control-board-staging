/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r590 (F204) / sort 361. A green station icon, including an override, is not outstanding QC work.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const root = __dirname;
const up = fs.readFileSync(path.join(root, 'supabase/migrations/20261028080000_r590_qc_signoff_override.sql'), 'utf8');
const down = fs.readFileSync(path.join(root, 'supabase/rollbacks/20261028080000_r590_qc_signoff_override.down.sql'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const mobile = fs.readFileSync(path.join(root, 'pdc-qc-mobile.js'), 'utf8');
const karrathaMobile = fs.readFileSync(path.join(root, 'karratha/pdc-qc-mobile.js'), 'utf8');
const service = fs.readFileSync(path.join(root, 'pdc-email-vehicle-location-service.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

test('r590 is the next free triple and leaves r588 and r589 alone', () => {
  assert.match(up, /r590 \(F204\) \/ sort 361/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt is not a target/);
  assert.match(up, /r588 \/ F202/);
  assert.match(up, /r589 \/ F203/);
  assert.match(up, /sort 359 \/ F201 is not present|r587 \/ F201 sort 359 is not present/);
  assert.match(up, /sort 361 \/ F204 is taken/);
  assert.equal(scanSql(up).length, 0);
  assert.equal(scanSql(down).length, 0);
  assert.match(down, /2d9f3d968a51790d3395c0367af70578/);
  assert.match(down, /e4c7271b2efe49ed45117f600b6fe954/);
  assert.match(down, /e6018eac99505f2548df1ae0c8647c58/);
});

test('a green icon counts and the button is given the outstanding sentence', () => {
  assert.match(up, /station_icon_completion_578/);
  assert.match(up, /pdc_qc_line_counts_complete_590/);
  assert.match(up, /qc_signoff_outstanding_590/);
  assert.match(up, /is still required\. The station icon is not green\./);
  assert.match(up, /still has an open booking\./);
  assert.match(up, /The vehicle is still in /);
  assert.match(up, /The vehicle is not at PMB or the QC gate\./);
  assert.match(up, /This vehicle is not an active workshop vehicle\./);
  assert.match(up, /A job-card line is not on a station and is not ticked\./);
  assert.match(up, / is not ticked\./);
  assert.match(up, /has no hours, so it cannot be signed off\./);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /9be0883b1a555f48f3c1ba9fa111c891/);
  assert.match(up, /b62fb7c29ffd2a1629f214f696e5cb14/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/i);
  assert.match(up, /pins\.n = 241/);
  const check = up.slice(up.indexOf('$chk590$') + 8, up.lastIndexOf('$chk590$'));
  assert.doesNotMatch(check, /expected_function_md5\s*\)\s*(=|<>|!=|is\s+distinct\s+from|is\s+not\s+distinct\s+from)\s*[0-9]+/i);
});

test('the sign-off bar stays visible and names what is outstanding', () => {
  const start = app.indexOf('function qcPageSignoffCacheKey(');
  const end = app.indexOf('async function qcPageLoadSignoffOutstanding(');
  const source = app.slice(start, end);
  const context = {
    qcPageSignoffBlockers: new Map(),
    qcPageOperationLines: vehicle => vehicle.lines || [],
    qcPageStageLabel: stage => ({ FITTING: 'Fitting', SUBLET: 'Sublet' }[stage] || stage),
    qcPageAllOperationLinesComplete: vehicle => {
      const lines = vehicle.lines || [];
      return lines.length > 0 && lines.every(line => line.completed === true);
    },
  };
  vm.createContext(context);
  vm.runInContext(`${source}\nthis.status = qcPageSignoffStatus;`, context);
  const unticked = context.status({
    __emailVehicleId: 'v',
    __emailVehicleVersion: 1,
    lines: [{ completed: false, stageCode: 'FITTING', description: 'FILL WITH FUEL' }],
  }, { photoValid: true, outstanding: [] });
  assert.equal(unticked.ready, false);
  assert.match(unticked.note, /Fitting: FILL WITH FUEL is not ticked\./);

  const sublet = context.status({
    __emailVehicleId: 'bc6e92b8-b476-4645-956c-5305f10c7231',
    __emailVehicleVersion: 39,
    lines: [{ completed: true, stageCode: 'SUBLET', description: 'Transport' }],
  }, { photoValid: true, outstanding: ['Sublet is still required. The station icon is not green.'] });
  assert.equal(sublet.ready, false);
  assert.match(sublet.note, /Sublet is still required\. The station icon is not green\./);

  const ready = context.status({
    __emailVehicleId: 'bc6e92b8-b476-4645-956c-5305f10c7231',
    __emailVehicleVersion: 39,
    lines: [{ completed: true, stageCode: 'FITTING', description: 'FILL WITH FUEL' }],
  }, { photoValid: true, outstanding: [] });
  assert.equal(ready.ready, true);
  assert.match(ready.note, /Photo stored\./);

  assert.match(app, /qc-signoff-button/);
  assert.match(app, /signoff\.ready && !signoffBusy/);
  assert.doesNotMatch(app, /signoffReady \? `<button/);
  assert.equal(mobile, karrathaMobile);
  assert.match(mobile, /qcPageSignoffStatus/);
  assert.match(service, /readQcSignoffOutstanding/);
  assert.match(service, /outstanding: Array\.isArray\(body\?\.outstanding\)/);
  assert.match(index, /r590=2026\.10\.28\.r590/);
});
