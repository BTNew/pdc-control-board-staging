'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const versionMatches = [...appSource.matchAll(/const\s+APP_VERSION\s*=\s*['"]([^'"]+)['"]/g)];
assert.strictEqual(versionMatches.length, 1, 'app.js must define APP_VERSION exactly once');
const version = versionMatches[0][1];
assert.match(version, /^\d{4}\.\d{2}\.\d{2}\.\d{2}-[a-z0-9-]+$/i, `APP_VERSION has an unexpected format: ${version}`);

const htmlFiles = ['index.html', 'no-vehicles.html', 'staging.html', 'test-50.html', 'test-75.html', 'test-100.html'];
const versionedAssetPattern = /(?:app\.js|styles\.css|desktop-operations\.css|data(?:-no-vehicles|-test-\d+)?\.js)\?v=([^"'&<\s]+)/g;

for (const file of htmlFiles) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const assetVersions = [...source.matchAll(versionedAssetPattern)].map(match => match[1]);
  assert.ok(assetVersions.length >= 3, `${file} should cache-bust its application assets`);
  for (const assetVersion of assetVersions) {
    assert.strictEqual(assetVersion, version, `${file} contains stale asset version ${assetVersion}; expected ${version}`);
  }
}

for (const file of ['index.html', 'no-vehicles.html', 'staging.html']) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  const marker = (source.match(/id="app-version"[^>]*>\s*Version\s+([^<\s]+)/) || [])[1];
  assert.strictEqual(marker, version, `${file} has a stale visible version marker`);
}

console.log(`Version consistency checks passed (${version})`);
