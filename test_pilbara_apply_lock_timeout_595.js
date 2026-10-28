'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const up = fs.readFileSync('supabase/migrations/20261028084500_r595_pilbara_apply_lock_timeout.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028084500_r595_pilbara_apply_lock_timeout.down.sql', 'utf8');

test('r595 publishes a 120s Pilbara apply and one station-revision lock', () => {
  assert.match(up, /SET statement_timeout = '120s'/);
  assert.match(up, /pdc:workshop:station-revision/);
  assert.match(up, /pilbara_apply_lock_timeout_595/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /9be0883b1a555f48f3c1ba9fa111c891/);
  assert.match(up, /b62fb7c29ffd2a1629f214f696e5cb14/);
  assert.match(up, /preview_navision_upload_profile/);
  assert.match(up, /014450/);
  assert.doesNotMatch(up, /vjdtsswhroyguxyfjdkt(?! is not a target)/);
  assert.match(down, /RESET statement_timeout/);
  assert.match(down, /7aa472fdd742efb91d733fde081f8e70/);
  assert.equal((up.match(/pdc:workshop:station-revision/g) || []).length >= 2, true);
});

test('a fictional Pilbara row is the sample the preview parses', () => {
  assert.match(up, /TOYOTA-ORDER-900001/);
  assert.match(up, /classification' IS DISTINCT FROM 'new'/);
  assert.match(up, /did not parse/);
});
