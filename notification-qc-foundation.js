'use strict';

/*
 * Pure staging foundation for notification previews, QC authority and offline
 * queue validation. This module intentionally has no I/O, network or storage.
 */

const INTENDED_FUTURE_SENDER = 'pmbcontroller@gmail.com';
const NOTIFICATION_EVENT_TYPES = Object.freeze({
  ARRIVAL_PMB: 'arrival_pmb',
  WORKSHOP_BOOKING: 'workshop_booking',
  SCHEDULE_CHANGE: 'schedule_change',
  PARTS: 'parts',
  SUBLET: 'sublet',
  STOPPAGE: 'stoppage',
  QC_REQUIRED: 'qc_required',
  QC_COMPLETED: 'qc_completed',
  RFT: 'rft',
  WEEKLY: 'weekly'
});
const SUPPORTED_EVENT_TYPES = Object.freeze(Object.values(NOTIFICATION_EVENT_TYPES));
const RECIPIENT_KINDS = Object.freeze(['salesperson', 'customer', 'workshop', 'parts', 'sublet', 'qc', 'admin']);
const OFFLINE_ACTION_TYPES = Object.freeze(['qc_enter', 'qc_physical_verify', 'qc_defect', 'qc_admin_reopen', 'photo_metadata']);

function invariant(condition, message, code) {
  if (!condition) {
    const error = new TypeError(message);
    error.code = code || 'INVALID_CONTRACT';
    throw error;
  }
}

function cleanString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizeEmail(value) {
  const email = cleanString(value).toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : '';
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === 'object') {
    return Object.keys(value).sort().reduce((result, key) => {
      if (value[key] !== undefined) result[key] = stableValue(value[key]);
      return result;
    }, {});
  }
  return value;
}

function stableSerialize(value) {
  return JSON.stringify(stableValue(value));
}

// FNV-1a represented as an unsigned, fixed-width hex string. It is an identity
// token, not a security primitive.
function deterministicHash(value) {
  const text = typeof value === 'string' ? value : stableSerialize(value);
  let hash = 0x811c9dc5;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, '0');
}

function assertSupportedEventType(type) {
  invariant(SUPPORTED_EVENT_TYPES.includes(type), `Unsupported notification event type: ${type}`, 'UNSUPPORTED_EVENT_TYPE');
  return type;
}

function normalizeRecipient(candidate, fallbackKind) {
  if (typeof candidate === 'string') candidate = { email: candidate };
  if (!candidate || typeof candidate !== 'object') return null;
  const email = normalizeEmail(candidate.email);
  if (!email) return null;
  const kind = cleanString(candidate.kind || candidate.role || fallbackKind).toLowerCase() || 'salesperson';
  invariant(RECIPIENT_KINDS.includes(kind), `Unsupported recipient kind: ${kind}`, 'UNSUPPORTED_RECIPIENT_KIND');
  return Object.freeze({ email, name: cleanString(candidate.name), kind });
}

/** Resolve explicit recipients and role keys against a caller-provided directory. */
function resolveRecipients(event, directory) {
  invariant(event && typeof event === 'object', 'Event is required', 'EVENT_REQUIRED');
  directory = directory && typeof directory === 'object' ? directory : {};
  const candidates = [];
  const explicit = Array.isArray(event.recipients) ? event.recipients : [];
  candidates.push(...explicit.map(item => ({ item, kind: item && item.kind })));

  const keys = Array.isArray(event.recipientKeys) ? event.recipientKeys : [];
  for (const key of keys) {
    const entry = directory[key];
    const entries = Array.isArray(entry) ? entry : [entry];
    for (const item of entries) candidates.push({ item, kind: key });
  }
  if (event.salespersonKey && directory[event.salespersonKey]) {
    candidates.push({ item: directory[event.salespersonKey], kind: 'salesperson' });
  }

  const byEmail = new Map();
  for (const candidate of candidates) {
    const recipient = normalizeRecipient(candidate.item, candidate.kind);
    if (!recipient) continue;
    if (!byEmail.has(recipient.email)) byEmail.set(recipient.email, recipient);
  }
  return Object.freeze([...byEmail.values()].sort((a, b) => a.email.localeCompare(b.email)));
}

