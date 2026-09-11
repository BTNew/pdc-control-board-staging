'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createPdcOperationalRefreshCoordinator } = require('./vehicle-locations-refresh');

function harness() {
  const reads = [], finishes = [];
  let active = 0, maximum = 0, route = 'dashboard';
  const coordinator = createPdcOperationalRefreshCoordinator({
    getRoute: () => route,
    loaders: { snapshot: context => new Promise((resolve, reject) => {
      maximum = Math.max(maximum, ++active);
      reads.push({ context, resolve: value => { active--; resolve(value); }, reject: error => { active--; reject(error); } });
    }) },
    onFinish: result => finishes.push(result),
  });
  return { coordinator, reads, finishes, maximum: () => maximum, route: value => { route = value; } };
}
const settle = () => new Promise(resolve => setImmediate(resolve));

test('revision bursts run one active read and one follow-up containing newer data', async () => {
  const h = harness();
  const pending = h.coordinator.refresh();
  for (let i = 0; i < 50; i++) assert.equal(h.coordinator.refresh({ trailing: true }), pending);
  assert.equal(h.reads.length, 1);
  h.reads[0].resolve({ ok: true, revision: 1 });
  await settle();
  assert.equal(h.reads.length, 2);
  h.reads[1].resolve({ ok: true, revision: 50 });
  await pending;
  assert.equal(h.maximum(), 1);
  assert.equal(h.finishes.at(-1).results[0].value.revision, 50);
  assert.equal(h.coordinator.isRefreshing(), false);
});

test('updates during the follow-up are retained and resolve the current route', async () => {
  const h = harness();
  const pending = h.coordinator.refresh();
  h.coordinator.refresh({ trailing: true });
  h.route('workflow');
  h.reads[0].resolve({ ok: true });
  await settle();
  assert.equal(h.reads[1].context.route, 'workflow');
  h.coordinator.refresh({ trailing: true });
  h.coordinator.refresh({ trailing: true });
  h.reads[1].resolve({ ok: true });
  await settle();
  assert.equal(h.reads.length, 3);
  h.reads[2].resolve({ ok: true });
  await pending;
  assert.equal(h.maximum(), 1);
});

test('failed read still drains a queued revision', async () => {
  const h = harness();
  const pending = h.coordinator.refresh();
  h.coordinator.refresh({ trailing: true });
  h.reads[0].reject(new Error('temporary network failure'));
  await settle();
  h.reads[1].resolve({ ok: true });
  await pending;
  assert.deepEqual(h.finishes.map(r => r.ok), [false, true]);
});

test('sign-out invalidation cancels queued work and stale completion', async () => {
  const h = harness();
  const pending = h.coordinator.refresh();
  h.coordinator.refresh({ trailing: true });
  h.coordinator.invalidate();
  h.reads[0].resolve({ ok: true });
  assert.equal((await pending).stale, true);
  assert.equal(h.reads.length, 1);
  assert.equal(h.finishes.length, 0);
});

test('explicit supersede replaces old queued work without an extra refresh', async () => {
  const h = harness();
  const first = h.coordinator.refresh();
  h.coordinator.refresh({ trailing: true });
  const second = h.coordinator.refresh({ supersede: true });
  h.reads[1].resolve({ ok: true });
  await second;
  h.reads[0].resolve({ ok: true });
  await first;
  assert.equal(h.reads.length, 2);
  assert.deepEqual(h.finishes.map(r => r.generation), [2]);
});
