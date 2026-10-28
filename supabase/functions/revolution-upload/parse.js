/**
 * Revolution report parser for the Admin Upload preview (r591).
 * The .xls name is not BIFF. Revolution sends an Office Open XML workbook,
 * an HTML table, or a SpreadsheetML workbook. No model is called.
 * The rows and apply functions are not in this file. They stay pinned.
 */
export const PINS = {
  rows: '9be0883b1a555f48f3c1ba9fa111c891',
  apply: 'b62fb7c29ffd2a1629f214f696e5cb14',
  department135: 'fd05b9eef69498002ac06dd68e01cdff',
  karrathaAccessories: 'c70dc4234952dfb58cbc022c98bcecdb',
  broomeAccessories: '46d4b464c5c1800c8ada245fb2d33bd3',
  pinCount: 241,
};

const SERVICE_WHOLE = 'PMG PD Service as a Whole w/Sublet';
const SERVICE_COMPLETE = 'PMG PD Service Complete w/Sublet';
const PARTS_TITLES = ['CW PMG PD Parts Status Complete', 'PMG PD Parts Status'];
const BT_TITLE = 'BT Allocation — Deal Items';
const KTA_TITLE = 'KTA Allocation - Deal Items';
const BASE_HEADERS = ['Dept', 'Stock #', 'Rego #', 'Owner Name', 'Parts Location', 'Key Tag Number', 'R/O #', 'Sub Status', 'Line #', 'Operation Desc', 'Estimated labour hours', 'Modified Date', 'Range #'];
const SUBLET_HEADERS = ['PO #', 'Job #', 'Document Line', 'Sublet Line', 'Description of sublet', 'Company', 'Division'];
const DEAL_HEADERS = ['Quote #', 'Stock #', 'PO Line', 'Price Level Desc', 'Notes', 'PO #', 'Transaction Sub-Type', 'Transaction Type'];
const PARTS_REQUIRED = ['Dept', 'R/O #', 'Line #', 'Parts Attached', 'Parts on Backorder', 'Backorder with PO (1=Yes, 0=No)'];
const DATE_FMT = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]);
const SALES_DEALERS = new Set(['37047', '037047', '14450', '014450']);

export class ContractError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ContractError';
  }
}

function norm(value) {
  if (value == null) return '';
  if (typeof value === 'number' && Number.isFinite(value) && Math.abs(value - Math.round(value)) < 1e-9) value = Math.round(value);
  return String(value).trim();
}

function unwrapHeader(value) {
  const text = norm(value);
  const match = /^=\s*"((?:[^"]|"")*)"$/.exec(text);
  return match ? match[1].replace(/""/g, '"').trim() : text;
}

function headerNames(headers) {
  const names = (headers || []).map(unwrapHeader);
  while (names.length && names[names.length - 1] === '') names.pop();
  return names;
}

function decodeXml(text) {
  return String(text)
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, num) => String.fromCodePoint(Number(num)))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

function columnIndex(ref) {
  let n = 0;
  for (const ch of ref) {
    if (ch >= 'A' && ch <= 'Z') n = n * 26 + (ch.charCodeAt(0) - 64);
    else if (ch >= 'a' && ch <= 'z') n = n * 26 + (ch.charCodeAt(0) - 96);
    else break;
  }
  return n;
}

function rowIndex(ref) {
  const digits = String(ref).replace(/^[A-Za-z]+/, '');
  return Number(digits);
}

