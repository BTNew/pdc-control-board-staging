'use strict';

const assert = require('assert');
const foundation = require('./notification-qc-foundation.js');

const {
  INTENDED_FUTURE_SENDER,
  NOTIFICATION_EVENT_TYPES: TYPES,
  SUPPORTED_EVENT_TYPES,
  deterministicHash,
  stableSerialize,
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
} = foundation;

function throwsCode(fn, code) {
  assert.throws(fn, error => error && error.code === code, `expected error code ${code}`);
}

assert.deepStrictEqual(SUPPORTED_EVENT_TYPES, [
  'arrival_pmb', 'workshop_booking', 'schedule_change', 'parts', 'sublet',
  'stoppage', 'qc_required', 'qc_completed', 'rft', 'weekly'
]);
for (const type of Object.values(TYPES)) assert.strictEqual(assertSupportedEventType(type), type);
throwsCode(() => assertSupportedEventType('email_everybody'), 'UNSUPPORTED_EVENT_TYPE');
assert.strictEqual(INTENDED_FUTURE_SENDER, 'pmbcontroller@gmail.com');

// Stable identity is independent of object insertion order.
assert.strictEqual(stableSerialize({ z: 1, a: { y: 2, x: 3 } }), '{"a":{"x":3,"y":2},"z":1}');
assert.strictEqual(deterministicHash({ a: 1, b: 2 }), deterministicHash({ b: 2, a: 1 }));

const directory = {
  salesperson_7: { email: ' SALES@Example.com ', name: 'Sales Seven' },
  workshop: [
    { email: 'workshop@example.com', name: 'Workshop', kind: 'workshop' },
    { email: 'invalid', kind: 'workshop' }
  ],
  qc: { email: 'qc@example.com', kind: 'qc' }
};
const baseEvent = {
  type: TYPES.ARRIVAL_PMB,
  vehicleId: 'vehicle-123',
  occurredAt: '2026-08-12T08:30:00+08:00',
  revision: 7,
  recipientKeys: ['workshop'],
  salespersonKey: 'salesperson_7',
  recipients: [
    { email: 'QC@example.com', name: 'Quality', kind: 'qc' },
    { email: 'sales@example.com', name: 'Duplicate', kind: 'salesperson' },
    { email: 'bad address', kind: 'admin' }
  ],
  subject: 'Vehicle arrived at PMB',
  summary: 'Arrival captured',
  details: { registration: 'ABC123', stage: 'PMB' }
};
const recipients = resolveRecipients(baseEvent, directory);
assert.deepStrictEqual(recipients.map(item => item.email), ['qc@example.com', 'sales@example.com', 'workshop@example.com']);
assert(Object.isFrozen(recipients));
assert.strictEqual(recipients.find(item => item.email === 'sales@example.com').name, 'Duplicate', 'first explicit recipient wins deterministic dedup');
throwsCode(() => resolveRecipients({ recipients: [{ email: 'x@example.com', kind: 'hacker' }] }), 'UNSUPPORTED_RECIPIENT_KIND');

const preview = buildNotificationPreview(baseEvent, directory);
assert.strictEqual(preview.contractVersion, 1);
assert.strictEqual(preview.eventType, TYPES.ARRIVAL_PMB);
assert.strictEqual(preview.entityId, 'vehicle-123');
assert.strictEqual(preview.occurredAt, '2026-08-12T00:30:00.000Z');
assert.match(preview.previewId, /^preview_[0-9a-f]{8}$/);
assert.match(preview.idempotencyKey, /^notify:arrival_pmb:vehicle-123:[0-9a-f]{8}$/);
assert.strictEqual(preview.intendedSender, INTENDED_FUTURE_SENDER);
assert.strictEqual(preview.senderStatus, 'future_only_not_configured');
assert.strictEqual(preview.dryRun, true);
assert.strictEqual(preview.send, false);
assert.strictEqual(preview.outboundAllowed, false);
assert(Object.isFrozen(preview));

const reordered = {
  ...baseEvent,
  details: { stage: 'PMB', registration: 'ABC123' },
  recipients: [...baseEvent.recipients].reverse()
};
assert.strictEqual(notificationIdempotencyKey(baseEvent, recipients), notificationIdempotencyKey(reordered, resolveRecipients(reordered, directory)));
assert.strictEqual(buildNotificationPreview(baseEvent, directory).previewId, buildNotificationPreview(baseEvent, directory).previewId);
throwsCode(() => buildNotificationPreview({ ...baseEvent, type: 'unknown' }), 'UNSUPPORTED_EVENT_TYPE');
throwsCode(() => buildNotificationPreview({ ...baseEvent, vehicleId: '', entityId: '' }), 'ENTITY_ID_REQUIRED');
throwsCode(() => buildNotificationPreview({ ...baseEvent, occurredAt: 'not-a-date' }), 'OCCURRED_AT_REQUIRED');
throwsCode(() => buildNotificationPreview({ ...baseEvent, revision: null }), 'REVISION_REQUIRED');

