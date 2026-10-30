const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync, readdirSync, existsSync } = require('node:fs');
const { spawn } = require('node:child_process');
const path = require('node:path');

const parserPath = path.join(__dirname, 'supabase/functions/revolution-upload/parse.js');

async function parser() {
  return import('./supabase/functions/revolution-upload/parse.js');
}

const PARAMS = 'Company = "01" Division = "1" Dept = "138" or Dept = "139" Status >= "20" and Status < "90"';
const SERVICE_HEADERS = ['Type', 'Dept', 'Stock #', 'Rego #', 'Owner Name', 'Parts Location', 'Key Tag Number', 'R/O #', 'Sub Status', 'Line #', 'Operation Desc', 'Estimated labour hours', 'Modified Date', 'Range #', 'PO #', 'Description of sublet', 'Create Advisor'];

function htmlTable(title, dataRows, headers = SERVICE_HEADERS) {
  const rows = [[title], [PARAMS], [], headers, ...dataRows];
  const html = `<table>${rows.map((row) => `<tr>${row.map((cell) => `<td>${cell == null ? '' : cell}</td>`).join('')}</tr>`).join('')}</table>`;
  return new TextEncoder().encode(html);
}

function serviceRow(over = {}) {
  const row = {
    type: 'D', dept: 138, stock: 'STK1', rego: '1ABC123', owner: 'Owner', location: 'Yard',
    key: 12, ro: 'J138100', status: 20, line: 1, desc: 'Service', hours: 1,
    modified: '2026-10-27 09:00:00', range: 1, po: '', sublet: '', advisor: 'ADV',
    ...over,
  };
  return [row.type, row.dept, row.stock, row.rego, row.owner, row.location, row.key, row.ro, row.status, row.line, row.desc, row.hours, row.modified, row.range, row.po, row.sublet, row.advisor];
}

test('the parser refuses BIFF, a TEST title, and an unknown report', async () => {
  const { readSheet, parseRevolutionUpload, ContractError } = await parser();
  await assert.rejects(readSheet(Uint8Array.from([0xd0, 0xcf, 0x11, 0xe0, 0, 0])), ContractError);
  const testTitle = htmlTable('KTA Allocation - Deal Items TEST', []);
  await assert.rejects(parseRevolutionUpload(testTitle, 'kta.xls'), /TEST report is refused/);
  await assert.rejects(parseRevolutionUpload(htmlTable('Workshop diary', []), 'diary.xls'), /not a known Revolution report/);
  const source = readFileSync(parserPath, 'utf8');
  assert.equal(source.includes("from 'node:zlib'"), false);
  assert.equal(source.includes("from 'node:crypto'"), false);
});

