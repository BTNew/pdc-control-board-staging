'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const canonicalRelativePath = './';
const canonicalSiteOrigin = 'https://btnew.github.io';
const canonicalSitePath = '/pdc-control-board-staging/';
const approvedExternalOrigins = new Set([
  'https://btnew.github.io',
  'https://cdsmnqxtyyoeoznmbidd.supabase.co',
  'wss://cdsmnqxtyyoeoznmbidd.supabase.co',
]);
const legacyEntryPages = ['staging.html', 'test-50.html', 'test-75.html', 'test-100.html', 'no-vehicles.html'];
const legacyEntryPattern = /(?:^|[\\/'"`])(?:staging|test-(?:50|75|100)|no-vehicles)\.html(?:$|[?#\\/'"`])/i;
const legacyAssetPattern = /(?:data-(?:test-(?:50|75|100)|no-vehicles)|random-100-vehicles\.csv)/i;

function read(name) {
  return fs.readFileSync(path.join(root, name), 'utf8');
}

function assertRedirectStub(name) {
  const html = read(name);
  assert.match(html, /<meta[^>]+http-equiv=["']refresh["'][^>]+content=["']0;\s*url=\.\/["']/i,
    `${name} must redirect immediately to the canonical staging root`);
  assert.match(html, /<link[^>]+rel=["']canonical["'][^>]+href=["']\.\/["']/i,
    `${name} must advertise the canonical staging root`);
  assert.match(html, /<a[^>]+href=["']\.\/["']/i,
    `${name} must expose only the canonical recovery link`);
  assert.doesNotMatch(html, /<(?:script|link)[^>]+(?:src|href)=["'][^"']+\.(?:js|css)(?:\?|["'])/i,
    `${name} must not load an older application or cache target`);
}

const index = read('index.html');
assert.match(index, /<link[^>]+rel=["']canonical["'][^>]+href=["']\.\/["']/i,
  'index.html must declare the canonical staging root');
assert.match(index, /<script[^>]+src=["']canonical-entry\.js["']/i,
  'index.html must load the canonical entry guard');
assert.ok(fs.existsSync(path.join(root, 'canonical-entry.js')), 'canonical entry guard must be committed');
assert.match(read('canonical-entry.js'), /pathname\.endsWith\(['"]\/index\.html['"]\)/,
  'direct index.html visits must be redirected to the canonical root');
assert.match(read('canonical-entry.js'), /location\.replace\(/,
  'canonical entry guard must use a safe browser redirect');

for (const page of legacyEntryPages) assertRedirectStub(page);

const app = read('app.js');
const lifecycle = read('vehicle-lifecycle-actions.js');
assert.doesNotMatch(app, /test-\d+|no-vehicles\.html/i,
  'obsolete test pages must not remain an enabled local-reset route');
assert.doesNotMatch(app, /pathname === ['"]\/pdc-control-board-staging\/index\.html['"]/,
  'direct index.html must not remain an approved staging runtime path');
assert.doesNotMatch(lifecycle, /['"]\/pdc-control-board-staging\/index\.html['"]/,
  'direct index.html must not remain an approved lifecycle runtime path');
assert.match(app, /pathname === ['"]\/pdc-control-board-staging\/['"]/,
  'the application must retain the canonical staging root path');
assert.match(lifecycle, /['"]\/pdc-control-board-staging\/['"]/,
  'lifecycle actions must retain the canonical staging root path');

const allSourceFiles = [];
function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === '.git' || entry.name === 'vendor' || entry.name === 'supabase') continue;
    const absolute = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(absolute);
    else allSourceFiles.push(absolute);
  }
}
walk(root);
for (const absolute of allSourceFiles) {
  const relative = path.relative(root, absolute).replaceAll('\\', '/');
  if (legacyEntryPages.includes(relative) || /^test_.*\.js$/i.test(relative)) continue;
  const text = fs.readFileSync(absolute, 'utf8');
  assert.doesNotMatch(text, legacyEntryPattern, `${relative} must not link to an obsolete entry page`);
  assert.doesNotMatch(text, legacyAssetPattern, `${relative} must not link to an obsolete fixture/cache target`);
}

const urlPattern = /\b(?:https?|wss?):\/\/[^\s"'<>`]+/gi;
for (const relative of ['index.html', 'app.js', 'pdc-auth.js', 'pdc-auth-registration.js', 'pdc-supabase-config.staging.js', 'vehicle-lifecycle-actions.js']) {
  for (const raw of read(relative).match(urlPattern) || []) {
    const url = raw.replace(/[),.;]+$/, '');
    const origin = new URL(url).origin;
    assert.ok(approvedExternalOrigins.has(origin), `${relative} contains an unapproved external origin: ${origin}`);
  }
}

assert.ok(index.includes(`https://${canonicalSiteOrigin.slice('https://'.length)}${canonicalSitePath}`) === false,
  'canonical HTML must not hard-code a second Pages path');
assert.strictEqual(canonicalSiteOrigin, 'https://btnew.github.io');
assert.strictEqual(canonicalSitePath, '/pdc-control-board-staging/');
console.log('legacy_website_links: PASS');
