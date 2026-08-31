'use strict';

const assert = require('assert');
const fs = require('fs');
const {
  PDC_EMAIL_AI_SUCCESSOR_REVISION_TABLE,
  createPdcEmailAiSuccessorInboxController,
} = require('./pdc-email-ai-successor-inbox.js');

function test(name, fn) {
  try { fn(); console.log(`PASS ${name}`); }
  catch (error) { console.error(`FAIL ${name}: ${error.message}`); process.exitCode = 1; }
}

test('successor UI is staging-bound and legacy .68 fallback remains hidden', () => {
  const staging = fs.readFileSync('staging.html', 'utf8');
  const successor = fs.readFileSync('pdc-email-ai-successor-inbox.js', 'utf8');
  assert.ok(staging.includes('pdc-email-ai-successor-inbox.js'));
  assert.ok(staging.includes('id="pdc-email-ai-successor-inbox"'));
  assert.ok(staging.includes('id="ai-intake-legacy-fallback" hidden'));
  assert.ok(staging.includes('cdsmnqxtyyoeoznmbidd.supabase.co'));
  assert.ok(!staging.includes('vjdtsswhroyguxyfjdkt.supabase.co'));
  assert.ok(!/^const api\s*=/m.test(successor));
});

test('controller refreshes from Realtime once and suppresses stale generations', async () => {
  const root = {
    innerHTML: '',
    querySelector(selector) {
      if (selector === '#pdc-successor-inbox-refresh') return { addEventListener() {} };
      if (selector === '.successor-load-more') return null;
      return null;
    },
  };
  let resolveFirst;
  let calls = 0;
  const client = { snapshot: () => {
    calls += 1;
    if (calls === 1) return new Promise(resolve => { resolveFirst = resolve; });
    return Promise.resolve({ ok: true, data: { revision: 2, items: [], has_more: false, next_cursor: null } });
  } };
  let change;
  const controller = createPdcEmailAiSuccessorInboxController({
    root,
    client,
    getAuthority: () => 'viewer|user|token',
    subscribeRealtime: (_table, handlers) => { change = handlers.onChange; return { unsubscribe() {} }; },
  });
  controller.mount();
  assert.strictEqual(PDC_EMAIL_AI_SUCCESSOR_REVISION_TABLE, 'pdc_email_ai_successor_ui_revision');
  await Promise.resolve();
  change();
  await new Promise(resolve => setImmediate(resolve));
  resolveFirst({ ok: true, data: { revision: 1, items: [{ intake_uid: 'stale' }], has_more: false, next_cursor: null } });
  await new Promise(resolve => setImmediate(resolve));
  assert.strictEqual(controller.state.data.revision, 2);
  assert.deepStrictEqual(controller.state.data.items, []);
  controller.unmount();
});
