'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { spawnSync } = require('child_process');

const sentinel = 'UNTRACKED_PACKAGE_SENTINEL.js';
const npmCli = path.join(path.dirname(process.execPath),'node_modules','npm','bin','npm-cli.js');

// Inspect the allowlist with lifecycle scripts disabled: local logs, populated
// environment files and generated SQL must not be members.
const result = spawnSync(process.execPath, [npmCli,'pack','--dry-run','--json','--ignore-scripts'], { encoding:'utf8' });
assert.strictEqual(result.status,0,result.stderr || result.stdout);
const report = JSON.parse(result.stdout);
const files = report.flatMap(item => item.files || []).map(item => item.path);
const indexHtml = fs.readFileSync('index.html','utf8');
const stagingHtml = fs.readFileSync('staging.html','utf8');
const localRefs = html => [...html.matchAll(/(?:src|href)=["']([^"'#?]+)(?:[?#][^"']*)?["']/g)]
  .map(([,value]) => value)
  .filter(value => value && !/^(?:https?:|data:|#)/.test(value));
const localIndexRefs = localRefs(indexHtml);
const localStagingRefs = [...stagingHtml.matchAll(/(?:src|href)=["']([^"'#?]+)(?:[?#][^"']*)?["']/g)]
  .map(([,value]) => value)
  .filter(value => value && !/^(?:https?:|data:|#)/.test(value));
const productionConfigName = 'pdc-supabase-config.production.js';
const productionConfigSource = fs.readFileSync(productionConfigName,'utf8');
const configContext = { window: { location: { origin:'https://btnew.github.io', pathname:'/pdc-control-board-login/' } } };
vm.runInNewContext(productionConfigSource,configContext,{filename:productionConfigName});
const productionConfig = configContext.window.PDC_SUPABASE_CONFIG;
assert.ok(files.includes('app.js'),'package allowlist must retain the application source');
assert.ok(files.includes('ai-auditor.css'),'package allowlist must retain the stylesheet required by staging.html and the packaged Stage-A UI regression');
assert.ok(files.includes('tests/sql/ai_auditor_253/07_typed_value_boundaries.sql'),'package allowlist must retain migration regression evidence');
assert.ok(files.includes(productionConfigName),'tracked production-safe browser config must be a package input');
assert.ok(!files.includes('random-100-vehicles.csv'),'private/synthetic vehicle fixture must not enter the package');
assert.ok(!indexHtml.includes('random-100-vehicles.csv'),'production index must not expose the vehicle fixture');
assert.ok(indexHtml.indexOf(productionConfigName) < indexHtml.indexOf('pdc-auth.js'),'production config must load before auth');
assert.deepStrictEqual(localIndexRefs.filter(ref => !files.includes(ref)).sort(),[],`package must include every local index.html asset reference`);
assert.deepStrictEqual(localStagingRefs.filter(ref => !files.includes(ref)).sort(),[],`package must include every local staging.html asset reference`);
assert.ok(!files.some(file => /(?:^|\/)(?:\.env$|\.env\.(?:local|staging|production)$|.*\.log$|pdc_auditor_253_test_signing_boundaries\.sql$)/.test(file)),'secret/evidence/runtime residue entered npm package');
assert.ok(!files.includes('pdc-supabase-config.js'),'environment-specific browser config must never be a package input');
assert.ok(productionConfig && typeof productionConfig === 'object','production browser config did not initialize');
assert.strictEqual(productionConfig.projectRef,'vjdtsswhroyguxyfjdkt','production browser config has the wrong project');
assert.strictEqual(productionConfig.url,'https://vjdtsswhroyguxyfjdkt.supabase.co','production browser config has the wrong endpoint');
assert.match(productionConfig.publishableKey,/^sb_publishable_[A-Za-z0-9_-]+$/,'production browser config must contain only a Supabase publishable browser key');
assert.ok(!/sb_secret_|service_role\s*[:=]|client[_-]?secret|password\s*[:=]|-----BEGIN [A-Z ]*PRIVATE KEY-----/i.test(productionConfigSource),'production browser config contains a forbidden secret/private marker');
assert.ok(!productionConfigSource.includes('cdsmnqxtyyoeoznmbidd'),'production browser config contains the staging project');
const allowedConfigFields = new Set(['environment','projectRef','url','publishableKey','auth','workshop','vehicleLifecycle']);
assert.strictEqual(productionConfig.environment,'production','production browser config must declare its environment explicitly');
assert.deepStrictEqual(Object.keys(productionConfig).filter(key => !allowedConfigFields.has(key)),[],'production browser config contains an unreviewed top-level field');

// Materialize exactly the reported package members and exercise the packaged
// regression suite. The child marker prevents this test from recursively
// materializing another package while preserving all allowlist assertions.
if (process.env.PDC_PACKAGE_MATERIALIZED_CHILD !== '1') {
  const materialized = fs.mkdtempSync(path.join(os.tmpdir(),'pdc-npm-pack-materialized-'));
  try {
    for (const file of files) {
      const source = path.resolve(file);
      const target = path.join(materialized,file);
      fs.mkdirSync(path.dirname(target),{recursive:true});
      fs.copyFileSync(source,target);
    }
    const packagedRegression = spawnSync(process.execPath,['test_all.js'],{
      cwd:materialized,
      encoding:'utf8',
      env:{...process.env,PDC_PACKAGE_MATERIALIZED_CHILD:'1'},
    });
    assert.strictEqual(packagedRegression.status,0,packagedRegression.stderr || packagedRegression.stdout);
    assert.match(packagedRegression.stdout,/Test summary: 9 passed, 0 failed, 0 skipped/,'materialized npm package regression summary mismatch');
  } finally { fs.rmSync(materialized,{recursive:true,force:true}); }
}

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

// A Windows checkout can be clean while core.autocrlf has transformed package
// inputs. Exercise the raw-byte gate directly and require it to reject CRLF
// bytes that differ from the staged Git blob.
const byteGateTemp = fs.mkdtempSync(path.join(os.tmpdir(),'pdc-npm-pack-byte-gate-'));
try {
  fs.mkdirSync(path.join(byteGateTemp,'scripts'),{recursive:true});
  fs.copyFileSync('scripts/verify_npm_pack_inputs.js',path.join(byteGateTemp,'scripts','verify_npm_pack_inputs.js'));
  fs.writeFileSync(path.join(byteGateTemp,'package.json'),JSON.stringify({files:['input.js']}));
  fs.writeFileSync(path.join(byteGateTemp,'README.md'),'readme\n');
  const largeLfInput = 'line\n'.repeat(300000);
  fs.writeFileSync(path.join(byteGateTemp,'input.js'),largeLfInput);
  assert.strictEqual(spawnSync('git',['init','-q'],{cwd:byteGateTemp}).status,0);
  assert.strictEqual(spawnSync('git',['config','user.name','PDC Test'],{cwd:byteGateTemp}).status,0);
  assert.strictEqual(spawnSync('git',['config','user.email','pdc-test@example.invalid'],{cwd:byteGateTemp}).status,0);
  assert.strictEqual(spawnSync('git',['add','package.json','README.md','input.js','scripts/verify_npm_pack_inputs.js'],{cwd:byteGateTemp}).status,0);
  assert.strictEqual(spawnSync('git',['commit','-q','-m','test baseline'],{cwd:byteGateTemp}).status,0);
  const exactLargeInput = spawnSync(process.execPath,[path.join(byteGateTemp,'scripts','verify_npm_pack_inputs.js')],{cwd:byteGateTemp,encoding:'utf8'});
  assert.strictEqual(exactLargeInput.status,0,exactLargeInput.stderr || exactLargeInput.stdout);
  fs.writeFileSync(path.join(byteGateTemp,'input.js'),largeLfInput.replaceAll('\n','\r\n'));
  assert.strictEqual(spawnSync('git',['update-index','--assume-unchanged','input.js'],{cwd:byteGateTemp}).status,0);
  assert.strictEqual(spawnSync('git',['status','--porcelain=v1'],{cwd:byteGateTemp,encoding:'utf8'}).stdout,'','test setup must make status alone appear clean');
  const byteBlocked = spawnSync(process.execPath,[path.join(byteGateTemp,'scripts','verify_npm_pack_inputs.js')],{
    cwd:byteGateTemp,
    encoding:'utf8',
  });
  assert.notStrictEqual(byteBlocked.status,0,'prepack byte gate accepted CRLF-transformed package input');
  assert.match(byteBlocked.stderr,/package worktree bytes differ from committed Git blobs/);
  assert.match(byteBlocked.stderr,/input\.js/);
} finally { fs.rmSync(byteGateTemp,{recursive:true,force:true}); }

// Reproduce archive/committed ambient input: even when the sensitive filename
// physically exists outside Git, the exact files[] allowlist must exclude it.
const archive = fs.mkdtempSync(path.join(os.tmpdir(),'pdc-npm-pack-archive-poison-'));
try {
  for (const name of ['package.json','README.md']) fs.copyFileSync(name,path.join(archive,name));
  fs.mkdirSync(path.join(archive,'scripts'),{recursive:true});
  fs.copyFileSync('scripts/verify_npm_pack_inputs.js',path.join(archive,'scripts','verify_npm_pack_inputs.js'));
  fs.writeFileSync(path.join(archive,'pdc-supabase-config.staging.js'),'window.STAGING=true;\n');
  fs.copyFileSync(productionConfigName,path.join(archive,productionConfigName));
  fs.writeFileSync(path.join(archive,'pdc-supabase-config.js'),'window.POISON_SECRET=true;\n');
  const packed = spawnSync(process.execPath,[npmCli,'pack','--dry-run','--json'],{cwd:archive,encoding:'utf8'});
  assert.strictEqual(packed.status,0,packed.stderr || packed.stdout);
  const jsonStart = packed.stdout.indexOf('[');
  assert.ok(jsonStart >= 0,packed.stdout);
  const packedFiles = JSON.parse(packed.stdout.slice(jsonStart)).flatMap(item=>item.files||[]).map(item=>item.path);
  assert.ok(packedFiles.includes('pdc-supabase-config.staging.js'),'staging-safe config must remain packageable');
  assert.ok(packedFiles.includes(productionConfigName),'tracked production-safe config must remain packageable');
  assert.ok(!packedFiles.includes('pdc-supabase-config.js'),'archive/committed ambient browser config leaked into package');
} finally { fs.rmSync(archive,{recursive:true,force:true}); }
console.log('NPM package allowlist, residue exclusions and exact-Git-byte prepack gate passed');
