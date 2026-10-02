'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const vm = require('node:vm');
const builder = require('./scripts/build_pages_runtime.js');

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-pages-artifact-test-'));
const sourceRoot = path.join(temporaryRoot, 'source');
fs.mkdirSync(sourceRoot);
for (const filename of builder.RUNTIME_FILES) {
  const target = path.join(sourceRoot, filename);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.copyFileSync(path.join(__dirname, filename), target);
}
test.after(() => {
  const absolute = path.resolve(temporaryRoot);
  const parent = path.resolve(os.tmpdir());
  if (path.dirname(absolute) !== parent || !path.basename(absolute).startsWith('pdc-pages-artifact-test-')) throw new Error('Unsafe fixture cleanup path');
  fs.rmSync(absolute, { recursive: true, force: true });
});

function filesBelow(root, relative = '') {
  return fs.readdirSync(path.join(root, relative), { withFileTypes: true }).flatMap(entry => {
    const filename = relative ? relative + '/' + entry.name : entry.name;
    return entry.isDirectory() ? filesBelow(root, filename) : [filename];
  }).sort();
}
function replaceFixture(t, filename, change) {
  const absolute = path.join(sourceRoot, filename), before = fs.readFileSync(absolute);
  fs.writeFileSync(absolute, change(before.toString('utf8')));
  t.after(() => fs.writeFileSync(absolute, before));
}

test('artifact keeps exact entry, deferred modules, PDF/QZ workers and guide bytes while excluding private repository material', () => {
  const excluded = [
    'review-evidence/fixture.json', 'handoffs/fixture.json', 'backend/runtime.py',
    'supabase/migrations/fixture.sql', 'tests/fixture.js', 'scripts/pdc_backup.py',
    'data/operational-export.json', 'outputs/backup.bin', 'sales/README.md',
    'sales/leads.js', 'deployment-identity.json'
  ];
  for (const filename of excluded) {
    const absolute = path.join(sourceRoot, filename);
    fs.mkdirSync(path.dirname(absolute), { recursive: true });
    fs.writeFileSync(absolute, 'Unlisted fictional private fixture');
  }
  const outputRoot = path.join(temporaryRoot, 'artifact');
  const result = builder.buildRuntimeArtifact(sourceRoot, outputRoot);
  assert.equal(result.fileCount, builder.RUNTIME_FILES.length);
  assert.deepEqual(filesBelow(outputRoot), [...builder.RUNTIME_FILES]);
  for (const filename of builder.RUNTIME_FILES) {
    const digest = root => crypto.createHash('sha256').update(fs.readFileSync(path.join(root, filename))).digest('hex');
    assert.equal(digest(outputRoot), digest(sourceRoot), filename + ' must keep its URL, content and file bytes');
  }
  for (const filename of excluded) assert.equal(fs.existsSync(path.join(outputRoot, filename)), false, filename);
  for (const filename of builder.ENTRY_POINTS) assert.ok(fs.existsSync(path.join(outputRoot, filename)), filename);
  for (const filename of ['workshop-planner.js', 'workshop-shared-actions.js', 'workshop-realtime.js', 'vendor/qz/qz-tray.js', 'vendor/pdfjs/pdf.worker.min.js', 'scripts/stage2b_c4_browser_export.js']) assert.ok(fs.existsSync(path.join(outputRoot, filename)), filename);
});

test('a newly referenced existing module must receive explicit publication review', t => {
  const added = path.join(sourceRoot, 'new-runtime-module.js');
  fs.writeFileSync(added, 'window.FICTIONAL_NEW_MODULE = true;');
  t.after(() => fs.unlinkSync(added));
  replaceFixture(t, 'app.js', text => text + '\nloadExternalScript("new-runtime-module.js");\n');
  assert.throws(() => builder.validateRuntime(sourceRoot), /dependency is not allowlisted/);
});

test('an HTML reference to a missing or private file fails rather than widening publication', t => {
  replaceFixture(t, 'sales/index.html', text => text + '\n<script src="../backend/runtime.py"></script>');
  assert.throws(() => builder.validateRuntime(sourceRoot), /dependency is not allowlisted/);
});

test('a missing required runtime file cannot produce a deceptively successful artifact', t => {
  const filename = path.join(sourceRoot, 'vendor/pdfjs/pdf.worker.min.js');
  const bytes = fs.readFileSync(filename);
  fs.unlinkSync(filename);
  t.after(() => fs.writeFileSync(filename, bytes));
  assert.throws(() => builder.buildRuntimeArtifact(sourceRoot, path.join(temporaryRoot, 'missing-artifact')), /ENOENT/);
  assert.equal(fs.existsSync(path.join(temporaryRoot, 'missing-artifact')), false);
});