test('service dry run keeps 138 and 139, skips status 99, and holds the gates', async () => {
  const { parseRevolutionUpload, dryRun, quietWindow, previewAllowsApply } = await parser();
  const file = htmlTable('PMG PD Service as a Whole w/Sublet', [
    serviceRow({}),
    serviceRow({ stock: 'STK2', key: 13, ro: 'J138200' }),
    serviceRow({ stock: 'STK80', key: 15, status: 80, ro: 'J138800', line: 1 }),
    serviceRow({ stock: 'STK80', key: 15, status: 80, ro: 'J138800', line: 2 }),
    serviceRow({ stock: 'STK99', key: 16, status: 99, ro: 'J138990' }),
    serviceRow({ dept: 140, ro: 'J140100' }),
    serviceRow({ dept: 139, stock: 'OTHER', key: 14, ro: 'J139100' }),
  ]);
  const parsed = await parseRevolutionUpload(file, 'service.html');
  assert.equal(parsed.kind, 'service_whole');
  assert.equal(parsed.excludedDepartments, 1);
  assert.equal(parsed.blankAdvisor, 0);
  const board = {
    vehicles: [
      { id: 'v-open', stock: 'GONE', jc: 'J138555', ls: 'active', visible: true, deleted: false, key: '4', dealer_code: '' },
      { id: 'v-sales', stock: 'SALES', jc: 'J139555', ls: 'active', visible: true, deleted: false, dealer_code: '014450' },
      { id: 'v-broome', stock: 'BROOME', jc: 'J138556', ls: 'rft', visible: true, deleted: false, dealer_code: '37047' },
      { id: 'v-known', stock: 'STK1', jc: 'J138100', ls: 'active', visible: true, deleted: false, key: '9' },
    ],
    jobs: [{ vehicle_id: 'v-open', ro: 'J138555', closed: false }, { vehicle_id: 'v-known', ro: 'J138100', closed: true }],
  };
  const result = dryRun(parsed, { board, knownShas: [] });
  assert.equal(result.counts.updated, 1);
  assert.equal(result.counts.new, 3);
  assert.equal(result.closed_vehicles, 1);
  assert.equal(result.counts.skipped, 1);
  assert.equal(result.hold_counts['status 99'], 1);
  assert.equal(result.holds.some((hold) => hold.stock === 'STK99' && hold.reason === 'status 99'), true);
  assert.equal(result.held_open_job_card, 1);
  assert.equal(result.sales_boards_left_alone, 2);
  assert.equal(result.counts.archived, 0);
  assert.equal(result.broome_sales_written, false);
  assert.equal(result.karratha_to_broome, false);
  assert.equal(previewAllowsApply(), false);
  assert.equal(result.apply_enabled, false);
  assert.equal(quietWindow(new Date('2026-10-27T23:10:00Z')), true);
  assert.equal(quietWindow(new Date('2026-10-27T23:40:00Z')), false);
  assert.equal(quietWindow(new Date('2026-10-28T04:30:00Z')), true);
  assert.equal(quietWindow(new Date('2026-10-28T10:00:00Z')), true);

  const clash = htmlTable('PMG PD Service as a Whole w/Sublet', [
    serviceRow({ stock: 'ONE', key: 77, ro: 'J138101' }),
    serviceRow({ stock: 'TWO', key: 77, ro: 'J138102' }),
  ]);
  const clashRun = dryRun(await parseRevolutionUpload(clash), { board: { vehicles: [], jobs: [] } });
  assert.equal(clashRun.errors.some((error) => error.code === 'key_not_unique'), true);
  assert.equal(clashRun.ok, false);

  const rows = [];
  for (let i = 0; i < 16; i += 1) rows.push(serviceRow({ stock: `NEW${i}`, ro: `J138${1000 + i}`, key: '' }));
  const wide = dryRun(await parseRevolutionUpload(htmlTable('PMG PD Service as a Whole w/Sublet', rows)), { board: { vehicles: [], jobs: [] } });
  // r761 (F367): no limit on new cars per upload.
  assert.equal(wide.needs_admin_confirm, false);
  assert.equal(wide.ok, true);
  assert.equal(wide.counts.new, 16);

  const duplicate = dryRun(parsed, { board, knownShas: [parsed.sha256] });
  assert.equal(duplicate.duplicate_file, true);
  assert.equal(duplicate.ok, false);
});

test('one hold list names each line once, with one reason', async () => {
  const { parseRevolutionUpload, dryRun, HOLD_REASONS } = await parser();
  const file = htmlTable('PMG PD Service as a Whole w/Sublet', [
    serviceRow({ stock: 'CLOSED', ro: 'J138301', line: 1 }),
    serviceRow({ stock: 'CLOSED', ro: 'J138301', line: 2 }),
    serviceRow({ stock: 'CHANGED', ro: 'J138302', line: 1 }),
    serviceRow({ stock: '', rego: 'RESTORE1', ro: 'J138303', line: 1 }),
    serviceRow({ stock: '', rego: 'LOCKED1', ro: 'J138304', line: 1 }),
    serviceRow({ stock: '', rego: 'LOCKED1', ro: 'J138304', line: 2 }),
    serviceRow({ stock: 'NEW99', status: 99, ro: 'J138399', line: 1 }),
    serviceRow({ stock: 'LIVE99', status: 99, ro: 'J138398', line: 1 }),
    serviceRow({ stock: 'CARRY', ro: 'J138305', line: 4 }),
    serviceRow({ stock: 'OPEN', ro: 'J138306', line: 1 }),
  ]);
  const parsed = await parseRevolutionUpload(file, 'holds.html');
  const result = dryRun(parsed, {
    board: { vehicles: [{ stock: 'LIVE99', ls: 'active', deleted: false, visible: true, jc: 'J138398' }], jobs: [] },
    guards: {
      closedVehicle: ['CLOSED'],
      identityChanged: ['CHANGED'],
      identityRestore: ['RESTORE1'],
      staffLock: ['LOCKED1'],
      duplicateLines: [{ ro: 'J138304', line: 2 }],
      carriedOver: [{ ro: 'J138305', line: 4 }],
    },
  });
  const counts = result.hold_counts;
  assert.equal(counts[HOLD_REASONS.closedVehicle], 2);
  assert.equal(counts[HOLD_REASONS.identityChanged], 1);
  assert.equal(counts[HOLD_REASONS.identityRestore], 1);
  assert.equal(counts[HOLD_REASONS.staffLock], 1);
  assert.equal(counts[HOLD_REASONS.duplicateLine], 1);
  assert.equal(counts[HOLD_REASONS.status99], 1);
  assert.equal(counts[HOLD_REASONS.carriedOver], 1);
  assert.equal(result.holds.length, 8);
  assert.equal(result.holds.some((hold) => hold.stock === 'LIVE99'), false);
  assert.equal(result.holds.some((hold) => hold.stock === 'OPEN'), false);
  assert.equal(result.counts.new, 1);
});

