/**
 * Local dry-run server for the Admin Upload page. It uses the same parser as the edge function.
 * It does not connect to staging or production and it does not write a ledger.
 */
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { dryRun, parseRevolutionUpload } from '../../supabase/functions/revolution-upload/parse.js';

const root = normalize(join(import.meta.dirname, '../..'));
const port = Number(process.env.PORT || 8765);
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png' };

const server = createServer(async (req, res) => {
  const url = new URL(req.url || '/', `http://127.0.0.1:${port}`);
  if (req.method === 'OPTIONS') {
    res.writeHead(204, cors());
    res.end();
    return;
  }
  if (url.pathname === '/revolution-upload') {
    await upload(req, res, url);
    return;
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.writeHead(405, cors());
    res.end('Method not allowed');
    return;
  }
  const relative = decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname);
  const path = normalize(join(root, relative));
  if (!path.startsWith(root)) {
    res.writeHead(403);
    res.end('No');
    return;
  }
  try {
    const body = await readFile(path);
    res.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream' });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
});

async function upload(req, res, url) {
  try {
    const { bytes, filename } = await readBody(req);
    const parsed = await parseRevolutionUpload(bytes, filename);
    const result = dryRun(parsed, { now: new Date() });
    const action = url.searchParams.get('action') || 'dry-run';
    const body = {
      ...result,
      apply_enabled: false,
      go_live: false,
      logged: false,
      ledger: 'local_preview',
      uploader: 'Preview staff',
      preview_only: true,
      message: 'Local dry run. Staging was not written. Craig has not approved go-live.',
    };
    send(res, action === 'apply' ? 409 : 200, body);
  } catch (error) {
    send(res, 422, { ok: false, apply_enabled: false, error: error instanceof Error ? error.message : 'The report was refused.' });
  }
}

function send(res, status, body) {
  res.writeHead(status, { ...cors(), 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function cors() {
  return { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, x-filename, x-uploader' };
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks);
  const type = req.headers['content-type'] || '';
  if (!type.includes('multipart/form-data')) {
    return { bytes: new Uint8Array(raw), filename: String(req.headers['x-filename'] || 'upload.xls') };
  }
  const boundary = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(type)?.[1] || /boundary=(?:"([^"]+)"|([^;]+))/i.exec(type)?.[2];
  if (!boundary) throw new Error('The upload had no file.');
  const marker = Buffer.from(`--${boundary}`);
  const start = raw.indexOf(marker);
  const next = raw.indexOf(marker, start + marker.length);
  const part = raw.subarray(start + marker.length + 2, next - 2);
  const split = part.indexOf(Buffer.from('\r\n\r\n'));
  const header = part.subarray(0, split).toString('utf8');
  const filename = /filename="([^"]*)"/.exec(header)?.[1] || 'upload.xls';
  return { bytes: new Uint8Array(part.subarray(split + 4)), filename };
}

server.listen(port, '127.0.0.1');
