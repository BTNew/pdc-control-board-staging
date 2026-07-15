'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = __dirname;
const authSource = fs.readFileSync(path.join(root, 'pdc-auth.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const configExample = fs.readFileSync(path.join(root, 'pdc-supabase-config.example.js'), 'utf8');
const vendor = fs.readFileSync(path.join(root, 'vendor', 'supabase', 'supabase-2.110.5.js'), 'utf8');

assert.ok(index.includes('<body class="auth-pending"'), 'Production shell must start locked');
assert.ok(index.includes('id="app-shell" inert aria-hidden="true"'), 'Production application must be inert before authorization');
assert.ok(index.includes('id="pdc-microsoft-login"'), 'Microsoft sign-in action is missing');
assert.ok(index.includes('id="pdc-auth-signout"'), 'Sign-out action is missing');
assert.ok(index.indexOf('vendor/supabase/supabase-2.110.5.js') < index.indexOf('pdc-auth.js'), 'Supabase client must load before the auth gate');
assert.ok(index.indexOf('pdc-supabase-config.js') < index.indexOf('pdc-auth.js'), 'Browser config must load before the auth gate');
assert.ok(index.indexOf('pdc-auth.js') < index.indexOf('app.js'), 'Auth gate must initialize before application code');
assert.ok(vendor.includes('supabase') && vendor.length > 150000, 'Pinned Supabase browser bundle is missing or incomplete');
assert.ok(configExample.includes("provider: 'azure'"), 'Microsoft/Azure must be the configured provider');
assert.ok(!authSource.includes('URLSearchParams') && !authSource.includes('AUTH_BYPASS'), 'Production auth must not support a query-string bypass');
assert.ok(authSource.includes("scopes: 'email'"), 'Azure OAuth must request the email scope required by Supabase');
assert.ok(authSource.includes(".from('pdc_user_roles')"), 'Authorization must check the protected PDC role table');
assert.ok(authSource.indexOf(".from('pdc_user_roles')") < authSource.indexOf('unlockApplication(session, role)'), 'Role authorization must occur before unlocking the app');

let domReadyHandler = null;
const context = {
  console,
  URL,
  Set,
  Object,
  String,
  Boolean,
  Error,
  Promise,
  CustomEvent: function CustomEvent(type, init) { this.type = type; this.detail = init?.detail; },
  window: {
    location: {
      origin: 'http://localhost:8765',
      pathname: '/index.html',
    },
    addEventListener() {},
    dispatchEvent() {},
    setTimeout,
  },
  document: {
    readyState: 'loading',
    addEventListener(type, handler) { if (type === 'DOMContentLoaded') domReadyHandler = handler; },
    getElementById() { return null; },
    body: {
      dataset: {},
      classList: { add() {}, remove() {} },
    },
  },
  setTimeout,
};
context.globalThis = context;
vm.createContext(context);
vm.runInContext(authSource, context, { filename: 'pdc-auth.js' });

assert.strictEqual(typeof domReadyHandler, 'function', 'Auth initialization should wait for the DOM');
const helpers = context.window.PDC_AUTH_TEST;
assert.ok(helpers.approvedRole({ email: 'staff@example.com', role: 'operator', active: true }, 'STAFF@example.com'), 'Approved roles should be case-insensitive by email');
assert.ok(!helpers.approvedRole({ email: 'staff@example.com', role: 'operator', active: false }, 'staff@example.com'), 'Inactive staff must be denied');
assert.ok(!helpers.approvedRole({ email: 'staff@example.com', role: 'owner', active: true }, 'staff@example.com'), 'Unknown roles must be denied');
assert.ok(!helpers.approvedRole({ email: 'other@example.com', role: 'administrator', active: true }, 'staff@example.com'), 'Mismatched email must be denied');
assert.strictEqual(helpers.safeRedirectTo('https://evil.example/login'), 'http://localhost:8765/index.html', 'OAuth redirect must stay on the current origin');
assert.strictEqual(helpers.safeRedirectTo('/index.html'), 'http://localhost:8765/index.html', 'Same-origin OAuth redirect should be accepted');

console.log('Microsoft authentication gate checks passed');