test('parts leave an unmatched repair order alone, and Karratha is not Broome sales', async () => {
  const { parseRevolutionUpload, dryRun } = await parser();
  const headers = ['Dept', 'R/O #', 'Line #', 'Parts Attached', 'Parts on Backorder', 'Backorder with PO (1=Yes, 0=No)'];
  const parts = htmlTable('CW PMG PD Parts Status Complete', [
    [138, 'J138100', 1, 1, 0, 0],
    [138, 'J138100', 2, 0, 1, 1],
    [138, 'J138200', 1, 0, 0, 0],
  ], headers);
  const parsed = await parseRevolutionUpload(parts, 'parts.html');
  assert.equal(parsed.rows.length, 2);
  assert.equal(parsed.rows[0]['Parts on Backorder'], 1);
  const result = dryRun(parsed, { board: { vehicles: [], jobs: [{ ro: 'J138100', closed: false }] } });
  assert.equal(result.counts.updated, 1);
  assert.equal(result.counts.skipped, 1);
  assert.equal(result.counts.archived, 0);

  const ktaHeaders = ['Type', 'Quote #', 'Stock #', 'PO Line', 'Price Level Desc', 'Notes', 'PO #', 'Transaction Sub-Type', 'Transaction Type'];
  const kta = htmlTable('KTA Allocation - Deal Items', [['D', 'Q1', 'KT1', 1, 'Accessory', '', 'PO9', 'Deal', 'Order']], ktaHeaders);
  const deal = await parseRevolutionUpload(kta, 'kta.html');
  assert.equal(deal.kind, 'kta_deal_items');
  assert.equal(deal.broome_sales, false);
  assert.equal(deal.rows.length, 1);
  const bt = htmlTable('BT Allocation — Deal Items', [['T1', 'Q9', 'BT9', 1, 'Skip', '', '', '', '']], ktaHeaders);
  const broome = await parseRevolutionUpload(bt, 'bt.html');
  assert.equal(broome.kind, 'bt_deal_items');
  assert.equal(broome.rows.length, 0);
  assert.equal(broome.broome_sales, true);
});

