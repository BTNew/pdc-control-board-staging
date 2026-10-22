/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r444 (F57, change request): the Sublet box lists every sublet with the 'Description of sublet' from the upload; operation
// lines keep a read-only PO reference; empty categories hidden; Bus 4x4 sub-groups framed. Synthetic data only.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), crypto = require('node:crypto');
const panels = require('./pdc-operation-panels.js');
const po = require('./pdc-sublet-po.js');
const appSource = fs.readFileSync('app.js', 'utf8');
const MIG = 'supabase/migrations/20261021083212_r444_sublet_po_descriptions.sql';
const DOWN = 'supabase/rollbacks/20261021083212_r444_sublet_po_descriptions.down.sql';
function summary(lines) {
  const context = vm.createContext({ app: { vehicleWorkshopDetailCache: new Map([['synthetic', { status: 'ready', detail: { vehicle_version: 2, job_card_lines: lines } }]]) },
    cleanNavisionText: x => String(x ?? '').trim(), vehicleWorkshopDetailCanonicalId: () => 'synthetic', vehicleKey: () => 'synthetic',
    escapeHtml: x => String(x ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'),
    vehicleWorkshopLineIdentity: (_s, l) => `source:${l.operation_line_id}`, vehicleWorkshopStageCode: s => String(s).toUpperCase() });
  vm.runInContext(appSource.slice(appSource.indexOf('function authenticatedOperationLineValid('), appSource.indexOf('function refreshAuthenticatedOperationSummaryRow(')), context);
  return context;
}
const V = '11111111-2222-4333-8444-555555555555';
const S = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const jc = (n, cat, desc, h = 0.5) => ({ line_identity: `source:${S(n)}`, source_line_id: S(n), operation_no: `PD${String(n).padStart(3, '0')}-ABCDEF01`,
  description: desc, source_kind: 'authenticated', department: '138', active: true, work_category: cat, stage_code: cat, estimated_hours: h });
const L = (n, pos, ticked, descs) => ({ line_key: `jc:J138000001:${n}`, line_identity: `source:${S(n)}`, operation_no: `PD${String(n).padStart(3, '0')}-ABCDEF01`, line_no: n,
  po_numbers: pos, po_details: pos.map((p, i) => ({ po_number: p, description: descs[i] })), ticked, version: ticked ? 1 : 0, tickable: true });
// Bus 4x4 conversion shape (synthetic text): PO on operation lines 5 and 6, tint 2 ticked, own Sublet 11 with a PO, 12 without.
const hiace = [jc(2, 'TINT', 'Sample tint', 1), jc(6, 'BUS_MECHANICAL', 'Sample springs', 40), jc(5, 'BUS_MECHANICAL', 'Sample tyres', 0.17),
  jc(4, 'BUS_ELECTRICAL', 'Sample UHF', 2), jc(11, 'SUBLET', 'SUB - Sample seat covers', 0.01), jc(12, 'SUBLET', 'SUB - no po', 0.01)];
const hiacePayload = { ok: true, can_tick: true, vehicle_id: V, lines: [L(6, ['GP19000006'], false, ['SPRINGS^^Key 001']), L(2, ['GP19000002'], true, ['Tint <b>co</b> "x"']),
  L(5, ['GP19000005', 'GP19000007'], false, ['TYRES', null]), L(11, ['GP19000011'], false, ['Seat covers^Key 001'])] };
const render = (lines, payload) => panels.arrange(po.decorateOperations(summary(lines).authenticatedEmailOperationLinesHtml({}), { vehicleId: V, payload }));
const subletBox = html => html.slice(html.indexOf('data-operation-panel="sublet"'));
const rows = html => [...subletBox(html).matchAll(/<li[^>]*?(?:data-line-key="jc:J138000001:(\d+)"|data-operation-source-id="0{8}-0000-4000-8000-0*(\d+)")[^>]*>/g)].map(m => Number(m[1] || m[2]));

test('description cleaning: as typed, Revolution ^ line breaks shown as " · ", blanks dropped, never upper-cased', () => {
  assert.equal(po.cleanDescription('SAMPLE BUS 4X4 LEAF SPRINGS & U-BOLTS^^Key 001'), 'SAMPLE BUS 4X4 LEAF SPRINGS & U-BOLTS · Key 001');
  assert.equal(po.cleanDescription('  Seat covers^ Key 001 '), 'Seat covers · Key 001');
  assert.equal(po.cleanDescription('mixed Case'), 'mixed Case');
  for (const x of ['', '   ', '^^', null, undefined]) assert.equal(po.cleanDescription(x), '');
  assert.deepEqual(po.poDetails({ po_numbers: ['GP1', 'GP2'], po_details: [{ po_number: 'GP1', description: 'A' }] }).map(d => [d.po, d.description]), [['GP1', 'A'], ['GP2', '']]);
  assert.deepEqual(po.poDetails({ po_numbers: ['GP1'] }).map(d => [d.po, d.description]), [['GP1', '']], 'older payload without po_details still works');
});

test('Sublet box: every sublet in PD line order, operation-line POs as linked rows with description, PO and the one tick; own lines keep theirs', () => {
  const html = render(hiace, hiacePayload);
  assert.deepEqual(rows(html), [2, 5, 6, 11, 12], 'PD line order, linked rows and own Sublet lines merged');
  const box = subletBox(html);
  assert.match(box, /data-line-key="jc:J138000001:6"><strong>PD line 6<\/strong><span><b class="pdc-sublet-desc">SPRINGS · Key 001<\/b><small class="pdc-sublet-on">On operation line: Sample springs · Bus 4x4 Mechanical<\/small><\/span><em class="pdc-sublet-kind">Op line PO<\/em> <span class="pdc-sublet-po-inline is-ordered"[^>]*><span class="pdc-sublet-po-chip">GP19000006<\/span><input type="checkbox" class="pdc-sublet-po-tick"[^>]*aria-label="PD line 6 sublet done"><\/span><\/li>/);
  assert.match(box, /<span class="pdc-sublet-desc-po">GP19000005<\/span> TYRES<\/b><b class="pdc-sublet-desc"><span class="pdc-sublet-desc-po">GP19000007<\/span> <i class="pdc-sublet-desc-missing">No sublet description in the upload yet<\/i><\/b>/, 'two POs on one line: each with its own description');
  assert.equal((box.match(/aria-label="PD line 5 sublet done"/g) || []).length, 1, 'one tick per line even with two POs');
  assert.match(box, /<b class="pdc-sublet-desc">Tint &lt;b&gt;co&lt;\/b&gt; &quot;x&quot;<\/b>/, 'description escaped');
  assert.doesNotMatch(html, /<b>co<\/b>/);
  assert.match(box, /data-pdc-sublet-row="own"><strong>PD line 11<\/strong><span>SUB - Sample seat covers<small class="pdc-sublet-own-desc"><b class="pdc-sublet-desc">Seat covers · Key 001<\/b><\/small><\/span><em>0\.01 h<\/em> <span class="pdc-sublet-po-inline/);
  assert.match(box, /data-pdc-sublet-row="own"><strong>PD line 12<\/strong><span>SUB - no po<\/span><em>0\.01 h<\/em> <span class="pdc-sublet-po-nopo"[^>]*>PO to raise<\/span><\/li>/, 'no GP PO: not tickable, "PO to raise" (r494; was "No PO")');
  assert.equal((html.match(/class="pdc-sublet-po-tick"/g) || []).length, 4, 'every tick in the Sublet box, none elsewhere');
  assert.equal((box.match(/class="pdc-sublet-po-tick"/g) || []).length, 4);
});

test('operation lines: read-only PO reference with ↓, title carries the description; no tick, line text and hours unchanged', () => {
  const base = summary(hiace).authenticatedEmailOperationLinesHtml({});
  const html = render(hiace, hiacePayload);
  const li = n => html.match(new RegExp(`<li data-operation-source-id="${S(n)}">[\\s\\S]*?</li>`))[0];
  assert.equal(li(6), `<li data-operation-source-id="${S(6)}"><strong>PD line 6</strong><span>Sample springs</span><em>40.00 h</em> <span class="pdc-sublet-po-ref is-ordered" title="GP19000006: SPRINGS · Key 001 (sublet not done yet; tick it in the Sublet box)">GP19000006<span aria-hidden="true"> ↓</span></span></li>`);
  assert.match(li(2), /pdc-sublet-po-ref is-done" title="GP19000002: Tint &lt;b&gt;co&lt;\/b&gt; &quot;x&quot; \(sublet done; tick it in the Sublet box\)"/);
  assert.match(li(5), />GP19000005, GP19000007<span aria-hidden="true"> ↓<\/span>/);
  assert.equal(li(4), base.match(new RegExp(`<li data-operation-source-id="${S(4)}">[\\s\\S]*?</li>`))[0], 'a line without a PO is unchanged');
  assert.match(panels.css || fs.readFileSync('pdc-operation-panels.js', 'utf8'), />\.pdc-sublet-po-ref\{grid-column:4;grid-row:1;justify-self:end;margin:0\}/);
});

test('Sublet header: "N sublets" and the done pill; orange while any PO line is unticked, green when all are; state attributes', () => {
  const html = render(hiace, hiacePayload);
  assert.match(html, /<section class="authenticated-operation-station pdc-op-panel is-full is-sublet-ordered" data-operation-panel="sublet"[^>]*><header><strong>Sublet<\/strong><small>5 sublets <span class="pdc-op-sublet-state is-ordered">1 of 5 sublets done<\/span><\/small><\/header>/);
  assert.match(html, /data-pdc-sublet-box data-pdc-sublet-state="ordered" data-pdc-sublet-count="1\/5"/); // r494 (F107): the whole line sublet with no GP PO counts as open (PO to raise)
  const done = { ...hiacePayload, lines: hiacePayload.lines.map(l => ({ ...l, ticked: true, version: 1 })) };
  const green = render(hiace, done);
  // r494 (F107): every GP PO line ticked, but a whole line sublet still has no PO: stays orange (PO to raise).
  assert.match(green, /pdc-op-panel is-full is-sublet-ordered" data-operation-panel="sublet"/);
  assert.match(green, /<small>5 sublets <span class="pdc-op-sublet-state is-ordered">4 of 5 sublets done<\/span><\/small>/);
  const none = render(hiace, { ok: true, can_tick: true, vehicle_id: V, lines: [] });
  assert.match(none, /is-sublet-ordered/, 'r494 (F107): own Sublet jobs with no GP PO: orange, PO to raise (was neutral)');
  assert.match(none, /data-operation-panel="sublet"/, 'own Sublet jobs still shown');
});

test('a vehicle with PO lines but no Sublet jobs of its own gets a Sublet box; a vehicle with no sublets has none; empty categories hidden', () => {
  const lines = [jc(21, 'TINT', 'Sample tint', 1), jc(31, 'FITTING', 'Sample bull bar', 6.5), jc(41, 'ELECTRICAL', 'Sample lightbar', 1.3)];
  const html = render(lines, { ok: true, can_tick: true, vehicle_id: V, lines: [L(31, ['GP19000032', 'GP19000033'], true, ['BULL BAR POWDER COAT', 'TRANSPORT SAMPLE']), L(21, ['GP19000021'], true, [''])] });
  assert.deepEqual(rows(html), [21, 31]);
  assert.match(html, /pdc-op-panel is-full is-sublet-done" data-operation-panel="sublet"/);
  assert.match(subletBox(html), /PD line 21<\/strong><span><b class="pdc-sublet-desc"><i class="pdc-sublet-desc-missing">No sublet description in the upload yet<\/i>/);
  const plain = render(lines, { ok: true, can_tick: true, vehicle_id: V, lines: [] });
  assert.doesNotMatch(plain, /data-operation-panel="sublet"|data-operation-station="SUBLET"/);
  assert.doesNotMatch(plain, /data-operation-panel="(bus4x4|hoist|fabrication|tyre)"|pdc-op-empty|No jobs/);
  assert.deepEqual([...plain.matchAll(/data-operation-panel="([^"]*)"/g)].map(m => m[1]).sort(), ['electrical', 'fitting', 'tint']);
});

test('Bus 4x4 sub-groups in grey framed boxes (CSS in the module; styles.css untouched); idempotent; no request without a session', () => {
  const src = fs.readFileSync('pdc-operation-panels.js', 'utf8');
  assert.match(src, /2px solid/); assert.match(src, /#e2e8f0/);
  assert.match(src, /is-sublet-ordered/); assert.match(src, /is-sublet-done/);
  const html = render(hiace, hiacePayload);
  assert.match(html, /data-operation-panel="bus4x4"[\s\S]*data-operation-category="bus_mechanical"[^>]*data-pdc-op-sub[\s\S]*data-operation-category="bus_electrical"[^>]*data-pdc-op-sub/);
  assert.equal(panels.arrange(po.decorateOperations(html, { vehicleId: V, payload: hiacePayload })), html, 'decorating and arranging again changes nothing');
  assert.equal(po.VERSION, '2026.10.21.r444'); assert.equal(panels.VERSION, '2026.10.21.r444');
  const { execFileSync } = require('node:child_process');
  const changed = execFileSync('git', ['diff', '--name-only', 'HEAD'], { encoding: 'utf8' });
  assert.doesNotMatch(changed, /^(styles\.css|app\.js)$/m, 'locked files untouched');
});

test('loader: cache-bust tags r444 in canonical-entry.js and index.html; auto-reload stays first', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8'), index = fs.readFileSync('index.html', 'utf8');
  assert.match(entry, /sublet-po=2026\.10\.21\.r444/); assert.match(entry, /operation-panels=2026\.10\.21\.r444/);
  assert.match(index, /&amp;sublet-po=2026\.10\.21\.r444&amp;operation-panels=2026\.10\.21\.r444/);
  assert.ok(entry.indexOf('pdc-sublet-po.js') < entry.indexOf('pdc-operation-panels.js'));
  const scripts = [...index.matchAll(/<script[^>]*src="([^"]+)"/g)].map(m => m[1]);
  assert.match(scripts[0], /^pdc-auto-reload\.js/);
});

test('migration: pins equal the md5 of the shipped bodies; undo restores the r439/r442 bodies; guards; never clears; apply unchanged', () => {
  const md5s = f => { const s = fs.readFileSync(f, 'utf8'), out = {}; let m; const re = /CREATE OR REPLACE FUNCTION ([^(]+)\([\s\S]*?\nAS \$f\$([\s\S]*?)\$f\$;/g;
    while ((m = re.exec(s))) out[m[1]] = crypto.createHash('md5').update(m[2]).digest('hex'); return out; };
  const after = { 'public.import_sublet_pos_439': '6083fb5bcf03d341d9101831c2217cb8', 'pdc_work_categories_private.sublet_po_vehicle_439': '756b7a4164a6e9ce37bb33c7c861b346',
    'pdc_codex_intake_private.service_sublet_po_feed_442': '66379d312c3fddfd2eaab5b37c0ba497', 'pdc_codex_intake_private.revolution_service_rows_20261006': '0534336e01558066cf7ec3dcb3995cd4' };
  const before = { 'public.import_sublet_pos_439': '6cc118c512e103e33bfe94118b91d8a1', 'pdc_work_categories_private.sublet_po_vehicle_439': 'bf4f60277f69b53cbd982c7aa24b2401',
    'pdc_codex_intake_private.service_sublet_po_feed_442': '6119632a2c961505b8875d1f0dcbdbaa', 'pdc_codex_intake_private.revolution_service_rows_20261006': 'fd1d9272719cba74fdca23f9015d6d08' };
  assert.deepEqual(md5s(MIG), after); assert.deepEqual(md5s(DOWN), before);
  const mig = fs.readFileSync(MIG, 'utf8'), down = fs.readFileSync(DOWN, 'utf8');
  for (const v of Object.values(after)) assert.match(mig, new RegExp(`SET prosrc_md5='${v}',release='r444'`));
  for (const v of Object.values(before)) assert.match(down, new RegExp(`SET prosrc_md5='${v}',release='r4(39|42)'`));
  assert.match(mig, /NOT BETWEEN 2 AND 45/); assert.match(mig, /cdsmnqxtyyoeoznmbidd/); assert.doesNotMatch(mig + down, /vjdtsswhroyguxyfjdkt/);
  assert.match(mig, /SET LOCAL lock_timeout = '2s'|SET LOCAL lock_timeout TO '2s'|SET LOCAL lock_timeout '2s'/);
  assert.match(mig, /'fc3717a5215de94c93ebb2c7facfe744'/, 'service apply guarded unchanged');
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.pdc_pilbara_service_apply_v1|CREATE OR REPLACE FUNCTION public\.set_pdc_sublet_line_tick_439/);
  assert.match(mig, /description=coalesce\(v_desc,\s*description\)|description = coalesce\(v_desc, description\)/, 'blank or missing never clears');
  assert.match(mig, /'sublet_po_descriptions_444','F57'[\s\S]*?,true,243,'r444'\)/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='sublet_po_descriptions_444'/);
  assert.match(down, /DROP COLUMN description_source_file_sha256, DROP COLUMN description/);
  const fl = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
  assert.match(fl, /^\| F57 \| 21 Oct 16:24 \|/m); assert.ok(fl.indexOf('| F57 |') > fl.indexOf('| F56 |'));
  assert.match(fs.readFileSync('docs/revolution-service-email.md', 'utf8'), /## Sublet descriptions — r444 \(F57\)/);
  assert.match(fs.readFileSync('tests/sublet_po_descriptions_444.sql', 'utf8'), /^ROLLBACK;$/m);
});

test('no live data in the release: no stock numbers, live POs or personal data in the r444 files', () => {
  for (const f of [MIG, DOWN, 'tests/sublet_po_descriptions_444.sql', 'test_sublet_box_444.js', 'pdc-sublet-po.js', 'pdc-operation-panels.js']) {
    // The intake's own system mailboxes (already pinned in the r442 validator body) are not personal data.
    const s = fs.readFileSync(f, 'utf8').replace(/noreply@revolutionsoftware\.com\.au|pmbcontroller@gmail\.com/g, '');
    assert.doesNotMatch(s, /\bGP(?!139|190)\d{8}\b/, `${f}: only synthetic GP13900xxx / GP19000xxx`);
    assert.doesNotMatch(s, /@(?!example\.invalid|pdc\.invalid)[a-z0-9-]+\.[a-z]/i, `${f}: no personal email address`);
    assert.doesNotMatch(s, /\b(stock|Stock)[ _#:]*\d{5,}/, `${f}: no stock numbers`);
  }
});
