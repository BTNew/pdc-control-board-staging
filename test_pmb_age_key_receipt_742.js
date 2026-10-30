'use strict';
// r742 (F347): the PMB age is the key receipt (latest of key date, staff key add, explicit To PMB); Tune first-seen is
// only the fallback when there is no key. An explicit To PMB release refreshes the age.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030083000_r742_pmb_age_is_key_receipt.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030083000_r742_pmb_age_is_key_receipt.down.sql', 'utf8');

test('key receipt is the latest of three sources and wins whenever a key exists', () => {
  assert.match(up, /SELECT greatest\(\n   \(SELECT a\.assigned_at FROM public\.pdc_vehicle_key_assigned_562 a WHERE a\.vehicle_id = p_vehicle_id\),/);
  assert.match(up, /e\.metadata->>'action' = 'update_pdc_vehicle_detail_fields_388'/);
  assert.match(up, /m\.to_location = 'PMB' AND m\.reason = 'Explicit Vehicle Locations release to PMB'/);
  assert.match(up, /ELSIF v_key IS NULL THEN\n  v_basis := 'tune'; v_arrived := v_tune;/);
  assert.match(up, /CREATE TRIGGER zz_pdc_arrival_age_563_move AFTER INSERT ON public\.vehicle_movements/);
  assert.match(up, /OR \(basis = 'tune' AND arrived_at IS NOT NULL AND arrived_at = tune_at AND key_at IS NULL\)\) NOT VALID;/);
  assert.match(up, /'AND trg\.n = 6', 'AND trg\.n = 7'/);
});

test('rows are recomputed, 13047269 is checked, and the rollback restores the r563 rule', () => {
  assert.match(up, /IF n < 100 THEN RAISE EXCEPTION 'r742: only % rows recomputed'/);
  assert.match(up, /r742: 13047269 still dated before 29 Oct/);
  assert.match(down, /ELSIF v_tune IS NOT NULL AND \(v_key IS NULL OR v_tune < v_key\) THEN/);
  assert.match(down, /DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_move ON public\.vehicle_movements;/);
  assert.match(down, /'AND trg\.n = 7', 'AND trg\.n = 6'/);
});
