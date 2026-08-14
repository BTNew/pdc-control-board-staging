'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const config = JSON.parse(fs.readFileSync('staticwebapp.config.json', 'utf8'));
const catchAll = (config.routes || []).find(route => route.route === '/*');
assert.deepStrictEqual(catchAll?.allowedRoles, ['authenticated'], 'SWA catch-all route must require authenticated users');
assert.deepStrictEqual(config.responseOverrides?.['401'], {
  redirect: '/.auth/login/aad',
  statusCode: 302,
}, 'anonymous requests must redirect to Microsoft login');
assert.strictEqual(config.navigationFallback?.rewrite, '/index.html', 'extensionless authenticated SPA routes must retain index fallback');

const exclusions = config.navigationFallback?.exclude || [];
const exclusionSet = new Set(exclusions);
const protectedRoots = ['/.git', '/.github', '/_staging_test_tools', '/node_modules', '/coverage', '/dist', '/build', '/private', '/supabase', '/tests', '/scripts', '/backend'];
const extensionPattern = exclusions.find(pattern => pattern.startsWith('/*.{'));
assert.ok(extensionPattern, 'non-SPA extension exclusion must exist');
const extensions = new Set(extensionPattern.slice(4, -1).split(','));

function excludedFromFallback(requestPath) {
  const cleanPath = String(requestPath || '').split(/[?#]/, 1)[0];
  if (exclusionSet.has(cleanPath)) return true;
  if (cleanPath.startsWith('/.env')) return true;
  if (protectedRoots.some(root => cleanPath.startsWith(`${root}/`))) return true;
  const basename = cleanPath.slice(cleanPath.lastIndexOf('/') + 1);
  const extension = basename.includes('.') ? basename.slice(basename.lastIndexOf('.') + 1).toLowerCase() : '';
  return extensions.has(extension);
}

function emulateRequest(requestPath, { authenticated = true, exists = false } = {}) {
  if (!authenticated) return { status: 302, location: '/.auth/login/aad', body: '' };
  if (exists) return { status: 200, location: '', body: 'static-file' };
  if (excludedFromFallback(requestPath)) return { status: 404, location: '', body: 'not-found' };
  return { status: 200, location: '', body: 'index.html' };
}

for (const requestPath of ['/', '/dashboard', '/vehicles/STK-1']) {
  assert.deepStrictEqual(emulateRequest(requestPath), { status: 200, location: '', body: 'index.html' }, `${requestPath}: authenticated extensionless SPA route must retain fallback`);
}

for (const requestPath of [
  '/private', '/private/missing',
  '/supabase', '/supabase/staging_only/secret.sql',
  '/tests', '/tests/fixtures/test.pem',
  '/scripts', '/scripts/build.py',
  '/backend', '/backend/runtime.py',
  '/.git', '/.git/config', '/.github/workflows/deploy.yml', '/.env.production',
  '/_staging_test_tools/run.sh', '/node_modules/package/index.js', '/coverage/index.html', '/dist/app.js', '/build/report.json',
  '/definitely-missing.js', '/missing.html', '/missing.css', '/missing.json', '/missing.md', '/missing.sql', '/missing.pem', '/missing.zip',
]) {
  const result = emulateRequest(requestPath);
  assert.strictEqual(result.status, 404, `${requestPath}: authenticated private/missing request must return 404`);
  assert.notStrictEqual(result.body, 'index.html', `${requestPath}: authenticated private/missing request must never receive SPA HTML`);
}

for (const requestPath of ['/', '/dashboard', '/private/missing', '/definitely-missing.js']) {
  assert.deepStrictEqual(emulateRequest(requestPath, { authenticated: false }), {
    status: 302,
    location: '/.auth/login/aad',
    body: '',
  }, `${requestPath}: anonymous request must redirect before fallback evaluation`);
}

for (const requestPath of ['/app.js', '/styles.css', '/assets/pmb-logo.png']) {
  const diskPath = path.join(__dirname, requestPath.slice(1));
  assert.ok(fs.existsSync(diskPath), `${requestPath}: static fixture must exist`);
  assert.strictEqual(emulateRequest(requestPath, { exists: true }).status, 200, `${requestPath}: existing authenticated static file remains available`);
}

console.log('PASS Azure SWA fail-closed routing and authentication semantics');