// All supported categories can be previewed and can never imply an outbound send.
for (const type of SUPPORTED_EVENT_TYPES) {
  const item = buildNotificationPreview({ ...baseEvent, type, revision: `revision-${type}` }, directory);
  assert.strictEqual(item.dryRun, true);
  assert.strictEqual(item.send, false);
  assert.strictEqual(item.outboundAllowed, false);
}

const change1 = { ...baseEvent, type: TYPES.SCHEDULE_CHANGE, revision: 10, summary: 'Moved to bay 1', occurredAt: '2026-08-12T01:00:00Z' };
const change2 = { ...baseEvent, type: TYPES.SCHEDULE_CHANGE, revision: 11, summary: 'Moved to bay 2', occurredAt: '2026-08-12T02:00:00Z' };
const parts = { ...baseEvent, type: TYPES.PARTS, revision: 12, summary: 'Parts ETA set', occurredAt: '2026-08-12T03:00:00Z' };
const consolidated = consolidateNotificationEvents([change2, change1, change1, parts], directory);
assert.strictEqual(consolidated.length, 2);
const schedules = consolidated.find(item => item.eventType === TYPES.SCHEDULE_CHANGE);
assert.strictEqual(schedules.consolidatedCount, 2);
assert.deepStrictEqual(schedules.summaries, ['Moved to bay 1', 'Moved to bay 2']);
assert.strictEqual(schedules.revision, '11', 'last chronological event is represented');
assert.strictEqual(schedules.dryRun, true);
assert.strictEqual(schedules.send, false);
assert.strictEqual(schedules.outboundAllowed, false);
assert.strictEqual(consolidateNotificationEvents([parts, change1, change2, change1], directory).find(item => item.eventType === TYPES.SCHEDULE_CHANGE).idempotencyKey, schedules.idempotencyKey);
assert.strictEqual(deduplicateNotificationPreviews([preview, preview]).length, 1);
throwsCode(() => deduplicateNotificationPreviews([{ ...preview, send: true }]), 'OUTBOUND_PREVIEW_FORBIDDEN');

// QC may only be entered after every required station is green.
const greenStations = [
  { code: 'MECHANICAL', required: true, status: 'green' },
  { code: 'PIT_INSPECTION', required: true, status: 'GREEN' },
  { code: 'OPTIONAL_DETAIL', required: false, status: 'red' }
];
assert.strictEqual(validateQcEntry(greenStations).allowed, true);
assert.strictEqual(assertQcEntry(greenStations).allowed, true);
const blocked = validateQcEntry([
  { code: 'MECHANICAL', required: true, status: 'red' },
  { code: 'PIT_INSPECTION', required: true, status: '' }
]);
assert.strictEqual(blocked.allowed, false);
assert.deepStrictEqual(blocked.blockingStations, ['MECHANICAL', 'PIT_INSPECTION']);
throwsCode(() => assertQcEntry([{ code: 'MECHANICAL', status: 'amber' }]), 'QC_STATIONS_NOT_GREEN');
throwsCode(() => validateQcEntry([]), 'STATIONS_REQUIRED');

// Email, AI, automation and remote completion are explicitly denied.
for (const method of ['email', 'ai', 'automation', 'remote']) {
  const denied = validatePhysicalQcCompletion({ method, actorId: 'actor-1', verifiedAt: '2026-08-12T04:00:00Z' });
  assert.strictEqual(denied.allowed, false);
  assert(denied.reasons.includes(`${method}_completion_denied`));
  throwsCode(() => completeQc({ method, actorId: 'actor-1', verifiedAt: '2026-08-12T04:00:00Z' }), 'QC_PHYSICAL_VERIFICATION_REQUIRED');
}
assert.strictEqual(validatePhysicalQcCompletion({ method: 'physical', actorId: '', verifiedAt: 'bad' }).allowed, false);
const qcComplete = completeQc({ method: 'physical', actorId: 'inspector-9', verifiedAt: '2026-08-12T12:00:00+08:00' });
assert.deepStrictEqual(qcComplete, { state: 'qc_complete', completedBy: 'inspector-9', completedAt: '2026-08-12T04:00:00.000Z', method: 'physical' });

const defect = mapQcDefectToStation({ stationCode: 'MECHANICAL', description: 'Loose fastener' }, ['MECHANICAL', 'PIT_INSPECTION']);
assert.deepStrictEqual(defect, { stationCode: 'MECHANICAL', description: 'Loose fastener', status: 'red', qcState: 'defect_returned_to_station' });
throwsCode(() => mapQcDefectToStation({ stationCode: 'UNKNOWN', description: 'Issue' }, ['MECHANICAL']), 'UNKNOWN_DEFECT_STATION');
throwsCode(() => mapQcDefectToStation({ stationCode: 'MECHANICAL', description: '' }), 'DEFECT_DESCRIPTION_REQUIRED');

