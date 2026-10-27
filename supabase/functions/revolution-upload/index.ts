/**
 * Staging-only dry run for a Revolution report upload (r591).
 * Parses the file in this function. Does not call a model.
 * Does not call the import or apply functions, and does not write a ledger row.
 * Craig has not approved go-live.
 */
import { dryRun, parseRevolutionUpload, previewAllowsApply } from './parse.js';

const PRODUCTION = 'vjdtsswhroyguxyfjdkt';
const STAGING = 'cdsmnqxtyyoeoznmbidd';
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-filename, x-uploader',
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
  let filename = req.headers.get('x-filename') || '';
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
  const result = dryRun(parsed, { knownShas: gate.knownShas, now: new Date() });
  result.duplicate_file = result.duplicate_file || gate.duplicate === true;
  if (result.duplicate_file && !result.errors.some((error) => error.code === 'duplicate_file')) {
    result.errors.push({ code: 'duplicate_file', message: 'This file sha256 is already in the import ledger.' });
    result.ok = false;
    result.counts.errors = result.errors.length;
  }
  const body = {
    ...result,
    apply_enabled: false,
    go_live: false,
    logged: false,
    ledger: gate.ledger,
    uploader,
    preview_only: true,
    action: action === 'apply' ? 'apply' : 'dry-run',
    message: action === 'apply' || !previewAllowsApply()
      ? 'Craig has not approved go-live. This preview did not write the import tables.'
      : 'Dry run only.',
  };
  return json(body, action === 'apply' ? 409 : 200);
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
