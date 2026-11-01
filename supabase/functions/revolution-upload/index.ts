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
  if (action === 'apply' && OTHER_781.has(parsed.kind)) return await applyOther781(projectUrl, auth, bytes, filename, parsed, result, uploader);
  if (action === 'apply') return await applyService(projectUrl, auth, bytes, filename, parsed, result, board.board, uploader);
  if (parsed.kind === 'service_whole') await previewDelta773(projectUrl, auth, bytes, filename, parsed, result, board.board, uploader);
  if (OTHER_781.has(parsed.kind)) await previewOther802(projectUrl, auth, parsed, result);
  const body = {
    ...result,
    apply_enabled: parsed.kind === 'service_whole' || OTHER_781.has(parsed.kind),
    go_live: false,
    logged: false,
    ledger: gate.ledger,
    uploader,
    preview_only: true,
    action: action === 'apply' ? 'apply' : 'dry-run',
    message: parsed.kind === 'service_whole' ? 'Dry run only. Nothing was written. Apply sends this file to the import queue.'
      : OTHER_781.has(parsed.kind) ? 'Dry run only. Nothing was written. Apply sends this file to its importer (runs within a minute).'
      : 'Dry run only. Apply is not on for this report.',
  };
  return json(body, 200);
});

// r781 (F386): Craig 31 Oct 2026 11:42 AWST "turn on the applys for the other uploads so i can do them".
// CW parts and BT / KTA deal items: the parsed rows (the rows Kajel sent, r591) are queued; a cron worker on the
// management connection runs them through the existing importer (parts: pdc_import_job_parts_csv_20260912;
// deal items: import_sales_accessories_20261020 / import_karratha_sales_accessories_20261025 manifest, preview, apply).
const OTHER_781 = new Set(['cw_parts', 'bt_deal_items', 'kta_deal_items']);

async function applyOther781(projectUrl, auth, bytes, filename, parsed, result, uploader) {
  const refuse = (error, extra = {}) => json({ ok: false, action: 'apply', error, ...extra }, 409);
  if (result.duplicate_file) return refuse('This file has already been imported.');
  // A parts row with bad flags is still sent: the importer records it as invalid, like Kajel's runs.
  const blocking = (result.errors || []).filter((error) => !['quiet_hours', 'parts_row'].includes(error.code));
  if (blocking.length) return refuse('The dry run found errors. Fix the file and try again.', { errors: blocking });
  const meta = {
    extract_text: String(parsed.parameters || ''),
    sheet: String(parsed.sheet || ''),
    title: String(parsed.title || ''),
    container: bytes.length >= 2 && bytes[0] === 0x50 && bytes[1] === 0x4b ? 'ooxml' : 'other',
  };
  const queued = await rpcAs(projectUrl, auth, 'revolution_upload_other_781', {
    p_kind: parsed.kind, p_sha: parsed.sha256, p_filename: filename || parsed.filename || 'upload.xls', p_meta: meta, p_rows: parsed.rows,
  });
  if (queued.ok !== true) return refuse(queued.message || queued.error || 'The upload could not be queued.');
  return json({
    ok: true,
    action: 'apply',
    kind: parsed.kind,
    other_upload_id: queued.upload_id,
    status: 'queued',
    rows_sent: parsed.rows.length,
    summary: result.summary || '',
    uploader,
    message: 'Sent to the importer. It runs within a minute; this page shows the result.',
  }, 200);
}

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
  // F388: no escape sequences here (the MCP deploy decodes them): any character above code 255 is refused.
  if (!value || [...value].some((ch) => ch.charCodeAt(0) > 255)) return '';
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

