/**
 * Staging-only Revolution report upload (r591 dry run, r602 board compare, r728 apply).
 * Parses the file in this function. Does not call a model.
 * r728 (F338): Craig 29 Oct 2026 16:58 AWST switched Kajel off and approved website Apply, Service as a Whole first.
 * Apply prepares the same rows Kajel sent (service_rows.js) and hands them to the existing job queue through the
 * r728 RPCs, signed in as the uploading administrator. The queue previews every part before it applies it.
 */
import { dryRun, parseRevolutionUpload, previewAllowsApply, readSheet } from './parse.js';
import { buildServiceRows } from './service_rows.js';

const PRODUCTION = 'vjdtsswhroyguxyfjdkt';
const STAGING = 'cdsmnqxtyyoeoznmbidd';
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info, x-filename, x-uploader',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const projectUrl = Deno.env.get('SUPABASE_URL') || '';
  if (projectUrl.includes(PRODUCTION) || !projectUrl.includes(STAGING)) {
    return json({ ok: false, error: 'This function runs on the staging board only.' }, 403);
  }
  if (req.method !== 'POST') return json({ ok: false, error: 'Upload the report with POST.' }, 405);

  const auth = req.headers.get('Authorization') || '';
  const uploader = await staffEmail(projectUrl, auth);
  if (!uploader) return json({ ok: false, error: 'Sign in as a PDC administrator before uploading a report.' }, 401);

  const action = new URL(req.url).searchParams.get('action') || 'dry-run';
  let bytes: Uint8Array;
  let filename = filenameFromHeader(req.headers.get('x-filename') || '');
  try {
    const loaded = await readUpload(req, filename);
    bytes = loaded.bytes;
    filename = loaded.filename || filename;
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : 'The upload could not be read.' }, 400);
  }

  let parsed;
  try {
    parsed = await parseRevolutionUpload(bytes, filename);
  } catch (error) {
    return json({
      ok: false,
      error: error instanceof Error ? error.message : 'The report was refused.',
      filename,
      apply_enabled: false,
      uploader,
    }, 422);
  }

  const gate = await readGate(projectUrl, parsed.sha256);
  const board = await readBoard(projectUrl, parsed.kind);
  if (!board.ok) {
    return json({
      ok: false,
      error: board.error,
      apply_enabled: false,
      preview_only: true,
      go_live: false,
      logged: false,
      filename,
      kind: parsed.kind,
      uploader,
      message: 'Craig has not approved go-live. This preview did not write the import tables.',
    }, action === 'apply' ? 409 : 503);
  }
  const result = dryRun(parsed, { knownShas: gate.knownShas, now: new Date(), board: board.board });
  result.duplicate_file = result.duplicate_file || gate.duplicate === true;
  if (result.duplicate_file && !result.errors.some((error) => error.code === 'duplicate_file')) {
    result.errors.push({ code: 'duplicate_file', message: 'This file sha256 is already in the import ledger.' });
    result.ok = false;
    result.counts.errors = result.errors.length;
    if (result.summary) result.summary = result.summary.replace(/errors \d+$/, `errors ${result.errors.length}`);
  }
  if (action === 'apply') return await applyService(projectUrl, auth, bytes, filename, parsed, result, board.board, uploader);
  const body = {
    ...result,
    apply_enabled: parsed.kind === 'service_whole',
    go_live: false,
    logged: false,
    ledger: gate.ledger,
    uploader,
    preview_only: true,
    action: action === 'apply' ? 'apply' : 'dry-run',
    message: parsed.kind === 'service_whole' ? 'Dry run only. Nothing was written. Apply sends this file to the import queue.' : 'Dry run only. Apply is on for Service as a Whole first; this report still waits.',
  };
  return json(body, 200);
});

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

async function staffEmail(projectUrl: string, auth: string) {
  if (!auth.toLowerCase().startsWith('bearer ')) return '';
  const apikey = Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  const response = await fetch(`${projectUrl}/auth/v1/user`, {
    headers: { Authorization: auth, apikey },
  });
  if (!response.ok) return '';
  const user = await response.json();
  const roles = await fetch(
    `${projectUrl}/rest/v1/pdc_user_roles?auth_user_id=eq.${user.id}&select=role,active,account_status`,
    { headers: { Authorization: auth, apikey, Accept: 'application/json' } },
  );
  if (!roles.ok) return '';
  const rows = await roles.json();
  const allowed = Array.isArray(rows) && rows.some((row) => row.role === 'administrator' && row.active && row.account_status === 'approved');
  return allowed ? String(user.email || user.id) : '';
}

function filenameFromHeader(value: string) {
  if (!value || /[^\u0000-\u00FF]/.test(value)) return '';
  try { return decodeURIComponent(value); } catch { return ''; }
}

async function readUpload(req: Request, filename: string) {
  const type = req.headers.get('content-type') || '';
  if (type.includes('multipart/form-data')) {
    const form = await req.formData();
    const file = form.get('file');
    if (!(file instanceof File)) throw new Error('Choose a Revolution report file.');
    return { bytes: new Uint8Array(await file.arrayBuffer()), filename: file.name || filename };
  }
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (!bytes.length) throw new Error('The upload was empty.');
  return { bytes, filename };
}