function u16(bytes, offset) { return bytes[offset] | (bytes[offset + 1] << 8); }
function u32(bytes, offset) {
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
}
function findEocd(bytes) {
  const start = Math.max(0, bytes.length - 22 - 65535);
  for (let i = bytes.length - 22; i >= start; i -= 1) {
    if (bytes[i] === 0x50 && bytes[i + 1] === 0x4b && bytes[i + 2] === 0x05 && bytes[i + 3] === 0x06) return i;
  }
  return -1;
}
async function inflateRaw(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
async function unzip(buffer) {
  const eocd = findEocd(buffer);
  if (eocd < 0) throw new ContractError('This .xls is not a readable Office Open XML workbook.');
  const count = u16(buffer, eocd + 10);
  let p = u32(buffer, eocd + 16);
  const files = new Map();
  for (let i = 0; i < count; i += 1) {
    if (u32(buffer, p) !== 0x02014b50) throw new ContractError('The workbook directory is incomplete.');
    const method = u16(buffer, p + 10);
    const compSize = u32(buffer, p + 20);
    const nameLen = u16(buffer, p + 28);
    const extraLen = u16(buffer, p + 30);
    const commentLen = u16(buffer, p + 32);
    const localOff = u32(buffer, p + 42);
    const name = new TextDecoder().decode(buffer.subarray(p + 46, p + 46 + nameLen));
    const localNameLen = u16(buffer, localOff + 26);
    const localExtraLen = u16(buffer, localOff + 28);
    const start = localOff + 30 + localNameLen + localExtraLen;
    const compressed = buffer.subarray(start, start + compSize);
    const data = method === 0 ? compressed : method === 8 ? await inflateRaw(compressed) : null;
    if (!data) throw new ContractError(`The workbook uses a compression this parser does not read (${method}).`);
    files.set(name, data);
    p += 46 + nameLen + extraLen + commentLen;
  }
  return files;
}
function md5Hex(bytes) {
  const s = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
  const k = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32));
  const bitLen = bytes.length * 8;
  const padded = new Uint8Array(((bytes.length + 8) >> 6 << 6) + 64);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(padded.length - 8, bitLen >>> 0, true);
  view.setUint32(padded.length - 4, Math.floor(bitLen / 2 ** 32), true);
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  for (let offset = 0; offset < padded.length; offset += 64) {
    const m = Array.from({ length: 16 }, (_, i) => view.getUint32(offset + i * 4, true));
    let a = a0, b = b0, c = c0, d = d0;
    for (let i = 0; i < 64; i += 1) {
      let f; let g;
      if (i < 16) { f = (b & c) | (~b & d); g = i; }
      else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
      else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
      else { f = c ^ (b | ~d); g = (7 * i) % 16; }
      f = (f + a + k[i] + m[g]) >>> 0;
      const rot = s[(i >> 4) * 4 + (i % 4)];
      const rotated = ((f << rot) | (f >>> (32 - rot))) >>> 0;
      a = d; d = c; c = b;
      b = (b + rotated) >>> 0;
    }
    a0 = (a0 + a) >>> 0; b0 = (b0 + b) >>> 0; c0 = (c0 + c) >>> 0; d0 = (d0 + d) >>> 0;
  }
  const out = new DataView(new ArrayBuffer(16));
  out.setUint32(0, a0, true); out.setUint32(4, b0, true); out.setUint32(8, c0, true); out.setUint32(12, d0, true);
  return [...new Uint8Array(out.buffer)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}
async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function sharedStrings(xml) {
  const out = [];
  const parts = xml.split(/<si[\s>]/).slice(1);
  for (const part of parts) {
    const inner = part.slice(0, part.indexOf('</si>')).replace(/<rPh\b[\s\S]*?<\/rPh>/g, '');
    const texts = [];
    inner.replace(/<t\b[^>]*>([\s\S]*?)<\/t>/g, (_, text) => { texts.push(decodeXml(text)); return ''; });
    out.push(texts.join(''));
  }
  return out;
}

function dateFormats(xml) {
  const custom = new Map();
  if (!xml) return { custom, xfs: [] };
  xml.replace(/<numFmt\b[^>]*numFmtId="(\d+)"[^>]*formatCode="([^"]*)"/g, (_, id, code) => {
    custom.set(Number(id), decodeXml(code));
    return '';
  });
  const xfs = [];
  const xfBlock = xml.split('<cellXfs')[1] || '';
  xfBlock.replace(/<xf\b([^>]*)\/?>/g, (_, attrs) => {
    const id = /numFmtId="(\d+)"/.exec(attrs);
    xfs.push(id ? Number(id[1]) : 0);
    return '';
  });
  return { custom, xfs };
}

function isDateFormat(fmtId, custom) {
  if (DATE_FMT.has(fmtId)) return true;
  const code = custom.get(fmtId);
  if (!code) return false;
  const lower = code.toLowerCase();
  if (lower.includes('%') || lower.includes('general')) return false;
  return /[dy]/.test(lower) && (lower.includes('m') || lower.includes('d'));
}

