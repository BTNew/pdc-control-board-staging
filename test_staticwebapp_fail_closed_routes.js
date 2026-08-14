'use strict';

const assert = require('assert');
const fs = require('fs');

const publiclyServedFiles = new Set(['index.html', 'app.js']);
const config = JSON.parse(fs.readFileSync('staticwebapp.config.json', 'utf8'));
const catchAll = config.routes.find(route => route.route === '/*');
assert(catchAll, 'catch-all authentication route is required');
assert.deepStrictEqual(catchAll.allowedRoles, ['authenticated']);
assert.strictEqual(catchAll.rewrite, undefined, 'catch-all authentication route must never rewrite missing requests');
assert.strictEqual(config.navigationFallback, undefined, 'navigationFallback must be absent so every missing request fails closed');
assert.strictEqual(config.responseOverrides?.['401']?.statusCode, 302);
assert.strictEqual(config.responseOverrides?.['401']?.redirect, '/.auth/login/aad');

function resolveRequest(requestPath, authenticated) {
  if (!authenticated) return { status: 302, location: '/.auth/login/aad', body: '' };
  const target = requestPath === '/' ? 'index.html' : requestPath.replace(/^\//, '');
  if (publiclyServedFiles.has(target)) {
    return { status: 200, location: '', body: fs.readFileSync(target, 'utf8') };
  }
  return { status: 404, location: '', body: 'Not Found' };
}

for (const requestPath of ['/', '/app.js']) {
  const response = resolveRequest(requestPath, true);
  assert.strictEqual(response.status, 200, `${requestPath} must resolve only because the exact file exists`);
}

for (const requestPath of [
  '/dashboard',
  '/vehicles/STK1',
  '/staticwebapp.config.json',
  '/private',
  '/private/missing',
  '/supabase',
  '/supabase/staging_only/254_disable_ai_auditor_typed_operation_control.sql',
  '/tests/fixtures/client.key.pem',
  '/scripts/build.py',
  '/backend/runtime.py',
  '/.git/config',
  '/.github/workflows/deploy.yml',
  '/.env',
  '/missing.js',
  '/missing.html',
  '/missing.sql',
  '/missing.md',
  '/missing.pem',
  '/missing.zip'
]) {
  const response = resolveRequest(requestPath, true);
  assert.strictEqual(response.status, 404, `${requestPath} must fail closed for authenticated users`);
  assert(!response.body.includes('<!DOCTYPE html'), `${requestPath} must never receive SPA HTML`);
  assert(!response.body.includes('2026.08.14.60-swa-control-file-proof'), `${requestPath} must never receive app HTML`);
}

for (const requestPath of ['/', '/private', '/private/missing', '/dashboard', '/missing.js']) {
  const response = resolveRequest(requestPath, false);
  assert.strictEqual(response.status, 302, `${requestPath} must redirect anonymous requests to AAD`);
  assert.strictEqual(response.location, '/.auth/login/aad');
}

console.log('PASS Azure SWA fail-closed routing and authentication semantics');