function canonicalEvent(event) {
  invariant(event && typeof event === 'object', 'Notification event is required', 'EVENT_REQUIRED');
  assertSupportedEventType(event.type);
  const entityId = cleanString(event.entityId || event.vehicleId);
  invariant(entityId, 'event.entityId or event.vehicleId is required', 'ENTITY_ID_REQUIRED');
  const occurredAt = cleanString(event.occurredAt);
  invariant(occurredAt && Number.isFinite(Date.parse(occurredAt)), 'event.occurredAt must be an ISO-compatible timestamp', 'OCCURRED_AT_REQUIRED');
  const revision = cleanString(String(event.revision == null ? '' : event.revision));
  invariant(revision, 'event.revision is required for idempotency', 'REVISION_REQUIRED');
  return {
    type: event.type,
    entityId,
    occurredAt: new Date(occurredAt).toISOString(),
    revision,
    subject: cleanString(event.subject),
    summary: cleanString(event.summary),
    details: stableValue(event.details || {})
  };
}

function notificationIdempotencyKey(event, recipients) {
  const canonical = canonicalEvent(event);
  const emails = (recipients || []).map(item => normalizeEmail(item.email || item)).filter(Boolean).sort();
  return `notify:${canonical.type}:${canonical.entityId}:${deterministicHash({ revision: canonical.revision, recipients: emails, details: canonical.details })}`;
}

function buildNotificationPreview(event, directory) {
  const canonical = canonicalEvent(event);
  const recipients = resolveRecipients(event, directory);
  const idempotencyKey = notificationIdempotencyKey(event, recipients);
  return Object.freeze({
    contractVersion: 1,
    previewId: `preview_${deterministicHash(idempotencyKey)}`,
    idempotencyKey,
    eventType: canonical.type,
    entityId: canonical.entityId,
    occurredAt: canonical.occurredAt,
    revision: canonical.revision,
    recipients,
    subject: canonical.subject || `[DRY RUN] ${canonical.type.replace(/_/g, ' ')}`,
    summary: canonical.summary,
    details: canonical.details,
    intendedSender: INTENDED_FUTURE_SENDER,
    senderStatus: 'future_only_not_configured',
    dryRun: true,
    send: false,
    outboundAllowed: false
  });
}