function excelDate(serial) {
  const whole = Math.floor(serial);
  const fraction = serial - whole;
  const utc = Date.UTC(1899, 11, 30) + whole * 86400000 + Math.round(fraction * 86400000);
  const date = new Date(utc);
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}`;
}

function numberValue(text) {
  if (text == null || text === '') return null;
  const value = Number(text);
  if (!Number.isFinite(value)) return text;
  if (Math.abs(value - Math.round(value)) < 1e-9) return Math.round(value);
  return value;
}

const textOf = (bytes) => new TextDecoder().decode(bytes || new Uint8Array());

async function readOoxml(buffer) {
  const files = await unzip(buffer);
  const workbook = textOf(files.get('xl/workbook.xml'));
  const rels = textOf(files.get('xl/_rels/workbook.xml.rels'));
  const sheets = [];
  workbook.replace(/<sheet\b([^>]*)\/?>/g, (_, attrs) => {
    const name = /name="([^"]*)"/.exec(attrs);
    const rid = /r:id="([^"]*)"/.exec(attrs);
    sheets.push({ name: name ? decodeXml(name[1]) : '', rid: rid ? rid[1] : '' });
    return '';
  });
  const targets = new Map();
  rels.replace(/<Relationship\b([^>]*)\/?>/g, (_, attrs) => {
    const id = /Id="([^"]*)"/.exec(attrs);
    const target = /Target="([^"]*)"/.exec(attrs);
    if (id && target) targets.set(id[1], target[1].replace(/^\//, ''));
    return '';
  });
  const chosen = sheets.find((sheet) => sheet.name === 'Results') || sheets[0];
  if (!chosen) throw new ContractError('The workbook has no worksheet.');
  let target = targets.get(chosen.rid) || 'xl/worksheets/sheet1.xml';
  if (!target.startsWith('xl/')) target = `xl/${target}`;
  const sheetXml = files.get(target);
  if (!sheetXml) throw new ContractError('The Results worksheet is missing.');
  const strings = files.has('xl/sharedStrings.xml') ? sharedStrings(textOf(files.get('xl/sharedStrings.xml'))) : [];
  const styles = dateFormats(textOf(files.get('xl/styles.xml')));
  const rows = new Map();
  const xml = textOf(sheetXml);
  const cellRe = /<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
  let match;
  while ((match = cellRe.exec(xml))) {
    const attrs = match[1];
    const body = match[2] || '';
    const ref = /r="([A-Za-z]+)(\d+)"/.exec(attrs);
    if (!ref) continue;
    const col = columnIndex(ref[1]);
    const row = Number(ref[2]);
    const type = /t="([^"]*)"/.exec(attrs);
    const style = /s="(\d+)"/.exec(attrs);
    const kind = type ? type[1] : '';
    let value = null;
    if (kind === 'inlineStr') {
      const texts = [];
      body.replace(/<t\b[^>]*>([\s\S]*?)<\/t>/g, (_, text) => { texts.push(decodeXml(text)); return ''; });
      value = texts.join('');
    } else {
      const raw = /<v>([\s\S]*?)<\/v>/.exec(body);
      if (raw) {
        const text = decodeXml(raw[1]);
        if (kind === 's') value = strings[Number(text)] ?? '';
        else if (kind === 'b') value = text === '1';
        else if (kind === 'str') value = text;
        else {
          const fmt = styles.xfs?.[style ? Number(style[1]) : 0] ?? 0;
          const number = numberValue(text);
          value = typeof number === 'number' && isDateFormat(fmt, styles.custom) ? excelDate(Number(text)) : number;
        }
      }
    }
    if (!rows.has(row)) rows.set(row, new Map());
    rows.get(row).set(col, value);
  }
  return gridFromMap(chosen.name, rows);
}

function gridFromMap(sheetName, rows) {
  const maxRow = rows.size ? Math.max(...rows.keys()) : 0;
  const grid = [];
  for (let r = 1; r <= maxRow; r += 1) {
    const cells = rows.get(r) || new Map();
    const maxCol = cells.size ? Math.max(...cells.keys()) : 0;
    const line = [];
    for (let c = 1; c <= maxCol; c += 1) line.push(cells.has(c) ? cells.get(c) : null);
    grid.push(line);
  }
  return { sheetName, rows: grid };
}

function readHtml(text) {
  const rows = [];
  const trRe = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
  let tr;
  while ((tr = trRe.exec(text))) {
    const cells = [];
    const tdRe = /<t[dh]\b([^>]*)>([\s\S]*?)<\/t[dh]>/gi;
    let td;
    while ((td = tdRe.exec(tr[1]))) {
      const span = Number(/colspan=["']?(\d+)/i.exec(td[1])?.[1] || 1);
      const plain = decodeXml(td[2].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim());
      cells.push(plain === '' ? null : coerceLoose(plain));
      for (let i = 1; i < span; i += 1) cells.push(null);
    }
    rows.push(cells);
  }
  if (!rows.length) throw new ContractError('The HTML table has no rows.');
  return { sheetName: 'Results', rows };
}

function readSpreadsheetMl(text) {
  const rows = [];
  const rowRe = /<Row\b[^>]*>([\s\S]*?)<\/Row>/gi;
  let row;
  while ((row = rowRe.exec(text))) {
    const cells = [];
    const cellRe = /<Cell\b([^>]*)>([\s\S]*?)<\/Cell>|<Cell\b([^>]*)\/>/gi;
    let cell;
    while ((cell = cellRe.exec(row[1]))) {
      const attrs = cell[1] || cell[3] || '';
      const index = /ss:Index="(\d+)"/.exec(attrs);
      if (index) while (cells.length < Number(index[1]) - 1) cells.push(null);
      const data = /<Data\b[^>]*>([\s\S]*?)<\/Data>/.exec(cell[2] || '');
      const type = /ss:Type="([^"]*)"/.exec(cell[2] || attrs);
      const textValue = data ? decodeXml(data[1]) : '';
      let value = textValue === '' ? null : textValue;
      if (value != null && type && /Number|DateTime/.test(type[1])) value = type[1] === 'DateTime' ? value.replace('T', ' ').replace(/\.\d+Z?$/, '') : numberValue(value);
      cells.push(value);
    }
    rows.push(cells);
  }
  if (!rows.length) throw new ContractError('The SpreadsheetML workbook has no rows.');
  return { sheetName: 'Results', rows };
}

function coerceLoose(text) {
  if (/^-?\d+$/.test(text)) return Number(text);
  if (/^-?\d+\.\d+$/.test(text)) return numberValue(text);
  return text;
}

export async function readSheet(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  if (bytes.length >= 4 && bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0) {
    throw new ContractError('This file is an old Excel BIFF workbook. Revolution sends an HTML table or an Office Open XML workbook saved with an .xls name.');
  }
  if (bytes.length >= 2 && bytes[0] === 0x50 && bytes[1] === 0x4b) return readOoxml(bytes);
  const text = new TextDecoder().decode(bytes).replace(/^\uFEFF/, '');
  if (/<Workbook[\s>]/.test(text) && /<Worksheet[\s>]/.test(text)) return readSpreadsheetMl(text);
  if (/<table[\s>]/i.test(text) || /<html[\s>]/i.test(text)) return readHtml(text);
  throw new ContractError('This file is not a Revolution HTML table or an Office Open XML workbook.');
}

function cell(row, index) {
  if (!row || index < 0 || index >= row.length) return null;
  const value = row[index];
  return value == null || value === '' ? null : value;
}

function classifyService(raw) {
  const ro = norm(raw['R/O #']).toUpperCase();
  const line = raw['Line #'];
  const dept = norm(raw.Dept);
  if (!ro && (line == null || line === '')) return 'footer';
  if (!['138', '139'].includes(dept)) {
    if (ro) return 'excluded_department';
    throw new ContractError(`row: R/O # ${ro || '(blank)'} / Dept ${dept || '(blank)'} is not a J138/J139 service line`);
  }
  if (!new RegExp(`^J${dept}[0-9]+$`).test(ro)) {
    throw new ContractError(`row: R/O # ${ro} / Dept ${dept} is not a J138/J139 service line`);
  }
  if (typeof line !== 'number' || !Number.isFinite(line) || line <= 0 || Math.round(line) !== line) {
    throw new ContractError(`row: Line # ${line} is not a positive whole number`);
  }
  const hours = raw['Estimated labour hours'];
  if (hours != null && (typeof hours !== 'number' || hours < 0)) {
    throw new ContractError(`row: Estimated labour hours ${hours} is not a non-negative number`);
  }
  return 'data';
}