test('public fallback operational rows or extra manifest fields block the artifact before any output', t => {
  replaceFixture(t, 'data-staging-empty.js', text => text.replace('"vehicles": []', '"vehicles": [{"customer":"Fictional fixture"}]'));
  assert.throws(() => builder.buildRuntimeArtifact(sourceRoot, path.join(temporaryRoot, 'row-artifact')), /operational records/);
  assert.equal(fs.existsSync(path.join(temporaryRoot, 'row-artifact')), false);
});

test('public deployment metadata cannot contain an unreviewed record payload', t => {
  replaceFixture(t, 'deployment-manifest.json', text => JSON.stringify({ ...JSON.parse(text), rows: [{ customer: 'Fictional fixture' }] }));
  assert.throws(() => builder.validateRuntime(sourceRoot), /unreviewed fields/);
});

test('a stale sales release identity blocks the artifact', t => {
  replaceFixture(t, 'deployment-manifest.json', text => JSON.stringify({ ...JSON.parse(text), salesTrackerVersion: 'fictional-stale-version' }));
  assert.throws(() => builder.validateRuntime(sourceRoot), /version does not match/);
});

test('privileged frontend credentials block publication without exposing their values', t => {
  const fake = 'sb_' + 'secret_' + 'FictionalTestOnly123456789';
  replaceFixture(t, 'site-switcher.js', text => text + '\nconst fictionalSecret = "' + fake + '";');
  assert.throws(() => builder.validateRuntime(sourceRoot), error => {
    assert.match(error.message, /Privileged token.*value redacted/);
    assert.equal(error.message.includes(fake), false);
    return true;
  });
});

test('existing output and source checkout are preserved instead of overwritten or recursively deleted', () => {
  const outputRoot = path.join(temporaryRoot, 'existing');
  fs.mkdirSync(outputRoot);
  fs.writeFileSync(path.join(outputRoot, 'keep.txt'), 'Keep this fixture');
  assert.throws(() => builder.buildRuntimeArtifact(sourceRoot, outputRoot), /new or empty/);
  assert.equal(fs.readFileSync(path.join(outputRoot, 'keep.txt'), 'utf8'), 'Keep this fixture');
  assert.throws(() => builder.buildRuntimeArtifact(sourceRoot, sourceRoot), /cannot replace/);
  assert.throws(() => builder.buildRuntimeArtifact(sourceRoot, temporaryRoot), /cannot replace/);
});

test('allowlist guards retain the one reviewed browser helper and refuse traversal or private paths', () => {
  for (const filename of ['../app.js', '/app.js', 'sales\\sales.js', 'supabase/fixture.sql', 'scripts/pdc_backup.py', 'review-evidence/fixture.json', 'sales/leads.js']) assert.equal(builder.safePublicPath(filename), false, filename);
  assert.equal(builder.safePublicPath('scripts/stage2b_c4_browser_export.js'), true);
});

