'use strict';

const assert = require('assert');
const {
  ARTIFACT_SCHEMA_VERSION,
  VehicleReferenceArtifactError,
  VehicleReferenceArtifactStaleError,
  artifactChecksum,
  buildVehicleReferenceArtifact,
  validateVehicleReferenceArtifact,
  parseWorkshopReference,
} = require('./scripts/workshop_vehicle_reference_artifact');

const UUID_A = '11111111-1111-4111-8111-111111111111';
const UUID_B = '22222222-2222-4222-8222-222222222222';
const REVISION = 17;
let passed = 0;

function item(id = UUID_A, identifiers = null) {
  return {
    vehicle_id: id,
    version: 3,
    is_archived: false,
    identifiers: identifiers || [
      { identifier_type: 'stock_number', value: 'STK-100', normalized_value: 'STK100', source_system: null, origin: 'canonical' },
      { identifier_type: 'source_record_id', value: 'ROW-100', normalized_value: 'ROW-100', source_system: 'NAVISION', origin: 'source_evidence' },
    ],
  };
}

function exported(items = [item()], conflicts = []) {
  const last = items.length ? items.at(-1).vehicle_id : null;
  return {
    outcome: 'exported',
    export_revision: REVISION,
    items,
    conflicts,
    completion: {
      complete: true,
      page_count: 1,
      terminal_cursor: last,
      pages: [{ after_cursor: null, end_cursor: last, item_count: items.length, has_more: false, next_cursor: null }],
    },
  };
}

function artifact(data = exported(), generatedAt = '2026-07-18T10:00:00.000Z') {
  return buildVehicleReferenceArtifact(data, {
    generatedAt,
    sourceEnvironment: 'test:stage2b-c2b',
  });
}

function clone(value) { return JSON.parse(JSON.stringify(value)); }
function resign(value) { value.checksum.value = artifactChecksum(value); return value; }
function expectError(label, fn, ErrorType = VehicleReferenceArtifactError, fragment = '') {
  assert.throws(fn, error => error instanceof ErrorType && (!fragment || error.message.includes(fragment)), label);
  passed += 1;
}
function pass(label, fn) { fn(); passed += 1; console.log(`PASS ${passed}: ${label}`); }

pass('typed artifact retains canonical UUID, version, state and source evidence', () => {
  const value = artifact();
  assert.strictEqual(value.schema_version, ARTIFACT_SCHEMA_VERSION);
  assert.strictEqual(value.items[0].vehicle_id, UUID_A);
  assert.strictEqual(value.items[0].version, 3);
  assert.strictEqual(value.items[0].is_archived, false);
  assert.ok(value.items[0].identifiers.some(row => row.origin === 'source_evidence'));
});

pass('typed artifact has revision, environment, timestamp, count, completion and SHA-256', () => {
  const value = artifact();
  assert.strictEqual(value.resolver_revision, REVISION);
  assert.strictEqual(value.source_environment, 'test:stage2b-c2b');
  assert.strictEqual(value.generated_at, '2026-07-18T10:00:00.000Z');
  assert.strictEqual(value.item_count, 1);
  assert.strictEqual(value.completion.complete, true);
  assert.strictEqual(value.checksum.algorithm, 'sha256');
  assert.match(value.checksum.value, /^[0-9a-f]{64}$/);
});

