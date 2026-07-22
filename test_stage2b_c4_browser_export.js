'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const exporter = require('./scripts/stage2b_c4_browser_export.js');

class ReadOnlyStorage {
  constructor(values) { this.values = { ...values }; this.keys = Object.keys(this.values); this.writeAttempts = 0; this.readKeys = []; }
  get length() { return this.keys.length; }
  key(index) { return this.keys[index] ?? null; }
  getItem(key) { this.readKeys.push(key); return Object.prototype.hasOwnProperty.call(this.values, key) ? this.values[key] : null; }
  setItem() { this.writeAttempts += 1; throw new Error('setItem forbidden'); }
  removeItem() { this.writeAttempts += 1; throw new Error('removeItem forbidden'); }
  clear() { this.writeAttempts += 1; throw new Error('clear forbidden'); }
}

async function main() {
  const storage = new ReadOnlyStorage({
    [exporter.KEYS.added]: JSON.stringify([
      { id: 'v1', stock: ' 13-0001 ', vin: 'JTNAA3BB4C5000001', order: 'ORD-1', client: 'must not export' },
      { id: 'v2', stock: 'TBA', vin: 'BADVIN', order: 'ORD-2', customer: 'must not export' },
    ]),
    [exporter.KEYS.edits]: JSON.stringify({
      '13-0001': { pdcJobcard: 'JC-1', pmbStage: 'FITTING', notes: 'must not export' },
      TBA: { pdcWorkshopBlocked: true },
    }),
    [exporter.KEYS.deleted]: '[]',
    [exporter.KEYS.po_tasks]: JSON.stringify({ '13-0001': ['task content excluded'] }),
    [exporter.KEYS.po_files]: JSON.stringify({ '13-0001': [{ name: 'secret.pdf', data: 'excluded' }] }),
    [exporter.KEYS.workshop_plans]: JSON.stringify([{ id: 'p1', vehicleKey: '13-0001', stage: 'FITTING', assignee: 'excluded' }]),
    [exporter.KEYS.canonical_links]: JSON.stringify({ '13-0001': '00000000-0000-4000-8000-000000000001' }),
    'vehicleTrackingCoreNotes:13-0001': JSON.stringify([{ text: 'excluded note text' }]),
    'unrelatedGitHubPagesApp:secret': 'must never be read or exported',
  });
  const windowObject = {
    location: { origin: 'http://127.0.0.1:8124' },
    VEHICLE_TRACKING_DATA: { vehicles: [{ stock: 'STATIC-001', customer: 'runtime-data-must-not-be-read' }] },
  };
  const first = await exporter.buildAssessmentExport({ localStorage: storage, windowObject });
  const second = await exporter.buildAssessmentExport({ localStorage: storage, windowObject });
  assert.deepStrictEqual(first, second, 'same browser state must produce byte-identical logical export');
  assert.strictEqual(first.local_storage_unchanged, true);
  assert.strictEqual(first.local_storage_sha256_before, first.local_storage_sha256_after);
  assert.strictEqual(storage.writeAttempts, 0, 'export must never call a storage write API');
  assert(!storage.readKeys.includes('unrelatedGitHubPagesApp:secret'), 'export must not read non-PDC localStorage values');
  assert.strictEqual(first.families.canonical_vehicle_link_count, 1);
  assert.strictEqual(first.vehicles.length, 2);
  assert.strictEqual(first.vehicles[0].job_card_number, 'JC-1');
  assert.strictEqual(first.vehicles[0].parts_task_count, 1);
  assert.deepStrictEqual(first.notes, [{ legacy_vehicle_key: '13-0001', note_count: 1 }]);
  assert.strictEqual(first.bookings[0].legacy_vehicle_key, '13-0001');
  const serialized = exporter.canonicalJson(first);
  for (const prohibited of ['must not export', 'excluded note text', 'task content excluded', 'secret.pdf', 'assignee', 'runtime-data-must-not-be-read', 'STATIC-001']) {
    assert(!serialized.includes(prohibited), `broad payload leaked: ${prohibited}`);
  }
  const malformedStorage = new ReadOnlyStorage({
    [exporter.KEYS.added]: '[]', [exporter.KEYS.edits]: '{}', [exporter.KEYS.deleted]: '[]',
    [exporter.KEYS.po_tasks]: '[]', [exporter.KEYS.workshop_plans]: '{}',
    [exporter.KEYS.audit]: '{',
    'vehicleTrackingCoreNotes:BAD': '{}',
  });
  const malformed = await exporter.buildAssessmentExport({ localStorage: malformedStorage, windowObject });
  assert.deepStrictEqual(malformed.parse_errors, [
    { family: 'notes:BAD', reason_code: 'invalid_type' },
    { family: 'po_tasks', reason_code: 'invalid_type' },
    { family: exporter.KEYS.audit, reason_code: 'invalid_json' },
    { family: 'workshop_plans', reason_code: 'invalid_type' },
  ]);
  assert.strictEqual(malformedStorage.writeAttempts, 0);
  const source = fs.readFileSync(path.join(__dirname, 'scripts', 'stage2b_c4_browser_export.js'), 'utf8');
  for (const pattern of [/\.setItem\s*\(/, /\.removeItem\s*\(/, /\.clear\s*\(/, /\bfetch\s*\(/, /XMLHttpRequest/, /sendBeacon/, /WebSocket/]) {
    assert(!pattern.test(source), `forbidden mutation/network primitive found: ${pattern}`);
  }
  assert(!source.includes('.supabase.co'), 'exporter must not contain a Supabase endpoint');
  console.log('Stage 2B C4 browser export read-only tests passed');
}

main().catch(error => { console.error(error); process.exit(1); });
