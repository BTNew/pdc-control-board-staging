'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const entry = fs.readFileSync('canonical-entry.js', 'utf8');
const mobile = fs.readFileSync('pdc-qc-mobile.js', 'utf8');
const css = fs.readFileSync('pdc-qc-mobile.css', 'utf8');
function boot({ phone = true, pathname = '/pdc-control-board-staging/', hash = '', search = '' } = {}) {
  const added = []; const history = []; const replaced = []; const classes = new Set();
  const location = { pathname, hash, search, replace: url => replaced.push(url) };
  const context = { window: { location, matchMedia: () => ({ matches: phone }), history: { replaceState: (...args) => history.push(args) } },
    document: { readyState: 'complete', createElement: tag => ({ tag }), head: { appendChild: node => added.push(node) },
      documentElement: { classList: { toggle: (name, on) => on ? classes.add(name) : classes.delete(name), remove: name => classes.delete(name) } } } };
  vm.runInNewContext(entry, context);
  return { added, history, replaced, classes };
}
test('phone root opens QC and loads both published mobile assets', () => {
  const b = boot();
  assert.equal(b.history[0][2], '/pdc-control-board-staging/#/qc');
  assert.equal(b.classes.has('pdc-qc-phone'), true);
  assert.ok(b.added.some(x => /^pdc-qc-mobile\.css\?v=/.test(x.href || '')));
  assert.ok(b.added.some(x => /^pdc-qc-mobile\.js\?v=/.test(x.src || '')));
});
test('phone workspace routes open QC, while desktop routes remain intact', () => {
  assert.equal(boot({ hash: '#/dashboard' }).history[0][2], '/pdc-control-board-staging/#/qc');
  const desktop = boot({ phone: false, hash: '#/dashboard' });
  assert.equal(desktop.history.length, 0);
  assert.equal(desktop.classes.has('pdc-qc-phone'), false);
});
test('OAuth and recovery fragments are not overwritten by phone boot', () => {
  for (const hash of ['#access_token=synthetic&type=recovery', '#error=access_denied', '#type=recovery']) {
    assert.equal(boot({ hash }).history.length, 0);
  }
});
test('canonical index redirect preserves query and authentication fragment', () => {
  const b = boot({ pathname: '/pdc-control-board-staging/index.html', search: '?code=synthetic', hash: '#type=recovery' });
  assert.equal(b.replaced[0], '/pdc-control-board-staging?code=synthetic#type=recovery');
  assert.equal(b.added.length, 0);
});
test('published mobile source compiles, uses existing authorities, and fails back on load errors', () => {
  new vm.Script(mobile);
  assert.match(mobile, /projectRef !== 'cdsmnqxtyyoeoznmbidd'/);
  assert.match(mobile, /service\.rejectQcVehicleToPmb/);
  assert.match(mobile, /desktopSignoff\(key\)/);
  assert.match(mobile, /qcPageQueueOperationState/);
  assert.match(mobile, /data\?\.vehicle_id !== row\.__emailVehicleId/);
  const b = boot(); b.added.find(x => x.tag === 'script').onerror();
  assert.equal(b.classes.has('pdc-qc-phone'), false);
});
test('phone stylesheet removes desktop chrome but never overrides the auth gate', () => {
  assert.match(css, /html\.pdc-qc-phone \.sidebar/);
  assert.match(css, /html\.pdc-qc-phone \.main > \.topbar/);
  assert.doesNotMatch(css, /auth-pending[^{}]*\{[^}]*display\s*:\s*(block|grid|flex)/);
  assert.match(css, /safe-area-inset-bottom/);
  assert.match(mobile, /document\.querySelector\('\.qc-page-panel'\)\.appendChild\(fileInput\)/);
  assert.doesNotMatch(mobile, /setAttribute\('capture'/);
  assert.match(mobile, /qcPhotoEvidenceIsValid\(photo\)/);
});