test('Pages workflow publishes only the guarded runtime artifact from staging main and never a pull request', () => {
  const workflow = fs.readFileSync(path.join(__dirname, '.github/workflows/pages-runtime.yml'), 'utf8');
  assert.match(workflow, /node --test test_\*\.js/);
  assert.match(workflow, /node scripts\/build_pages_runtime\.js --output _site/);
  assert.match(workflow, /path: _site/);
  assert.doesNotMatch(workflow, /path:\s*['"]?\.(?:['"]?\s*$)/m);
  assert.match(workflow, /pages\.build_type !== 'workflow'/);
  assert.match(workflow, /enablement: false/);
  assert.match(workflow, /github\.event_name != 'pull_request'/);
  assert.match(workflow, /github\.repository == 'BTNew\/pdc-control-board-staging'/);
  assert.match(workflow, /github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /needs: build/);
  assert.match(workflow, /pages: write/);
  assert.match(workflow, /id-token: write/);
  assert.match(workflow, /persist-credentials: false/);
  const actions = [...workflow.matchAll(/uses: actions\/[^@\s]+@([^\s]+)/g)];
  assert.equal(actions.length, 5);
  for (const action of actions) assert.match(action[1], /^[0-9a-f]{40}$/);
});

test('same-repository PR source observation is GET-only, enum-only and cannot configure or deploy Pages', async () => {
  const workflow = fs.readFileSync(path.join(__dirname, '.github/workflows/pages-runtime.yml'), 'utf8');
  const observation = workflow.match(/      - name: Observe Pages source for a same-repository pull request\r?\n([\s\S]+?)      - name: Require the GitHub Actions publishing source/);
  assert.ok(observation, 'the PR-only source observation step must exist separately from the main publishing guard');
  const block = observation[1];
  const condition = block.match(/if: ([^\r\n]+)/)?.[1];
  assert.ok(condition, 'source observation needs an explicit scope condition');
  assert.match(condition, /github\.event_name == 'pull_request'/);
  assert.match(condition, /github\.repository == 'BTNew\/pdc-control-board-staging'/);
  assert.match(condition, /github\.event\.pull_request\.head\.repo\.full_name == github\.repository/);
  assert.match(block, /PAGES_READ_TOKEN: \$\{\{ github\.token \}\}/);
  assert.match(workflow, /build:[\s\S]*?permissions:\s*contents: read\s*pages: read/);
  assert.doesNotMatch(block, /configure-pages|deploy-pages|pages: write|id-token: write|method:\s*['"](?:POST|PUT|PATCH|DELETE)['"]/i);
  const repo = 'BTNew/pdc-control-board-staging';
  const event = (eventName, repository = repo, headRepository = repo) => ({event_name:eventName,repository,ref:'refs/heads/main',event:{pull_request:{head:{repo:{full_name:headRepository}}}}});
  const allowed = github => vm.runInNewContext(condition, {github}, {timeout:100});
  assert.equal(allowed(event('pull_request')), true);
  assert.equal(allowed(event('pull_request', repo, 'fictional-fork/staging')), false);
  assert.equal(allowed(event('pull_request', 'fictional-owner/other')), false);
  assert.equal(allowed(event('push')), false);
  assert.equal(allowed(event('workflow_dispatch')), false);
  for (const pattern of [
    /- name: Require the GitHub Actions publishing source\s+if: ([^\r\n]+)/,
    /- name: Configure Pages metadata\s+if: ([^\r\n]+)/,
    /\n  deploy:\s*\n    if: ([^\r\n]+)/
  ]) {
    const guard = workflow.match(pattern)?.[1];
    assert.ok(guard, 'publishing and configuration must keep explicit non-PR conditions');
    assert.equal(vm.runInNewContext(guard, {github:event('pull_request')}, {timeout:100}), false);
  }
  const code = block.match(/node --input-type=module <<'NODE'\r?\n([\s\S]+?)\r?\n          NODE/)?.[1];
  assert.ok(code, 'the source observation must use the reviewed standalone read-only script');
  const run = async (buildType, ok = true, status = 200) => {
    const logs = [], calls = [];
    const sandbox = {
      process:{env:{GITHUB_API_URL:'https://api.github.com',GITHUB_REPOSITORY:repo,PAGES_READ_TOKEN:'FictionalPreviewTokenOnly'}},
      console:{log:value=>logs.push(String(value))},
      fetch:async(url, options)=>{calls.push({url,options});return {ok,status,json:async()=>({build_type:buildType,unreviewed_metadata:'FictionalPrivateMetadataOnly'})};}
    };
    let error;
    try { await vm.runInNewContext('(async()=>{\n'+code+'\n})()', sandbox, {timeout:100}); } catch (e) { error = e; }
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, 'https://api.github.com/repos/'+repo+'/pages');
    assert.equal(calls[0].options.method || 'GET', 'GET');
    assert.equal(calls[0].options.body, undefined);
    assert.equal(calls[0].options.headers.Authorization, 'Bearer FictionalPreviewTokenOnly');
    assert.equal(calls[0].options.headers['X-GitHub-Api-Version'], '2026-03-10');
    assert.equal(logs.some(line=>/FictionalPreviewTokenOnly|FictionalPrivateMetadataOnly/.test(line)), false);
    return {logs,error};
  };
  for (const type of ['legacy','workflow']) {
    const result = await run(type);
    assert.equal(result.error, undefined);
    assert.deepEqual(result.logs, ['Pages build_type: '+type]);
  }
  const unknown = await run('FictionalUnrecognizedBuildType');
  assert.match(unknown.error?.message || '', /unknown build type/);
  assert.doesNotMatch(unknown.error.message, /FictionalUnrecognizedBuildType|FictionalPreviewTokenOnly|FictionalPrivateMetadataOnly/);
  assert.deepEqual(unknown.logs, []);
  const failure = await run('workflow', false, 403);
  assert.match(failure.error?.message || '', /HTTP 403/);
  assert.deepEqual(failure.logs, []);
});
