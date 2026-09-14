'use strict';
const path = require('node:path');
const { performance } = require('node:perf_hooks');
const { createHash } = require('node:crypto');
const assert = require('node:assert/strict');
const { createFixture } = require('./dashboard-render-fixture.cjs');
const baseline = process.argv[2];
if (!baseline) throw Error('Pass a baseline app.js path; no network or database access is used.');
const output = [];
for (const notesPerVehicle of [0, 20]) {
  const variants = [['before', path.resolve(baseline)], ['after', path.resolve(__dirname, '../app.js')]];
  const results = variants.map(([variant, appPath]) => {
    const f = createFixture({ appPath, notesPerVehicle });
    for (let i = 0; i < 4; i++) f.context.renderIncomingDashboardBoard();
    const times = [];
    for (let i = 0; i < 15; i++) {
      f.resetStats();
      const start = performance.now();
      f.context.renderIncomingDashboardBoard();
      times.push(performance.now() - start);
    }
    return { variant, vehicleCount: 102, notesPerVehicle,
      medianMs: Number(times.sort((a, b) => a - b)[7].toFixed(2)),
      localStorageReads: f.stats.reads, bucketClassifications: f.stats.classifications,
      htmlBytes: Buffer.byteLength(f.host.innerHTML), htmlSha256: createHash('sha256').update(f.host.innerHTML).digest('hex') };
  });
  assert.equal(results[0].htmlSha256, results[1].htmlSha256, 'HTML must remain byte-for-byte identical');
  output.push(...results);
}
console.log(JSON.stringify({ scope: 'Synthetic 102-vehicle application HTML generation; excludes network, layout and paint', results: output }, null, 2));
