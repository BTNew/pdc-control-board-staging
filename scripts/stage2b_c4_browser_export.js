'use strict';

/* Stage 2B C4 browser-local readiness exporter.
 *
 * This file reads only PDC-owned localStorage values (plus location.origin
 * for provenance) and emits normalized identity/count/hash evidence. It performs
 * no localStorage mutation and no network request.
 * The downloaded JSON contains narrow identity/linkage evidence only; customer,
 * notes, file contents, audit details and other operational payloads are omitted.
 */
(function stage2bC4Module(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.PDC_STAGE2B_C4_EXPORT = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function factory() {
  const SCHEMA = 'pdc.stage2b.c4-browser-assessment/v1';
  const KEYS = Object.freeze({
    edits: 'vehicleTrackingCoreNavisionOnlyEdits:v1',
    added: 'vehicleTrackingCoreNavisionOnlyVehicles:v1',
    deleted: 'vehicleTrackingCoreNavisionOnlyDeleted:v1',
    po_tasks: 'vehicleTrackingCoreNavisionOnlyPoTasks:v1',
    po_files: 'vehicleTrackingCoreNavisionOnlyPoFiles:v1',
    audit: 'vehicleTrackingCoreNavisionOnlyAuditLog:v1',
    navision_import: 'vehicleTrackingCoreNavisionOnlyImport:v1',
    autocare: 'vehicleTrackingCoreNavisionOnlyAutocareDispatch:v1',
    workshop_plans: 'vehicleTrackingCoreWorkshopPlan:v1',
    workshop_view: 'vehicleTrackingCoreWorkshopView:v1',
    workshop_bay_setup: 'vehicleTrackingCoreWorkshopBaySetup:v1',
    canonical_links: 'workshopCanonicalVehicleLinks:v1',
  });
  const PDC_STORAGE_PREFIXES = Object.freeze(['vehicleTrackingCore', 'broomeToyotaVehicleCrm']);
  const NOTES_PREFIX = 'vehicleTrackingCoreNotes:';
  const WORKFLOW_PREFIXES = Object.freeze(['pmb', 'pdc', 'workshop']);
  const IDENTITY_KEYS = Object.freeze({
    stock_number: ['stock', 'stockNumber', 'stock_number'],
    vin: ['vin', 'VIN', 'chassis', 'chassisNo', 'autocareVin'],
    job_card_number: ['pdcJobcard', 'jobcard', 'jobCard', 'jobcardNumber', 'jobCardNumber', 'jcJobcard', 'jc'],
    permanent_vehicle_id: ['permanentVehicleId', 'permanent_vehicle_id'],
    toyota_order_number: ['order', 'toyotaOrder', 'salesOrder'],
    legacy_id: ['id'],
  });

  function canonicalize(value) {
    if (Array.isArray(value)) return value.map(canonicalize);
    if (value && typeof value === 'object') {
      const result = {};
      Object.keys(value).sort().forEach(key => { result[key] = canonicalize(value[key]); });
      return result;
    }
    return value;
  }

  function canonicalJson(value) {
    return JSON.stringify(canonicalize(value));
  }

  async function sha256Hex(text, cryptoObject) {
    const cryptoApi = cryptoObject || (typeof crypto !== 'undefined' ? crypto : null);
    if (!cryptoApi || !cryptoApi.subtle || typeof TextEncoder === 'undefined') {
      if (typeof require === 'function') return require('crypto').createHash('sha256').update(text, 'utf8').digest('hex');
      throw new Error('SHA-256 support is unavailable');
    }
    const digest = await cryptoApi.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
  }

  function isPdcStorageKey(key) {
    return PDC_STORAGE_PREFIXES.some(prefix => key.startsWith(prefix)) || key === KEYS.canonical_links;
  }

  function snapshotStorage(storage) {
    if (!storage || typeof storage.length !== 'number' || typeof storage.key !== 'function' || typeof storage.getItem !== 'function') {
      throw new Error('localStorage is unavailable');
    }
    const result = {};
    for (let index = 0; index < storage.length; index += 1) {
      const key = storage.key(index);
      if (typeof key !== 'string' || !isPdcStorageKey(key)) continue;
      result[key] = storage.getItem(key);
    }
    return canonicalize(result);
  }

  function parseJson(snapshot, key, fallback, parseErrors) {
    const raw = snapshot[key];
    if (raw == null) return fallback;
    try { return JSON.parse(raw); }
    catch (_) {
      parseErrors.push({ family: key, reason_code: 'invalid_json' });
      return fallback;
    }
  }

  function text(value) { return String(value == null ? '' : value).trim(); }
  function first(record, keys) {
    for (const key of keys) {
      const value = text(record && record[key]);
      if (value) return value;
    }
    return '';
  }
  function blankStock(value) {
    const stock = text(value);
    return !stock || stock === '0' || /^TBA$/i.test(stock) || /^PENDING-/i.test(stock);
  }
  function vehicleKey(record) {
    const stock = first(record, IDENTITY_KEYS.stock_number);
    const order = first(record, IDENTITY_KEYS.toyota_order_number);
    return stock && !blankStock(stock) ? stock : (order || first(record, IDENTITY_KEYS.legacy_id) || stock);
  }
  function deletedKey(record) {
    if (typeof record === 'string') return text(record);
    return first(record || {}, ['key', 'vehicleKey', 'stock', 'order', 'id']);
  }
  function countValue(value) {
    if (Array.isArray(value)) return value.length;
    if (value && typeof value === 'object') return Object.keys(value).length;
    return value == null || value === '' ? 0 : 1;
  }
  function workflowFields(edit) {
    return Object.keys(edit || {}).filter(key => WORKFLOW_PREFIXES.some(prefix => key.toLowerCase().startsWith(prefix))).sort();
  }
  function narrowVehicle(record, sourceFamily, sourceIndex, edit, poTasks, poFiles) {
    const key = vehicleKey(record);
    return {
      record_ref: `${sourceFamily}:${String(sourceIndex + 1).padStart(6, '0')}`,
      source_family: sourceFamily,
      legacy_vehicle_key: key,
      stock_number: first(record, IDENTITY_KEYS.stock_number) || null,
      vin: first(record, IDENTITY_KEYS.vin) || null,
      job_card_number: first(record, IDENTITY_KEYS.job_card_number) || null,
      permanent_vehicle_id: first(record, IDENTITY_KEYS.permanent_vehicle_id) || null,
      toyota_order_number: first(record, IDENTITY_KEYS.toyota_order_number) || null,
      legacy_id: first(record, IDENTITY_KEYS.legacy_id) || null,
      workflow_field_names: workflowFields(edit),
      parts_task_count: countValue(poTasks),
      parts_file_count: countValue(poFiles),
    };
  }

  async function buildAssessmentExport(environment) {
    const env = environment || {};
    const storage = env.localStorage || (typeof localStorage !== 'undefined' ? localStorage : null);
    const windowObject = env.windowObject || (typeof window !== 'undefined' ? window : {});
    const before = snapshotStorage(storage);
    const beforeJson = canonicalJson(before);
    const beforeHash = await sha256Hex(beforeJson, env.cryptoObject);
    const parseErrors = [];
    const added = parseJson(before, KEYS.added, [], parseErrors);
    const edits = parseJson(before, KEYS.edits, {}, parseErrors);
    const deleted = parseJson(before, KEYS.deleted, [], parseErrors);
    let poTasks = parseJson(before, KEYS.po_tasks, {}, parseErrors);
    let poFiles = parseJson(before, KEYS.po_files, {}, parseErrors);
    let plans = parseJson(before, KEYS.workshop_plans, [], parseErrors);
    let audit = parseJson(before, KEYS.audit, [], parseErrors);
    const navisionImport = parseJson(before, KEYS.navision_import, null, parseErrors);
    let canonicalLinks = parseJson(before, KEYS.canonical_links, {}, parseErrors);
    // Staging assessment scope is deliberately limited to PDC localStorage.
    // Runtime/static/Supabase-loaded vehicle collections are not inspected.
    const base = [];
    if (!Array.isArray(added) || !edits || typeof edits !== 'object' || Array.isArray(edits) || !Array.isArray(deleted)) {
      throw new Error('browser-local vehicle families have unexpected shapes');
    }
    for (const [family, value] of [['po_tasks', poTasks], ['po_files', poFiles]]) {
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        parseErrors.push({ family, reason_code: 'invalid_type' });
        if (family === 'po_tasks') poTasks = {}; else poFiles = {};
      }
    }
    if (!Array.isArray(plans)) { parseErrors.push({ family: 'workshop_plans', reason_code: 'invalid_type' }); plans = []; }
    if (!Array.isArray(audit)) { parseErrors.push({ family: 'audit', reason_code: 'invalid_type' }); audit = []; }
    if (!canonicalLinks || typeof canonicalLinks !== 'object' || Array.isArray(canonicalLinks)) {
      parseErrors.push({ family: 'canonical_links', reason_code: 'invalid_type' });
      canonicalLinks = {};
    }
    const deletedKeys = new Set(deleted.map(deletedKey).filter(Boolean));
    const combined = base.map((row, index) => ({ row, source: 'static', index }))
      .concat(added.map((row, index) => ({ row, source: 'added', index })));
    const vehicles = combined.filter(item => !deletedKeys.has(vehicleKey(item.row))).map(item => {
      const key = vehicleKey(item.row);
      const merged = { ...(item.row || {}), ...(edits[key] || edits[first(item.row, IDENTITY_KEYS.stock_number)] || {}) };
      return narrowVehicle(merged, item.source, item.index, edits[key] || {}, poTasks[key], poFiles[key]);
    }).sort((a, b) => a.record_ref.localeCompare(b.record_ref));
    const knownKeys = new Set(Object.values(KEYS));
    const notes = Object.keys(before).filter(key => key.startsWith(NOTES_PREFIX)).sort().map(key => {
      const value = parseJson(before, key, [], parseErrors);
      if (!Array.isArray(value)) {
        parseErrors.push({ family: `notes:${key.slice(NOTES_PREFIX.length)}`, reason_code: 'invalid_type' });
        return { legacy_vehicle_key: key.slice(NOTES_PREFIX.length), note_count: 0 };
      }
      return { legacy_vehicle_key: key.slice(NOTES_PREFIX.length), note_count: value.length };
    });
    const partsRecords = [];
    for (const [family, store] of [['po_tasks', poTasks], ['po_files', poFiles]]) {
      if (!store || typeof store !== 'object' || Array.isArray(store)) continue;
      Object.keys(store).sort().forEach(key => partsRecords.push({ family, legacy_vehicle_key: key, item_count: countValue(store[key]) }));
    }
    const workflows = Object.keys(edits).sort().map(key => ({
      legacy_vehicle_key: key,
      field_names: workflowFields(edits[key]),
    })).filter(row => row.field_names.length);
    const bookings = (Array.isArray(plans) ? plans : []).map((row, index) => ({
      booking_ref: `booking:${String(index + 1).padStart(6, '0')}`,
      legacy_vehicle_key: text(row?.vehicleKey),
      stage_code: text(row?.stage).toUpperCase() || null,
    })).sort((a, b) => a.booking_ref.localeCompare(b.booking_ref));
    const unknownVehicleKeys = Object.keys(before).filter(key =>
      (key.startsWith('vehicleTrackingCore') || key.startsWith('broomeToyotaVehicleCrm')) && !knownKeys.has(key) && !key.startsWith(NOTES_PREFIX)
    ).sort();
    const after = snapshotStorage(storage);
    const afterJson = canonicalJson(after);
    const afterHash = await sha256Hex(afterJson, env.cryptoObject);
    if (beforeJson !== afterJson || beforeHash !== afterHash) throw new Error('read-only invariant failed: localStorage changed during export');
    const payload = canonicalize({
      schema: SCHEMA,
      computer_name: text(env.computerName) || null,
      exported_at: text(env.exportedAt) || null,
      source_origin: text(env.origin || windowObject.location?.origin) || null,
      local_storage_sha256_before: beforeHash,
      local_storage_sha256_after: afterHash,
      local_storage_unchanged: true,
      families: {
        static_vehicle_count: base.length,
        added_vehicle_count: added.length,
        deleted_vehicle_count: deleted.length,
        edit_row_count: Object.keys(edits).length,
        audit_row_count: countValue(audit),
        navision_import_present: navisionImport != null,
        canonical_vehicle_link_count: Object.keys(canonicalLinks).length,
        unknown_vehicle_storage_keys: unknownVehicleKeys,
      },
      vehicles,
      deleted_records: deleted.map((row, index) => ({ record_ref: `deleted:${String(index + 1).padStart(6, '0')}`, legacy_vehicle_key: deletedKey(row) })),
      notes,
      parts_records: partsRecords,
      workflow_records: workflows,
      bookings,
      parse_errors: parseErrors.sort((a, b) => `${a.family}:${a.reason_code}`.localeCompare(`${b.family}:${b.reason_code}`)),
      excluded_payloads: ['customer data', 'note text', 'Parts content', 'file content', 'audit details', 'Navision payload'],
    });
    payload.assessment_export_sha256 = await sha256Hex(canonicalJson(payload), env.cryptoObject);
    return payload;
  }

  async function downloadAssessmentExport(environment) {
    const computerName = text(environment?.computerName) || 'Computer';
    const exportedAt = text(environment?.exportedAt) || new Date().toISOString();
    const payload = await buildAssessmentExport({ ...(environment || {}), computerName, exportedAt });
    const documentObject = environment?.documentObject || (typeof document !== 'undefined' ? document : null);
    const urlApi = environment?.urlApi || (typeof URL !== 'undefined' ? URL : null);
    if (!documentObject || !urlApi || typeof Blob === 'undefined') throw new Error('browser download APIs are unavailable');
    const blob = new Blob([`${canonicalJson(payload)}\n`], { type: 'application/json' });
    const url = urlApi.createObjectURL(blob);
    const anchor = documentObject.createElement('a');
    anchor.href = url;
    const safeComputerName = computerName.normalize('NFKD')
      .replace(/[^A-Za-z0-9._-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 48) || 'Computer';
    const safeTimestamp = exportedAt.replace(/[:.]/g, '-');
    anchor.download = `PDC-Read-Only-Browser-Assessment-${safeComputerName}-${safeTimestamp}-${payload.assessment_export_sha256.slice(0, 12)}.json`;
    documentObject.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    urlApi.revokeObjectURL(url);
    return payload;
  }

  return Object.freeze({
    SCHEMA, KEYS, NOTES_PREFIX, PDC_STORAGE_PREFIXES, isPdcStorageKey, canonicalJson, snapshotStorage,
    buildAssessmentExport, downloadAssessmentExport,
  });
}));
