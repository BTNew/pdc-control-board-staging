'use strict';
// r755 (F360, Craig rule B): the key becomes WPC when final check passes (QC to RFT), not on the way into QC.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030113500_r755_wpc_after_final_check.sql', 'utf8');
test('r755: trigger fires on the move to RFT with a real key, never on the way into QC; check 465; website wording', () => {
  const body = up.slice(up.indexOf('CREATE OR REPLACE FUNCTION pdc_key_number_private.qc_key_to_wpc_830()'), up.indexOf('REVOKE ALL ON FUNCTION pdc_key_number_private.qc_key_to_wpc_830()'));
  assert.match(body, /IF v_new_eff = 'RFT' AND v_old_eff <> 'RFT'\n\s+AND pdc_key_number_private\.key_token_575\(NEW\.key_number\) IS NOT NULL THEN/);
  assert.doesNotMatch(body, /v_new_eff = 'QC'/);
  assert.match(body, /set_config\('pdc\.wpc_cause_830', 'final_check_pass', true\)/);
  assert.match(up, /a car was already made WPC on the way into QC; decide those first/);
  assert.match(up, /'wpc_after_final_check_755', 'F360',/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261030113500_r755_wpc_after_final_check.down.sql'));
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(app, /Pass final check for \$\{label\}\?\\n\\nThe key number becomes WPC/);
  assert.match(app, /Final check passed\. Key number is now WPC/);
});