expectError('truncated export is rejected', () => {
  const value = clone(artifact()); value.completion.complete = false; validateVehicleReferenceArtifact(resign(value), { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'truncated');

expectError('missing terminal cursor is rejected', () => {
  const value = clone(artifact()); delete value.completion.terminal_cursor; validateVehicleReferenceArtifact(resign(value), { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'terminal cursor');

expectError('malformed item is rejected', () => {
  const value = clone(artifact()); value.items[0].customer = 'must not leak'; validateVehicleReferenceArtifact(resign(value), { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'prohibited field');

expectError('incorrect item count is rejected', () => {
  const value = clone(artifact()); value.item_count = 2; validateVehicleReferenceArtifact(resign(value), { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'item count');

expectError('checksum mismatch is rejected', () => {
  const value = clone(artifact()); value.items[0].version = 4; validateVehicleReferenceArtifact(value, { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'checksum mismatch');

const wrongBoundary = clone(artifact());
wrongBoundary.completion.pages[0].end_cursor = UUID_B;
wrongBoundary.completion.terminal_cursor = UUID_B;
expectError('page boundary that does not correspond to artifact items is rejected', () => validateVehicleReferenceArtifact(resign(wrongBoundary), { expectedResolverRevision: REVISION }), VehicleReferenceArtifactError, 'boundary');

const badTimestamp = clone(artifact());
badTimestamp.generated_at = '2026-07-18';
expectError('generation timestamp must be an explicit UTC instant', () => validateVehicleReferenceArtifact(resign(badTimestamp), { expectedResolverRevision: REVISION }), VehicleReferenceArtifactError, 'timestamp');

expectError('stale revision is rejected', () => validateVehicleReferenceArtifact(artifact(), { expectedResolverRevision: REVISION + 1 }), VehicleReferenceArtifactStaleError, 'stale');

expectError('missing current revision refuses offline validation', () => validateVehicleReferenceArtifact(artifact()), VehicleReferenceArtifactError, 'current resolver revision');

expectError('malformed conflict array is rejected', () => {
  const value = clone(artifact()); value.conflicts = {}; validateVehicleReferenceArtifact(resign(value), { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'malformed');

expectError('duplicate normalized identifier without conflict evidence is rejected', () => {
  const duplicate = item(UUID_B, [
    { identifier_type: 'stock_number', value: 'STK 100', normalized_value: 'STK100', source_system: null, origin: 'alias' },
  ]);
  validateVehicleReferenceArtifact(artifact(exported([item(), duplicate])), { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'lacks explicit conflict');

pass('duplicate normalized identifier with complete conflict evidence is retained for fail-closed matching', () => {
  const duplicate = item(UUID_B, [
    { identifier_type: 'stock_number', value: 'STK 100', normalized_value: 'STK100', source_system: null, origin: 'alias' },
  ]);
  const conflict = {
    classification: 'canonical_alias_conflict', identifier_type: 'stock_number', normalized_value: 'STK100', source_system: null,
    vehicle_ids: [UUID_A, UUID_B],
    candidates: [
      { vehicle_id: UUID_A, origin: 'canonical', value: 'STK-100' },
      { vehicle_id: UUID_B, origin: 'alias', value: 'STK 100' },
    ],
  };
  const value = artifact(exported([item(), duplicate], [conflict]));
  assert.strictEqual(value.conflicts.length, 1);
});

expectError('permanent vehicle ID alias is never authoritative', () => {
  artifact(exported([item(UUID_A, [
    { identifier_type: 'permanent_vehicle_id', value: 'PERM-1', normalized_value: 'PERM-1', source_system: null, origin: 'alias' },
  ])]));
}, VehicleReferenceArtifactError, 'permanent-vehicle-ID aliases');

pass('canonical permanent vehicle ID remains permitted', () => {
  const value = artifact(exported([item(UUID_A, [
    { identifier_type: 'permanent_vehicle_id', value: 'PERM-1', normalized_value: 'PERM-1', source_system: null, origin: 'canonical' },
  ])]));
  assert.strictEqual(value.items[0].identifiers[0].origin, 'canonical');
});

pass('deterministic regeneration has identical logical checksum despite timestamp change', () => {
  const first = artifact(exported(), '2026-07-18T10:00:00.000Z');
  const second = artifact(exported(), '2026-07-18T10:01:00.000Z');
  assert.strictEqual(first.checksum.value, second.checksum.value);
  assert.notStrictEqual(first.generated_at, second.generated_at);
});

expectError('invalid cursor chain is rejected', () => {
  const value = clone(artifact()); value.completion.pages[0].after_cursor = UUID_B; validateVehicleReferenceArtifact(resign(value), { expectedResolverRevision: REVISION });
}, VehicleReferenceArtifactError, 'cursor chain');

expectError('prohibited broad vehicle fields do not enter artifacts', () => {
  artifact(exported([{ ...item(), customer_name: 'Secret Customer', notes: 'Secret note' }]));
}, VehicleReferenceArtifactError, 'prohibited field');

expectError('legacy format is disabled by default', () => parseWorkshopReference({ vehicles: [], vehicleIdentityExport: { outcome: 'exported', export_revision: REVISION } }, { expectedResolverRevision: REVISION }), VehicleReferenceArtifactError, 'disabled');

pass('legacy rollback requires explicit flag, exact version and emits diagnostic', () => {
  const diagnostics = [];
  const legacy = {
    vehicles: [{ id: UUID_A, version: 3, is_archived: false, stock_number: ' STK-100 ', permanent_vehicle_id: 'perm-100' }],
    vehicleIdentityExport: { outcome: 'exported', export_revision: REVISION, conflicts: [], rollback_used: true },
  };
  const parsed = parseWorkshopReference(legacy, {
    expectedResolverRevision: REVISION,
    allowLegacyRollback: true,
    legacySourceEnvironment: 'test:c2b-rollback',
    diagnostic: message => diagnostics.push(message),
  });
  assert.strictEqual(parsed.vehicles[0].vehicle_id, UUID_A);
  assert.deepStrictEqual(parsed.vehicles[0].identifiers.map(row => row.origin), ['canonical', 'canonical']);
  assert.ok(diagnostics[0].includes('WARNING'));
});

expectError('legacy rollback refuses missing or changed version', () => parseWorkshopReference({ vehicles: [], vehicleIdentityExport: { outcome: 'exported', export_revision: REVISION } }, {
  expectedResolverRevision: REVISION + 1, allowLegacyRollback: true,
  legacySourceEnvironment: 'test:c2b-rollback',
}), VehicleReferenceArtifactError, 'version validation');

console.log(`Workshop typed vehicle reference artifact checks passed: ${passed}`);