function checkServiceHeaders(headers) {
  let names = headerNames(headers);
  if (names[0] === 'Type') names = names.slice(1);
  else if (names.includes('Type')) throw new ContractError('headers: Type is only accepted as the first column');
  if (names[names.length - 1] === 'Create Advisor') names = names.slice(0, -1);
  else if (names.some((name) => name.toLowerCase() === 'create advisor')) {
    throw new ContractError('headers: Create Advisor must be exactly the last column');
  }
  if (names.slice(0, BASE_HEADERS.length).join('|') !== BASE_HEADERS.join('|')) {
    throw new ContractError('headers: expected the 13 service columns first');
  }
  const extra = names.slice(BASE_HEADERS.length);
  if (new Set(extra).size !== extra.length || extra.some((name) => !SUBLET_HEADERS.includes(name)) || !extra.includes('PO #')) {
    throw new ContractError('headers: only the optional sublet columns may follow, and PO # is required');
  }
  return names;
}

function checkWholeParameters(params) {
  const text = norm(params);
  const need = [
    [/Company\s*=\s*"01"/, 'Company = "01"'],
    [/Division\s*=\s*"1"/, 'Division = "1"'],
    [/Dept\s*=\s*"138"\s+or\s+Dept\s*=\s*"139"/i, 'Dept = "138" or Dept = "139"'],
    [/Status\s*>=\s*"20"\s+and\s+Status\s*<\s*"90"/i, 'Status >= "20" and Status < "90"'],
  ];
  const missing = need.filter(([pattern]) => !pattern.test(text)).map(([, label]) => label);
  if (missing.length) throw new ContractError(`parameters: a full open-R/O snapshot needs ${missing.join(', ')}`);
}