// r773 (F375): the dry run asks the server which stocks are line-for-line what the last OK apply had (same hash as the
// r771 skip), so the preview shows real changes only. Read-only; a failure leaves the board compare as it was.
async function previewDelta773(projectUrl, auth, bytes, filename, parsed, result, board, uploader) {
  try {
    const prepared = buildServiceRows({
      grid: await readSheet(bytes),
      parsed,
      board,
      upload: { uploader_email: uploader, upload_id: '00000000-0000-0000-0000-000000000000', uploaded_at: new Date().toISOString(), filename: filename || parsed.filename, sha256: parsed.sha256 },
      priorDecisions: await priorDecisions(projectUrl),
    });
    const hashes = {};
    for (let i = 0; i < prepared.rows.length; i += 1500) {
      const part = await rpcAs(projectUrl, auth, 'revolution_upload_delta_773', { p_rows: prepared.rows.slice(i, i + 1500) });
      if (part.ok !== true || !part.hashes) { result.delta = { ok: false, error: part.error || 'delta_unavailable' }; return; }
      for (const [stock, list] of Object.entries(part.hashes)) hashes[stock] = [...(hashes[stock] || []), ...(Array.isArray(list) ? list : [])];
    }
    const compared = await rpcAs(projectUrl, auth, 'revolution_upload_delta_compare_773', { p_hashes: hashes });
    if (compared.ok !== true) { result.delta = { ok: false, error: compared.error || 'delta_unavailable' }; return; }
    const up = (stock) => String(stock || '').toUpperCase();
    const unchanged = new Set((compared.unchanged || []).map(up));
    const changed = new Set((compared.changed || []).map(up));
    const heldBefore = new Set((compared.held_before || []).map(up));
    const seenBefore = (stock) => unchanged.has(up(stock)) || changed.has(up(stock));
    const changes = result.changes || {};
    const keepUpdated = []; const nowUnchanged = []; const retrying = []; const awaiting = []; const stillNew = []; const staysOff = [];
    for (const entry of changes.updated || []) {
      if (unchanged.has(up(entry.stock))) nowUnchanged.push(entry);
      else if (heldBefore.has(up(entry.stock))) retrying.push(entry);
      else keepUpdated.push(entry);
    }
    // r802 (F417): a stock off the board that every earlier apply held (completed, delivered, needs restore) stays off; it is not new.
    for (const entry of changes.new || []) (seenBefore(entry.stock) ? awaiting : heldBefore.has(up(entry.stock)) ? staysOff : stillNew).push(entry);
    changes.updated = keepUpdated;
    changes.unchanged = [...(changes.unchanged || []), ...nowUnchanged];
    changes.held_before = retrying;
    changes.awaiting_approval = awaiting;
    changes.new = stillNew;
    changes.stays_off = staysOff;
    result.changes = changes;
    result.counts.updated = keepUpdated.length;
    result.counts.unchanged = changes.unchanged.length;
    result.counts.new = stillNew.length;
    result.counts.held_before = retrying.length;
    result.counts.awaiting_approval = awaiting.length;
    result.counts.stays_off = staysOff.length;
    // r777 (F381): split "leaving the board" by what the server will do.
    const leaving = Array.isArray(changes.archived) ? changes.archived : [];
    if (leaving.length) {
      const nav = await rpcAs(projectUrl, auth, 'revolution_upload_navision_777', { p_stocks: leaving.map((entry) => entry.stock) });
      if (nav.ok === true && Array.isArray(nav.on_navision)) {
        const dealers = new Map(nav.on_navision.map((row) => [up(row.stock), row.dealer]));
        changes.leaving_tagged = leaving.filter((entry) => dealers.has(up(entry.stock))).map((entry) => ({ ...entry, dealer: dealers.get(up(entry.stock)) }));
        changes.archived = leaving.filter((entry) => !dealers.has(up(entry.stock)));
        result.counts.archived = changes.archived.length;
        result.counts.leaving_tagged = changes.leaving_tagged.length;
      }
    }
    result.delta = { ok: true, since: 'last OK apply', unchanged: unchanged.size, changed: changed.size, held_before: heldBefore.size, first_time: (compared.first_time || []).length, held_in_file: prepared.holds.length };
    result.summary = `${stillNew.length} new, ${keepUpdated.length} changed, ${retrying.length} held last time (retrying), ${staysOff.length} staying off the board, ${changes.unchanged.length} unchanged, ${awaiting.length} awaiting approval, ${result.counts.archived || 0} completing, ${result.counts.leaving_tagged || 0} staying tagged`;
  } catch (error) {
    result.delta = { ok: false, error: error instanceof Error ? error.message : 'delta_unavailable' };
  }
}

// r802 (F417): Craig 1 Nov 12:04 "Shouldnt it just tell me whats changing?". CW parts and deal items: compare each RO / stock with
// the rows of the last good apply of the same report, so a file that matches the last one shows nothing changing.
async function previewOther802(projectUrl, auth, parsed, result) {
  try {
    const delta = await rpcAs(projectUrl, auth, 'revolution_upload_other_delta_802', { p_kind: parsed.kind, p_rows: parsed.rows });
    if (delta.ok !== true || !Array.isArray(delta.unchanged)) { result.delta = { ok: false, error: delta.error || 'delta_unavailable' }; return; }
    if (!delta.since) { result.delta = { ok: true, since: null }; return; }
    const up = (value) => String(value || '').trim().toUpperCase();
    const unchanged = new Set(delta.unchanged.map(up));
    const skippedLast = new Set((delta.skipped_last || []).map(up));
    const changes = result.changes || {};
    const keyOf = (entry) => up(entry.stock || entry.ro);
    const moved = { updated: [], unchanged: [...(changes.unchanged || [])], new: [], skipped_last: [] };
    for (const entry of changes.updated || []) (unchanged.has(keyOf(entry)) ? moved.unchanged : moved.updated).push(entry);
    for (const entry of changes.new || []) {
      if (skippedLast.has(keyOf(entry))) moved.skipped_last.push(entry);
      else if (unchanged.has(keyOf(entry))) moved.unchanged.push(entry);
      else moved.new.push(entry);
    }
    Object.assign(changes, moved);
    result.changes = changes;
    result.counts.updated = moved.updated.length;
    result.counts.unchanged = moved.unchanged.length;
    result.counts.new = moved.new.length;
    result.counts.skipped_last = moved.skipped_last.length;
    result.delta = { ok: true, since: delta.since, unchanged: unchanged.size, changed: (delta.changed || []).length, first_time: (delta.first_time || []).length };
    const errors = (result.errors || []).length;
    result.summary = parsed.kind === 'cw_parts'
      ? `${moved.updated.length} job cards changed, ${moved.unchanged.length} unchanged, ${result.counts.skipped || 0} not on the board, errors ${errors}`
      : `${moved.new.length} new, ${moved.updated.length} changed, ${moved.unchanged.length} unchanged, ${moved.skipped_last.length} not on Navision (skipped last time), errors ${errors}`;
  } catch (error) {
    result.delta = { ok: false, error: error instanceof Error ? error.message : 'delta_unavailable' };
  }
}

