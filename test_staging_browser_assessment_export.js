'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const ui = require('./staging-browser-assessment.js');
const exporter = require('./scripts/stage2b_c4_browser_export.js');

class ReadOnlyStorage {
  constructor(values) { this.values = { ...values }; this.keys = Object.keys(this.values); this.writeAttempts = 0; }
  get length() { return this.keys.length; }
  key(index) { return this.keys[index] ?? null; }
  getItem(key) { return Object.prototype.hasOwnProperty.call(this.values, key) ? this.values[key] : null; }
  setItem() { this.writeAttempts += 1; throw new Error('setItem forbidden'); }
  removeItem() { this.writeAttempts += 1; throw new Error('removeItem forbidden'); }
  clear() { this.writeAttempts += 1; throw new Error('clear forbidden'); }
}

function fakeWindow(role) {
  const listeners = new Map();
  return {
    PDC_AUTH_CONTEXT: role ? { role } : null,
    addEventListener(name, fn) { listeners.set(name, fn); },
    dispatch(name, detail) { listeners.get(name)?.({ detail }); },
    listeners,
  };
}

function fakeDocument() {
  const buttonListeners = new Map();
  const button = {
    hidden: true,
    disabled: false,
    addEventListener(name, fn) { buttonListeners.set(name, fn); },
    async click() { return buttonListeners.get('click')?.({ preventDefault() {} }); },
  };
  const status = { textContent: '', hidden: true };
  return {
    button,
    status,
    getElementById(id) {
      if (id === 'browser-assessment-export') return button;
      if (id === 'browser-assessment-export-status') return status;
      return null;
    },
  };
}

async function main() {
  assert.strictEqual(ui.isAdministrator({ role: 'administrator' }), true);
  for (const role of [null, 'viewer', 'operator', 'importer', 'Administrator']) {
    assert.strictEqual(ui.isAdministrator(role ? { role } : null), false, `${role} must not be administrator`);
  }
  assert.strictEqual(ui.sanitizeComputerName('  Computer A  '), 'Computer A');
  assert.strictEqual(ui.filenameLabel('Computer A'), 'Computer-A');
  assert.throws(() => ui.sanitizeComputerName('   '), /computer name/i);

  const viewerWindow = fakeWindow('viewer');
  const viewerDocument = fakeDocument();
  let viewerDownloads = 0;
  ui.install({
    windowObject: viewerWindow,
    documentObject: viewerDocument,
    exporter: { downloadAssessmentExport: async () => { viewerDownloads += 1; } },
    promptFn: () => 'Computer B',
  });
  assert.strictEqual(viewerDocument.button.hidden, true, 'viewer button must remain hidden');
  await viewerDocument.button.click();
  assert.strictEqual(viewerDownloads, 0, 'viewer must not dispatch an export');

  const adminWindow = fakeWindow('administrator');
  const adminDocument = fakeDocument();
  const calls = [];
  ui.install({
    windowObject: adminWindow,
    documentObject: adminDocument,
    exporter: { downloadAssessmentExport: async options => { calls.push(options); return { assessment_export_sha256: 'abc' }; } },
    promptFn: () => 'Computer A',
    now: () => new Date('2026-07-22T04:05:06.000Z'),
  });
  assert.strictEqual(adminDocument.button.hidden, false, 'administrator button must be visible');
  await adminDocument.button.click();
  assert.strictEqual(calls.length, 1);
  assert.deepStrictEqual(calls[0], { computerName: 'Computer A', exportedAt: '2026-07-22T04:05:06.000Z' });
  assert.match(adminDocument.status.textContent, /downloaded/i);

  adminWindow.PDC_AUTH_CONTEXT = { role: 'viewer' };
  adminWindow.dispatch('pdc-auth-ready', adminWindow.PDC_AUTH_CONTEXT);
  assert.strictEqual(adminDocument.button.hidden, true, 'live role downgrade must hide the button');
  adminWindow.dispatch('pdc-auth-locked', { reason: 'disabled' });
  assert.strictEqual(adminDocument.button.hidden, true, 'lockout must keep the button hidden');

  const storage = new ReadOnlyStorage({
    [exporter.KEYS.added]: JSON.stringify([{ stock: '12000001', customer: 'customer-secret-sentinel' }]),
    [exporter.KEYS.edits]: '{}',
    [exporter.KEYS.deleted]: '[]',
    'vehicleTrackingCoreNotes:12000001': JSON.stringify([{ text: 'note-secret-sentinel' }]),
  });
  const payload = await exporter.buildAssessmentExport({
    localStorage: storage,
    windowObject: { location: { origin: 'https://btnew.github.io' }, VEHICLE_TRACKING_DATA: { vehicles: [] } },
    computerName: 'Computer A',
    exportedAt: '2026-07-22T04:05:06.000Z',
  });
  assert.strictEqual(payload.computer_name, 'Computer A');
  assert.strictEqual(payload.exported_at, '2026-07-22T04:05:06.000Z');
  assert.strictEqual(payload.local_storage_unchanged, true);
  assert.strictEqual(storage.writeAttempts, 0);
  const serialized = JSON.stringify(payload);
  assert(!serialized.includes('customer-secret-sentinel'), 'customer payload leaked');
  assert(!serialized.includes('note-secret-sentinel'), 'note payload leaked');
  const downloaded = { filename: null, clicks: 0, appended: 0, revoked: 0 };
  const anchor = {
    href: '', download: '',
    click() { downloaded.clicks += 1; downloaded.filename = this.download; },
    remove() {},
  };
  await exporter.downloadAssessmentExport({
    localStorage: storage,
    windowObject: { location: { origin: 'https://btnew.github.io' }, VEHICLE_TRACKING_DATA: { vehicles: [] } },
    computerName: 'Computer A',
    exportedAt: '2026-07-22T04:05:06.000Z',
    documentObject: {
      createElement: () => anchor,
      body: { appendChild() { downloaded.appended += 1; } },
    },
    urlApi: {
      createObjectURL: () => 'blob:read-only-assessment',
      revokeObjectURL() { downloaded.revoked += 1; },
    },
  });
  assert.strictEqual(downloaded.clicks, 1);
  assert.strictEqual(downloaded.appended, 1);
  assert.strictEqual(downloaded.revoked, 1);
  assert.match(downloaded.filename, /^PDC-Read-Only-Browser-Assessment-Computer-A-2026-07-22T04-05-06-000Z-[0-9a-f]{12}\.json$/);
  assert.strictEqual(storage.writeAttempts, 0);

  const staging = fs.readFileSync(path.join(__dirname, 'staging.html'), 'utf8');
  assert(staging.includes('id="browser-assessment-export"'));
  assert(staging.includes('scripts/stage2b_c4_browser_export.js'));
  assert(staging.includes('staging-browser-assessment.js'));
  const index = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  assert(!index.includes('browser-assessment-export'), 'temporary staging control must not enter production shell');
  assert(!index.includes('staging-browser-assessment.js'), 'temporary staging script must not enter production shell');

  for (const file of ['staging-browser-assessment.js', 'scripts/stage2b_c4_browser_export.js']) {
    const source = fs.readFileSync(path.join(__dirname, file), 'utf8');
    for (const pattern of [/\.setItem\s*\(/, /\.removeItem\s*\(/, /\.clear\s*\(/, /\bfetch\s*\(/, /XMLHttpRequest/, /sendBeacon/, /WebSocket/]) {
      assert(!pattern.test(source), `${file} contains forbidden mutation/network primitive ${pattern}`);
    }
  }
  console.log('Temporary staging browser assessment export tests passed');
}

main().catch(error => { console.error(error); process.exit(1); });
