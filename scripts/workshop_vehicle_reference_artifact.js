'use strict';

const crypto = require('crypto');

const ARTIFACT_SCHEMA_VERSION = 'pdc.workshop.vehicle-reference/v2';
const ALLOWED_ITEM_KEYS = new Set(['vehicle_id', 'version', 'is_archived', 'identifiers']);
const ALLOWED_IDENTIFIER_KEYS = new Set([
  'identifier_type', 'value', 'normalized_value', 'source_system', 'origin',
]);
const ALLOWED_CONFLICT_KEYS = new Set([
  'classification', 'identifier_type', 'normalized_value', 'source_system',
  'vehicle_ids', 'candidates',
]);
const ALLOWED_CANDIDATE_KEYS = new Set(['vehicle_id', 'origin', 'value']);
const ALLOWED_IDENTIFIER_TYPES = new Set([
  'stock_number', 'vin', 'job_card_number', 'permanent_vehicle_id',
  'toyota_order_number', 'source_record_id',
]);
const ALLOWED_ORIGINS = new Set(['canonical', 'alias', 'source_evidence']);
const ALLOWED_ALIAS_TYPES = new Set([
  'stock_number', 'vin', 'job_card_number', 'toyota_order_number', 'source_record_id',
]);
const ALLOWED_CONFLICT_CLASSES = new Set([
  'canonical_alias_conflict', 'canonical_source_evidence_conflict',
  'ambiguous_normalized_identity',
]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256_RE = /^[0-9a-f]{64}$/;
const SOURCE_ENV_RE = /^(staging|test):[a-z0-9][a-z0-9-]{2,127}$/;
const ISO_UTC_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/;

class VehicleReferenceArtifactError extends Error {}
class VehicleReferenceArtifactStaleError extends VehicleReferenceArtifactError {}

function normalizeLegacyStock(value) {
  return String(value || '').trim().toUpperCase().replace(/[\s-]+/g, '');
}

function isRealLegacyStock(value) {
  const raw = String(value || '').trim().toUpperCase();
  const normalized = normalizeLegacyStock(value);
  return Boolean(normalized)
    && !new Set(['0', 'TBA', 'TBD', 'UNKNOWN', 'NA', 'N/A', 'NONE', 'UNASSIGNED']).has(normalized)
    && !['NEW-', 'PD-', 'PENDING-', 'TEMP-'].some(prefix => raw.startsWith(prefix));
}

function fail(message) {
  throw new VehicleReferenceArtifactError(message);
}

function exactKeys(value, allowed, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label} must be an object`);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) fail(`${label} contains prohibited field: ${key}`);
  }
}

function stableStringify(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`;
  return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(',')}}`;
}

function artifactLogicalPayload(artifact) {
  return {
    schema_version: artifact.schema_version,
    resolver_revision: artifact.resolver_revision,
    source_environment: artifact.source_environment,
    item_count: artifact.item_count,
    completion: artifact.completion,
    items: artifact.items,
    conflicts: artifact.conflicts,
  };
}

function artifactChecksum(artifact) {
  return crypto.createHash('sha256')
    .update(stableStringify(artifactLogicalPayload(artifact)), 'utf8')
    .digest('hex');
}

function normalizeClaim(claim, itemLabel) {
  exactKeys(claim, ALLOWED_IDENTIFIER_KEYS, `${itemLabel} identifier`);
  const identifierType = claim.identifier_type;
  const origin = claim.origin;
  if (!ALLOWED_IDENTIFIER_TYPES.has(identifierType)) fail(`${itemLabel} identifier type is invalid`);
  if (!ALLOWED_ORIGINS.has(origin)) fail(`${itemLabel} identifier origin is invalid`);
  if (origin === 'alias' && identifierType === 'permanent_vehicle_id') {
    fail(`${itemLabel} permanent-vehicle-ID aliases are not authoritative`);
  }
  if (origin === 'alias' && !ALLOWED_ALIAS_TYPES.has(identifierType)) {
    fail(`${itemLabel} contains a prohibited alias type`);
  }
  if (typeof claim.value !== 'string' || !claim.value.trim()) fail(`${itemLabel} identifier value is invalid`);
  if (typeof claim.normalized_value !== 'string' || !claim.normalized_value.trim()) {
    fail(`${itemLabel} normalized identifier is invalid`);
  }
  const scoped = ['job_card_number', 'toyota_order_number', 'source_record_id'].includes(identifierType);
  if (scoped && typeof claim.source_system !== 'string') fail(`${itemLabel} scoped identifier lacks source_system`);
  if (!scoped && claim.source_system !== null) fail(`${itemLabel} unscoped identifier has source_system`);
  return {
    identifier_type: identifierType,
    value: claim.value,
    normalized_value: claim.normalized_value,
    source_system: claim.source_system,
    origin,
  };
}

function claimSortKey(claim) {
  return [claim.identifier_type, claim.source_system || '', claim.normalized_value, claim.origin, claim.value].join('\u0000');
}

function normalizeItem(item) {
  exactKeys(item, ALLOWED_ITEM_KEYS, 'vehicle item');
  if (!UUID_RE.test(String(item.vehicle_id || ''))) fail('vehicle item has no valid canonical UUID');
  if (!Number.isInteger(item.version) || item.version < 1) fail('vehicle item version is invalid');
  if (typeof item.is_archived !== 'boolean') fail('vehicle item archived state is invalid');
  if (!Array.isArray(item.identifiers)) fail('vehicle item identifiers are malformed');
  const identifiers = item.identifiers.map(claim => normalizeClaim(claim, `vehicle ${item.vehicle_id}`));
  const seen = new Set();
  for (const claim of identifiers) {
    const key = claimSortKey(claim);
    if (seen.has(key)) fail(`vehicle ${item.vehicle_id} contains duplicate identifier evidence`);
    seen.add(key);
  }
  identifiers.sort((a, b) => claimSortKey(a).localeCompare(claimSortKey(b)));
  return { vehicle_id: item.vehicle_id.toLowerCase(), version: item.version, is_archived: item.is_archived, identifiers };
}

function normalizeConflict(conflict) {
  exactKeys(conflict, ALLOWED_CONFLICT_KEYS, 'conflict evidence');
  if (!ALLOWED_CONFLICT_CLASSES.has(conflict.classification)) fail('conflict classification is invalid');
  if (!ALLOWED_IDENTIFIER_TYPES.has(conflict.identifier_type)) fail('conflict identifier type is invalid');
  if (typeof conflict.normalized_value !== 'string' || !conflict.normalized_value.trim()) fail('conflict normalized value is invalid');
  if (!(conflict.source_system === null || typeof conflict.source_system === 'string')) fail('conflict source system is invalid');
  if (!Array.isArray(conflict.vehicle_ids) || conflict.vehicle_ids.length < 2) fail('conflict vehicle IDs are malformed');
  const vehicleIds = conflict.vehicle_ids.map(String);
  if (vehicleIds.some(id => !UUID_RE.test(id)) || new Set(vehicleIds).size !== vehicleIds.length) fail('conflict vehicle IDs are invalid');
  if (!Array.isArray(conflict.candidates) || conflict.candidates.length < 2) fail('conflict candidates are malformed');
  const candidates = conflict.candidates.map(candidate => {
    exactKeys(candidate, ALLOWED_CANDIDATE_KEYS, 'conflict candidate');
    if (!UUID_RE.test(String(candidate.vehicle_id || ''))) fail('conflict candidate UUID is invalid');
    if (!ALLOWED_ORIGINS.has(candidate.origin)) fail('conflict candidate origin is invalid');
    if (typeof candidate.value !== 'string' || !candidate.value.trim()) fail('conflict candidate value is invalid');
    return { vehicle_id: candidate.vehicle_id.toLowerCase(), origin: candidate.origin, value: candidate.value };
  });
  candidates.sort((a, b) => stableStringify(a).localeCompare(stableStringify(b)));
  vehicleIds.sort();
  return {
    classification: conflict.classification,
    identifier_type: conflict.identifier_type,
    normalized_value: conflict.normalized_value,
    source_system: conflict.source_system,
    vehicle_ids: vehicleIds.map(id => id.toLowerCase()),
    candidates,
  };
}

function validateCompletion(completion, items) {
  const allowed = new Set(['complete', 'page_count', 'terminal_cursor', 'pages']);
  exactKeys(completion, allowed, 'completion evidence');
  if (completion.complete !== true) fail('artifact is truncated');
  if (!Number.isInteger(completion.page_count) || completion.page_count < 1) fail('page count is invalid');
  if (!Object.prototype.hasOwnProperty.call(completion, 'terminal_cursor')) fail('terminal cursor is missing');
  if (!Array.isArray(completion.pages) || completion.pages.length !== completion.page_count) fail('page evidence is incomplete');
  let priorEnd = null;
  let total = 0;
  completion.pages.forEach((page, index) => {
    exactKeys(page, new Set(['after_cursor', 'end_cursor', 'item_count', 'has_more', 'next_cursor']), `page ${index + 1}`);
    if (page.after_cursor !== priorEnd) fail(`page ${index + 1} cursor chain is invalid`);
    if (!Number.isInteger(page.item_count) || page.item_count < 0) fail(`page ${index + 1} item count is invalid`);
    if (typeof page.has_more !== 'boolean') fail(`page ${index + 1} completion marker is invalid`);
    if (page.item_count === 0 ? page.end_cursor !== null : !UUID_RE.test(String(page.end_cursor || ''))) {
      fail(`page ${index + 1} end cursor is invalid`);
    }
    const expectedPageEnd = page.item_count ? items[total + page.item_count - 1]?.vehicle_id : null;
    if (page.end_cursor !== expectedPageEnd) fail(`page ${index + 1} boundary does not match artifact items`);
    if (page.has_more) {
      if (page.item_count < 1 || page.next_cursor !== page.end_cursor) fail(`page ${index + 1} continuation cursor is invalid`);
    } else if (index !== completion.pages.length - 1 || page.next_cursor !== null) {
      fail(`page ${index + 1} terminal evidence is invalid`);
    }
    priorEnd = page.end_cursor;
    total += page.item_count;
  });
  if (completion.pages.at(-1).has_more !== false) fail('artifact lacks a terminal page');
  const expectedTerminal = items.length ? items.at(-1).vehicle_id : null;
  if (completion.terminal_cursor !== expectedTerminal || priorEnd !== expectedTerminal) fail('terminal cursor does not match artifact items');
  if (total !== items.length) fail('page item counts do not match artifact items');
}

function validateVehicleReferenceArtifact(artifact, options = {}) {
  exactKeys(artifact, new Set([
    'schema_version', 'resolver_revision', 'generated_at', 'source_environment',
    'item_count', 'completion', 'items', 'conflicts', 'checksum',
  ]), 'vehicle identity artifact');
  if (artifact.schema_version !== ARTIFACT_SCHEMA_VERSION) fail('unsupported vehicle reference artifact schema');
  if (!Number.isInteger(artifact.resolver_revision) || artifact.resolver_revision < 0) fail('resolver revision is invalid');
  if (typeof options.expectedResolverRevision !== 'number' || !Number.isInteger(options.expectedResolverRevision)) {
    fail('current resolver revision is required to validate an offline artifact');
  }
  if (artifact.resolver_revision !== options.expectedResolverRevision) {
    throw new VehicleReferenceArtifactStaleError('vehicle reference artifact is stale; regenerate it');
  }
  if (typeof artifact.generated_at !== 'string' || !ISO_UTC_RE.test(artifact.generated_at)
      || !Number.isFinite(Date.parse(artifact.generated_at))) fail('generation timestamp is invalid');
  if (typeof artifact.source_environment !== 'string' || !SOURCE_ENV_RE.test(artifact.source_environment)) fail('source environment identifier is invalid');
  if (!Array.isArray(artifact.items) || !Array.isArray(artifact.conflicts)) fail('artifact items or conflicts are malformed');
  const items = artifact.items.map(normalizeItem).sort((a, b) => a.vehicle_id.localeCompare(b.vehicle_id));
  const ids = items.map(item => item.vehicle_id);
  if (new Set(ids).size !== ids.length) fail('artifact contains duplicate canonical UUIDs');
  if (!Number.isInteger(artifact.item_count) || artifact.item_count !== items.length) fail('artifact item count is incorrect');
  validateCompletion(artifact.completion, items);
  const conflicts = artifact.conflicts.map(normalizeConflict)
    .sort((a, b) => stableStringify(a).localeCompare(stableStringify(b)));

  const normalized = { ...artifact, items, conflicts };
  if (!artifact.checksum || artifact.checksum.algorithm !== 'sha256' || !SHA256_RE.test(String(artifact.checksum.value || ''))) {
    fail('artifact checksum metadata is invalid');
  }
  const computed = artifactChecksum(normalized);
  if (computed !== artifact.checksum.value) fail('artifact checksum mismatch');

  const claimOwners = new Map();
  for (const item of items) {
    for (const claim of item.identifiers) {
      const key = [claim.identifier_type, claim.source_system || '', claim.normalized_value].join('\u0000');
      if (!claimOwners.has(key)) claimOwners.set(key, new Set());
      claimOwners.get(key).add(item.vehicle_id);
    }
  }
  for (const [key, owners] of claimOwners) {
    if (owners.size > 1) {
      const [identifierType, sourceSystem, normalizedValue] = key.split('\u0000');
      const hasConflict = conflicts.some(row => row.identifier_type === identifierType
        && (row.source_system || '') === sourceSystem
        && row.normalized_value === normalizedValue
        && owners.size === row.vehicle_ids.length
        && [...owners].every(id => row.vehicle_ids.includes(id)));
      if (!hasConflict) fail('duplicate normalized identifier lacks explicit conflict evidence');
    }
  }
  return normalized;
}

function buildVehicleReferenceArtifact(exportData, options = {}) {
  if (!exportData || exportData.outcome !== 'exported') fail('successful migration-031 export is required');
  const generatedAt = options.generatedAt || new Date().toISOString();
  const artifact = {
    schema_version: ARTIFACT_SCHEMA_VERSION,
    resolver_revision: exportData.export_revision,
    generated_at: generatedAt,
    source_environment: options.sourceEnvironment,
    item_count: Array.isArray(exportData.items) ? exportData.items.length : -1,
    completion: exportData.completion,
    items: exportData.items,
    conflicts: exportData.conflicts,
    checksum: { algorithm: 'sha256', value: '' },
  };
  const normalizedWithoutChecksum = {
    ...artifact,
    items: artifact.items.map(normalizeItem).sort((a, b) => a.vehicle_id.localeCompare(b.vehicle_id)),
    conflicts: artifact.conflicts.map(normalizeConflict).sort((a, b) => stableStringify(a).localeCompare(stableStringify(b))),
  };
  validateCompletion(normalizedWithoutChecksum.completion, normalizedWithoutChecksum.items);
  normalizedWithoutChecksum.checksum.value = artifactChecksum(normalizedWithoutChecksum);
  return validateVehicleReferenceArtifact(normalizedWithoutChecksum, { expectedResolverRevision: exportData.export_revision });
}

function parseWorkshopReference(referenceData, options = {}) {
  if (!referenceData || typeof referenceData !== 'object' || Array.isArray(referenceData)) fail('reference data must be an object');
  if (referenceData.vehicleIdentityArtifact) {
    const artifact = validateVehicleReferenceArtifact(referenceData.vehicleIdentityArtifact, options);
    return {
      ...referenceData,
      vehicles: artifact.items,
      vehicleIdentityExport: {
        outcome: 'exported',
        export_revision: artifact.resolver_revision,
        conflicts: artifact.conflicts,
        rollback_used: false,
        artifact_schema_version: artifact.schema_version,
        artifact_checksum: artifact.checksum.value,
      },
    };
  }
  if (!options.allowLegacyRollback) fail('legacy workshop reference format is disabled; regenerate a typed artifact');
  if (typeof options.legacySourceEnvironment !== 'string' || !SOURCE_ENV_RE.test(options.legacySourceEnvironment)) {
    fail('legacy reference rollback is restricted to an explicit staging/test environment');
  }
  if (typeof options.diagnostic === 'function') options.diagnostic('WARNING: explicit staging/test legacy reference rollback is active');
  const meta = referenceData.vehicleIdentityExport;
  if (!Array.isArray(referenceData.vehicles) || !meta || meta.outcome !== 'exported'
      || !Number.isInteger(meta.export_revision) || meta.export_revision !== options.expectedResolverRevision) {
    fail('legacy reference format failed explicit version validation');
  }
  const indexItems = referenceData.vehicles.map(_item => {
    const identifiers = Array.isArray(_item.identifiers) && _item.identifiers.length
      ? _item.identifiers
      : [
        ...(isRealLegacyStock(_item.stock_number)
          ? [{ identifier_type: 'stock_number', value: _item.stock_number,
            normalized_value: normalizeLegacyStock(_item.stock_number), source_system: null, origin: 'canonical' }]
          : []),
        ...(typeof _item.permanent_vehicle_id === 'string' && _item.permanent_vehicle_id.trim()
          ? [{ identifier_type: 'permanent_vehicle_id', value: _item.permanent_vehicle_id,
            normalized_value: _item.permanent_vehicle_id.trim().toUpperCase(), source_system: null, origin: 'canonical' }]
          : []),
      ];
    return normalizeItem({
    vehicle_id: _item.vehicle_id || _item.id,
    version: _item.version,
    is_archived: _item.is_archived,
    identifiers,
    });
  });
  return { ...referenceData, vehicles: indexItems };
}

module.exports = {
  ARTIFACT_SCHEMA_VERSION,
  VehicleReferenceArtifactError,
  VehicleReferenceArtifactStaleError,
  stableStringify,
  artifactChecksum,
  buildVehicleReferenceArtifact,
  validateVehicleReferenceArtifact,
  parseWorkshopReference,
};
