/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const up = fs.readFileSync('supabase/migrations/20261026110000_r536_category_unstarted_release.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261026110000_r536_category_unstarted_release.down.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const karratha = fs.readFileSync('karratha/app.js', 'utf8');

test('r536 preview asks before releasing an unstarted booking and leaves Department 135 frozen', () => {
  assert.match(up, /PREVIEW/);
  assert.match(up, /SQL is not applied/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /sort_order=315/);
  assert.match(up, /Pin count stays 241/);
  assert.match(up, /'confirm_release'/);
  assert.match(up, /This will release the unstarted/);
  assert.match(up, /running_job_keeps_its_bay_time/);
  assert.match(up, /category_release_536/);
  assert.match(up, /Split or cancel the affected unstarted booking before changing its work category\. Started and completed work stays protected\./);
  assert.match(up, /b1b23383b96acd867c246cf6e57572dc/);
  assert.match(up, /1c0424ad5da9a534ea4ae7b0ebae5c29/);
  assert.doesNotMatch(up, /sort_order=314/);
  assert.equal(scanSql(up).length, 0);
  assert.match(down, /1c0424ad5da9a534ea4ae7b0ebae5c29/);
  assert.match(down, /sort_order=315/);
  assert.match(down, /Does not put a released booking back/);
  assert.equal(scanSql(down).length, 0);
  assert.match(app, /data-original-category=/);
  assert.match(app, /p_release_unstarted/);
  assert.match(app, /confirm_release/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /r536=2026\.10\.26\.r536/);
  assert.doesNotMatch(karratha, /confirm_release/);
  assert.doesNotMatch(karratha, /p_release_unstarted/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F150 \|/);
});
