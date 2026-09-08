'use strict';

const assert = require('assert');

const storage = new Map();
const replacements = [];
global.window = {
  addEventListener: () => {},
  location: {
    href: 'https://btnew.github.io/pdc-control-board-staging/?page=workshop',
    replace: value => replacements.push(value),
  },
  sessionStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
  },
};
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.parseIsoTimestamp = value => {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const planner = require('./workshop-planner.js');

(async () => {
  global.fetch = async () => ({ ok: true, json: async () => ({}) });
  assert.strictEqual(await planner.workshopEnsureCurrentDeployment(), true,
    'a malformed manifest is ignored rather than creating a reload loop');
  assert.strictEqual(replacements.length, 0);

  const staleManifest = {
    siteVersion: '2026.09.09.04-stale-fixture',
    workshopPlannerVersion: '2026.09.09.04-stale-fixture',
  };
  global.fetch = async () => ({ ok: true, json: async () => staleManifest });
  assert.strictEqual(await planner.workshopEnsureCurrentDeployment(), false);
  assert.strictEqual(replacements.length, 1, 'a valid version mismatch triggers one reload');
  assert.match(replacements[0], /deployment=2026\.09\.09\.04-stale-fixture/);

  assert.strictEqual(await planner.workshopEnsureCurrentDeployment(), false);
  assert.strictEqual(replacements.length, 1,
    'the same persistent mismatch is fail-closed after one reload attempt');

  for (let index = 0; index < 9; index += 1) {
    global.fetch = async () => ({ ok: true, json: async () => ({
      siteVersion: `2026.09.09.${10 + index}-rotation`,
      workshopPlannerVersion: `2026.09.09.${10 + index}-rotation`,
    }) });
    assert.strictEqual(await planner.workshopEnsureCurrentDeployment(), false);
  }
  const replacementsAfterRotation = replacements.length;
  global.fetch = async () => ({ ok: true, json: async () => staleManifest });
  assert.strictEqual(await planner.workshopEnsureCurrentDeployment(), false);
  assert.strictEqual(replacements.length, replacementsAfterRotation,
    'an earlier identity remains guarded after more than eight deployment rotations');

  const noStorageWindow = { ...window, sessionStorage: null };
  global.window = noStorageWindow;
  global.fetch = async () => ({ ok: true, json: async () => ({
    siteVersion: '2026.09.09.05-no-storage',
    workshopPlannerVersion: '2026.09.09.05-no-storage',
  }) });
  assert.strictEqual(await planner.workshopEnsureCurrentDeployment(), false);
  assert.strictEqual(replacements.length, replacementsAfterRotation,
    'without a persistent session guard the planner fails closed instead of reloading');

  console.log('workshop deployment freshness loop guard: PASS');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