test('SpreadsheetML is accepted and a local dry run does not enable apply', async () => {
  const { parseRevolutionUpload } = await parser();
  const xml = `<?xml version="1.0"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet ss:Name="Results"><Table>
    <Row><Cell><Data ss:Type="String">KTA Allocation - Deal Items</Data></Cell></Row>
    <Row><Cell><Data ss:Type="String">Company = "01"</Data></Cell></Row>
    <Row><Cell><Data ss:Type="String"></Data></Cell></Row>
    <Row><Cell><Data ss:Type="String">Type</Data></Cell><Cell><Data ss:Type="String">Quote #</Data></Cell><Cell><Data ss:Type="String">Stock #</Data></Cell><Cell><Data ss:Type="String">PO Line</Data></Cell><Cell><Data ss:Type="String">Price Level Desc</Data></Cell><Cell><Data ss:Type="String">Notes</Data></Cell><Cell><Data ss:Type="String">PO #</Data></Cell><Cell><Data ss:Type="String">Transaction Sub-Type</Data></Cell><Cell><Data ss:Type="String">Transaction Type</Data></Cell></Row>
    <Row><Cell><Data ss:Type="String">D</Data></Cell><Cell><Data ss:Type="String">Q2</Data></Cell><Cell><Data ss:Type="String">KT2</Data></Cell><Cell><Data ss:Type="Number">2</Data></Cell><Cell><Data ss:Type="String">Mat</Data></Cell><Cell><Data ss:Type="String"></Data></Cell><Cell><Data ss:Type="String">PO2</Data></Cell><Cell><Data ss:Type="String">Deal</Data></Cell><Cell><Data ss:Type="String">Order</Data></Cell></Row>
  </Table></Worksheet></Workbook>`;
  const parsed = await parseRevolutionUpload(new TextEncoder().encode(xml), 'kta.xml');
  assert.equal(parsed.rows[0]['Stock #'], 'KT2');
  assert.equal(parsed.rows[0]['PO Line'], 2);
});

test('the migration does not rewrite Kajel and the ledger starts empty', () => {
  const up = readFileSync('supabase/migrations/20261028080000_r591_revolution_upload.sql', 'utf8');
  const down = readFileSync('supabase/rollbacks/20261028080000_r591_revolution_upload.down.sql', 'utf8');
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006'), false);
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1'), false);
  assert.match(up, /Craig has not approved go-live/);
  assert.match(up, /9be0883b1a555f48f3c1ba9fa111c891/);
  assert.match(up, /b62fb7c29ffd2a1629f214f696e5cb14/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /<>241/);
  assert.match(up, /sort_order=362/);
  assert.match(down, /DROP TABLE IF EXISTS pdc_codex_intake_private.revolution_upload_seen/);
  assert.match(up, /the ledger was not created empty/);
});

test('a local dry-run post leaves apply disabled', async () => {
  const child = spawn(process.execPath, ['tools/revolution-upload/preview-server.mjs'], {
    env: { ...process.env, PORT: '8766' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('preview server did not listen')), 5000);
      child.stdout.on('data', () => {});
      child.stderr.on('data', () => {});
      const probe = setInterval(async () => {
        try {
          const response = await fetch('http://127.0.0.1:8766/index.html', { method: 'HEAD' });
          if (response.ok) { clearInterval(probe); clearTimeout(timer); resolve(); }
        } catch { /* not up yet */ }
      }, 50);
    });
    const file = htmlTable('PMG PD Service as a Whole w/Sublet', [serviceRow({})]);
    const form = new FormData();
    form.append('file', new Blob([file], { type: 'text/html' }), 'sample-service.html');
    const response = await fetch('http://127.0.0.1:8766/revolution-upload?action=dry-run', { method: 'POST', body: form });
    const payload = await response.json();
    if (response.status !== 200) assert.fail(payload.error || JSON.stringify(payload));
    assert.equal(response.status, 200);
    assert.equal(payload.apply_enabled, false);
    assert.equal(payload.kind, 'service_whole');
    assert.equal(payload.logged, false);
    assert.equal(payload.uploader, 'Preview staff');
    assert.match(payload.md5, /^[a-f0-9]{32}$/);
    const apply = await fetch('http://127.0.0.1:8766/revolution-upload?action=apply', { method: 'POST', body: form });
    assert.equal(apply.status, 409);
    const refused = await apply.json();
    assert.equal(refused.apply_enabled, false);
    assert.match(refused.message, /not approved go-live/);
  } finally {
    child.kill();
  }
});