function serviceLines(grid, title) {
  const rows = grid.rows;
  if (norm(rows[0]?.[0]) !== title) throw new ContractError(`title: expected ${title}`);
  const params = norm(rows[1]?.[0]);
  if (title === SERVICE_WHOLE) checkWholeParameters(params);
  else if (!params.includes('Company = "01"') || !params.includes('Division = "1"')) {
    throw new ContractError('parameters: Company 01 / Division 1 required');
  }
  const headerRow = rows[3] || [];
  const typed = unwrapHeader(headerRow[0]) === 'Type';
  const advised = unwrapHeader(headerRow.filter((value) => norm(value) !== '').at(-1)) === 'Create Advisor';
  const headers = checkServiceHeaders(headerRow);
  const data = [];
  const excluded = [];
  let footer = 0;
  let blankAdvisor = 0;
  for (let index = 4; index < rows.length; index += 1) {
    const excelRow = index + 1;
    let cells = rows[index] || [];
    if (cells.every((value) => value == null || norm(value) === '')) continue;
    let typeValue = null;
    if (typed) {
      typeValue = cells[0];
      cells = cells.slice(1);
    }
    const advisor = advised ? cell(cells, headers.length) : null;
    const raw = {};
    headers.forEach((header, offset) => { raw[header] = cell(cells, offset); });
    if (typed) {
      const marker = norm(typeValue);
      if (marker !== 'D' && marker !== 'T1') throw new ContractError(`row ${excelRow}: Type '${typeValue}' is not D (data) or T1 (footer); only D and T1 are accepted`);
      const kind = classifyService(raw);
      if (marker === 'T1' && kind !== 'footer') throw new ContractError(`row ${excelRow}: Type T1 (footer) but the row has an R/O # or Line #`);
      if (marker === 'D' && kind === 'footer') throw new ContractError(`row ${excelRow}: Type D (data) but the row has no R/O # and no Line #`);
    }
    const kind = classifyService(raw);
    if (advised && kind === 'data' && norm(advisor) === '') {
      blankAdvisor += 1;
      continue;
    }
    if (kind === 'footer') footer += 1;
    else if (kind === 'excluded_department') excluded.push(excelRow);
    else data.push({ row: excelRow, raw });
  }
  if (footer > 1) throw new ContractError('more than one footer row');
  const groups = new Map();
  const order = [];
  for (const item of data) {
    const key = `${norm(item.raw.Dept)}|${norm(item.raw['R/O #']).toUpperCase()}|${Math.round(item.raw['Line #'])}`;
    if (!groups.has(key)) {
      groups.set(key, []);
      order.push(key);
    }
    groups.get(key).push(item);
  }
  const lines = order.map((key) => {
    const group = groups.get(key);
    const first = group[0].raw;
    const raw = {};
    for (const header of BASE_HEADERS) raw[header] = first[header] ?? null;
    const pos = [];
    const descriptions = new Map();
    for (const item of group) {
      const po = norm(item.raw['PO #']).replace(/\s+/g, '').toUpperCase();
      if (po && !pos.includes(po)) pos.push(po);
      const description = norm(item.raw['Description of sublet']);
      if (po && description) {
        const list = descriptions.get(po) || [];
        if (!list.includes(description)) list.push(description);
        descriptions.set(po, list);
      }
    }
    const subStatus = raw['Sub Status'];
    return {
      department: norm(raw.Dept),
      stock_number: raw['Stock #'] == null || raw['Stock #'] === '' ? null : raw['Stock #'],
      rego: raw['Rego #'] == null || raw['Rego #'] === '' ? null : raw['Rego #'],
      repair_order_number: norm(raw['R/O #']).toUpperCase(),
      original_line_number: Math.round(raw['Line #']),
      operation_description: raw['Operation Desc'] == null ? '' : String(raw['Operation Desc']),
      sub_status: subStatus == null || subStatus === '' ? null : subStatus,
      hours: raw['Estimated labour hours'] == null ? null : raw['Estimated labour hours'],
      raw,
      source_row_numbers: group.map((item) => item.row),
      sublet_pos: pos,
      sublet_po_descriptions: Object.fromEntries([...descriptions].map(([po, list]) => [po, list.join('^').slice(0, 4000)])),
      collapse: { rule: 'r442_one_row_per_dept_ro_line', source_rows: group.length, hours_summed: false },
    };
  });
  return { title, parameters: params, lines, excludedDepartments: excluded.length, footer, blankAdvisor };
}

