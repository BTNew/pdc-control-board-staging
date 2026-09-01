'use strict';

(function attachPdcEmailAiV2Actions(root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.PDC_EMAIL_AI_V2_ACTIONS = api;
}(typeof window !== 'undefined' ? window : globalThis, function pdcEmailAiV2ActionsFactory() {
  const STAGING_PROJECT_REF = 'cdsmnqxtyyoeoznmbidd';
  const STAGING_SUPABASE_URL = 'https://cdsmnqxtyyoeoznmbidd.supabase.co';
  const PLAN_SCHEMA_VERSION = 'pdc-email-ai-plan-v1';
  const ACTION_CONTRACT_VERSION = 'pdc-email-ai-actions-v1';
  const ACTION_RPC = 'apply_pdc_email_ai_typed_action_surface_20260901';
  const CONTRACT_RPC = 'get_pdc_email_ai_successor_action_contract_20260901';
  const SNAPSHOT_RPC = 'get_pdc_email_vehicle_location_snapshot';
  const ACTION_TYPES = Object.freeze([
    'activate_vehicle', 'operation_add', 'operation_update',
    'parts_eta_set', 'parts_complete', 'booking_set', 'booking_move',
    'booking_cancel', 'required_work_set', 'work_complete', 'note_append',
    'location_set', 'rft_transfer', 'rft_collect',
  ]);
  const ACTION_TYPE_SET = new Set(ACTION_TYPES);
  const WORK_KEYS = new Set([
    'PARTS', 'TINT', 'HOIST', 'FITTING', 'BUS_4X4', 'FABRICATION',
    'ELECTRICAL', 'TYRE', 'PIT_INSPECTION', 'SUBLET',
  ]);
  const LOCATIONS = new Set(['YH', 'PMB', 'QC', 'RFT', 'OTHER', 'IT']);
  const TAXONOMY_DISPOSITIONS = new Set(['classified', 'review', 'unsupported', 'conflict']);
  const FORBIDDEN_KEYS = new Set([
    'sql', 'table', 'tables', 'column', 'schema', 'rpc', 'function',
    'query', 'mutation', 'dml', 'service_role', 'administrator', 'admin',
    'rls_bypass', 'security_definer',
  ]);
  const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const DIGEST_RE = /^[0-9a-f]{64}$/;
  const VIN_RE = /^[A-HJ-NPR-Z0-9]{17}$/i;
  const STOCK_RE = /^[A-Z0-9][A-Z0-9-]{3,79}$/i;
  const TAXONOMY_RE = /^pdc-operation-taxonomy-(?:proposed|approved)\/v[0-9]+$/;

  function isObject(value) {
    return !!value && typeof value === 'object' && !Array.isArray(value);
  }

  function exactKeys(value, expected, label) {
    if (!isObject(value) || Object.keys(value).sort().join('\u0000') !== [...expected].sort().join('\u0000')) {
      throw new TypeError(`${label} keys do not match the strict contract`);
    }
  }

  function text(value, label, min = 1, max = 500) {
    if (typeof value !== 'string' || value !== value.trim() || value.length < min || value.length > max || /[\u0000-\u001f\u007f]/.test(value)) {
      throw new TypeError(`${label} is invalid`);
    }
    return value;
  }

  function uuid(value, label) {
    const normalized = text(value, label, 36, 36).toLowerCase();
    if (!UUID_RE.test(normalized)) throw new TypeError(`${label} must be a canonical UUID`);
    return normalized;
  }

  function digest(value, label) {
    const normalized = text(value, label, 64, 64).toLowerCase();
    if (!DIGEST_RE.test(normalized)) throw new TypeError(`${label} must be a lowercase SHA-256 digest`);
    return normalized;
  }

  function nullableUuid(value, label) {
    return value === null ? null : uuid(value, label);
  }

  function positiveInteger(value, label) {
    if (!Number.isInteger(value) || value < 1) throw new TypeError(`${label} must be a positive integer`);
    return value;
  }

  function dateTime(value, label) {
    const normalized = text(value, label, 20, 40);
    if (Number.isNaN(Date.parse(normalized))) throw new TypeError(`${label} must be a date-time`);
    return normalized;
  }

  function noForbiddenKeys(value, path = 'plan') {
    if (Array.isArray(value)) {
      value.forEach((child, index) => noForbiddenKeys(child, `${path}[${index}]`));
      return;
    }
    if (!isObject(value)) return;
    Object.entries(value).forEach(([key, child]) => {
      if (FORBIDDEN_KEYS.has(key.toLowerCase())) throw new TypeError(`${path}.${key} is forbidden`);
      noForbiddenKeys(child, `${path}.${key}`);
    });
  }

  function validateIdentity(value, label) {
    exactKeys(value, ['stock_number', 'vin', 'backend_record_id'], label);
    if (value.stock_number !== null) {
      const stock = text(value.stock_number, `${label}.stock_number`, 4, 80).toUpperCase();
      if (!STOCK_RE.test(stock)) throw new TypeError(`${label}.stock_number is invalid`);
      value.stock_number = stock;
    }
    if (value.vin !== null) {
      const vin = text(value.vin, `${label}.vin`, 17, 17).toUpperCase();
      if (!VIN_RE.test(vin)) throw new TypeError(`${label}.vin is invalid`);
      value.vin = vin;
    }
    value.backend_record_id = nullableUuid(value.backend_record_id, `${label}.backend_record_id`);
    if (value.stock_number === null && value.vin === null && value.backend_record_id === null) {
      throw new TypeError(`${label} requires a vehicle identity`);
    }
  }

  function validatePayload(actionType, payload, label) {
    if (!isObject(payload)) throw new TypeError(`${label} must be an object`);
    if (actionType === 'activate_vehicle') {
      exactKeys(payload, ['backend_record_id', 'stock_number', 'vin', 'job_card_number'], label);
      uuid(payload.backend_record_id, `${label}.backend_record_id`);
      const stock = text(payload.stock_number, `${label}.stock_number`, 4, 80).toUpperCase();
      if (!STOCK_RE.test(stock)) throw new TypeError(`${label}.stock_number is invalid`);
      payload.stock_number = stock;
      if (payload.vin !== null) {
        payload.vin = text(payload.vin, `${label}.vin`, 17, 17).toUpperCase();
        if (!VIN_RE.test(payload.vin)) throw new TypeError(`${label}.vin is invalid`);
      }
      if (payload.job_card_number !== null) text(payload.job_card_number, `${label}.job_card_number`, 1, 80);
    } else if (actionType === 'operation_add' || actionType === 'operation_update') {
      exactKeys(payload, ['operation_no', 'source_row_no', 'work_key', 'description', 'estimated_hours', 'taxonomy_version', 'taxonomy_disposition', 'source_uid'], label);
      text(payload.operation_no, `${label}.operation_no`, 3, 20);
      if (!/^OP[1-9][0-9]{0,2}$/i.test(payload.operation_no)) throw new TypeError(`${label}.operation_no is invalid`);
      positiveInteger(payload.source_row_no, `${label}.source_row_no`);
      payload.work_key = text(payload.work_key, `${label}.work_key`, 2, 32).toUpperCase();
      if (!WORK_KEYS.has(payload.work_key)) throw new TypeError(`${label}.work_key is not controlled`);
      text(payload.description, `${label}.description`, 1, 500);
      if (typeof payload.estimated_hours !== 'number' || !Number.isFinite(payload.estimated_hours) || payload.estimated_hours < 0 || payload.estimated_hours > 999.99) throw new TypeError(`${label}.estimated_hours is invalid`);
      if (Math.round(payload.estimated_hours * 100) !== payload.estimated_hours * 100) throw new TypeError(`${label}.estimated_hours has more than two decimal places`);
      if (!TAXONOMY_RE.test(text(payload.taxonomy_version, `${label}.taxonomy_version`, 1, 160))) throw new TypeError(`${label}.taxonomy_version is invalid`);
      if (!TAXONOMY_DISPOSITIONS.has(payload.taxonomy_disposition)) throw new TypeError(`${label}.taxonomy_disposition is invalid`);
      text(payload.source_uid, `${label}.source_uid`, 1, 200);
    } else if (actionType === 'parts_eta_set') {
      exactKeys(payload, ['eta'], label);
      if (payload.eta !== null) {
        const eta = text(payload.eta, `${label}.eta`, 10, 10);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(eta) || Number.isNaN(Date.parse(`${eta}T00:00:00Z`))) throw new TypeError(`${label}.eta is invalid`);
        payload.eta = eta;
      }
    } else if (actionType === 'parts_complete' || actionType === 'rft_transfer' || actionType === 'rft_collect') {
      exactKeys(payload, ['confirmed'], label);
      if (payload.confirmed !== true) throw new TypeError(`${label}.confirmed must be true`);
    } else if (actionType === 'booking_set') {
      exactKeys(payload, ['stage_code', 'bay_number', 'scheduled_start_at', 'duration_minutes', 'technician_id'], label);
      text(payload.stage_code, `${label}.stage_code`, 2, 40);
      positiveInteger(payload.bay_number, `${label}.bay_number`);
      dateTime(payload.scheduled_start_at, `${label}.scheduled_start_at`);
      positiveInteger(payload.duration_minutes, `${label}.duration_minutes`);
      if (payload.duration_minutes < 60) throw new TypeError(`${label}.duration_minutes is too short`);
      nullableUuid(payload.technician_id, `${label}.technician_id`);
    } else if (actionType === 'booking_move') {
      exactKeys(payload, ['booking_id', 'expected_booking_version', 'stage_code', 'bay_number', 'scheduled_start_at', 'duration_minutes', 'override_reason'], label);
      uuid(payload.booking_id, `${label}.booking_id`);
      positiveInteger(payload.expected_booking_version, `${label}.expected_booking_version`);
      text(payload.stage_code, `${label}.stage_code`, 2, 40);
      positiveInteger(payload.bay_number, `${label}.bay_number`);
      dateTime(payload.scheduled_start_at, `${label}.scheduled_start_at`);
      positiveInteger(payload.duration_minutes, `${label}.duration_minutes`);
      if (payload.duration_minutes < 60) throw new TypeError(`${label}.duration_minutes is too short`);
      if (payload.override_reason !== null) text(payload.override_reason, `${label}.override_reason`, 3, 400);
    } else if (actionType === 'booking_cancel') {
      exactKeys(payload, ['booking_id', 'expected_booking_version', 'reason'], label);
      uuid(payload.booking_id, `${label}.booking_id`);
      positiveInteger(payload.expected_booking_version, `${label}.expected_booking_version`);
      text(payload.reason, `${label}.reason`, 3, 400);
    } else if (actionType === 'required_work_set') {
      exactKeys(payload, ['work_key', 'required'], label);
      payload.work_key = text(payload.work_key, `${label}.work_key`, 2, 32).toUpperCase();
      if (!WORK_KEYS.has(payload.work_key)) throw new TypeError(`${label}.work_key is not controlled`);
      if (typeof payload.required !== 'boolean') throw new TypeError(`${label}.required must be boolean`);
    } else if (actionType === 'work_complete') {
      exactKeys(payload, ['booking_id', 'expected_booking_version', 'work_key', 'completed_at'], label);
      uuid(payload.booking_id, `${label}.booking_id`);
      positiveInteger(payload.expected_booking_version, `${label}.expected_booking_version`);
      payload.work_key = text(payload.work_key, `${label}.work_key`, 2, 32).toUpperCase();
      if (!WORK_KEYS.has(payload.work_key)) throw new TypeError(`${label}.work_key is not controlled`);
      dateTime(payload.completed_at, `${label}.completed_at`);
    } else if (actionType === 'note_append') {
      exactKeys(payload, ['text', 'event_at'], label);
      text(payload.text, `${label}.text`, 1, 2000);
      dateTime(payload.event_at, `${label}.event_at`);
    } else if (actionType === 'location_set') {
      exactKeys(payload, ['location', 'reason'], label);
      payload.location = text(payload.location, `${label}.location`, 2, 20).toUpperCase();
      if (!LOCATIONS.has(payload.location)) throw new TypeError(`${label}.location is not controlled`);
      text(payload.reason, `${label}.reason`, 3, 400);
    } else {
      throw new TypeError(`unsupported action_type ${actionType}`);
    }
    return payload;
  }

  function validatePdcEmailAiV2Plan(value) {
    if (!isObject(value)) throw new TypeError('plan must be an object');
    let plan;
    try {
      plan = JSON.parse(JSON.stringify(value));
    } catch (_error) {
      throw new TypeError('plan must be JSON-serializable');
    }
    noForbiddenKeys(plan);
    exactKeys(plan, ['schema_version', 'source', 'versions', 'instructions'], 'plan');
    if (plan.schema_version !== PLAN_SCHEMA_VERSION) throw new TypeError('schema_version is invalid');

    exactKeys(plan.source, ['receipt_id', 'source_digest', 'evidence_digest', 'thread_id', 'message_id', 'attachment_digests'], 'source');
    plan.source.receipt_id = uuid(plan.source.receipt_id, 'source.receipt_id');
    plan.source.source_digest = digest(plan.source.source_digest, 'source.source_digest');
    plan.source.evidence_digest = digest(plan.source.evidence_digest, 'source.evidence_digest');
    text(plan.source.thread_id, 'source.thread_id', 1, 512);
    text(plan.source.message_id, 'source.message_id', 1, 1024);
    if (!Array.isArray(plan.source.attachment_digests) || plan.source.attachment_digests.length > 25) throw new TypeError('source.attachment_digests is invalid');
    plan.source.attachment_digests = plan.source.attachment_digests.map((item, index) => digest(item, `source.attachment_digests[${index}]`));
    if (new Set(plan.source.attachment_digests).size !== plan.source.attachment_digests.length) throw new TypeError('source.attachment_digests contains duplicates');

    exactKeys(plan.versions, ['model', 'prompt', 'taxonomy', 'rules', 'action_contract', 'supabase_actions'], 'versions');
    Object.keys(plan.versions).forEach(key => text(plan.versions[key], `versions.${key}`, 1, 160));
    if (plan.versions.action_contract !== ACTION_CONTRACT_VERSION) throw new TypeError('versions.action_contract is invalid');
    if (!Array.isArray(plan.instructions) || plan.instructions.length > 200) throw new TypeError('instructions must contain 0 to 200 rows');
    const instructionIds = new Set();
    plan.instructions.forEach((instruction, index) => {
      const label = `instructions[${index}]`;
      exactKeys(instruction, ['instruction_id', 'vehicle_id', 'identity', 'expected_vehicle_version', 'action_type', 'payload', 'evidence_refs'], label);
      text(instruction.instruction_id, `${label}.instruction_id`, 1, 160);
      if (instructionIds.has(instruction.instruction_id)) throw new TypeError('instruction_id must be unique');
      instructionIds.add(instruction.instruction_id);
      instruction.vehicle_id = uuid(instruction.vehicle_id, `${label}.vehicle_id`);
      validateIdentity(instruction.identity, `${label}.identity`);
      instruction.expected_vehicle_version = positiveInteger(instruction.expected_vehicle_version, `${label}.expected_vehicle_version`);
      instruction.action_type = text(instruction.action_type, `${label}.action_type`, 1, 80);
      if (!ACTION_TYPE_SET.has(instruction.action_type)) throw new TypeError(`${label}.action_type is not allowed`);
      validatePayload(instruction.action_type, instruction.payload, `${label}.payload`);
      if (!Array.isArray(instruction.evidence_refs) || instruction.evidence_refs.length < 1 || instruction.evidence_refs.length > 20) throw new TypeError(`${label}.evidence_refs is invalid`);
      instruction.evidence_refs = instruction.evidence_refs.map((ref, refIndex) => text(ref, `${label}.evidence_refs[${refIndex}]`, 1, 300));
      if (new Set(instruction.evidence_refs).size !== instruction.evidence_refs.length) throw new TypeError(`${label}.evidence_refs contains duplicates`);
    });
    return plan;
  }

  function isStagingConfig(config) {
    return !!config
      && String(config.projectRef || '') === STAGING_PROJECT_REF
      && String(config.url || '').replace(/\/$/, '') === STAGING_SUPABASE_URL;
  }

  function createPdcEmailAiV2Actions(options = {}) {
    const config = options.config || null;
    const client = options.client || null;
    const rpc = options.rpc || ((name, params) => {
      if (!client || typeof client.rpc !== 'function') throw new Error('Supabase client unavailable');
      return client.rpc(name, params);
    });
    const getAccessToken = options.getAccessToken || (() => null);

    function guard() {
      if (!isStagingConfig(config)) return { ok: false, code: 'production_target_rejected' };
      if (typeof getAccessToken() !== 'string' || !getAccessToken().trim()) return { ok: false, code: 'authenticated_session_required' };
      return null;
    }

    async function callFixedRpc(name, params) {
      try {
        const response = await rpc(name, params);
        const error = response && response.error;
        if (error) return { ok: false, code: error.code || 'rpc_failed', status: error.status || null, error: error.message || String(error) };
        const body = response && Object.prototype.hasOwnProperty.call(response, 'data') ? response.data : response && response.body !== undefined ? response.body : response;
        if (!isObject(body)) return { ok: false, code: 'invalid_rpc_response' };
        return { ok: true, body };
      } catch (error) {
        return { ok: false, code: 'rpc_unavailable', error: error?.message || String(error) };
      }
    }

    async function readSnapshot() {
      const blocked = guard();
      if (blocked) return blocked;
      const response = await callFixedRpc(SNAPSHOT_RPC, {});
      if (!response.ok) return response;
      if (response.body.ok !== true || response.body.code !== 'ok' || !isObject(response.body.data)) return { ok: false, code: 'authoritative_snapshot_invalid', body: response.body };
      return { ok: true, code: 'ok', data: response.body.data, revision: response.body.revision ?? null };
    }

    async function getContract() {
      const blocked = guard();
      if (blocked) return blocked;
      const response = await callFixedRpc(CONTRACT_RPC, {});
      if (!response.ok) return response;
      if (response.body.ok !== true || !Array.isArray(response.body.actions)) return { ok: false, code: 'typed_contract_invalid' };
      return { ok: true, code: response.body.code || 'typed_action_contract', data: response.body };
    }

    async function applyPlan(plan) {
      const blocked = guard();
      if (blocked) return blocked;
      let validated;
      try {
        validated = validatePdcEmailAiV2Plan(plan);
      } catch (error) {
        return { ok: false, code: 'typed_plan_invalid', error: error.message };
      }
      const actionResponse = await callFixedRpc(ACTION_RPC, { p_plan: validated });
      const snapshot = await readSnapshot();
      if (!actionResponse.ok) {
        return { ...actionResponse, authoritative_readback: snapshot.ok ? snapshot.data : null, readback_ok: snapshot.ok };
      }
      if (!snapshot.ok) {
        return { ok: false, code: 'authoritative_readback_unavailable', action_result: actionResponse.body, readback_error: snapshot.code };
      }
      return {
        ...actionResponse.body,
        ok: actionResponse.body.ok === true,
        code: actionResponse.body.code || 'typed_action_result',
        action_result: actionResponse.body,
        authoritative_readback: snapshot.data,
        readback_revision: snapshot.revision,
        readback_ok: true,
      };
    }

    return Object.freeze({ applyPlan, getContract, readSnapshot });
  }

  return Object.freeze({
    ACTION_CONTRACT_VERSION,
    ACTION_RPC,
    ACTION_TYPES,
    CONTRACT_RPC,
    PLAN_SCHEMA_VERSION,
    SNAPSHOT_RPC,
    STAGING_PROJECT_REF,
    STAGING_SUPABASE_URL,
    createPdcEmailAiV2Actions,
    isStagingConfig,
    validatePdcEmailAiV2Plan,
  });
}));