async function changedRows782(projectUrl, auth, rows) {
  try {
    const hashes = {};
    for (let i = 0; i < rows.length; i += 1500) {
      const part = await rpcAs(projectUrl, auth, 'revolution_upload_delta_773', { p_rows: rows.slice(i, i + 1500) });
      if (part.ok !== true || !part.hashes) return rows;
      for (const [stock, list] of Object.entries(part.hashes)) hashes[stock] = [...(hashes[stock] || []), ...(Array.isArray(list) ? list : [])];
    }
    const compared = await rpcAs(projectUrl, auth, 'revolution_upload_delta_compare_773', { p_hashes: hashes });
    if (compared.ok !== true || !Array.isArray(compared.unchanged)) return rows;
    const unchanged = new Set(compared.unchanged.map((stock) => String(stock || '').trim().toUpperCase()));
    const stockOf = (row) => String(row?.stock_number || '').trim().toUpperCase();
    const changed = rows.filter((row) => !unchanged.has(stockOf(row)));
    if (changed.length) return changed;
    // Nothing changed: still send one stock so the last part runs the archive step for cars that left the file.
    const first = stockOf(rows[0]);
    return rows.filter((row) => stockOf(row) === first);
  } catch (_) {
    return rows;
  }
}

async function applyService(projectUrl, auth, bytes, filename, parsed, result, board, uploader) {
  const refuse = (error, extra = {}) => json({ ok: false, action: 'apply', error, ...extra }, 409);
  if (parsed.kind !== 'service_whole') return refuse('Apply is on for Service as a Whole first. This report still waits.');
  if (result.duplicate_file) return refuse('This file has already been imported.');
  const blocking = (result.errors || []).filter((error) => error.code !== 'quiet_hours');
  if (blocking.length) return refuse('The dry run found errors. Fix the file and try again.', { errors: blocking });
  const begin = await rpcAs(projectUrl, auth, 'revolution_upload_begin_728', { p_sha: parsed.sha256, p_filename: filename || parsed.filename || 'upload.xls', p_mode: 'apply' });
  if (begin.ok !== true) return refuse(begin.message || begin.error || 'The import could not start.');
  // r777b (F382): a refusal after begin must not leave a loading job that blocks the next upload for 30 minutes.
  const abandon = async (error, extra = {}) => {
    await rpcAs(projectUrl, auth, 'revolution_upload_abandon_777', { p_upload: begin.upload_id, p_reason: error }).catch(() => ({}));
    return refuse(error, { upload_id: begin.upload_id, ...extra });
  };
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
    return await abandon(error instanceof Error ? error.message : 'The rows could not be prepared.');
  }
  if (!prepared.rows.length) return await abandon('No lines to send.', { needs_hours: prepared.needsHours.length });
  // r763 (F369): record the whole-file snapshot first; without it the archive step refuses every part (snapshot_not_recorded).
  const snapshot = prepared.snapshot || {};
  const snapshotLines = Array.isArray(snapshot.lines) ? snapshot.lines : [];
  if (!snapshotLines.length) return await abandon('The snapshot could not be prepared.');
  let recorded = null;
  for (let i = 0; i < snapshotLines.length; i += 2500) {
    recorded = await rpcAs(projectUrl, auth, 'revolution_upload_snapshot_763', { p_upload: begin.upload_id, p_header: snapshot.header, p_lines: snapshotLines.slice(i, i + 2500) });
    if (recorded.ok !== true) return await abandon(recorded.error || 'The snapshot could not be recorded.', { snapshot: recorded });
  }
  if (recorded && recorded.lines_recorded !== snapshotLines.length) return await abandon('The snapshot is incomplete.', { snapshot: recorded });
  // r782 (F387): send only stocks that changed since their last OK apply (plus new and held-before ones). The snapshot
  // above already holds every line, so the last-part archive still sees the whole file. If the delta cannot be read,
  // every row is sent as before.
  const sendRows = await changedRows782(projectUrl, auth, prepared.rows);
  for (let i = 0; i < sendRows.length; i += 400) {
    const added = await rpcAs(projectUrl, auth, 'revolution_upload_rows_728', { p_upload: begin.upload_id, p_rows: sendRows.slice(i, i + 400) });
    if (added.ok !== true) return await abandon(added.error || 'The rows could not be sent.');
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
    snapshot_lines: recorded ? recorded.lines_recorded : 0,
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