async function readBoard(projectUrl: string, kind: string) {
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!service) return { ok: false, error: 'The current board could not be read.' };
  const response = await fetch(`${projectUrl}/rest/v1/rpc/pdc_revolution_board_602`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${service}`,
      apikey: service,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_kind: kind }),
  });
  if (!response.ok) return { ok: false, error: 'The current board could not be read.' };
  const payload = await response.json();
  if (!payload || payload.ok !== true || !Array.isArray(payload.vehicles) || !Array.isArray(payload.jobs)) {
    return { ok: false, error: 'The current board could not be read.' };
  }
  return { ok: true, board: { vehicles: payload.vehicles, jobs: payload.jobs } };
}

async function readGate(projectUrl: string, sha256: string) {
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!service) return { ledger: 'not_configured', knownShas: [], duplicate: false };
  const response = await fetch(`${projectUrl}/rest/v1/rpc/pdc_revolution_upload_gate_591`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${service}`,
      apikey: service,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ p_new: 0, p_archived: 0, p_confirm: false, p_sha: sha256 }),
  });
  if (!response.ok) return { ledger: 'not_applied', knownShas: [], duplicate: false };
  const payload = await response.json();
  return {
    ledger: 'staging_gate',
    knownShas: payload?.duplicate_file ? [sha256] : [],
    duplicate: payload?.duplicate_file === true,
  };
}


// r728 (F338): Apply for Service as a Whole. Every write goes through the r728 RPCs with the uploader's own token.
async function rpcAs(projectUrl: string, auth: string, name: string, body: unknown) {
  const apikey = Deno.env.get('SUPABASE_ANON_KEY') || '';
  const response = await fetch(`${projectUrl}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { Authorization: auth, apikey, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) return { ok: false, error: payload?.message || `${name} failed` };
  return payload;
}

async function priorDecisions(projectUrl: string) {
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  const response = await fetch(`${projectUrl}/rest/v1/rpc/revolution_prior_decisions_728`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${service}`, apikey: service, 'Content-Type': 'application/json' },
    body: '{}',
  });
  if (!response.ok) return {};
  return await response.json();
}

async function applyService(projectUrl, auth, bytes, filename, parsed, result, board, uploader) {
  const refuse = (error, extra = {}) => json({ ok: false, action: 'apply', error, ...extra }, 409);
  if (parsed.kind !== 'service_whole') return refuse('Apply is on for Service as a Whole first. This report still waits.');
  if (result.duplicate_file) return refuse('This file has already been imported.');
  const blocking = (result.errors || []).filter((error) => error.code !== 'quiet_hours');
  if (blocking.length) return refuse('The dry run found errors. Fix the file and try again.', { errors: blocking });
  const begin = await rpcAs(projectUrl, auth, 'revolution_upload_begin_728', { p_sha: parsed.sha256, p_filename: filename || parsed.filename || 'upload.xls', p_mode: 'apply' });
  if (begin.ok !== true) return refuse(begin.message || begin.error || 'The import could not start.');
  let prepared;
  try {
    prepared = buildServiceRows({
      grid: await readSheet(bytes),
      parsed,
      board,
      upload: { uploader_email: uploader, upload_id: begin.upload_id, uploaded_at: new Date().toISOString(), filename: filename || parsed.filename, sha256: parsed.sha256 },
      priorDecisions: await priorDecisions(projectUrl),
    });
  } catch (error) {
    return refuse(error instanceof Error ? error.message : 'The rows could not be prepared.', { upload_id: begin.upload_id });
  }
  if (!prepared.rows.length) return refuse('No lines to send.', { upload_id: begin.upload_id, needs_hours: prepared.needsHours.length });
  for (let i = 0; i < prepared.rows.length; i += 400) {
    const added = await rpcAs(projectUrl, auth, 'revolution_upload_rows_728', { p_upload: begin.upload_id, p_rows: prepared.rows.slice(i, i + 400) });
    if (added.ok !== true) return refuse(added.error || 'The rows could not be sent.', { upload_id: begin.upload_id });
  }
  const finish = await rpcAs(projectUrl, auth, 'revolution_upload_finish_728', { p_upload: begin.upload_id });
  if (finish.ok !== true) return refuse(finish.error || 'The import could not be queued.', { upload_id: begin.upload_id });
  return json({
    ok: true,
    action: 'apply',
    upload_id: begin.upload_id,
    job_id: begin.job_id,
    status: finish.status,
    note: finish.note || '',
    rows_sent: finish.rows_sent,
    rows_held: finish.rows_held,
    new_board_vehicles: finish.new_board_vehicles,
    needs_hours: prepared.needsHours,
    holds: prepared.holds.length,
    summary: prepared.summary,
    uploader,
    message: finish.status === 'held'
      ? `Stopped for an administrator: ${finish.note || 'sanity gate'}.`
      : 'Sent to the import queue. Each part is previewed, then applied. This page shows progress.',
  }, 200);
}
