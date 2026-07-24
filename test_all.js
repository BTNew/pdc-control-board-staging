'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const root = __dirname;
const dataSource = fs.readFileSync(path.join(root, 'data.js'), 'utf8');
const isCleanImportBuild = /["']?vehicles["']?\s*:\s*\[\s*\]/.test(dataSource) && dataSource.length < 5000;
const skipped = new Map();
if (isCleanImportBuild) {
  skipped.set('test_master_sheet_import.js', 'clean import build intentionally ships without the 321-vehicle master dataset');
}
const tests = fs.readdirSync(root)
  .filter(file => /^test_.*\.js$/.test(file) && file !== 'test_all.js')
  .sort((a, b) => a.localeCompare(b));

if (process.argv.includes('--list')) {
  for (const file of tests) {
    const reason = skipped.get(file);
    console.log(reason ? `${file} (skip: ${reason})` : file);
  }
  process.exit(0);
}

let passed = 0;
let failed = 0;
let skippedCount = 0;

for (const file of tests) {
  const reason = skipped.get(file);
  if (reason) {
    skippedCount += 1;
    console.log(`\nSKIP ${file} — ${reason}`);
    continue;
  }
  console.log(`\nRUN  ${file}`);
  const result = spawnSync(process.execPath, [file], { cwd: root, stdio: 'inherit' });
  if (result.status === 0) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL ${file} (exit ${result.status ?? 'unknown'})`);
  }
}

console.log(`\nTest summary: ${passed} passed, ${failed} failed, ${skippedCount} skipped`);
if (failed) process.exit(1);
