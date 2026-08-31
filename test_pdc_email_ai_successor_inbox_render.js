'use strict';

const assert = require('assert');
const fs = require('fs');
const {
  renderSuccessorInbox,
  successorInboxSummary,
} = require('./pdc-email-ai-successor-inbox.js');

function fakeDocument() {
  const nodes = [];
  return {
    createElement(tagName) {
      const node = { tagName, children: [], dataset: {}, className: '', textContent: '', innerHTML: '', append(...items) { this.children.push(...items); }, setAttribute(name, value) { this[name] = value; } };
      nodes.push(node);
      return node;
    },
    nodes,
  };
}

function test(name, fn) {
  try { fn(); console.log(`PASS ${name}`); }
  catch (error) { console.error(`FAIL ${name}: ${error.message}`); process.exitCode = 1; }
}

test('one parent email renders separate vehicle result rows and complete detail markers', () => {
  const documentRef = fakeDocument();
  const html = renderSuccessorInbox({
    ok: true,
    revision: 12,
    items: [{
      intake_uid: 'imap:514', received_at: '2026-08-31T01:02:03Z', sender: 'sender@example.test', subject: 'Two vehicle Job Card',
      attachment_summary: { count: 1, names: ['job-card.pdf'] }, disposition: 'PARTIAL_FAILURE', verification_status: 'PARTIAL',
      summary: { before: '2 active cars', requested: 'Parts ETA and Tyre', result: 'Parts ETA applied; Tyre blocked' },
      transaction: { plan: { schema_version: 'pdc-email-ai-plan-v1' }, versions: { model: 'm1', prompt: 'p1', instruction_set: 'i1', taxonomy: 't1', action_contract: 'a1' }, readback: { parity: false } },
      vehicle_results: [
        { vehicle_id: 'v1', stock: '100001', vehicle: 'HiAce', actions: [{ action_type: 'parts_eta_set', canonical_rpc: 'update_pdc_parts_eta', disposition: 'APPLIED_AND_VERIFIED', before: '—', requested: '2026-09-01', result: '2026-09-01' }] },
        { vehicle_id: 'v2', stock: '100002', vehicle: 'Hilux', actions: [{ action_type: 'location_set', disposition: 'BLOCKED_EXACT_REASON', reason: 'ambiguous location' }] },
      ],
      retry_state: { attempts: 2, quarantine: false },
    }],
  });
  assert.ok(html.includes('imap:514'));
  assert.ok(html.includes('100001') && html.includes('100002'));
  assert.ok(html.includes('PARTIAL_FAILURE'));
  assert.ok(html.includes('update_pdc_parts_eta'));
  assert.ok(html.includes('BLOCKED_EXACT_REASON'));
  assert.ok(html.includes('pdc-email-ai-plan-v1'));
  assert.ok(html.includes('2026-09-01'));
  assert.strictEqual(successorInboxSummary({ items: [{ vehicle_results: [{}, {}] }] }).vehicleCount, 2);
});

test('loading, empty and error states are distinct', () => {
  assert.ok(renderSuccessorInbox({ state: 'loading' }).includes('Loading successor AI Intake'));
  assert.ok(renderSuccessorInbox({ state: 'empty', items: [] }).includes('No successor emails received'));
  assert.ok(renderSuccessorInbox({ state: 'error', error: 'snapshot_unavailable' }).includes('snapshot_unavailable'));
});

test('published fixture covers quarantine and multi-vehicle accounting', () => {
  const fixture = JSON.parse(fs.readFileSync('tests/fixtures/pdc_email_ai_successor_inbox_ui.json', 'utf8'));
  const html = renderSuccessorInbox({ ok: true, revision: 9, items: fixture.items });
  assert.ok(html.includes('fixture:multi-vehicle-515'));
  assert.ok(html.includes('fixture:quarantine-516'));
  assert.ok(html.includes('QUARANTINED'));
  assert.ok(html.includes('13000001') && html.includes('13000002'));
});