assert.deepStrictEqual(validateAdminReopen({ role: 'operator', reason: '' }).reasons, ['admin_required', 'reason_required']);
assert.strictEqual(validateAdminReopen({ role: 'administrator', reason: 'Recheck defect' }).allowed, true);
throwsCode(() => reopenQc({ role: 'admin', reason: '  ' }), 'QC_REOPEN_DENIED');
assert.deepStrictEqual(reopenQc({ isAdmin: true, actorId: 'admin-1', reason: 'Physical reinspection requested' }), {
  state: 'qc_required', reason: 'Physical reinspection requested', reopenedBy: 'admin-1'
});

const rftPreview = qcCompleteToRftPreview(qcComplete, { ...baseEvent, type: TYPES.QC_COMPLETED, revision: 20, summary: 'Ready for transport' }, directory);
assert.strictEqual(rftPreview.eventType, TYPES.RFT);
assert.strictEqual(rftPreview.dryRun, true);
assert.strictEqual(rftPreview.send, false);
assert.strictEqual(rftPreview.intendedSender, INTENDED_FUTURE_SENDER);
throwsCode(() => qcCompleteToRftPreview({ state: 'qc_complete', method: 'ai' }, baseEvent, directory), 'QC_COMPLETE_REQUIRED');
throwsCode(() => qcCompleteToRftPreview({ state: 'qc_required', method: 'physical' }, baseEvent, directory), 'QC_COMPLETE_REQUIRED');

// Photo payloads contain private object metadata only; URLs and bytes are denied.
const photo = {
  storageKey: 'dealer/vehicle-123/qc/photo-1.webp',
  contentType: 'image/webp',
  sizeBytes: 2048,
  checksum: 'sha256:abc',
  capturedAt: '2026-08-12T04:00:00Z'
};
const validPhoto = validatePrivatePhotoMetadata(photo);
assert.strictEqual(validPhoto.valid, true);
assert.deepStrictEqual(validPhoto.metadata, photo);
for (const bad of [
  { ...photo, publicUrl: 'https://cdn.example.com/photo.webp' },
  { ...photo, caption: 'unexpected free-form content' },
  { ...photo, storageKey: 'https://bucket.example.com/photo.webp' },
  { ...photo, content: 'raw-bytes' },
  { ...photo, data: 'data:image/png;base64,AAAA' },
  { ...photo, storageKey: '../escape.webp' },
  { ...photo, contentType: 'text/html' },
  { ...photo, sizeBytes: 16 * 1024 * 1024 }
]) assert.strictEqual(validatePrivatePhotoMetadata(bad).valid, false);

// PWA queue is replay-only, idempotent and cannot produce notification effects.
const offlineAction = {
  type: 'qc_physical_verify',
  entityId: 'vehicle-123',
  clientMutationId: 'device-a:42',
  createdAt: '2026-08-12T04:00:00Z',
  payload: { method: 'physical', actorId: 'inspector-9' }
};
const queueItem = createOfflineQueueItem(offlineAction);
assert.match(queueItem.queueId, /^offline_[0-9a-f]{8}$/);
assert.strictEqual(queueItem.status, 'pending');
assert.strictEqual(queueItem.attempts, 0);
assert.strictEqual(queueItem.requiresAuthenticatedReplay, true);
assert.strictEqual(queueItem.conflictPolicy, 'server_authority_revalidate');
assert.strictEqual(queueItem.notificationSideEffectAllowed, false);
assert.strictEqual(queueItem.dryRun, true);
assert.strictEqual(createOfflineQueueItem({ ...offlineAction, createdAt: '2026-08-13T04:00:00Z' }).queueId, queueItem.queueId, 'retries retain deterministic identity');
assert.strictEqual(deduplicateOfflineQueue([queueItem, queueItem]).length, 1);
throwsCode(() => createOfflineQueueItem({ ...offlineAction, type: 'send_email' }), 'OFFLINE_ACTION_TYPE_FORBIDDEN');
throwsCode(() => createOfflineQueueItem({ ...offlineAction, clientMutationId: '' }), 'OFFLINE_IDENTITY_REQUIRED');
throwsCode(() => createOfflineQueueItem({ ...offlineAction, createdAt: 'today' }), 'OFFLINE_CREATED_AT_REQUIRED');
throwsCode(() => createOfflineQueueItem({ ...offlineAction, type: 'photo_metadata', payload: { ...photo, url: 'https://public.example/a' } }), 'PRIVATE_PHOTO_METADATA_REQUIRED');
const photoQueue = createOfflineQueueItem({ ...offlineAction, type: 'photo_metadata', payload: photo });
assert.strictEqual(photoQueue.notificationSideEffectAllowed, false);
throwsCode(() => deduplicateOfflineQueue([{ ...queueItem, notificationSideEffectAllowed: true }]), 'OFFLINE_NOTIFICATION_FORBIDDEN');

console.log('Notification dry-run, QC authority, private photo metadata and PWA offline queue foundation checks passed');
