'use strict';
// r677 (F287): business conflicts are PT409, never 40001/40P01 (PostgREST retries those in a loop).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261028290000_r677_conflicts_not_retryable.sql', 'utf8');
test('sweep keeps Kajel apply, the clock tick and checked functions out, and moves only the two tick pins', () => {
  assert.match(sql, /proname NOT IN \('pdc_pilbara_service_apply_v1', 'workshop_clock_tick', 'start_workshop_work_pre_116'\)/);
  assert.match(sql, /NOT LIKE 'karratha%'/);
  assert.match(sql, /strpos\(c\.check_sql, md5\(p\.prosrc\)\) > 0/);
  assert.match(sql, /r\.proname NOT IN \('set_pdc_pit_line_tick_401', 'set_pdc_sublet_line_tick_439'\)/);
  assert.match(sql, /'\\1''PT409'''/);
});
test('no new browser code treats 40001 as a QC, pit or sublet conflict', () => {
  for (const f of ['pdc-email-vehicle-location-service.js', 'pdc-sublet-po.js', 'pdc-qc-mobile.js']) {
    assert.doesNotMatch(fs.readFileSync(f, 'utf8'), /'40001'/, f);
  }
});
