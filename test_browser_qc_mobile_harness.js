'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');

const {
  PUBLIC_FIXTURE_ASSETS,
  createFixtureServer,
} = require('./browser_qc_mobile_reliability');
const harnessSource = fs.readFileSync('browser_qc_mobile_reliability.js', 'utf8');

for (const contract of [
  "serviceWorkers: 'block'",
  "page.routeWebSocket('**/*'",
  'externalWebSockets.push(',
  "fetch('https://non-local.invalid/qc-harness-probe')",
  "new WebSocket('wss://non-local.invalid/qc-harness-probe')",
  "navigator.serviceWorker.register('/service-worker-hostile.js')",
]) assert.ok(harnessSource.includes(contract), `browser network isolation contract missing: ${contract}`);

function request(server, requestPath) {
  return new Promise((resolve, reject) => {
    const request = http.request({
      host: '127.0.0.1',
      port: server.address().port,
      method: 'GET',
      path: requestPath,
    }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve({
        status: response.statusCode,
        headers: response.headers,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    request.on('error', reject);
    request.end();
  });
}

async function listen(server) {
  await new Promise((resolve, reject) => server.listen(0, '127.0.0.1', error => error ? reject(error) : resolve()));
}

async function close(server) {
  if (!server.listening) return;
  await new Promise(resolve => server.close(resolve));
}

(async () => {
  assert.ok(PUBLIC_FIXTURE_ASSETS instanceof Set, 'fixture server must use an explicit public asset allowlist');
  for (const asset of [
    'test-75.html',
    'favicon.svg',
    'styles.css',
    'desktop-operations.css',
    'workshop-planner.css',
    'assets/pmb-logo.png',
    'data-test-75.js',
    'arb-labor-catalog.js',
    'ai-board-advisor.js',
    'workshop-eligibility.js',
    'workshop-data-service.js',
    'workshop-planner.js',
    'workshop-realtime.js',
    'workshop-shared-actions.js',
    'vehicle-location-lifecycle.js',
    'app.js',
  ]) assert.ok(PUBLIC_FIXTURE_ASSETS.has(asset), `fixture allowlist must include required asset ${asset}`);

  const ignoredCheckoutProbe = path.join(__dirname, '.env.qc-browser-harness-probe');
  fs.writeFileSync(ignoredCheckoutProbe, 'IGNORED-CHECKOUT-SECRET-MUST-NOT-LEAK');
  const checkoutServer = createFixtureServer();
  await listen(checkoutServer);
  try {
    assert.strictEqual((await request(checkoutServer, '/test-75.html')).status, 200, 'normal checkout fixture loads through the default allowlist');
    for (const hostilePath of [
      '/.git',
      '/package.json',
      '/docs/website-development/STATUS.md',
      '/test_browser_qc_mobile_harness.js',
      '/browser_qc_mobile_reliability.js',
      '/scripts/pdc_staging_runtime.py',
      '/.env.qc-browser-harness-probe',
      '/definitely-unknown-checkout-file.txt',
    ]) {
      const rejected = await request(checkoutServer, hostilePath);
      assert.strictEqual(rejected.status, 404, `${hostilePath} is directly rejected from the checkout server`);
      assert.strictEqual(rejected.body, 'not found', `${hostilePath} cannot disclose checkout bytes`);
    }
  } finally {
    await close(checkoutServer);
    fs.rmSync(ignoredCheckoutProbe, { force: true });
  }

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-qc-browser-harness-'));
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-qc-browser-outside-'));
  const platformLimitations = [];
  try {
    for (const [name, body] of Object.entries({
      'test-75.html': '<!doctype html><title>fixture</title>',
      'package.json': 'PACKAGE-METADATA-MUST-NOT-LEAK',
      '.env.local': 'IGNORED-LOCAL-SECRET-MUST-NOT-LEAK',
      'unknown.txt': 'UNKNOWN-MUST-NOT-LEAK',
      '..name.txt': 'VALID-DOT-DOT-PREFIX',
    })) fs.writeFileSync(path.join(temp, name), body);
    fs.mkdirSync(path.join(temp, '.git'));
    fs.writeFileSync(path.join(temp, '.git', 'config'), 'GIT-METADATA-MUST-NOT-LEAK');
    fs.mkdirSync(path.join(temp, 'docs'));
    fs.writeFileSync(path.join(temp, 'docs', 'private.md'), 'DOCS-MUST-NOT-LEAK');
    fs.mkdirSync(path.join(temp, 'tests'));
    fs.writeFileSync(path.join(temp, 'tests', 'private.js'), 'TESTS-MUST-NOT-LEAK');
    fs.mkdirSync(path.join(temp, 'scripts'));
    fs.writeFileSync(path.join(temp, 'scripts', 'private.pyc'), 'IGNORED-SCRIPT-MUST-NOT-LEAK');
    fs.mkdirSync(path.join(temp, 'directory.txt'));

    const server = createFixtureServer(temp, new Set([...PUBLIC_FIXTURE_ASSETS, '..name.txt', 'directory.txt']));
    await listen(server);
    try {
      const normal = await request(server, '/test-75.html?cache-bust=1');
      assert.strictEqual(normal.status, 200, 'allowlisted fixture asset loads');
      assert.ok(normal.body.includes('<title>fixture</title>'), 'allowlisted fixture body is served');
      assert.strictEqual(normal.headers['x-content-type-options'], 'nosniff', 'fixture responses disable MIME sniffing');
      assert.ok(normal.headers['content-security-policy']?.includes("connect-src 'self'"), 'fixture responses restrict browser connections to the local origin');

      const validDotPrefix = await request(server, '/..name.txt');
      assert.strictEqual(validDotPrefix.status, 200, 'an allowlisted filename beginning ..name is not mistaken for traversal');

      for (const hostilePath of [
        '/.git',
        '/.git/config',
        '/package.json',
        '/.env.local',
        '/docs/private.md',
        '/tests/private.js',
        '/scripts/private.pyc',
        '/unknown.txt',
        '/directory.txt',
        '/../package.json',
        '/%2e%2e/package.json',
        '/%2e%2e%2fpackage.json',
        '/..%5cpackage.json',
        '/assets%2fpmb-logo.png',
        '/assets%5cpmb-logo.png',
        '/%252e%252e%252fpackage.json',
        '//package.json',
        '/%',
        '/%E0%A4%A',
      ]) {
        const rejected = await request(server, hostilePath);
        assert.strictEqual(rejected.status, 404, `${hostilePath} is rejected fail-closed`);
        assert.strictEqual(rejected.body, 'not found', `${hostilePath} returns only the generic denial body`);
      }

      const afterMalformed = await request(server, '/test-75.html');
      assert.strictEqual(afterMalformed.status, 200, 'malformed URL probes do not terminate the fixture server');
    } finally {
      await close(server);
    }

    fs.writeFileSync(path.join(outside, 'secret.txt'), 'OUTSIDE-ROOT-SECRET');
    for (const [kind, linkName, target, type, allowlistedPath] of [
      ['file symlink', 'linked-secret.txt', path.join(outside, 'secret.txt'), 'file', 'linked-secret.txt'],
      ['directory junction', 'linked-directory', outside, 'junction', 'linked-directory/secret.txt'],
    ]) {
      const link = path.join(temp, linkName);
      try {
        fs.symlinkSync(target, link, type);
      } catch (error) {
        if (['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) {
          platformLimitations.push(`${kind}:${error.code}`);
          continue;
        }
        throw error;
      }
      const linkServer = createFixtureServer(temp, new Set([allowlistedPath]));
      await listen(linkServer);
      try {
        const rejected = await request(linkServer, `/${allowlistedPath}`);
        assert.strictEqual(rejected.status, 404, `${kind} escape is rejected even when allowlisted`);
        assert.ok(!rejected.body.includes('OUTSIDE-ROOT-SECRET'), `${kind} cannot disclose outside-root bytes`);
      } finally {
        await close(linkServer);
      }
    }

    const symlinkRoot = path.join(temp, 'linked-root');
    try {
      fs.symlinkSync(outside, symlinkRoot, 'junction');
      const rootServer = createFixtureServer(symlinkRoot, new Set(['secret.txt']));
      await listen(rootServer);
      try {
        assert.strictEqual((await request(rootServer, '/secret.txt')).status, 404, 'a reparse/symlink fixture root is rejected');
      } finally {
        await close(rootServer);
      }
    } catch (error) {
      if (!['EPERM', 'EACCES', 'ENOTSUP'].includes(error.code)) throw error;
      platformLimitations.push(`root junction:${error.code}`);
    }
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
    fs.rmSync(outside, { recursive: true, force: true });
  }

  console.log(`QC browser harness hostile filesystem probes passed${platformLimitations.length ? ` with platform limitations: ${platformLimitations.join(', ')}` : ''}`);
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