/** Remove exact retries, then combine adjacent same vehicle/type/recipient events. */
function consolidateNotificationEvents(events, directory) {
  invariant(Array.isArray(events), 'events must be an array', 'EVENTS_ARRAY_REQUIRED');
  const unique = new Map();
  for (const event of events) {
    const preview = buildNotificationPreview(event, directory);
    if (!unique.has(preview.idempotencyKey)) unique.set(preview.idempotencyKey, preview);
  }
  const groups = new Map();
  for (const preview of unique.values()) {
    const recipientKey = preview.recipients.map(item => item.email).join(',');
    const key = `${preview.eventType}\u0000${preview.entityId}\u0000${recipientKey}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(preview);
  }
  return Object.freeze([...groups.values()].map(group => {
    group.sort((a, b) => a.occurredAt.localeCompare(b.occurredAt) || a.revision.localeCompare(b.revision));
    const last = group[group.length - 1];
    const keys = group.map(item => item.idempotencyKey);
    return Object.freeze({
      ...last,
      previewId: `preview_${deterministicHash(keys)}`,
      idempotencyKey: `consolidated:${deterministicHash(keys)}`,
      consolidatedCount: group.length,
      sourceIdempotencyKeys: Object.freeze(keys),
      summaries: Object.freeze(group.map(item => item.summary).filter(Boolean)),
      dryRun: true,
      send: false,
      outboundAllowed: false
    });
  }).sort((a, b) => a.occurredAt.localeCompare(b.occurredAt) || a.idempotencyKey.localeCompare(b.idempotencyKey)));
}

function deduplicateNotificationPreviews(previews) {
  invariant(Array.isArray(previews), 'previews must be an array', 'PREVIEWS_ARRAY_REQUIRED');
  const seen = new Set();
  return Object.freeze(previews.filter(preview => {
    invariant(preview && preview.dryRun === true && preview.send === false && preview.outboundAllowed === false,
      'Only non-outbound dry-run previews are accepted', 'OUTBOUND_PREVIEW_FORBIDDEN');
    invariant(cleanString(preview.idempotencyKey), 'Preview idempotencyKey is required', 'IDEMPOTENCY_KEY_REQUIRED');
    if (seen.has(preview.idempotencyKey)) return false;
    seen.add(preview.idempotencyKey);
    return true;
  }));
}

function normalizeStations(stations) {
  invariant(Array.isArray(stations) && stations.length > 0, 'At least one station is required', 'STATIONS_REQUIRED');
  return stations.map(station => {
    invariant(station && typeof station === 'object', 'Station entries must be objects', 'INVALID_STATION');
    const code = cleanString(station.code);
    invariant(code, 'Station code is required', 'STATION_CODE_REQUIRED');
    return { code, required: station.required !== false, status: cleanString(station.status).toLowerCase() };
  });
}

function validateQcEntry(stations) {
  const normalized = normalizeStations(stations);
  const blockingStations = normalized.filter(station => station.required && station.status !== 'green').map(station => station.code);
  return Object.freeze({ allowed: blockingStations.length === 0, blockingStations: Object.freeze(blockingStations), normalizedStations: Object.freeze(normalized) });
}

function assertQcEntry(stations) {
  const result = validateQcEntry(stations);
  invariant(result.allowed, `QC entry blocked by required stations: ${result.blockingStations.join(', ')}`, 'QC_STATIONS_NOT_GREEN');
  return result;
}

function validatePhysicalQcCompletion(action) {
  invariant(action && typeof action === 'object', 'QC completion action is required', 'QC_ACTION_REQUIRED');
  const method = cleanString(action.method).toLowerCase();
  const actorId = cleanString(action.actorId);
  const verifiedAt = cleanString(action.verifiedAt);
  const denied = ['email', 'ai', 'automation', 'remote'];
  const reasons = [];
  if (method !== 'physical') reasons.push(denied.includes(method) ? `${method}_completion_denied` : 'physical_verification_required');
  if (!actorId) reasons.push('actor_required');
  if (!verifiedAt || !Number.isFinite(Date.parse(verifiedAt))) reasons.push('verified_at_required');
  return Object.freeze({ allowed: reasons.length === 0, reasons: Object.freeze(reasons) });
}

function completeQc(action) {
  const result = validatePhysicalQcCompletion(action);
  invariant(result.allowed, `QC cannot complete: ${result.reasons.join(', ')}`, 'QC_PHYSICAL_VERIFICATION_REQUIRED');
  return Object.freeze({ state: 'qc_complete', completedBy: cleanString(action.actorId), completedAt: new Date(action.verifiedAt).toISOString(), method: 'physical' });
}

function mapQcDefectToStation(defect, stationCodes) {
  invariant(defect && typeof defect === 'object', 'Defect is required', 'DEFECT_REQUIRED');
  const stationCode = cleanString(defect.stationCode);
  const description = cleanString(defect.description);
  invariant(stationCode, 'Defect stationCode is required', 'DEFECT_STATION_REQUIRED');
  invariant(description, 'Defect description is required', 'DEFECT_DESCRIPTION_REQUIRED');
  if (Array.isArray(stationCodes)) invariant(stationCodes.includes(stationCode), `Unknown defect station: ${stationCode}`, 'UNKNOWN_DEFECT_STATION');
  return Object.freeze({ stationCode, description, status: 'red', qcState: 'defect_returned_to_station' });
}

function validateAdminReopen(action) {
  const isAdmin = action && (action.isAdmin === true || cleanString(action.role).toLowerCase() === 'admin' || cleanString(action.role).toLowerCase() === 'administrator');
  const reason = cleanString(action && action.reason);
  return Object.freeze({ allowed: Boolean(isAdmin && reason), reasons: Object.freeze([!isAdmin ? 'admin_required' : '', !reason ? 'reason_required' : ''].filter(Boolean)) });
}

function reopenQc(action) {
  const result = validateAdminReopen(action);
  invariant(result.allowed, `QC reopen denied: ${result.reasons.join(', ')}`, 'QC_REOPEN_DENIED');
  return Object.freeze({ state: 'qc_required', reason: cleanString(action.reason), reopenedBy: cleanString(action.actorId) });
}

function qcCompleteToRftPreview(qcCompletion, event, directory) {
  invariant(qcCompletion && qcCompletion.state === 'qc_complete' && qcCompletion.method === 'physical', 'Physical QC completion is required before RFT', 'QC_COMPLETE_REQUIRED');
  return buildNotificationPreview({ ...event, type: NOTIFICATION_EVENT_TYPES.RFT }, directory);
}

function validatePrivatePhotoMetadata(photo) {
  const reasons = [];
  if (!photo || typeof photo !== 'object' || Array.isArray(photo)) return Object.freeze({ valid: false, reasons: Object.freeze(['metadata_object_required']) });
  const allowedKeys = new Set(['storageKey', 'contentType', 'sizeBytes', 'checksum', 'capturedAt']);
  const storageKey = cleanString(photo.storageKey);
  const contentType = cleanString(photo.contentType).toLowerCase();
  if (!storageKey || storageKey.startsWith('/') || storageKey.includes('..') || /^https?:\/\//i.test(storageKey)) reasons.push('private_storage_key_required');
  if (!/^image\/(jpeg|png|webp|heic)$/.test(contentType)) reasons.push('unsupported_image_content_type');
  if (!Number.isInteger(photo.sizeBytes) || photo.sizeBytes <= 0 || photo.sizeBytes > 15 * 1024 * 1024) reasons.push('invalid_photo_size');
  for (const key of Object.keys(photo)) {
    if (!allowedKeys.has(key)) reasons.push(`${key}_forbidden`);
  }
  if (Object.values(photo).some(value => typeof value === 'string' && (/^https?:\/\//i.test(value) || /^data:/i.test(value)))) reasons.push('public_or_inline_content_forbidden');
  return Object.freeze({ valid: reasons.length === 0, reasons: Object.freeze([...new Set(reasons)]), metadata: reasons.length ? null : Object.freeze({ storageKey, contentType, sizeBytes: photo.sizeBytes, checksum: cleanString(photo.checksum), capturedAt: cleanString(photo.capturedAt) }) });
}

function createOfflineQueueItem(action) {
  invariant(action && typeof action === 'object', 'Offline action is required', 'OFFLINE_ACTION_REQUIRED');
  invariant(OFFLINE_ACTION_TYPES.includes(action.type), `Offline action type not allowed: ${action.type}`, 'OFFLINE_ACTION_TYPE_FORBIDDEN');
  const entityId = cleanString(action.entityId);
  const clientMutationId = cleanString(action.clientMutationId);
  const createdAt = cleanString(action.createdAt);
  invariant(entityId && clientMutationId, 'entityId and clientMutationId are required', 'OFFLINE_IDENTITY_REQUIRED');
  invariant(createdAt && Number.isFinite(Date.parse(createdAt)), 'createdAt must be a timestamp', 'OFFLINE_CREATED_AT_REQUIRED');
  invariant(action.payload && typeof action.payload === 'object' && !Array.isArray(action.payload), 'payload object is required', 'OFFLINE_PAYLOAD_REQUIRED');
  invariant(action.type !== 'photo_metadata' || validatePrivatePhotoMetadata(action.payload).valid, 'Invalid private photo metadata', 'PRIVATE_PHOTO_METADATA_REQUIRED');
  const identity = { type: action.type, entityId, clientMutationId };
  return Object.freeze({
    contractVersion: 1,
    queueId: `offline_${deterministicHash(identity)}`,
    ...identity,
    createdAt: new Date(createdAt).toISOString(),
    payload: stableValue(action.payload),
    status: 'pending',
    attempts: 0,
    requiresAuthenticatedReplay: true,
    conflictPolicy: 'server_authority_revalidate',
    notificationSideEffectAllowed: false,
    dryRun: true
  });
}

function deduplicateOfflineQueue(items) {
  invariant(Array.isArray(items), 'Offline queue must be an array', 'OFFLINE_QUEUE_ARRAY_REQUIRED');
  const seen = new Set();
  return Object.freeze(items.filter(item => {
    invariant(item && item.notificationSideEffectAllowed === false && item.dryRun === true, 'Offline queue cannot send notifications', 'OFFLINE_NOTIFICATION_FORBIDDEN');
    const key = cleanString(item.queueId) || deterministicHash({ type: item.type, entityId: item.entityId, clientMutationId: item.clientMutationId });
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }));
}

module.exports = Object.freeze({
  INTENDED_FUTURE_SENDER,
  NOTIFICATION_EVENT_TYPES,
  SUPPORTED_EVENT_TYPES,
  OFFLINE_ACTION_TYPES,
  stableSerialize,
  deterministicHash,
  assertSupportedEventType,
  resolveRecipients,
  notificationIdempotencyKey,
  buildNotificationPreview,
  consolidateNotificationEvents,
  deduplicateNotificationPreviews,
  validateQcEntry,
  assertQcEntry,
  validatePhysicalQcCompletion,
  completeQc,
  mapQcDefectToStation,
  validateAdminReopen,
  reopenQc,
  qcCompleteToRftPreview,
  validatePrivatePhotoMetadata,
  createOfflineQueueItem,
  deduplicateOfflineQueue
});