test('the five review files match Kajel row for row where Kajel sent them', async (t) => {
  const dir = process.env.KAJEL_REVIEW_DIR || '/tmp/kajel-review/review-20261027-1811';
  if (!existsSync(path.join(dir, 'downloads'))) {
    t.skip('the confidential review archive is not on this machine');
    return;
  }
  const { parseRevolutionUpload } = await parser();
  const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
  async function parsed(name) {
    return parseRevolutionUpload(readFileSync(path.join(dir, 'downloads', name)));
  }
  const cw = await parsed('cwparts-0807Z.xls');
  const cwKajel = JSON.parse(readFileSync(path.join(dir, 'cw/parts/rows.json'), 'utf8'));
  assert.equal(cw.rows.length, cwKajel.length);
  assert.equal(same(cw.rows, cwKajel), true);
  for (const name of ['bt-0535Z.xls', 'bt-0808Z.xls']) {
    const deal = await parsed(name);
    const kajel = JSON.parse(readFileSync(path.join(dir, 'bt', name.slice(3, 8), 'rows.json'), 'utf8'));
    assert.equal(deal.rows.length, kajel.length);
    assert.equal(same(deal.rows, kajel), true);
    assert.equal(deal.broome_sales, true);
  }
  const kta = await parsed('kta-0829Z.xls');
  const ktaKajel = JSON.parse(readFileSync(path.join(dir, 'kta/rows.json'), 'utf8'));
  assert.equal(kta.rows.length, ktaKajel.length);
  assert.equal(same(kta.rows, ktaKajel), true);
  assert.equal(kta.broome_sales, false);

  const service = await parsed('service-0938Z.xls');
  const sent = [];
  for (const part of readdirSync(path.join(dir, 'svc')).filter((name) => name.startsWith('part-'))) {
    sent.push(...JSON.parse(readFileSync(path.join(dir, 'svc', part, 'request.json'), 'utf8')));
  }
  const columns = ['Dept', 'Stock #', 'Rego #', 'Owner Name', 'Parts Location', 'Key Tag Number', 'R/O #', 'Sub Status', 'Line #', 'Operation Desc', 'Estimated labour hours', 'Modified Date', 'Range #'];
  const ours = new Map(service.rows.map((row) => [`${row.department}|${row.repair_order_number}|${row.original_line_number}`, row]));
  const fieldDiffs = {};
  let missing = 0;
  for (const row of sent) {
    const key = `${row.department}|${String(row.repair_order_number).toUpperCase()}|${row.original_line_number}`;
    const match = ours.get(key);
    if (!match) { missing += 1; continue; }
    for (const column of columns) {
      if (String(match.raw[column] ?? '') !== String(row.raw_row[column] ?? '')) fieldDiffs[column] = (fieldDiffs[column] || 0) + 1;
    }
    if (JSON.stringify(match.source_row_numbers) !== JSON.stringify(row.raw_row.source_row_numbers)) fieldDiffs.source_row_numbers = (fieldDiffs.source_row_numbers || 0) + 1;
    if (JSON.stringify(match.sublet_pos) !== JSON.stringify(row.raw_row.sublet_pos || [])) fieldDiffs.sublet_pos = (fieldDiffs.sublet_pos || 0) + 1;
  }
  assert.equal(sent.length, 6533);
  assert.equal(service.rows.length, 6866);
  assert.equal(missing, 0);
  assert.deepEqual(fieldDiffs, {});
  const sentKeys = new Set(sent.map((row) => `${row.department}|${String(row.repair_order_number).toUpperCase()}|${row.original_line_number}`));
  const holds = JSON.parse(readFileSync(path.join(dir, 'svc/not-sent.json'), 'utf8'));
  let holdMiss = 0;
  for (const hold of holds) {
    const found = service.rows.some((row) => row.repair_order_number === String(hold.ro).toUpperCase() && String(row.original_line_number) === String(hold.line));
    if (!found) holdMiss += 1;
  }
  assert.equal(holds.length, 192);
  assert.equal(holdMiss, 0);
  const holdKeys = new Set(holds.map((hold) => `${String(hold.ro).toUpperCase()}|${hold.line}`));
  let unlisted = 0;
  for (const row of service.rows) {
    const key = `${row.department}|${row.repair_order_number}|${row.original_line_number}`;
    if (sentKeys.has(key)) continue;
    if (holdKeys.has(`${row.repair_order_number}|${row.original_line_number}`)) continue;
    unlisted += 1;
  }
  assert.equal(service.rows.length - sent.length, 333);
  assert.equal(unlisted, 141);

  const { dryRun, HOLD_REASONS } = await parser();
  const staff = JSON.parse(readFileSync(path.join(dir, 'svc/staff-lock-holds.json'), 'utf8'));
  const lineHolds = JSON.parse(readFileSync(path.join(dir, 'svc/line-holds.json'), 'utf8'));
  const carried = JSON.parse(readFileSync(path.join(dir, 'svc/not-sent.json'), 'utf8'));
  const board = JSON.parse(readFileSync(path.join(dir, 'svc/board-index.json'), 'utf8'));
  const guards = { closedVehicle: [], identityChanged: [], identityRestore: [], staffLock: [], duplicateLines: [], carriedOver: carried };
  for (const hold of staff) {
    if (hold.reason === 'preview_conflict:closed_vehicle_requires_review') guards.closedVehicle.push(hold.stock);
    else if (hold.reason === 'preview_conflict:semantic_identity_changed_requires_review') guards.identityChanged.push(hold.stock);
    else if (hold.reason === 'preview_conflict:historical_identity_requires_restore') guards.identityRestore.push(hold.stock);
    else if (String(hold.reason).startsWith('staff_lock_change_on_apply')) guards.staffLock.push(hold.stock);
    else throw new Error(`unexpected staff hold reason ${hold.reason}`);
  }
  for (const hold of lineHolds) {
    if (hold.reason === 'ambiguous_existing_operation_duplicate_line_on_board') guards.duplicateLines.push({ ro: hold.ro, line: hold.line });
    else if (hold.reason !== 'status_99_new_vehicle_skip') throw new Error(`unexpected line hold reason ${hold.reason}`);
  }
  const result = dryRun(service, { board, guards });
  const expected = new Map();
  const remember = (ro, line, reason) => {
    const key = `${String(ro).toUpperCase()}|${line}`;
    if (expected.has(key) && expected.get(key) !== reason) throw new Error(`reason clash ${key}`);
    expected.set(key, reason);
  };
  const byIdentity = new Map();
  for (const row of service.rows) {
    const seen = new Set();
    for (const identity of [row.stock_number, row.rego].map((value) => String(value ?? '').trim().toUpperCase()).filter(Boolean)) {
      if (seen.has(identity)) continue;
      seen.add(identity);
      if (!byIdentity.has(identity)) byIdentity.set(identity, []);
      byIdentity.get(identity).push(row);
    }
  }
  const duplicateKeys = new Set(guards.duplicateLines.map((line) => `${String(line.ro).toUpperCase()}|${line.line}`));
  for (const hold of staff) {
    const rows = byIdentity.get(String(hold.stock).trim().toUpperCase()) || [];
    const reason = hold.reason.startsWith('staff_lock')
      ? HOLD_REASONS.staffLock
      : hold.reason.endsWith('closed_vehicle_requires_review')
        ? HOLD_REASONS.closedVehicle
        : hold.reason.endsWith('semantic_identity_changed_requires_review')
          ? HOLD_REASONS.identityChanged
          : HOLD_REASONS.identityRestore;
    let matched = 0;
    for (const row of rows) {
      const key = `${row.repair_order_number}|${row.original_line_number}`;
      if (duplicateKeys.has(key)) continue;
      remember(row.repair_order_number, row.original_line_number, reason);
      matched += 1;
    }
    assert.equal(matched, hold.lines, hold.part);
  }
  for (const hold of lineHolds) {
    const reason = hold.reason === 'status_99_new_vehicle_skip' ? HOLD_REASONS.status99 : HOLD_REASONS.duplicateLine;
    remember(hold.ro, hold.line, reason);
  }
  for (const hold of carried) remember(hold.ro, hold.line, HOLD_REASONS.carriedOver);
  const actual = new Map(result.holds.map((hold) => [`${hold.ro}|${hold.line}`, hold.reason]));
  const diffs = [];
  for (const [key, reason] of expected) if (actual.get(key) !== reason) diffs.push('missing');
  for (const [key, reason] of actual) if (expected.get(key) !== reason) diffs.push('extra');
  assert.equal(diffs.length, 0);
  assert.equal(result.holds.length, 333);
  assert.deepEqual(result.hold_counts, {
    [HOLD_REASONS.closedVehicle]: 59,
    [HOLD_REASONS.identityChanged]: 16,
    [HOLD_REASONS.identityRestore]: 1,
    [HOLD_REASONS.staffLock]: 62,
    [HOLD_REASONS.status99]: 2,
    [HOLD_REASONS.duplicateLine]: 1,
    [HOLD_REASONS.carriedOver]: 192,
  });
  assert.equal(6533 + result.holds.length, 6866);
});