function partsRows(grid) {
  const title = norm(grid.rows[0]?.[0]);
  if (!PARTS_TITLES.includes(title)) throw new ContractError(`title: expected a parts status report, got ${title}`);
  const params = norm(grid.rows[1]?.[0]);
  if (!params.includes('Company = "01"') || !params.includes('Division = "1"')) throw new ContractError('parameters: Company 01 / Division 1 required');
  const headers = (grid.rows[3] || []).map((value) => (value == null ? '' : String(value)));
  for (const name of PARTS_REQUIRED) {
    if (headers.filter((header) => header === name).length !== 1) throw new ContractError(`headers: ${name} must appear once`);
  }
  const groups = new Map();
  let excluded = 0;
  let footer = 0;
  for (let index = 4; index < grid.rows.length; index += 1) {
    const cells = grid.rows[index] || [];
    if (cells.every((value) => value == null)) continue;
    const mapped = {};
    headers.forEach((header, offset) => { if (header) mapped[header] = cell(cells, offset); });
    if (!mapped['R/O #']) { footer += 1; continue; }
    const dept = norm(mapped.Dept);
    if (!['138', '139'].includes(dept)) { excluded += 1; continue; }
    if (!new RegExp(`^J${dept}[0-9]+$`).test(norm(mapped['R/O #']))) throw new ContractError(`row ${index + 1}: R/O # is not J${dept}`);
    const key = `${dept}|${mapped['R/O #']}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push({ row: index + 1, mapped });
  }
  const flag = (value) => (typeof value === 'number' && (value === 0 || value === 1) ? value : null);
  const rows = [...groups.entries()].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([, items]) => {
    const flags = items.map((item) => PARTS_REQUIRED.slice(3).map((header) => flag(item.mapped[header])));
    const lines = items.map((item) => item.mapped['Line #']);
    const reasons = [];
    if (flags.some((item) => item.some((value) => value == null))) reasons.push('invalid_numeric_flag');
    if (flags.some((item) => item[2] === 1 && item[1] === 0)) reasons.push('po_without_backorder');
    if (new Set(lines).size !== lines.length || lines.some((line) => typeof line !== 'number' || line < 1 || Math.round(line) !== line)) reasons.push('duplicate_or_invalid_line');
    const row = {
      Dept: Number(norm(items[0].mapped.Dept)),
      'R/O #': items[0].mapped['R/O #'],
      source_row_numbers: items.map((item) => item.row),
      source_operation_lines: lines,
      aggregation: 'Maximum valid numeric flag across exact Company01/Division1/department/jobcard; invalid group held',
    };
    PARTS_REQUIRED.slice(3).forEach((header, offset) => {
      row[header] = reasons.length ? null : Math.max(...flags.map((item) => item[offset]));
    });
    if (reasons.length) row.review_reasons = reasons;
    return row;
  });
  return { title, parameters: params, rows, excludedDepartments: excluded, footer };
}

function dealRows(grid, title, kind) {
  if (norm(grid.rows[0]?.[0]) !== title) throw new ContractError(`title: expected ${title}`);
  const headers = (grid.rows[3] || []).slice(0, 9).map((value) => (value == null ? '' : String(value)));
  const expected = ['Type', ...DEAL_HEADERS];
  if (headers.join('|') !== expected.join('|')) throw new ContractError('headers: deal item columns do not match');
  const rows = [];
  for (let index = 4; index < grid.rows.length; index += 1) {
    const cells = grid.rows[index] || [];
    if (cells.every((value) => value == null)) continue;
    if (cells[0] !== 'D') continue;
    const row = { row: index + 1 };
    DEAL_HEADERS.forEach((header, offset) => { row[header] = cell(cells, offset + 1); });
    rows.push(row);
  }
  return { title, kind, parameters: norm(grid.rows[1]?.[0]), rows, broome_sales: kind !== 'kta_deal_items' };
}

export function identifyReport(grid) {
  const title = norm(grid.rows?.[0]?.[0]);
  if (title.toUpperCase().includes('TEST')) throw new ContractError('A TEST report is refused.');
  if (title === SERVICE_WHOLE) return 'service_whole';
  if (title === SERVICE_COMPLETE) return 'service_complete';
  if (PARTS_TITLES.includes(title)) return 'cw_parts';
  if (title === BT_TITLE) return 'bt_deal_items';
  if (title === KTA_TITLE) return 'kta_deal_items';
  throw new ContractError(`This file is not a known Revolution report (title ${title || 'blank'}).`);
}

export async function parseRevolutionUpload(buffer, filename = '') {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  const grid = await readSheet(bytes);
  const kind = identifyReport(grid);
  const sha256 = await sha256Hex(bytes);
  const md5 = md5Hex(bytes);
  let parsed;
  if (kind === 'service_whole' || kind === 'service_complete') parsed = serviceLines(grid, kind === 'service_whole' ? SERVICE_WHOLE : SERVICE_COMPLETE);
  else if (kind === 'cw_parts') parsed = partsRows(grid);
  else if (kind === 'bt_deal_items') parsed = dealRows(grid, BT_TITLE, kind);
  else parsed = dealRows(grid, KTA_TITLE, kind);
  return {
    kind,
    filename: filename || '',
    sheet: grid.sheetName,
    sha256,
    md5,
    pins: PINS,
    ...parsed,
    rows: parsed.lines || parsed.rows,
  };
}

function stockKey(value) {
  return norm(value).toUpperCase();
}

function vehicleKey(row) {
  return stockKey(row.stock_number) || stockKey(row.rego);
}

function statusText(value) {
  return norm(value);
}

export function quietWindow(date = new Date()) {
  const perth = new Date(date.toLocaleString('en-US', { timeZone: 'Australia/Perth' }));
  const minutes = perth.getHours() * 60 + perth.getMinutes();
  const near = (hour, minute) => Math.abs(minutes - (hour * 60 + minute)) <= 20;
  return near(7, 0) || near(12, 30) || near(18, 0);
}

export const HOLD_REASONS = {
  closedVehicle: 'closed-vehicle conflict',
  identityChanged: 'identity changed',
  identityRestore: 'identity restore',
  staffLock: 'staff-lock',
  status99: 'status 99',
  duplicateLine: 'duplicate line',
  carriedOver: 'carried-over not-sent',
};

function rowIdentityKeys(row) {
  const keys = [];
  const stock = stockKey(row.stock_number);
  const rego = stockKey(row.rego);
  if (stock) keys.push(stock);
  if (rego && rego !== stock) keys.push(rego);
  return keys;
}

function lineKey(row) {
  return `${norm(row.repair_order_number).toUpperCase()}|${norm(row.original_line_number)}`;
}

function guardSet(values) {
  return new Set((values || []).map((value) => stockKey(value)).filter(Boolean));
}

function liveBoardStocks(vehicles) {
  const stocks = new Set();
  for (const vehicle of vehicles || []) {
    if (vehicle.deleted === true || norm(vehicle.ls) === 'deleted') continue;
    const key = stockKey(vehicle.stock);
    if (key) stocks.add(key);
  }
  return stocks;
}

export function serviceHolds(parsed, options = {}) {
  const guards = options.guards || {};
  const closedVehicle = guardSet(guards.closedVehicle);
  const identityChanged = guardSet(guards.identityChanged);
  const identityRestore = guardSet(guards.identityRestore);
  const staffLock = guardSet(guards.staffLock);
  const duplicateLines = new Set((guards.duplicateLines || []).map((line) => `${norm(line.ro).toUpperCase()}|${norm(line.line)}`));
  const carriedOver = new Set((guards.carriedOver || []).map((line) => `${norm(line.ro).toUpperCase()}|${norm(line.line)}`));
  const live = liveBoardStocks(options.vehicles);
  const holds = [];
  for (const row of parsed.rows || []) {
    if (!['138', '139'].includes(String(row.department))) continue;
    const key = lineKey(row);
    const identities = rowIdentityKeys(row);
    const matches = (set) => identities.some((identity) => set.has(identity));
    let reason = '';
    if (carriedOver.has(key)) reason = HOLD_REASONS.carriedOver;
    else if (statusText(row.sub_status) === '99' && !matches(live)) reason = HOLD_REASONS.status99;
    else if (duplicateLines.has(key)) reason = HOLD_REASONS.duplicateLine;
    else if (matches(closedVehicle)) reason = HOLD_REASONS.closedVehicle;
    else if (matches(identityChanged)) reason = HOLD_REASONS.identityChanged;
    else if (matches(identityRestore)) reason = HOLD_REASONS.identityRestore;
    else if (matches(staffLock)) reason = HOLD_REASONS.staffLock;
    if (!reason) continue;
    holds.push({
      reason,
      department: String(row.department),
      stock: row.stock_number == null || row.stock_number === '' ? null : String(row.stock_number),
      rego: row.rego == null || row.rego === '' ? null : String(row.rego),
      ro: norm(row.repair_order_number).toUpperCase(),
      line: row.original_line_number,
    });
  }
  return holds;
}

export function dryRun(parsed, options = {}) {
  const board = options.board || { vehicles: [], jobs: [] };
  const known = new Set((options.knownShas || []).map((value) => String(value).toLowerCase()));
  const duplicate = known.has(parsed.sha256);
  const errors = [];
  if (duplicate) errors.push({ code: 'duplicate_file', message: 'This file sha256 is already in the import ledger.' });
  const vehicles = board.vehicles || [];
  const jobs = board.jobs || [];
  const openJobs = new Set(jobs.filter((job) => job.closed === false || job.closed === 'false').map((job) => String(job.vehicle_id)));
  const byStock = new Map();
  for (const vehicle of vehicles) {
    const key = stockKey(vehicle.stock);
    if (key) byStock.set(key, vehicle);
  }
  let fresh = 0;
  let updated = 0;
  let archived = 0;
  let skipped = 0;
  let heldOpen = 0;
  let salesLeft = 0;
  const closedVehicles = [];
  const holds = (parsed.kind === 'service_whole' || parsed.kind === 'service_complete')
    ? serviceHolds(parsed, { vehicles, guards: options.guards || {} })
    : [];
  const heldLines = new Set(holds.map((hold) => `${hold.ro}|${hold.line}`));
  if (parsed.kind === 'service_whole' || parsed.kind === 'service_complete') {
    skipped += parsed.excludedDepartments || 0;
    const passing = [];
    for (const row of parsed.rows) {
      if (!['138', '139'].includes(String(row.department))) { skipped += 1; continue; }
      if (heldLines.has(`${norm(row.repair_order_number).toUpperCase()}|${norm(row.original_line_number)}`)) continue;
      passing.push(row);
    }
    const byVehicle = new Map();
    for (const row of parsed.rows.filter((item) => ['138', '139'].includes(String(item.department)))) {
      const key = vehicleKey(row);
      if (!key) continue;
      if (!byVehicle.has(key)) byVehicle.set(key, []);
      byVehicle.get(key).push(row);
    }
    const onSheet = new Set();
    for (const [key, rows] of byVehicle) {
      onSheet.add(key);
      const actionable = rows.filter((row) => !heldLines.has(`${norm(row.repair_order_number).toUpperCase()}|${norm(row.original_line_number)}`));
      const open = actionable.filter((row) => statusText(row.sub_status) !== '99');
      if (open.length && open.every((row) => statusText(row.sub_status) === '80')) closedVehicles.push(key);
      if (!actionable.length) continue;
      if (byStock.has(key)) updated += 1;
      else fresh += 1;
    }
    const seenKeys = new Map();
    for (const row of passing) {
      const tag = statusText(row.raw?.['Key Tag Number']);
      if (!tag || tag === '0') continue;
      const owner = vehicleKey(row);
      if (seenKeys.has(tag) && seenKeys.get(tag) !== owner) errors.push({ code: 'key_not_unique', message: 'Two stocks in this file use the same key.' });
      seenKeys.set(tag, owner);
      const other = vehicles.find((vehicle) => statusText(vehicle.key) === tag && stockKey(vehicle.stock) && stockKey(vehicle.stock) !== owner);
      if (other) errors.push({ code: 'key_not_unique', message: 'A key in this file is already on another active vehicle.' });
    }
    for (const vehicle of vehicles) {
      const key = stockKey(vehicle.stock);
      const card = norm(vehicle.jc);
      const live = vehicle.visible === true && vehicle.deleted !== true && ['active', 'rft'].includes(norm(vehicle.ls));
      if (!live || !key || onSheet.has(key) || !/^J13[89]/.test(card)) continue;
      const dealer = norm(vehicle.dealer_code);
      if (SALES_DEALERS.has(dealer)) { salesLeft += 1; continue; }
      if (openJobs.has(String(vehicle.id))) { heldOpen += 1; continue; }
      archived += 1;
    }
  } else if (parsed.kind === 'cw_parts') {
    const ros = new Set(jobs.map((job) => norm(job.ro).toUpperCase()));
    for (const row of parsed.rows) {
      if (row.review_reasons) { errors.push({ code: 'parts_row', message: row.review_reasons.join(',') }); skipped += 1; continue; }
      if (ros.has(norm(row['R/O #']).toUpperCase())) updated += 1;
      else skipped += 1;
    }
    skipped += parsed.excludedDepartments || 0;
  } else {
    const stocks = new Set(vehicles.map((vehicle) => stockKey(vehicle.stock)).filter(Boolean));
    for (const row of parsed.rows) {
      const key = stockKey(row['Stock #']);
      if (key && stocks.has(key)) updated += 1;
      else fresh += 1;
    }
    if (parsed.kind === 'kta_deal_items') salesLeft = 0;
  }
  const sanity = fresh > 15 || archived > 15;
  if (sanity) errors.push({ code: 'sanity_gate', message: 'More than 15 new vehicles or archives. An administrator must confirm before apply.' });
  const uniqueErrors = [];
  const seen = new Set();
  for (const error of errors) {
    const token = `${error.code}|${error.message}`;
    if (seen.has(token)) continue;
    seen.add(token);
    uniqueErrors.push(error);
  }
  const stopping = uniqueErrors.filter((error) => error.code !== 'sanity_gate' || !options.adminConfirm);
  return {
    ok: stopping.length === 0,
    kind: parsed.kind,
    filename: parsed.filename,
    sha256: parsed.sha256,
    md5: parsed.md5,
    sheet: parsed.sheet,
    title: parsed.title,
    row_count: parsed.rows.length,
    counts: { new: fresh, updated, archived, skipped, errors: uniqueErrors.length, holds: holds.length },
    holds,
    hold_counts: holds.reduce((counts, hold) => { counts[hold.reason] = (counts[hold.reason] || 0) + 1; return counts; }, {}),
    closed_vehicles: closedVehicles.length,
    held_open_job_card: heldOpen,
    sales_boards_left_alone: salesLeft,
    broome_sales_written: false,
    karratha_to_broome: false,
    duplicate_file: duplicate,
    needs_admin_confirm: sanity,
    quiet_hours: quietWindow(options.now),
    apply_enabled: false,
    would_call: callPlan(parsed.kind),
    errors: uniqueErrors,
    pins: PINS,
  };
}

function callPlan(kind) {
  if (kind === 'service_whole' || kind === 'service_complete') {
    return [
      'pdc_codex_intake_private.revolution_service_rows_20261006',
      'public.pdc_pilbara_service_preview_v1',
      'public.pdc_pilbara_service_apply_v1',
    ];
  }
  if (kind === 'cw_parts') return ['pdc_tune_parts_status_v5'];
  if (kind === 'kta_deal_items') return ['pdc_sales_private.import_karratha_sales_accessories_20261025'];
  return ['pdc_sales_private.import_sales_accessories_20261020'];
}

export function previewAllowsApply() {
  return false;
}
