'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const sentinel = 'UNTRACKED_PACKAGE_SENTINEL.js';
const npmCli = path.join(path.dirname(process.execPath),'node_modules','npm','bin','npm-cli.js');

// Inspect the allowlist with lifecycle scripts disabled: local logs, populated
// environment files and generated SQL must not be members.
const result = spawnSync(process.execPath, [npmCli,'pack','--dry-run','--json','--ignore-scripts'], { encoding:'utf8' });
assert.strictEqual(result.status,0,result.stderr || result.stdout);
const report = JSON.parse(result.stdout);
const files = report.flatMap(item => item.files || []).map(item => item.path);
assert.ok(files.includes('app.js'),'package allowlist must retain the application source');
assert.ok(files.includes('tests/sql/ai_auditor_253/07_typed_value_boundaries.sql'),'package allowlist must retain migration regression evidence');
assert.ok(!files.some(file => /(?:^|\/)(?:\.env$|\.env\.(?:local|staging|production)$|.*\.log$|pdc_auditor_253_test_signing_boundaries\.sql$)/.test(file)),'secret/evidence/runtime residue entered npm package');

// Standard npm pack runs prepack. Prove its Git gate rejects an arbitrary
// untracked JavaScript file that the broad static-site allowlist would match.
const temp = fs.mkdtempSync(path.join(os.tmpdir(),'pdc-npm-pack-gate-'));
try {
  const gate = path.join(temp,'verify_npm_pack_inputs.js');
  fs.copyFileSync('scripts/verify_npm_pack_inputs.js',gate);
  assert.strictEqual(spawnSync('git',['init','-q'],{cwd:temp}).status,0);
  fs.writeFileSync(path.join(temp,'tracked.js'),'tracked\n');
  assert.strictEqual(spawnSync('git',['add','tracked.js'],{cwd:temp}).status,0);
  fs.writeFileSync(path.join(temp,sentinel),'untracked\n');
  const blocked = spawnSync(process.execPath,[gate],{cwd:temp,encoding:'utf8'});
  assert.notStrictEqual(blocked.status,0,'prepack gate accepted an untracked matching package input');
  assert.ok(blocked.stderr.includes('NPM_PACK_INPUTS_BLOCKED'));
} finally { fs.rmSync(temp,{recursive:true,force:true}); }
console.log('NPM package allowlist, residue exclusions and tracked-only prepack gate passed');
