'use strict';
// r727 (F337): Craig 29 Oct 16:12, "if a vehicle has a key number, it needs to be placed at PMB automatically".
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const sql = fs.readFileSync('supabase/migrations/20261029190000_r727_key_means_pmb.sql', 'utf8');
test('a keyed car at IT / YH / Other / blank is put at PMB on every insert or update', () => {
  assert.match(sql, /CREATE TRIGGER zzzz_pdc_key_means_pmb_727 BEFORE INSERT OR UPDATE OF key_number, current_location, location_override, lifecycle_state, deleted_at/);
  assert.match(sql, /IF v_eff NOT IN \('YH', 'IT', 'OTHER', ''\) OR v_loc NOT IN \('YH', 'IT', 'OTHER', '', 'PMB'\) THEN RETURN NEW; END IF;/);
  assert.match(sql, /NEW\.current_location := 'PMB';/);
  assert.match(sql, /NEW\.date_to_pmb := coalesce\(NEW\.date_to_pmb/);
});
test('QC, PIT, RFT and finished cars are never touched; imports keep working', () => {
  assert.match(sql, /OR NEW\.qc_completed_at IS NOT NULL OR NEW\.rft_transferred_at IS NOT NULL OR NEW\.rft_collected_at IS NOT NULL THEN\n    RETURN NEW;/);
  assert.match(sql, /coalesce\(auth\.uid\(\), NEW\.updated_by, NEW\.created_by\) AS w\) x WHERE w IS NOT NULL/, 'an import has no signed-in user');
  assert.match(sql, /'r727: import window'/);
  assert.match(sql, /expected_function_md5\) <> 241/);
});
test('existing keyed cars are moved, a check guards it, and there is a rollback', () => {
  assert.match(sql, /UPDATE public\.vehicles SET current_location = current_location/);
  assert.match(sql, /'key_means_pmb_727', 'F337'/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261029190000_r727_key_means_pmb.down.sql'));
});
